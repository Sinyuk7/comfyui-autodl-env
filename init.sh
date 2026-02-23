#!/bin/bash

# ==========================================
# ComfyUI AutoDL 自动化装配脚本
# ==========================================

# 1. 开启 AutoDL 学术加速 (提升 GitHub/Pip/下载 速度)
source /etc/network_turbo

# 2. 定义绝对路径变量
BASE_DIR="/root/autodl-tmp"
COMFYUI_DIR="$BASE_DIR/ComfyUI"
ENV_REPO_DIR="$BASE_DIR/comfyui-autodl-env"

echo ">>> 开始执行模块化装配..."

# ------------------------------------------
# 模块 A: 核心引擎部署
# ------------------------------------------
if [ ! -d "$COMFYUI_DIR" ]; then
    echo ">>> [1/5] 正在克隆 ComfyUI 官方仓库..."
    git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_DIR"
else
    echo ">>> [1/5] ComfyUI 目录已存在，跳过克隆。"
fi

echo ">>> [2/5] 安装/校验 ComfyUI 核心依赖..."
cd "$COMFYUI_DIR"
pip install -r requirements.txt > /dev/null 2>&1

# ------------------------------------------
# 模块 B: 配置与逻辑注入 (Symlink)
# ------------------------------------------
echo ">>> [3/5] 映射持久化配置文件..."

# 强制映射额外模型路径配置
ln -sf "$ENV_REPO_DIR/extra_model_paths.yaml" "$COMFYUI_DIR/extra_model_paths.yaml"

# 映射自定义工作流目录 (在 ComfyUI 内建一个 user_workflows 指向你的仓库)
ln -sf "$ENV_REPO_DIR/workflows" "$COMFYUI_DIR/user_workflows"

# ------------------------------------------
# 模块 C: 插件生态装配
# ------------------------------------------
echo ">>> [4/5] 拉取 Custom Nodes..."
MANAGER_DIR="$COMFYUI_DIR/custom_nodes/ComfyUI-Manager"

if [ ! -d "$MANAGER_DIR" ]; then
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git "$MANAGER_DIR"
    # 后续若有其他插件，可在此处继续追加 git clone
else
    echo ">>> ComfyUI-Manager 已存在，跳过。"
fi

# ------------------------------------------
# 模块 D: 重资产(模型)自动化拉取
# ------------------------------------------
echo ">>> [5/5] 校验并下载大模型..."

# 确保 aria2 多线程下载工具已安装
apt-get install -y aria2 > /dev/null 2>&1

# 封装幂等下载函数：仅当文件不存在时触发下载
download_model() {
    local url=$1
    local out_file=$2
    local target_dir=$3
    
    mkdir -p "$target_dir"
    
    if [ ! -f "$target_dir/$out_file" ]; then
        echo "--> 正在高速下载: $out_file"
        # -x 16: 16线程下载 | -s 16: 16个连接数 | -k 1M: 分块大小
        aria2c -x 16 -s 16 -k 1M -d "$target_dir" -o "$out_file" "$url"
    else
        echo "--> 模型已就绪: $out_file，跳过下载。"
    fi
}

# --- 在此配置你需要每次开机自动拉取的模型 ---
# 用法示例： download_model "直链URL" "保存的文件名" "目标文件夹路径"

# 修改 init.sh 中的变量定义
SHARED_MODEL_DIR="/root/autodl-tmp/shared_models"
CKPT_DIR="$SHARED_MODEL_DIR/checkpoints"
LORA_DIR="$SHARED_MODEL_DIR/loras"

# 示例：下载 SDXL Base 模型 (使用时取消注释并替换为实际直链)
# download_model "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors" "sd_xl_base.safetensors" "$CKPT_DIR"

echo ">>> 装配流程全部完成！"
echo ">>> 请使用以下命令启动服务: python main.py --listen 127.0.0.1 --port 6006"


# ------------------------------------------
# 模块 E: Shell 环境注入
# ------------------------------------------
echo ">>> 注入自定义 Shell 配置..."
BASHRC="/root/.bashrc"
ALIAS_FILE="$ENV_REPO_DIR/aliases.sh"

# 检查是否已经注入过，防止重复写入
if ! grep -q "$ALIAS_FILE" "$BASHRC"; then
    echo "" >> "$BASHRC"
    echo "# AutoDL Env Custom Aliases" >> "$BASHRC"
    echo "if [ -f \"$ALIAS_FILE\" ]; then" >> "$BASHRC"
    echo "    source \"$ALIAS_FILE\"" >> "$BASHRC"
    echo "fi" >> "$BASHRC"
fi