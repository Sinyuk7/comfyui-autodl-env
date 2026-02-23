#!/bin/bash

# ==========================================
# setup_nodes.sh - 插件生态(Custom Nodes)自动化装配
# ==========================================

set -euo pipefail

# 接收环境变量兜底
COMFYUI_DIR="${COMFYUI_DIR:-/root/autodl-tmp/ComfyUI}"
ENV_REPO_DIR="${ENV_REPO_DIR:-/root/autodl-tmp/comfyui-autodl-env}"
PYTHON_BIN="${PYTHON_BIN:-python}"
NODES_DIR="$COMFYUI_DIR/custom_nodes"

mkdir -p "$NODES_DIR"
cd "$NODES_DIR"

echo ">>> [5/6] 校验与部署 Custom Nodes..."

# 1. 强制安装基础管理插件 ComfyUI-Manager
if [ ! -d "ComfyUI-Manager" ]; then
    echo "    -> 正在克隆 ComfyUI-Manager..."
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git "ComfyUI-Manager"
else
    echo "    -> ComfyUI-Manager 已存在，跳过。"
fi

# 2. 批量拉取自定义节点清单 (按需)
NODES_LIST="$ENV_REPO_DIR/custom_nodes.txt"

if [ -f "$NODES_LIST" ]; then
    echo "    -> 发现 custom_nodes.txt，开始批量检查并同步插件..."
    while IFS= read -r repo_url || [ -n "$repo_url" ]; do
        # 清洗空格，忽略空行与注释
        repo_url="$(echo "$repo_url" | sed 's/^\s*//;s/\s*$//')"
        [ -z "$repo_url" ] && continue
        case "$repo_url" in
            \#*) continue ;;
        esac
        
        # 提取仓库名
        repo_name="$(basename "$repo_url" .git)"
        
        if [ ! -d "$repo_name" ]; then
            echo "    -> 正在拉取: $repo_name"
            git clone "$repo_url" "$repo_name"
            
            # 自动化依赖安装 (如果插件根目录存在 requirements.txt)
            if [ -f "$repo_name/requirements.txt" ]; then
                echo "    -> 正在为 $repo_name 安装专属依赖..."
                if ! "$PYTHON_BIN" -m pip install -r "$repo_name/requirements.txt" >/dev/null 2>&1; then
                    echo "WARNING: $repo_name 依赖安装发生异常，请后续在 Manager 中检查。"
                fi
            fi
        else
            echo "    -> $repo_name 已存在，跳过。"
        fi
    done < "$NODES_LIST"
else
    echo "    -> 提示: 未发现 custom_nodes.txt，除 Manager 外不执行额外插件拉取。"
fi

echo "    -> 插件生态装配完成。"