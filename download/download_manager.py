#!/usr/bin/env python3
import os
import subprocess
import yaml
import argparse
from pathlib import Path

# 环境配置
ENV_REPO_DIR = os.getenv("ENV_REPO_DIR", "/root/autodl-tmp/comfyui-autodl-env")
EXTRA_MODEL_PATHS = os.path.join(ENV_REPO_DIR, "extra_model_paths.yaml")
PRESETS_FILE = os.path.join(ENV_REPO_DIR, "model_presets.yaml")

def get_target_path(target_key):
    """根据 YAML 映射获取物理下载目录"""
    with open(EXTRA_MODEL_PATHS, 'r') as f:
        paths = yaml.safe_load(f)
    # 假设映射结构为 autodl_shared -> base_path
    base = paths['autodl_shared']['base_path']
    folder = paths['autodl_shared'].get(target_key, "checkpoints")
    return os.path.join(base, folder.strip('/'))

def download_url(url, filename, target_dir):
    """使用 aria2c 下载通用 URL"""
    os.makedirs(target_dir, exist_ok=True)
    target_file = os.path.join(target_dir, filename)
    if os.path.exists(target_file):
        print(f"    [SKIP] 文件已存在: {filename}")
        return
    
    print(f"    [URL] 正在下载: {filename} ...")
    # 使用 16 线程加速
    cmd = [
        "aria2c", "-c", "-x", "16", "-s", "16", "-k", "1M",
        "-d", target_dir, "-o", filename, url
    ]
    subprocess.run(cmd, check=True)

def download_hf(repo, filename, target_dir):
    """使用 hf-cli 下载并清理缓存"""
    os.makedirs(target_dir, exist_ok=True)
    target_file = os.path.join(target_dir, filename)
    if os.path.exists(target_file):
        print(f"    [SKIP] 模型已存在: {filename}")
        return

    print(f"    [HF] 正在从 {repo} 同步: {filename} ...")
    # 强制启用满血传输环境
    env = os.environ.copy()
    env["HF_HUB_ENABLE_HF_TRANSFER"] = "1"
    
    cmd = [
        "hf", "download", repo, filename,
        "--local-dir", target_dir,
        "--local-dir-use-symlinks", "False"
    ]
    subprocess.run(cmd, env=env, check=True)
    
    # 自动化空间回收逻辑
    print(f"    [CLEAN] 正在回收 HF 缓存...")
    subprocess.run(["hf", "cache", "rm", f"model/{repo}", "--yes"], capture_output=True)

def run_preset(preset_name):
    """一键装配预设组合"""
    if not os.path.exists(PRESETS_FILE):
        print(f"错误: 找不到预设文件 {PRESETS_FILE}")
        return

    with open(PRESETS_FILE, 'r') as f:
        all_presets = yaml.safe_load(f).get('presets', {})
    
    items = all_presets.get(preset_name)
    if not items:
        print(f"错误: 未定义预设 '{preset_name}'")
        return

    print(f">>> 正在执行预设装配: {preset_name}")
    for item in items:
        try:
            target_dir = get_target_path(item['target'])
            if item['type'] == 'hf':
                download_hf(item['source'], item['file'], target_dir)
            else:
                download_url(item['source'], item['file'], target_dir)
        except Exception as e:
            print(f"    [ERROR] 下载 {item.get('name')} 失败: {e}")
            
    print(f">>> 预设 {preset_name} 执行完毕。")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="AutoDL 通用下载管理器")
    parser.add_argument("--preset", help="要运行的模型预设名称")
    args = parser.parse_args()

    if args.preset:
        run_preset(args.preset)
    else:
        parser.print_help()