#!/usr/bin/env python3
import os
import subprocess
import pathlib
import logging

logging.basicConfig(level=logging.INFO, format='    %(levelname)s: %(message)s')
logger = logging.getLogger("node_setup")

def run_command(cmd, cwd=None):
    try:
        subprocess.run(cmd, cwd=cwd, check=True, capture_output=True, text=True)
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"执行失败: {' '.join(cmd)} | 错误: {e.stderr}")
        return False

def setup_custom_nodes():
    # 从环境变量获取路径
    comfy_dir = os.getenv("COMFYUI_DIR", "/root/autodl-tmp/ComfyUI")
    env_repo_dir = os.getenv("ENV_REPO_DIR", "/root/autodl-tmp/comfyui-autodl-env")
    python_bin = os.getenv("PYTHON_BIN", "python")
    
    nodes_dir = pathlib.Path(comfy_dir) / "custom_nodes"
    nodes_list_file = pathlib.Path(env_repo_dir) / "custom_nodes.txt"
    
    nodes_dir.mkdir(parents=True, exist_ok=True)

    # 1. 优先安装 Manager
    manager_path = nodes_dir / "ComfyUI-Manager"
    if not manager_path.exists():
        logger.info("正在克隆 ComfyUI-Manager...")
        run_command(["git", "clone", "https://github.com/ltdrdata/ComfyUI-Manager.git"], cwd=nodes_dir)

    # 2. 批量处理 custom_nodes.txt
    if not nodes_list_file.exists():
        logger.warning("未发现 custom_nodes.txt，跳过自定义插件同步。")
        return

    with open(nodes_list_file, "r") as f:
        for line in f:
            url = line.strip()
            if not url or url.startswith("#"):
                continue
            
            repo_name = url.split("/")[-1].replace(".git", "")
            repo_path = nodes_dir / repo_name
            
            if not repo_path.exists():
                logger.info(f"正在拉取插件: {repo_name}")
                if run_command(["git", "clone", url], cwd=nodes_dir):
                    # 自动安装依赖
                    req_file = repo_path / "requirements.txt"
                    if req_file.exists():
                        logger.info(f"正在安装 {repo_name} 的依赖...")
                        run_command([python_bin, "-m", "pip", "install", "-r", str(req_file)])
            else:
                logger.info(f"插件 {repo_name} 已存在，跳过。")

if __name__ == "__main__":
    setup_custom_nodes()