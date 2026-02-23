#!/bin/bash

# ==========================================
# ComfyUI AutoDL 自动化装配脚本
# ==========================================

set -euo pipefail

# 1. 网络加速与环境变量隔离
export HF_HUB_ENABLE_HF_TRANSFER="1"

if [ -f /etc/network_turbo ]; then
    source /etc/network_turbo
    echo ">>> 已开启 AutoDL 学术加速 (代理模式)"
    # 取消镜像强制设定，走代理直连官方
    unset HF_ENDPOINT 
else
    echo "NOTICE: 未检测到学术加速，启用 hf-mirror.com 国内镜像降级..."
    export HF_ENDPOINT="https://hf-mirror.com"
fi


# 2. 定义绝对路径变量
BASE_DIR="/root/autodl-tmp"
COMFYUI_DIR="$BASE_DIR/ComfyUI"
ENV_REPO_DIR="$BASE_DIR/comfyui-autodl-env"
OLD_CACHE_DIR="/root/.cache"
NEW_CACHE_DIR="$BASE_DIR/.cache"

# 3. 环境变量与缓存隔离
export PIP_CACHE_DIR="$NEW_CACHE_DIR/pip"
export HF_HOME="$NEW_CACHE_DIR/huggingface"
export HF_HUB_ENABLE_HF_TRANSFER="1"

echo ">>> 开始执行模块化装配 (幂等模式)..."

# ------------------------------------------
# 模块 A: 缓存迁移与兜底 (安全模式)
# ------------------------------------------
echo ">>> [1/6] 检查并迁移系统盘残留缓存..."
mkdir -p "$OLD_CACHE_DIR" "$PIP_CACHE_DIR" "$HF_HOME"

for CACHE_TYPE in "pip" "huggingface"; do
    OLD_PATH="$OLD_CACHE_DIR/$CACHE_TYPE"
    NEW_PATH="$NEW_CACHE_DIR/$CACHE_TYPE"
    
    if [ -d "$OLD_PATH" ] && [ ! -L "$OLD_PATH" ]; then
        echo "    -> 发现旧系统盘缓存 $CACHE_TYPE，正在安全迁移至数据盘..."
        # 严格校验：仅当复制成功后，才删除原文件，防止跨盘迁移丢数据
        if cp -a "$OLD_PATH/." "$NEW_PATH/"; then
            rm -rf "$OLD_PATH"
            ln -sf "$NEW_PATH" "$OLD_PATH"
        else
            echo "ERROR: $CACHE_TYPE 缓存迁移失败，中止执行" >&2
            exit 1
        fi
    elif [ ! -e "$OLD_PATH" ]; then
        ln -sf "$NEW_PATH" "$OLD_PATH"
    fi
done

# ------------------------------------------
# 模块 B: 核心引擎部署
# ------------------------------------------
if [ ! -d "$COMFYUI_DIR" ]; then
    echo ">>> [2/6] 正在克隆 ComfyUI 官方仓库..."
    git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_DIR"
else
    echo ">>> [2/6] ComfyUI 目录已存在，跳过克隆。"
fi

echo ">>> [3/6] 安装/校验核心依赖与 HF 工具..."
PYTHON_BIN="$(command -v python || true)"

if ! pip install -U huggingface_hub hf_transfer >/dev/null 2>&1; then
    echo "WARNING: HF tools install failed"
fi

cd "$COMFYUI_DIR"

DESIRED_TORCH_INDEX="https://download.pytorch.org/whl/nightly/cu130"
if $PYTHON_BIN -c "import torch" >/dev/null 2>&1; then
    echo "    -> torch appears installed"
else
    echo "    -> torch not found; attempting install..."
    if ! pip install --pre torch torchvision torchaudio --index-url "$DESIRED_TORCH_INDEX"; then
        echo "ERROR: torch install failed" >&2
        exit 1
    fi
fi

if ! pip install -r requirements.txt >/dev/null 2>&1; then
    echo "WARNING: requirements.txt install failed"
fi

# ------------------------------------------
# 模块 C: 配置与逻辑注入
# ------------------------------------------
echo ">>> [4/6] 映射持久化配置文件..."
mkdir -p "$ENV_REPO_DIR/workflows"

if [ ! -f "$ENV_REPO_DIR/extra_model_paths.yaml" ]; then
    touch "$ENV_REPO_DIR/extra_model_paths.yaml"
fi

ln -sf "$ENV_REPO_DIR/extra_model_paths.yaml" "$COMFYUI_DIR/extra_model_paths.yaml"
ln -sf "$ENV_REPO_DIR/workflows" "$COMFYUI_DIR/user_workflows"

# ------------------------------------------
# 模块 D: 插件生态装配
# ------------------------------------------
echo ">>> [5/6] 校验 Custom Nodes..."
MANAGER_DIR="$COMFYUI_DIR/custom_nodes/ComfyUI-Manager"

if [ ! -d "$MANAGER_DIR" ]; then
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git "$MANAGER_DIR"
else
    echo "    -> ComfyUI-Manager 已存在，跳过。"
fi

if ! command -v aria2c >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq aria2 >/dev/null 2>&1 || true
fi

# ------------------------------------------
# 模块 E: Shell 环境闭环注入
# ------------------------------------------
echo ">>> [6/6] 注入自定义 Shell 配置..."
BASHRC="/root/.bashrc"
ALIAS_FILE="$ENV_REPO_DIR/aliases.sh"
touch "$BASHRC"

if grep -q "# === AutoDL Env Config ===" "$BASHRC"; then
    sed -i '/# === AutoDL Env Config ===/,/# === AutoDL Env End ===/d' "$BASHRC"
fi

cat << EOF >> "$BASHRC"
# === AutoDL Env Config ===
export PIP_CACHE_DIR="$PIP_CACHE_DIR"
export HF_HOME="$HF_HOME"
export HF_HUB_ENABLE_HF_TRANSFER="1"
if [ -n "${HF_ENDPOINT:-}" ]; then
    export HF_ENDPOINT="$HF_ENDPOINT"
fi
if [ -f "$ALIAS_FILE" ]; then
    source "$ALIAS_FILE"
fi
# === AutoDL Env End ===
EOF

if [ -w /usr/local/bin ]; then
    cat > /usr/local/bin/comfy <<EOF
#!/bin/bash
cd "$COMFYUI_DIR"
exec "$(command -v python)" main.py "\$@"
EOF
    chmod +x /usr/local/bin/comfy || true
fi

echo ">>> 装配流程全部完成！"