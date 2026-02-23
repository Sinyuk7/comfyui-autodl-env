import os
import shutil
import pathlib

# --- 配置区 ---
LOCAL_COMFY_ROOT = r"D:\ComfyUI_windows_portable\ComfyUI"
GIT_REPO_ROOT = r"."  # 你的 Git 仓库根目录

# 仅保留你确认需要的核心轻量级文件
SYNC_MAP = {
    "user/default/comfy.settings.json": "configs/user/comfy.settings.json",
    "user/default/comfy.shortcuts.json": "configs/user/comfy.shortcuts.json",
    "user/__manager/config.ini": "configs/manager/config.ini",
    "user/__manager/channels.list": "configs/manager/channels.list",
}

def sync_essentials():
    print(f">>> 开始提取核心配置文件...")
    git_base = pathlib.Path(GIT_REPO_ROOT)
    
    for rel_path, git_rel_path in SYNC_MAP.items():
        src = pathlib.Path(LOCAL_COMFY_ROOT) / rel_path
        dst = git_base / git_rel_path
        
        if src.exists():
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            print(f"    [OK] 已提取: {rel_path}")
        else:
            print(f"    [SKIP] 未找到文件: {rel_path}")

if __name__ == "__main__":
    sync_essentials()