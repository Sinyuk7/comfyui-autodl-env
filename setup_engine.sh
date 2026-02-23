#!/bin/bash

# ==========================================
# setup_engine.sh - [2026 最终永久修复版]
# ==========================================

set -euo pipefail

# 1. 注入永久环境变量逻辑
LOCAL_BIN="/root/.local/bin"
BASHRC="/root/.bashrc"

echo ">>> [0/6] 配置永久环境变量..."
# 如果路径不在 PATH 中，则临时加入当前会话
export PATH="$LOCAL_BIN:$PATH"

# 如果 .bashrc 中还没配置过这个路径，则写入
if ! grep -q "$LOCAL_BIN" "$BASHRC"; then
    echo "    -> 将 $LOCAL_BIN 写入 $BASHRC..."
    echo "export PATH=\"$LOCAL_BIN:\$PATH\"" >> "$BASHRC"
    echo "    -> 永久路径配置完成。"
fi

# 2. 基础环境校验
COMFYUI_DIR="${COMFYUI_DIR:-/root/autodl-tmp/ComfyUI}"
PYTHON_BIN="${PYTHON_BIN:-python}"
DESIRED_TORCH_INDEX="https://download.pytorch.org/whl/nightly/cu130"

echo ">>> [1/6] 硬件与驱动校验..."
if ! command -v uv >/dev/null 2>&1; then
    echo "    -> 安装 uv 包管理器..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    source $HOME/.cargo/env
fi

DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n 1)
DRIVER_MAJOR=$(echo "$DRIVER_VERSION" | awk -F'.' '{print $1}')
if [ "$DRIVER_MAJOR" -lt 580 ]; then
    echo "ERROR: cu130 需要驱动版本 >= 580 (当前: $DRIVER_VERSION)。" >&2
    exit 1
fi
echo "    -> 硬件校验通过: $DRIVER_VERSION"

# 3. 仓库校验
echo ">>> [2/6] 校验/克隆 ComfyUI 仓库..."
if [ ! -d "$COMFYUI_DIR" ]; then
    git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_DIR"
else
    echo "    -> ComfyUI 目录已存在。"
fi

# 4. 工具链安装
echo ">>> [3/6] 安装/更新高速工具链 (uv-managed)..."
uv tool install hf --force
uv tool install huggingface-hub --force
uv pip install --system -U huggingface_hub hf_transfer

# 5. PyTorch cu130 校验与安装
cd "$COMFYUI_DIR"
echo ">>> [4/6] 精确校验 PyTorch (cu130)..."
CHECK_CU130_CMD="import torch, sys; sys.exit(0) if torch.version.cuda and float(torch.version.cuda) >= 13.0 else sys.exit(1)"

if "$PYTHON_BIN" -c "$CHECK_CU130_CMD" >/dev/null 2>&1; then
    echo "    -> torch (cu130+) 已就绪。"
else
    echo "    -> 正在升级 PyTorch 环境至 cu130..."
    uv pip install --system --upgrade --pre torch torchvision torchaudio --index-url "$DESIRED_TORCH_INDEX"
fi

# 6. ComfyUI 依赖
echo ">>> [5/6] 安装 ComfyUI 核心依赖..."
uv pip install --system -r requirements.txt

echo ">>> 核心引擎部署全部完成！"