#!/usr/bin/env python3
import os
import subprocess
import pathlib
import argparse
import logging
import re

# ==========================================
# 视觉与日志配置
# ==========================================
class Colors:
    BLUE = '\033[94m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    RESET = '\033[0m'
    BOLD = '\033[1m'

logging.basicConfig(level=logging.INFO, format='%(message)s')
logger = logging.getLogger("node_setup")

def log_info(msg): logger.info(f"{Colors.BLUE}ℹ [INFO]{Colors.RESET} {msg}")
def log_success(msg): logger.info(f"{Colors.GREEN}✔ [SUCCESS]{Colors.RESET} {msg}")
def log_warn(msg): logger.warning(f"{Colors.YELLOW}⚠ [WARN]{Colors.RESET} {msg}")
def log_error(msg): logger.error(f"{Colors.RED}✖ [ERROR]{Colors.RESET} {msg}")
def log_title(msg): logger.info(f"\n{Colors.BOLD}{Colors.BLUE}=== {msg} ==={Colors.RESET}")

# ==========================================
# 核心工具函数
# ==========================================
def parse_repo_url(line):
    """解析并校验 Git 链接，兼容 SSH 与 HTTPS"""
    url = line.strip()
    if not url or url.startswith("#"):
        return None, None
    
    # 严格限定支持的协议前缀
    if not re.match(r'^(https?://|git@)', url):
        log_warn(f"跳过非法的 Git 链接 (仅支持 http/https/ssh): {url}")
        return None, None
        
    # 兼容 ssh(user@host:repo) 和 https(host/repo)
    raw_name = re.split(r'[/:]', url)[-1]
    repo_name = raw_name.replace('.git', '')
    
    if not repo_name:
        log_warn(f"无法解析仓库名称，已跳过: {url}")
        return None, None
        
    return url, repo_name

def run_cmd(cmd, cwd=None, check=True, quiet=False):
    """通用的安全指令执行包装器"""
    try:
        res = subprocess.run(cmd, cwd=cwd, check=check, capture_output=True, text=True)
        return True, res.stdout.strip()
    except subprocess.CalledProcessError as e:
        if not quiet:
            log_error(f"指令执行失败: {' '.join(cmd)}\n目录: {cwd}\n错误: {e.stderr.strip()}")
        return False, e.stderr.strip()

def get_git_remote(repo_path):
    """获取 Git 仓库的远程地址"""
    success, output = run_cmd(["git", "remote", "get-url", "origin"], cwd=repo_path, quiet=True)
    return output if success else None

def safe_git_pull(repo_path, repo_name):
    """执行严谨的节点仓库更新: Status -> Stash -> Pull -> Pop"""
    success, status = run_cmd(["git", "status", "--porcelain"], cwd=repo_path)
    is_dirty = bool(status.strip())

    if is_dirty:
        log_warn(f"[{repo_name}] 发现未提交的修改，正在暂存 (Stash)...")
        run_cmd(["git", "stash", "push", "-m", "auto-update-stash"], cwd=repo_path)

    log_info(f"[{repo_name}] 正在拉取远程更新...")
    pull_success, pull_out = run_cmd(["git", "pull", "--rebase"], cwd=repo_path, check=False, quiet=True)

    if not pull_success:
        log_error(f"[{repo_name}] 更新失败，触发回滚。日志: {pull_out}")
        run_cmd(["git", "rebase", "--abort"], cwd=repo_path, check=False, quiet=True)
    else:
        log_success(f"[{repo_name}] 更新完成。")

    if is_dirty:
        log_info(f"[{repo_name}] 正在恢复本地修改 (Stash Pop)...")
        pop_success, pop_out = run_cmd(["git", "stash", "pop"], cwd=repo_path, check=False, quiet=True)
        if not pop_success:
            log_warn(f"[{repo_name}] 恢复时可能产生冲突，请进入该目录手动解决。")

# ==========================================
# 业务逻辑路由
# ==========================================
def cmd_init(nodes_dir, nodes_list_file, python_bin):
    """指令: 根据 custom_nodes.txt 首次克隆并初始化插件"""
    log_title("初始化自定义节点生态")
    nodes_dir.mkdir(parents=True, exist_ok=True)

    # 1. 强制安装基础 Manager
    manager_path = nodes_dir / "ComfyUI-Manager"
    if not manager_path.exists():
        log_info("正在装配核心底座: ComfyUI-Manager...")
        run_cmd(["git", "clone", "https://github.com/ltdrdata/ComfyUI-Manager.git"], cwd=nodes_dir)
        log_success("ComfyUI-Manager 安装就绪。")

    if not nodes_list_file.exists():
        log_warn(f"清单文件缺失: {nodes_list_file}，跳过批量装配。")
        return

    # 2. 批量拉取与依赖注入
    with open(nodes_list_file, "r") as f:
        for line in f:
            url, repo_name = parse_repo_url(line)
            if not url: continue
            
            repo_path = nodes_dir / repo_name
            
            if not repo_path.exists():
                log_info(f"拉取新插件: {repo_name} ...")
                if run_cmd(["git", "clone", url], cwd=nodes_dir)[0]:
                    req_file = repo_path / "requirements.txt"
                    if req_file.exists():
                        log_info(f"正在为 {repo_name} 构建 Python 依赖...")
                        run_cmd([python_bin, "-m", "pip", "install", "-r", str(req_file)])
                    log_success(f"插件 {repo_name} 装配成功。")
            else:
                log_info(f"插件已存在，跳过: {repo_name}")

def cmd_update(nodes_dir):
    """指令: 安全更新本地所有的自定义节点"""
    log_title("执行节点安全更新策略")
    if not nodes_dir.exists():
        log_error("Custom nodes 目录不存在！")
        return

    for item in nodes_dir.iterdir():
        if item.is_dir() and (item / ".git").exists():
            safe_git_pull(item, item.name)

def cmd_sync(nodes_dir, env_repo_dir, nodes_list_file):
    """指令: 扫描本地节点 -> 更新配置 -> 严谨提交至 Git"""
    log_title("执行环境清单双向同步")
    
    log_info("正在扫描物理目录内的 Git 仓库...")
    repo_urls = []
    for item in nodes_dir.iterdir():
        if item.is_dir() and (item / ".git").exists():
            url = get_git_remote(item)
            if url: repo_urls.append(url)
            
    if not repo_urls:
        log_warn("未发现任何节点 Git 仓库，同步中止。")
        return

    repo_urls.sort(key=str.lower)

    log_info("开始环境仓库的版本控制同步...")
    _, status = run_cmd(["git", "status", "--porcelain"], cwd=env_repo_dir)
    is_dirty = bool(status.strip())

    try:
        # A: 暂存本地不可预知的更改
        if is_dirty:
            log_info("-> 保护环境仓库现场 (Stash)...")
            run_cmd(["git", "stash", "push", "-m", "auto-sync-guard"], cwd=env_repo_dir)

        # B: 与远程基线对齐
        log_info("-> 同步远程环境基线 (Pull Rebase)...")
        run_cmd(["git", "pull", "--rebase"], cwd=env_repo_dir)

        # C: 覆写配置文件
        log_info("-> 刷新 custom_nodes.txt 物理文件...")
        with open(nodes_list_file, "w", encoding="utf-8") as f:
            f.write("# AutoDL ComfyUI 自动生成的插件快照\n")
            for url in repo_urls:
                f.write(f"{url}\n")

        # D: 分析 Diff 并提交
        run_cmd(["git", "add", "custom_nodes.txt"], cwd=env_repo_dir)
        diff_success, _ = run_cmd(["git", "diff", "--staged", "--quiet"], cwd=env_repo_dir, check=False)
        
        if not diff_success:
            log_info("-> 检测到节点架构变更，正在提交与推送...")
            run_cmd(["git", "commit", "-m", "chore: sync custom_nodes.txt via AutoDL script"], cwd=env_repo_dir)
            run_cmd(["git", "push"], cwd=env_repo_dir)
            log_success("云端环境快照已更新！")
        else:
            log_success("本地节点架构与云端一致，无需提交。")

    finally:
        # E: 恢复用户的开发现场
        if is_dirty:
            log_info("-> 恢复环境仓库现场 (Stash Pop)...")
            run_cmd(["git", "stash", "pop"], cwd=env_repo_dir, check=False, quiet=True)

# ==========================================
# 调度入口
# ==========================================
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="ComfyUI 自定义节点管理引擎 (AutoDL 专版)")
    parser.add_argument("--init", action="store_true", help="模式: 依据清单初始化插件生态")
    parser.add_argument("--update", action="store_true", help="模式: 批量安全拉取本地插件的更新")
    parser.add_argument("--sync", action="store_true", help="模式: 扫描本地插件并上传同步至 Git 环境仓库")
    
    args = parser.parse_args()

    COMFY_DIR = os.getenv("COMFYUI_DIR", "/root/autodl-tmp/ComfyUI")
    ENV_REPO_DIR = os.getenv("ENV_REPO_DIR", "/root/autodl-tmp/comfyui-autodl-env")
    PYTHON_BIN = os.getenv("PYTHON_BIN", "python")
    
    NODES_DIR = pathlib.Path(COMFY_DIR) / "custom_nodes"
    NODES_LIST_FILE = pathlib.Path(ENV_REPO_DIR) / "custom_nodes.txt"

    if args.init:
        cmd_init(NODES_DIR, NODES_LIST_FILE, PYTHON_BIN)
    elif args.update:
        cmd_update(NODES_DIR)
    elif args.sync:
        cmd_sync(NODES_DIR, ENV_REPO_DIR, NODES_LIST_FILE)
    else:
        parser.print_help()