#!/usr/bin/env python3
import os
import yaml
import pathlib
import logging

# 配置日志
logging.basicConfig(level=logging.INFO, format='    %(levelname)s: %(message)s')
logger = logging.getLogger("model_setup")

def ensure_dir(path):
    """确保目录存在且权限正确"""
    p = pathlib.Path(path)
    if not p.exists():
        p.mkdir(parents=True, exist_ok=True)
        logger.info(f"创建目录: {p}")
    # 强制设置 755 权限，解决 GUI 点不进去的问题
    os.chmod(p, 0o755)

def safe_link(src, dst):
    """安全地建立软链接，不覆盖物理文件"""
    src_p = pathlib.Path(src)
    dst_p = pathlib.Path(dst)
    
    if src_p.exists() and not dst_p.exists():
        dst_p.symlink_to(src_p)
        logger.info(f"逻辑对齐: {src_p.name} -> {dst_p.parent.name}/")

def sync_models(yaml_path):
    if not os.path.exists(yaml_path):
        logger.warning(f"配置文件不存在: {yaml_path}")
        return

    try:
        with open(yaml_path, 'r') as f:
            config = yaml.safe_load(f)
        
        if not config:
            return

        for section, details in config.items():
            base_path = details.get('base_path')
            if not base_path:
                continue
            
            base_path = os.path.expanduser(base_path)
            ensure_dir(base_path)

            # 1. 创建所有子目录
            for key, folder in details.items():
                if key == 'base_path' or not isinstance(folder, str):
                    continue
                full_path = os.path.join(base_path, folder.strip('/'))
                ensure_dir(full_path)

            # 2. 自动分类对齐 (解决 Flux 下载后找不到模型的问题)
            ckpt_dir = pathlib.Path(base_path) / "checkpoints"
            unet_dir = pathlib.Path(base_path) / "unet"
            
            if ckpt_dir.exists() and unet_dir.exists():
                for model_file in ckpt_dir.glob("*.safetensors"):
                    # 如果文件名包含 flux 或 diffusion，自动链接到 unet 目录
                    name_lower = model_file.name.lower()
                    if "flux" in name_lower or "diffusion" in name_lower:
                        safe_link(model_file, unet_dir / model_file.name)

    except Exception as e:
        logger.error(f"执行失败: {e}")

if __name__ == "__main__":
    # 从环境变量读取 YAML 路径，或使用默认值
    env_yaml = os.getenv("YAML_PATH", "/root/autodl-tmp/comfyui-autodl-env/extra_model_paths.yaml")
    sync_models(env_yaml)