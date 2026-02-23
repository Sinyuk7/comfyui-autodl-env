#!/bin/bash

# ==========================================
# setup_engine.sh - [2026 修正版]
# 修复 uv 环境权限问题，加入 --system 参数
# ==========================================

set -euo pipefail

# 1. 注入路径与基础变量
export PATH="/root/.local/bin:$PATH"
COMFYUI_DIR="${COMFYUI_DIR:-/root/autodl-tmp/ComfyUI}"
PYTHON_BIN="${PYTHON_BIN:-python}"
DESIRED_TORCH_INDEX="https://download.pytorch.org/whl/nightly/cu130"

echo ">>> [1/6] 硬件与基础环境校验..."

# 确保 uv 已安装
if ! command -v uv >/dev/null 2>&1; then
    echo "    -> 安装 uv 包管理器..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    source $HOME/.cargo/env
fi

# 驱动版本校验
DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n 1)
DRIVER_MAJOR=$(echo "$DRIVER_VERSION" | awk -F'.' '{print $1}')
if [ "$DRIVER_MAJOR" -lt 580 ]; then
    echo "ERROR: cu130 需要驱动版本 >= 580 (当前: $DRIVER_VERSION)。" >&2
    exit 1
fi
echo "    -> 硬件校验通过: $DRIVER_VERSION"

echo ">>> [2/6] 校验/克隆 ComfyUI 仓库..."
if [ ! -d "$COMFYUI_DIR" ]; then
    git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_DIR"
else
    echo "    -> ComfyUI 目录已存在，跳过克隆。"
fi

echo ">>> [3/6] 安装/更新高速工具链 (uv-managed)..."
# uv tool 独立管理环境，无需 --system
uv tool install hf --force
uv tool install huggingface-hub --force

# 安装到系统/Conda环境需添加 --system
uv pip install --system -U huggingface_hub hf_transfer

cd "$COMFYUI_DIR"

echo ">>> [4/6] 精确校验 PyTorch (cu130)..."
CHECK_CU130_CMD="import torch, sys; sys.exit(0) if torch.version.cuda and float(torch.version.cuda) >= 13.0 else sys.exit(1)"

if "$PYTHON_BIN" -c "$CHECK_CU130_CMD" >/dev/null 2>&1; then
    echo "    -> torch (cu130+) 已就绪。"
else
    echo "    -> 正在升级 PyTorch 环境至 cu130..."
    # 添加 --system 参数
    uv pip install --system --upgrade --pre torch torchvision torchaudio --index-url "$DESIRED_TORCH_INDEX"
fi

echo ">>> [5/6] 安装 ComfyUI 核心依赖..."
# 添加 --system 参数
uv pip install --system -r requirements.txt

echo ">>> 核心引擎部署完成。"