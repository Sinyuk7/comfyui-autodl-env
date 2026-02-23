#!/bin/bash

# ==========================================
# setup_cache.sh - 缓存重定向与数据盘安全迁移 (V2.0)
# ==========================================

set -euo pipefail

# 基础目录配置
OLD_CACHE_BASE="/root/.cache"
NEW_CACHE_BASE="${NEW_CACHE_DIR:-/root/autodl-tmp/.cache}"

# 定义需要迁移的子目录 (按需扩展)
CACHE_DIRS=(
    "pip"
    "huggingface"
    "torch"
    "matplotlib"
    "npm"
    "ModelScope"
    "triton"
)

echo ">>> [1/2] 初始化环境与校验路径..."
mkdir -p "$OLD_CACHE_BASE"
mkdir -p "$NEW_CACHE_BASE"

# 检查 rsync 是否安装，若无则回退到 cp
USE_RSYNC=false
if command -v rsync >/dev/null 2>&1; then
    USE_RSYNC=true
fi

echo ">>> [2/2] 开始执行缓存重定向..."

for CACHE_TYPE in "${CACHE_DIRS[@]}"; do
    OLD_PATH="$OLD_CACHE_BASE/$CACHE_TYPE"
    NEW_PATH="$NEW_CACHE_BASE/$CACHE_TYPE"

    # 情况 A: 已经是正确的软链接，跳过
    if [[ -L "$OLD_PATH" ]]; then
        TARGET=$(readlink -f "$OLD_PATH")
        if [[ "$TARGET" == "$NEW_PATH" ]]; then
            echo "    [SKIP] $CACHE_TYPE 已重定向至数据盘。"
            continue
        else
            echo "    [WARN] $CACHE_TYPE 已是软链接，但指向异常 ($TARGET)，正在修正..."
            rm "$OLD_PATH"
        fi
    fi

    # 确保数据盘目标目录存在
    mkdir -p "$NEW_PATH"

    # 情况 B: 系统盘存在实体目录，需迁移数据
    if [[ -d "$OLD_PATH" && ! -L "$OLD_PATH" ]]; then
        echo "    [MOVE] 发现系统盘残留数据: $CACHE_TYPE，正在迁移..."
        
        if $USE_RSYNC; then
            # rsync -a: 归档模式; --remove-source-files: 迁移后删除源文件
            rsync -a --remove-source-files "$OLD_PATH/" "$NEW_PATH/"
        else
            cp -a "$OLD_PATH/." "$NEW_PATH/"
        fi
        
        # 清理残余空目录
        rm -rf "$OLD_PATH"
        echo "    [OK] $CACHE_TYPE 数据迁移完成。"
    fi

    # 情况 C: 建立最终软链接
    # 使用 -n 防止在已存在的目录链接内嵌套创建
    if [[ ! -e "$OLD_PATH" ]]; then
        ln -snf "$NEW_PATH" "$OLD_PATH"
        echo "    [LINK] $CACHE_TYPE -> $NEW_PATH 建立完成。"
    fi
done

echo ">>> 全部缓存架构迁移/校验完成。当前系统盘负载已优化。"