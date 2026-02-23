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
echo ">>> [3/7] 映射持久化配置文件与构建模型目录..."
mkdir -p "$ENV_REPO_DIR/workflows"

# 确保 YAML 文件存在
if [ ! -f "$ENV_REPO_DIR/extra_model_paths.yaml" ]; then
    touch "$ENV_REPO_DIR/extra_model_paths.yaml"
fi

# 建立映射链接
ln -sf "$ENV_REPO_DIR/extra_model_paths.yaml" "$COMFYUI_DIR/extra_model_paths.yaml"
ln -sf "$ENV_REPO_DIR/workflows" "$COMFYUI_DIR/user_workflows"

# 执行模型目录构建与分类对齐
if [ -f "$ENV_REPO_DIR/setup_models.py" ]; then
    export YAML_PATH="$ENV_REPO_DIR/extra_model_paths.yaml"
    "$PYTHON_BIN" "$ENV_REPO_DIR/setup_models.py"
else
    echo "    -> ERROR: 未找到 setup_models.py" >&2
fi

# ------------------------------------------
# 模块 D: 插件生态装配 (Python 版本)
# ------------------------------------------
echo ">>> [4/7] 正在同步 Custom Nodes 插件生态..."
if [ -f "$ENV_REPO_DIR/setup_nodes.py" ]; then
    export COMFYUI_DIR="$COMFYUI_DIR"
    export ENV_REPO_DIR="$ENV_REPO_DIR"
    export PYTHON_BIN="$PYTHON_BIN"
    
    # 必须追加 --init 触发路由
    "$PYTHON_BIN" "$ENV_REPO_DIR/setup_nodes.py" --init
else
    echo "    -> 提示: 未找到 setup_nodes.py"
fi

# ------------------------------------------
# 模块 E: 个人偏好与 Manager 配置同步 (新增)
# ------------------------------------------
echo ">>> [5/7] 正在同步本地 UI 偏好与 Manager 配置..."

# 物理路径准备
mkdir -p "$COMFYUI_DIR/user/default"
mkdir -p "$COMFYUI_DIR/user/__manager"

# 1. 映射 UI 设置与快捷键 (不含工作流)
[ -f "$ENV_REPO_DIR/configs/user/comfy.settings.json" ] && ln -sf "$ENV_REPO_DIR/configs/user/comfy.settings.json" "$COMFYUI_DIR/user/default/comfy.settings.json"
[ -f "$ENV_REPO_DIR/configs/user/comfy.shortcuts.json" ] && ln -sf "$ENV_REPO_DIR/configs/user/comfy.shortcuts.json" "$COMFYUI_DIR/user/default/comfy.shortcuts.json"

# 2. 映射 Manager 核心配置 (不含下载代理)
[ -f "$ENV_REPO_DIR/configs/manager/config.ini" ] && ln -sf "$ENV_REPO_DIR/configs/manager/config.ini" "$COMFYUI_DIR/user/__manager/config.ini"
[ -f "$ENV_REPO_DIR/configs/manager/channels.list" ] && ln -sf "$ENV_REPO_DIR/configs/manager/channels.list" "$COMFYUI_DIR/user/__manager/channels.list"

# ------------------------------------------
# 模块 F: Shell 环境闭环注入 (原模块 E 顺延)
# ------------------------------------------
echo ">>> [6/7] 注入自定义 Shell 配置..."
BASHRC="/root/.bashrc"
ALIAS_FILE="$ENV_REPO_DIR/aliases.sh"
touch "$BASHRC"

if grep -q "# === AutoDL Env Config ===" "$BASHRC"; then
    sed -i '/# === AutoDL Env Config ===/,/# === AutoDL Env End ===/d' "$BASHRC"
fi

# 动态注入环境变量
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

# ------------------------------------------
# 模块 G: 全局指令装配 (防端口冲突版)
# ------------------------------------------
echo ">>> [7/7] 构建全局 'comfy' 指令..."
if [ -w /usr/local/bin ]; then
    cat > /usr/local/bin/comfy <<EOF
#!/bin/bash

# 1. 释放 6006 端口 (静默击杀占用该端口的进程)
if command -v fuser >/dev/null 2>&1; then
    fuser -k 6006/tcp >/dev/null 2>&1 || true
else
    # 备用击杀方案
    lsof -ti:6006 | xargs kill -9 >/dev/null 2>&1 || true
fi

echo ">>> 端口 6006 已释放，正在启动 ComfyUI..."

# 2. 启动服务
cd "$COMFYUI_DIR"
exec "$PYTHON_BIN" main.py --port 6006 "\$@"
EOF
    chmod +x /usr/local/bin/comfy || true
fi

echo ">>> 装配流程全部完成！全局指令 'comfy' 已就绪。"