import os
import subprocess
import datetime
import logging

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger("shutdown_sync")

# 路径配置
ENV_REPO_DIR = "/root/autodl-tmp/comfyui-autodl-env"
PYTHON_BIN = "python" # 或使用绝对路径

def run_cmd(cmd, cwd=None):
    try:
        # 继承当前环境变量（包含代理）
        subprocess.run(cmd, cwd=cwd, check=True, capture_output=True, text=True)
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"指令失败: {' '.join(cmd)}\n错误: {e.stderr.strip()}")
        return False

def main():
    logger.info(">>> 启动关机前环境状态同步...")

    # 1. 同步插件清单 (调用 setup_nodes.py)
    # 这会更新 custom_nodes.txt
    setup_nodes = os.path.join(ENV_REPO_DIR, "setup_nodes.py")
    if os.path.exists(setup_nodes):
        logger.info("Step 1: 扫描并更新插件清单...")
        # 注意：这里只运行 --sync 逻辑中的扫描部分，不直接在 setup_nodes 里 push
        # 我们由 shutdown.py 统一处理全库 push
        run_cmd([PYTHON_BIN, setup_nodes, "--sync"])

    # 2. Git 提交与推送
    os.chdir(ENV_REPO_DIR)
    
    # 检查是否有变动 (包括工作流、配置和插件清单)
    status = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True).stdout.strip()
    
    if not status:
        logger.info(">>> 检测到环境无变动，跳过同步。")
        return

    logger.info("Step 2: 发现变动，正在提交至云端...")
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    commit_msg = f"chore: auto-sync snapshot {timestamp}"

    # Git 序列
    if run_cmd(["git", "add", "."]):
        if run_cmd(["git", "commit", "-m", commit_msg]):
            logger.info("正在执行 Git Push (需学术加速)...")
            if run_cmd(["git", "push"]):
                logger.info(f"✅ 同步成功: {commit_msg}")
            else:
                logger.error("❌ Push 失败，请检查网络或 SSH 权限。")

if __name__ == "__main__":
    main()