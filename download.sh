
#!/bin/bash

set -euo pipefail

# download.sh - 模型下载工具（基于 aria2c），支持单文件与批量清单。
#
# 简要说明（中文）：
#  - 单文件下载：
#      ./download.sh <url> <out_file> <target_dir>
#    例：
#      ./download.sh "https://.../model.safetensors" model.safetensors /root/autodl-tmp/shared_models/checkpoints
#
#  - 批量下载（清单文件）：
#      ./download.sh -f models.txt
#    清单格式（每行）：
#      url|filename|target_dir
#    或用空格分隔：
#      url filename target_dir
#    支持以 '#' 开头的注释行。
#
# 配置项（可以通过环境变量覆盖）：
#  - DOWNLOAD_THREADS (默认 16)：aria2 的 -x 参数（线程）
#  - DOWNLOAD_CONNS   (默认 16)：aria2 的 -s 参数（连接数）
#  - DOWNLOAD_CHUNK   (默认 1M)：aria2 的 -k 参数（分块大小）
#
# 使用建议：在有大型模型且支持多连接的网络环境下增大线程/连接数可加速下载；低带宽或受限环境请适当减小。

# 默认常量（可通过环境变量覆盖）
THREADS=${DOWNLOAD_THREADS:-16}
CONNS=${DOWNLOAD_CONNS:-16}
CHUNK=${DOWNLOAD_CHUNK:-1M}

ensure_aria2() {
    if ! command -v aria2c >/dev/null 2>&1; then
        echo "ERROR: 未检测到 aria2c，请先安装 (例如: apt-get install -y aria2)" >&2
        exit 1
    fi
}

download_model() {
    local url="$1"
    local out_file="$2"
    local target_dir="$3"

    mkdir -p "$target_dir"

    if [ ! -f "$target_dir/$out_file" ]; then
        echo "--> 正在高速下载: $out_file"
        aria2c -x "$THREADS" -s "$CONNS" -k "$CHUNK" -d "$target_dir" -o "$out_file" "$url"
        ret=$?
        if [ $ret -ne 0 ]; then
            echo "ERROR: aria2c 失败，退出码 $ret" >&2
            return $ret
        fi
    else
        echo "--> 模型已就绪: $out_file，跳过下载。"
    fi
}

process_file() {
    local file="$1"
    while IFS= read -r line || [ -n "$line" ]; do
        line="$(echo "$line" | sed 's/^\s*//;s/\s*$//')"
        [ -z "$line" ] && continue
        case "$line" in
            \#*) continue ;;
        esac
        #支持 | 分隔或空格分隔
        if echo "$line" | grep -q "|"; then
            IFS='|' read -r url out target <<< "$line"
        else
            # split by whitespace into 3 parts
            read -r url out target <<< "$line"
        fi
        if [ -z "$target" ] || [ -z "$out" ] || [ -z "$url" ]; then
            echo "WARN: invalid line: $line" >&2
            continue
        fi
        download_model "$url" "$out" "$target"
    done < "$file"
}

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <url> <out_file> <target_dir>  OR  $0 -f models.txt" >&2
    exit 2
fi

ensure_aria2

if [ "$1" = "-f" ]; then
    if [ -z "${2-}" ] || [ ! -f "$2" ]; then
        echo "ERROR: missing or non-existent list file" >&2
        exit 2
    fi
    process_file "$2"
    exit 0
fi

# single download
if [ "$#" -ne 3 ]; then
    echo "ERROR: expected 3 arguments for single download" >&2
    echo "Usage: $0 <url> <out_file> <target_dir>" >&2
    exit 2
fi

download_model "$1" "$2" "$3"
