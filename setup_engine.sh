#!/bin/bash

# ==========================================
# ComfyUI AutoDL 自动化装配主控脚本 (调度器)
# ==========================================

set -euo pipefail

# 1. 网络加速与环境变量隔离
export HF_HUB_ENABLE_HF_TRANSFER="1"

if [ -f /etc/network_turbo ]; then
    source /etc/network_turbo
    echo ">>> 已开启 AutoDL 学术加速 (代理模式)"
    unset HF_ENDPOINT 
else
    echo "NOTICE: 未检测到学术加速，启用 hf-mirror.com 国内镜像降级..."
    export HF_ENDPOINT="https://hf-mirror.com"
fi

# 2. 定义全局路径变量并导出，供子脚本使用
export BASE_DIR="/root/autodl-tmp"
export COMFYUI_DIR="$BASE_DIR/ComfyUI"
export ENV_REPO_DIR="$BASE_DIR/comfyui-autodl-env"
export PYTHON_BIN="$(command -v python || true)"

OLD_CACHE_DIR="/root/.cache"
NEW_CACHE_DIR="$BASE_DIR/.cache"

# 3. 环境变量与缓存隔离
export PIP_CACHE_DIR="$NEW_CACHE_DIR/pip"
export HF_HOME="$NEW_CACHE_DIR/huggingface"

echo ">>> 开始执行模块化装配 (主控调度模式)..."

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
# 模块 B: 核心引擎部署 (调用子脚本)
# ------------------------------------------
if [ -f "$ENV_REPO_DIR/setup_engine.sh" ]; then
    bash "$ENV_REPO_DIR/setup_engine.sh"
else
    echo "ERROR: 未找到 setup_engine.sh，装配中止。" >&2
    exit 1
fi

# ------------------------------------------
# 模块 C: 配置、逻辑注入与目录生成 (调用子脚本)
# ------------------------------------------
echo ">>> [4/6] 映射持久化配置文件与构建模型目录..."
mkdir -p "$ENV_REPO_DIR/workflows"

if [ ! -f "$ENV_REPO_DIR/extra_model_paths.yaml" ]; then
    touch "$ENV_REPO_DIR/extra_model_paths.yaml"
fi

ln -sf "$ENV_REPO_DIR/extra_model_paths.yaml" "$COMFYUI_DIR/extra_model_paths.yaml"
ln -sf "$ENV_REPO_DIR/workflows" "$COMFYUI_DIR/user_workflows"

if [ -f "$ENV_REPO_DIR/setup_models.sh" ]; then
    bash "$ENV_REPO_DIR/setup_models.sh"
else
    echo "    -> 提示: 未找到 setup_models.sh，跳过目录创建。"
fi

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
EOF

if [ -n "${HF_ENDPOINT:-}" ]; then
    echo "export HF_ENDPOINT=\"$HF_ENDPOINT\"" >> "$BASHRC"
fi

cat << EOF >> "$BASHRC"
if [ -f "$ALIAS_FILE" ]; then
    source "$ALIAS_FILE"
fi
# === AutoDL Env End ===
EOF

if [ -w /usr/local/bin ]; then
    cat > /usr/local/bin/comfy <<EOF
#!/bin/bash
cd "$COMFYUI_DIR"
exec "$PYTHON_BIN" main.py "\$@"
EOF
    chmod +x /usr/local/bin/comfy || true
fi

echo ">>> 装配流程全部完成！"