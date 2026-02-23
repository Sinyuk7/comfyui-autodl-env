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

# 2. 定义全局路径变量并导出，供子模块使用
export BASE_DIR="/root/autodl-tmp"
export COMFYUI_DIR="$BASE_DIR/ComfyUI"
export ENV_REPO_DIR="$BASE_DIR/comfyui-autodl-env"
export NEW_CACHE_DIR="$BASE_DIR/.cache"
export PYTHON_BIN="$(command -v python || true)"

# 3. 环境变量导出 (当前会话生效)
export PIP_CACHE_DIR="$NEW_CACHE_DIR/pip"
export HF_HOME="$NEW_CACHE_DIR/huggingface"
export TORCH_HOME="$NEW_CACHE_DIR/torch"

echo ">>> 开始执行模块化装配 (主控调度模式)..."

# ------------------------------------------
# 模块 A: 缓存迁移与兜底 (调用子脚本)
# ------------------------------------------
if [ -f "$ENV_REPO_DIR/setup_cache.sh" ]; then
    bash "$ENV_REPO_DIR/setup_cache.sh"
else
    echo "ERROR: 未找到 setup_cache.sh，装配中止。" >&2
    exit 1
fi

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
# 模块 C: 目录与配置映射 (调用 Python 脚本)
# ------------------------------------------
echo ">>> [4/6] 映射持久化配置文件与构建模型目录..."
mkdir -p "$ENV_REPO_DIR/workflows"

# 确保 YAML 文件存在
if [ ! -f "$ENV_REPO_DIR/extra_model_paths.yaml" ]; then
    touch "$ENV_REPO_DIR/extra_model_paths.yaml"
fi

# 建立映射链接
ln -sf "$ENV_REPO_DIR/extra_model_paths.yaml" "$COMFYUI_DIR/extra_model_paths.yaml"
ln -sf "$ENV_REPO_DIR/workflows" "$COMFYUI_DIR/user_workflows"

# 改为直接运行 Python 脚本
if [ -f "$ENV_REPO_DIR/setup_models.py" ]; then
    export YAML_PATH="$ENV_REPO_DIR/extra_model_paths.yaml"
    "$PYTHON_BIN" "$ENV_REPO_DIR/setup_models.py"
else
    echo "    -> ERROR: 未找到 setup_models.py" >&2
fi



# ------------------------------------------
# 模块 D: 插件生态装配 (调用子脚本)
# ------------------------------------------
if ! command -v aria2c >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq aria2 >/dev/null 2>&1 || true
fi

if [ -f "$ENV_REPO_DIR/setup_nodes.sh" ]; then
    bash "$ENV_REPO_DIR/setup_nodes.sh"
else
    echo "    -> 提示: 未找到 setup_nodes.sh，跳过插件装配。"
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

# 动态注入新增加的 TORCH_HOME 等变量
cat << EOF >> "$BASHRC"
# === AutoDL Env Config ===
export PIP_CACHE_DIR="$PIP_CACHE_DIR"
export HF_HOME="$HF_HOME"
export TORCH_HOME="$TORCH_HOME"
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
exec "$PYTHON_BIN" main.py --port 6006 "\$@"
EOF
    chmod +x /usr/local/bin/comfy || true
fi

echo ">>> 装配流程全部完成！全局指令 'comfy' 已就绪。"