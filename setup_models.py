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
        logger.info(f"创建物理目录: {p}")
    # 强制设置 755 权限，解决浏览器点不进去的问题
    os.chmod(p, 0o755)

def safe_link(src, dst):
    """安全地建立软链接，永不覆盖真实模型文件"""
    src_p = pathlib.Path(src)
    dst_p = pathlib.Path(dst)
    
    if src_p.exists() and not dst_p.exists():
        dst_p.symlink_to(src_p)
        logger.info(f"逻辑映射: {src_p.name} -> {dst_p.parent.name}/")

def sync_models(yaml_path):
    if not os.path.exists(yaml_path):
        logger.warning(f"未找到配置文件: {yaml_path}")
        return

    try:
        with open(yaml_path, 'r') as f:
            config = yaml.safe_load(f)
        if not config: return

        for section, details in config.items():
            base_path = os.path.expanduser(details.get('base_path', ''))
            if not base_path: continue
            
            ensure_dir(base_path)

            # 1. 初始化 YAML 中定义的所有目录
            for key, folder in details.items():
                if key == 'base_path' or not isinstance(folder, str):
                    continue
                ensure_dir(os.path.join(base_path, folder.strip('/')))

            # 2. 自动分类补全 (解决 GUI 找不到模型的问题)
            ckpt_dir = pathlib.Path(base_path) / "checkpoints"
            unet_dir = pathlib.Path(base_path) / "unet"
            
            if ckpt_dir.exists() and unet_dir.exists():
                for model_file in ckpt_dir.glob("*.safetensors"):
                    name_lower = model_file.name.lower()
                    # 针对 Flux 或扩散模型自动建立 unet 链接
                    if "flux" in name_lower or "diffusion" in name_lower:
                        safe_link(model_file, unet_dir / model_file.name)

    except Exception as e:
        logger.error(f"模型同步异常: {e}")

if __name__ == "__main__":
    env_yaml = os.getenv("YAML_PATH", "/root/autodl-tmp/comfyui-autodl-env/extra_model_paths.yaml")
    sync_models(env_yaml)