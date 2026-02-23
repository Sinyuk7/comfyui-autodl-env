#!/bin/bash

# ==========================================
# HuggingFace 自动化下载工具 (2026 满血自清理版)
# ==========================================

set -euo pipefail

# --- 1. 环境配置 ---
export HF_HUB_ENABLE_HF_TRANSFER="${HF_HUB_ENABLE_HF_TRANSFER:-1}"
export HF_HUB_DISABLE_PROGRESS_BARS="${HF_HUB_DISABLE_PROGRESS_BARS:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 因为在 download 子目录，需要取其父目录作为仓库根目录
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_REPO_DIR="${ENV_REPO_DIR:-$REPO_ROOT}"
HF_BIN="${HF_BIN:-hf}"

# 默认基础路径 (解析 yaml 逻辑)
DEFAULT_BASE_PATH="/root/autodl-tmp/shared_models"
if [ -f "$ENV_REPO_DIR/extra_model_paths.yaml" ]; then
    bp=$(awk -F": " '/base_path/ {print $2; exit}' "$ENV_REPO_DIR/extra_model_paths.yaml" || true)
    [ -n "$bp" ] && DEFAULT_BASE_PATH="${bp%/}"
fi

# --- 2. 辅助函数 ---

# 检查 CLI 是否就绪
ensure_hf() {
    if ! command -v "$HF_BIN" >/dev/null 2>&1; then
        echo "ERROR: hf CLI 未安装或未在 PATH 中。请运行 setup_engine.sh 修复。" >&2
        exit 1
    fi
}

# 自动疏通残留文件锁 (自愈逻辑)
clear_repo_lock() {
    local repo="$1"
    local safe_name="models--$(echo "$repo" | sed 's/\//--/g')"
    local lock_dir="/root/autodl-tmp/.cache/huggingface/hub/.locks/$safe_name"
    if [ -d "$lock_dir" ]; then
        echo "--> [Lock] 正在清理残留锁文件: $repo"
        rm -rf "$lock_dir"
    fi
}

# 判断下载模式
is_snapshot() {
    local file="$1"
    [ -z "$file" ] && return 0
    return 1
}

# --- 3. 核心执行函数 ---

download_snapshot() {
    local repo="$1"
    local target_dir="$2"
    local repo_type="${3:-model}"
    local revision="${4:-main}"
    local include="${5:-}"
    local exclude="${6:-}"

    mkdir -p "$target_dir"
    clear_repo_lock "$repo"

    echo "--> [Snapshot] 正在同步: $repo"
    echo "    目标: $target_dir | 类型: $repo_type | 版本: $revision"

    cmd=(
        "$HF_BIN" download "$repo"
        --repo-type "$repo_type"
        --revision "$revision"
        --local-dir "$target_dir"
        --local-dir-use-symlinks False
        --max-workers 16
    )

    [ -n "$include" ] && cmd+=(--include "$include")
    [ -n "$exclude" ] && cmd+=(--exclude "$exclude")

    # 执行下载
    "${cmd[@]}"

    # --- 新增：自动化空间回收 ---
    echo "--> [CLEAN] 下载成功，正在回收缓存空间..."
    # 构造 hf cache rm 需要的 ID 格式，例如 model/repo_id
    "$HF_BIN" cache rm "${repo_type:-model}/$repo" --yes >/dev/null 2>&1 || true
}

download_file() {
    local repo="$1"
    local file="$2"
    local target_dir="$3"
    local repo_type="${4:-model}"
    local revision="${5:-main}"

    mkdir -p "$target_dir"
    clear_repo_lock "$repo"

    local out_file
    out_file="$(basename "$file")"

    if [ -f "$target_dir/$out_file" ]; then
        echo "--> [Skip] 文件已存在: $out_file"
        return 0
    fi

    echo "--> [File] 正在下载: $repo/$file"

    # 执行下载
    "$HF_BIN" download "$repo" "$file" \
        --repo-type "$repo_type" \
        --revision "$revision" \
        --local-dir "$target_dir" \
        --local-dir-use-symlinks False

    # --- 新增：自动化空间回收 ---
    echo "--> [CLEAN] 下载成功，正在回收缓存空间..."
    "$HF_BIN" cache rm "${repo_type:-model}/$repo" --yes >/dev/null 2>&1 || true
}

download_model() {
    local repo="${1:-}"
    local file="${2:-}"
    local target="${3:-}"
    local repo_type="${4:-model}"
    local revision="${5:-main}"
    local include="${6:-}"
    local exclude="${7:-}"

    [ -z "$repo" ] && { echo "ERROR: repo_id 不能为空" >&2; return 1; }
    [ -z "$target" ] && target="$DEFAULT_BASE_PATH"

    if is_snapshot "$file"; then
        download_snapshot "$repo" "$target/$repo" "$repo_type" "$revision" "$include" "$exclude"
    else
        download_file "$repo" "$file" "$target" "$repo_type" "$revision"
    fi
}

# --- 4. 清单解析器 ---

process_manifest() {
    local manifest="$1"
    while IFS='|' read -r repo file target type rev inc exc || [ -n "$repo" ]; do
        repo=$(echo "$repo" | xargs); [[ -z "$repo" || "$repo" == \#* ]] && continue
        file=$(echo "$file" | xargs)
        target=$(echo "$target" | xargs)
        type=$(echo "${type:-model}" | xargs)
        rev=$(echo "${rev:-main}" | xargs)
        inc=$(echo "$inc" | xargs)
        exc=$(echo "$exc" | xargs)

        download_model "$repo" "$file" "$target" "$type" "$rev" "$inc" "$exc"
    done < "$manifest"
}

# --- 5. 入口逻辑 ---

ensure_hf

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <repo> [file] [target] [type] [rev]  OR  $0 -f <manifest>"
    exit 2
fi

if [ "$1" = "-f" ]; then
    [ ! -f "${2:-}" ] && { echo "ERROR: 找不到清单文件 $2" >&2; exit 1; }
    process_manifest "$2"
    exit 0
fi

download_model "${1:-}" "${2:-}" "${3:-}" "${4:-model}" "${5:-main}"