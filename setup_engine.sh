#!/bin/bash

# ==========================================
# setup_engine.sh - ComfyUI 核心引擎与底层依赖装配
# ==========================================

set -euo pipefail

# 接收环境变量，若为空则使用默认兜底值
COMFYUI_DIR="${COMFYUI_DIR:-/root/autodl-tmp/ComfyUI}"
PYTHON_BIN="${PYTHON_BIN:-python}"
DESIRED_TORCH_INDEX="https://download.pytorch.org/whl/nightly/cu130"

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
if "$PYTHON_BIN" -c "import torch" >/dev/null 2>&1; then
    echo "    -> torch appears installed"
else
    echo "    -> torch not found; attempting install..."
    if ! "$PYTHON_BIN" -m pip install --pre torch torchvision torchaudio --index-url "$DESIRED_TORCH_INDEX"; then
        echo "ERROR: torch install failed" >&2
        exit 1
    fi
fi

# 3. 安装 ComfyUI 核心依赖
if ! "$PYTHON_BIN" -m pip install -r requirements.txt >/dev/null 2>&1; then
    echo "WARNING: requirements.txt install failed"
fi

echo "    -> 核心引擎部署完成。"