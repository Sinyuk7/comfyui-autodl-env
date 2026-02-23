#!/bin/bash

# ==========================================
# setup_engine.sh - [2026 最终生产力版]
# 逻辑：uv 驱动 / CUDA 13.0 适配 / hf 官方工具链
# ==========================================

set -euo pipefail

# 1. 注入路径与永久环境变量
LOCAL_BIN="/root/.local/bin"
BASHRC="/root/.bashrc"
export PATH="$LOCAL_BIN:$PATH"

echo ">>> [0/6] 配置永久环境变量..."
if ! grep -q "$LOCAL_BIN" "$BASHRC"; then
    echo "export PATH=\"$LOCAL_BIN:\$PATH\"" >> "$BASHRC"
fi

# 2. 基础环境与硬件校验
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
    echo "ERROR: CUDA 13.0 需要驱动版本 >= 580 (当前: $DRIVER_VERSION)。" >&2
    exit 1
fi
echo "    -> 驱动校验通过: $DRIVER_VERSION"

# 3. 仓库装配
echo ">>> [2/6] 校验/克隆 ComfyUI 仓库..."
if [ ! -d "$COMFYUI_DIR" ]; then
    git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_DIR"
fi

# 4. 工具链纠偏（解决 hf 冲突）
echo ">>> [3/6] 安装官方 hf 满血版工具链..."
# 彻底移除会产生命名冲突的独立 tool
uv tool uninstall hf || true
uv tool uninstall huggingface-hub || true

# 通过系统环境安装带 CLI 的官方库，确保 'hf' 命令包含 auth/download/upload
uv pip install --system -U "huggingface_hub[cli]" hf_transfer

# 5. 核心引擎（PyTorch cu130）安装
cd "$COMFYUI_DIR"
echo ">>> [4/6] 精确校验 PyTorch (cu130)..."
CHECK_CU130="import torch, sys; sys.exit(0) if torch.version.cuda and float(torch.version.cuda) >= 13.0 else sys.exit(1)"

if "$PYTHON_BIN" -c "$CHECK_CU130" >/dev/null 2>&1; then
    echo "    -> torch (cu130+) 已就绪。"
else
    echo "    -> 正在升级 PyTorch 至 2.12.0.dev+cu130..."
    uv pip install --system --upgrade --pre torch torchvision torchaudio --index-url "$DESIRED_TORCH_INDEX"
fi

# 6. 业务依赖
echo ">>> [5/6] 安装 ComfyUI 核心依赖..."
uv pip install --system -r requirements.txt

echo ">>> 引擎部署全部完成！"