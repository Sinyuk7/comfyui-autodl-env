#!/bin/bash

# ==========================================
# setup_cache.sh - 缓存重定向与数据盘安全迁移
# ==========================================

set -euo pipefail

# 基础目录兜底
OLD_CACHE_BASE="/root/.cache"
NEW_CACHE_BASE="${NEW_CACHE_DIR:-/root/autodl-tmp/.cache}"

# 定义需要接管并迁移的缓存子目录 (支持自由扩展)
CACHE_DIRS=(
    "pip"
    "huggingface"
    "torch"
    "matplotlib"
    "npm"
)

echo ">>> [1/6] 检查并迁移系统盘残留缓存..."
mkdir -p "$OLD_CACHE_BASE" "$NEW_CACHE_BASE"

for CACHE_TYPE in "${CACHE_DIRS[@]}"; do
    OLD_PATH="$OLD_CACHE_BASE/$CACHE_TYPE"
    NEW_PATH="$NEW_CACHE_BASE/$CACHE_TYPE"
    
    # 确保目标路径存在，避免 cp 报错
    mkdir -p "$NEW_PATH"

    if [ -d "$OLD_PATH" ] && [ ! -L "$OLD_PATH" ]; then
        echo "    -> 发现旧系统盘缓存 [$CACHE_TYPE]，正在安全迁移至数据盘..."
        if cp -a "$OLD_PATH/." "$NEW_PATH/"; then
            rm -rf "$OLD_PATH"
            ln -sf "$NEW_PATH" "$OLD_PATH"
        else
            echo "ERROR: [$CACHE_TYPE] 缓存迁移失败，中止执行" >&2
            exit 1
        fi
    elif [ ! -e "$OLD_PATH" ]; then
        # 即使旧目录不存在，也提前打好软链接，防止后续程序直接写入系统盘
        ln -sf "$NEW_PATH" "$OLD_PATH"
    fi
done

echo "    -> 缓存架构迁移/校验完成。"