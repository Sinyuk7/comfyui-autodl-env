#!/bin/bash

# ==========================================
# setup_models.sh - 动态构建模型池目录结构
# ==========================================

set -euo pipefail

# 接收环境变量，若为空则使用默认值
ENV_REPO_DIR="${ENV_REPO_DIR:-/root/autodl-tmp/comfyui-autodl-env}"
PYTHON_BIN="${PYTHON_BIN:-python}"
YAML_PATH="$ENV_REPO_DIR/extra_model_paths.yaml"

if [ ! -f "$YAML_PATH" ]; then
    echo "    -> 未找到 $YAML_PATH，跳过模型目录构建。"
    exit 0
fi

# 动态解析 YAML 并创建目录
$PYTHON_BIN -c "
import yaml, os, sys
try:
    yaml_path = '$YAML_PATH'
    if os.path.getsize(yaml_path) > 0:
        with open(yaml_path, 'r') as f:
            data = yaml.safe_load(f)
        if data:
            for conf_name, conf_data in data.items():
                base = conf_data.get('base_path', '')
                if not base: continue
                # 1. 创建主节点目录
                os.makedirs(base, exist_ok=True)
                # 2. 遍历并创建所有子目录
                for k, v in conf_data.items():
                    if k == 'base_path' or not isinstance(v, str): continue
                    # 清理尾部斜杠
                    target = os.path.join(base, v.strip('/'))
                    os.makedirs(target, exist_ok=True)
            print('    -> 模型池目录架构初始化/校验完成')
except Exception as e:
    print(f'WARNING: 自动创建目录失败: {e}')
" || true