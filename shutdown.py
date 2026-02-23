import os
import subprocess
import datetime
import logging

# 配置日志格式
logging.basicConfig(level=logging.INFO, format='%(message)s')
logger = logging.getLogger("sync_engine")

# 路径常量
ENV_REPO_DIR = "/root/autodl-tmp/comfyui-autodl-env"
PYTHON_BIN = "python" 

def run_cmd(cmd, cwd=None):
    """安全执行 shell 指令"""
    try:
        subprocess.run(cmd, cwd=cwd, check=True, capture_output=True, text=True)
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"失败: {' '.join(cmd)}\n{e.stderr.strip()}")
        return False

def main():
    logger.info("\n" + "="*40)
    logger.info(">>> 开始执行环境快照同步...")
    logger.info("="*40)

    # 1. 调用现有的插件同步逻辑
    # 这会运行 setup_nodes.py 中的扫描逻辑，更新 custom_nodes.txt
    setup_nodes = os.path.join(ENV_REPO_DIR, "setup_nodes.py")
    if os.path.exists(setup_nodes):
        logger.info("Step 1: 正在扫描并刷新插件清单...")
        # 内部逻辑会处理 Git Stash 等安全操作
        run_cmd([PYTHON_BIN, setup_nodes, "--sync"])

    # 2. 执行 Git 推送
    os.chdir(ENV_REPO_DIR)
    
    # 检测变动（含 workflows/*.json, custom_nodes.txt, comfy.settings.json）
    status = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True).stdout.strip()
    
    if not status:
        logger.info(">>> [SKIP] 检测到环境无任何变动，无需同步。")
        return

    logger.info("Step 2: 检测到环境变更，准备推送至远程仓库...")
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    commit_msg = f"chore: sync snapshot at {timestamp}"

    # 提交序列
    if run_cmd(["git", "add", "."]):
        if run_cmd(["git", "commit", "-m", commit_msg]):
            logger.info(f"正在推送变更 (Commit: {commit_msg})...")
            # 注意：此处依赖环境变量中的学术加速
            if run_cmd(["git", "push"]):
                logger.info("✅ [SUCCESS] 云端同步完成！您可以安全关闭机器了。")
            else:
                logger.error("❌ [ERROR] Push 失败，请检查网络或 SSH 权限。")
        else:
            logger.error("❌ [ERROR] Commit 失败。")

if __name__ == "__main__":
    main()