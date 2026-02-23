import os
import subprocess

# 本地路径
NODE_PATH = r"D:\ComfyUI_windows_portable\ComfyUI\custom_nodes"
OUTPUT_FILE = "custom_nodes.txt"

def get_git_remote(repo_path):
    try:
        # 使用 git 指令获取远程仓库地址
        result = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            cwd=repo_path,
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except Exception:
        return None

def scan_nodes():
    nodes_found = []
    print(f"正在扫描: {NODE_PATH}")
    
    for item in os.listdir(NODE_PATH):
        full_path = os.path.join(NODE_PATH, item)
        if os.path.isdir(full_path):
            # 检查是否存在 .git 目录
            if os.path.exists(os.path.join(full_path, ".git")):
                url = get_git_remote(full_path)
                if url:
                    nodes_found.append(url)
                    print(f"找到仓库: {item} -> {url}")

    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write("# 本地扫描生成的插件清单\n")
        for url in nodes_found:
            f.write(f"{url}\n")
    
    print(f"\n扫描完成！请将 {OUTPUT_FILE} 上传到你的 Git 仓库中。")

if __name__ == "__main__":
    scan_nodes()