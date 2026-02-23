#!/bin/bash

set -euo pipefail

# ==========================================
# 模型下载工具 (增强版)
# 支持单文件、批量清单、断点续传、URL参数清洗
# ==========================================

THREADS=${DOWNLOAD_THREADS:-16}
CONNS=${DOWNLOAD_CONNS:-16}
CHUNK=${DOWNLOAD_CHUNK:-1M}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 因为在 download 子目录，需要取其父目录作为仓库根目录
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_REPO_DIR="${ENV_REPO_DIR:-$REPO_ROOT}"

DEFAULT_BASE_PATH="/root/autodl-tmp/shared_models"
if [ -f "$ENV_REPO_DIR/extra_model_paths.yaml" ]; then
    bp=$(awk -F": " '/base_path/ {print $2; exit}' "$ENV_REPO_DIR/extra_model_paths.yaml" || true)
    if [ -n "$bp" ]; then
        DEFAULT_BASE_PATH="${bp%/}"
    fi
fi

ensure_aria2() {
    if ! command -v aria2c >/dev/null 2>&1; then
        echo "ERROR: 未检测到 aria2c，请先安装 (apt-get install -y aria2)" >&2
        exit 1
    fi
}

download_model() {
    local url="${1:-}"
    local out_file="${2:-}"
    local target_dir="${3:-}"

    if [ -z "$url" ] || [ -z "$out_file" ] || [ -z "$target_dir" ]; then
        echo "ERROR: download_model 缺少必要参数" >&2
        return 1
    fi

    mkdir -p "$target_dir"

    if [ -f "$target_dir/$out_file" ] && [ ! -f "$target_dir/$out_file.aria2" ]; then
        echo "--> 模型已就绪: $out_file，跳过下载。"
        return 0
    fi

    echo "--> 正在下载: $out_file (目录: $target_dir)"
    aria2c -c -x "$THREADS" -s "$CONNS" -k "$CHUNK" \
           --auto-file-renaming=false \
           --console-log-level=error --summary-interval=5 \
           -d "$target_dir" -o "$out_file" "$url"
    
    ret=$?
    if [ $ret -ne 0 ]; then
        echo "ERROR: 下载失败或中断 ($out_file)，退出码 $ret" >&2
        return $ret
    fi
    echo "--> 下载完成: $out_file"
}

process_file() {
    local file="${1:-}"
    while IFS= read -r line || [ -n "$line" ]; do
        line="$(echo "$line" | sed 's/^\s*//;s/\s*$//')"
        [ -z "$line" ] && continue
        case "$line" in
            \#*) continue ;;
        esac
        
        if echo "$line" | grep -q "|"; then
            IFS='|' read -r url out target <<< "$line"
        else
            read -r url out target <<< "$line"
        fi

        url="${url:-}"
        out="${out:-}"
        target="${target:-}"

        if [ -z "$url" ]; then continue; fi
        
        if [ -z "$out" ]; then
            clean_url="${url%%\?*}"
            out="$(basename "$clean_url")"
        fi
        
        if [ -z "$target" ]; then
            target="$DEFAULT_BASE_PATH"
        fi

        download_model "$url" "$out" "$target"
    done < "$file"
}

ensure_aria2

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <url> [out_file] [target_dir]  OR  $0 -f models.txt" >&2
    exit 2
fi

if [ "${1:-}" = "-f" ]; then
    if [ -z "${2:-}" ] || [ ! -f "${2:-}" ]; then
        echo "ERROR: 清单文件不存在" >&2
        exit 2
    fi
    process_file "$2"
    exit 0
fi

if [ "$#" -ge 1 ] && [ "$#" -le 3 ]; then
    url="${1:-}"
    out="${2:-}"
    target="${3:-}"
    
    if [ -z "$out" ]; then
        clean_url="${url%%\?*}"
        out="$(basename "$clean_url")"
    fi
    if [ -z "$target" ]; then
        target="$DEFAULT_BASE_PATH"
    fi
    download_model "$url" "$out" "$target"
    exit $?
fi

echo "ERROR: 参数无效" >&2
exit 2