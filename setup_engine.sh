#!/bin/bash

# ==========================================
# setup_engine.sh - ComfyUI 核心引擎与底层依赖装配
# ==========================================

set -euo pipefail

# 接收环境变量，若为空则使用默认兜底值
COMFYUI_DIR="${COMFYUI_DIR:-/root/autodl-tmp/ComfyUI}"
PYTHON_BIN="${PYTHON_BIN:-python}"
DESIRED_TORCH_INDEX="https://download.pytorch.org/whl/nightly/cu130"

echo ">>> [硬件校验] 检查 NVIDIA 驱动是否支持 CUDA 13.0..."
if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo "ERROR: 未找到 nvidia-smi，无法校验驱动版本。" >&2
    exit 1
fi

# 提取驱动主版本号进行比对
DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n 1)
DRIVER_MAJOR=$(echo "$DRIVER_VERSION" | awk -F'.' '{print $1}')

if [ "$DRIVER_MAJOR" -lt 580 ]; then
    echo "ERROR: cu130 目标环境需要 NVIDIA 驱动版本 >= 580.xxx (检测到当前版本为: $DRIVER_VERSION)。" >&2
    echo "ERROR: 请联系 AutoDL 平台升级宿主机显卡驱动，或将本脚本回退至 cu128。" >&2
    exit 1
fi
echo "    -> 驱动校验通过: $DRIVER_VERSION (支持 CUDA 13.0+)"

echo ">>> [2/6] 校验/克隆 ComfyUI 官方仓库..."
if [ ! -d "$COMFYUI_DIR" ]; then
    git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_DIR"
else
    echo "    -> ComfyUI 目录已存在，跳过克隆。"
fi

echo ">>> [3/6] 安装/校验核心底层依赖..."

# 1. 安装 Hugging Face 传输工具
if ! "$PYTHON_BIN" -m pip install -U huggingface_hub hf_transfer >/dev/null 2>&1; then
    echo "WARNING: HF tools install failed"
fi

cd "$COMFYUI_DIR"

# 2. 校验与安装 PyTorch 环境
CHECK_CU130_CMD="import torch, sys; sys.exit(0) if torch.version.cuda and float(torch.version.cuda) >= 13.0 else sys.exit(1)"

if "$PYTHON_BIN" -c "$CHECK_CU130_CMD" >/dev/null 2>&1; then
    echo "    -> torch (cu130+) appears installed"
else
    echo "    -> torch with cu130 not found; attempting install/upgrade..."
    if ! "$PYTHON_BIN" -m pip install --upgrade --pre torch torchvision torchaudio --index-url "$DESIRED_TORCH_INDEX"; then
        echo "ERROR: torch install/upgrade failed" >&2
        exit 1
    fi
fi

# 3. 安装 ComfyUI 核心依赖
if ! "$PYTHON_BIN" -m pip install -r requirements.txt >/dev/null 2>&1; then
    echo "WARNING: requirements.txt install failed"
fi

echo "    -> 核心引擎部署完成。"