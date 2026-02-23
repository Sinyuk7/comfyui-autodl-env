#!/usr/bin/env python3
# download/download_manager.py
import os
import yaml
import argparse

# ==========================================
# 环境变量预设：必须在导入任何 HF 库前注入
# ==========================================
os.environ["HF_HUB_ENABLE_HF_TRANSFER"] = "1"
os.environ["HF_HUB_DISABLE_PROGRESS_BARS"] = "0"

from strategies.url_strategy import UrlStrategy
from strategies.hf_strategy import HfStrategy

# ==========================================
# 基础路径配置
# ==========================================
ENV_REPO_DIR = os.getenv("ENV_REPO_DIR", "/root/autodl-tmp/comfyui-autodl-env")
EXTRA_MODEL_PATHS = os.path.join(ENV_REPO_DIR, "extra_model_paths.yaml")
PRESETS_FILE = os.path.join(ENV_REPO_DIR, "model_presets.yaml")

# 策略路由注册表
STRATEGY_MAP = {
    'url': UrlStrategy(),
    'hf': HfStrategy(),
    'hf_snapshot': HfStrategy()
}

def get_target_path(target_key: str) -> str:
    """解析 extra_model_paths.yaml 获取物理目录"""
    try:
        with open(EXTRA_MODEL_PATHS, 'r') as f:
            paths = yaml.safe_load(f)
        base = paths['autodl_shared']['base_path']
        folder = paths['autodl_shared'].get(target_key, "checkpoints")
        return os.path.join(base, str(folder).strip('/'))
    except Exception as e:
        print(f"    [WARN] 解析路径映射失败，回退至默认路径: {e}")
        return f"/root/autodl-tmp/shared_models/{target_key}"

def run_preset(preset_name: str):
    """解析 YAML 预设并分发任务给具体的 Strategy"""
    if not os.path.exists(PRESETS_FILE):
        print(f"ERROR: 找不到预设清单文件 {PRESETS_FILE}")
        return

    with open(PRESETS_FILE, 'r') as f:
        all_presets = yaml.safe_load(f).get('presets', {})
    
    items = all_presets.get(preset_name)
    if not items:
        print(f"ERROR: 未定义预设 '{preset_name}'")
        return

    print(f">>> 启动预设装配: {preset_name}")

    for item in items:
        target_dir = get_target_path(item.get('target', 'checkpoints'))
        dl_type = item.get('type', 'url')
        
        # 获取对应策略，默认回退到 url 策略
        strategy = STRATEGY_MAP.get(dl_type, STRATEGY_MAP['url'])
        
        # 触发完整生命周期
        # 避免重复传入 'source'（来自 item 和显式参数）导致的 TypeError
        call_kwargs = dict(item)
        call_kwargs.pop('source', None)
        strategy.execute(
            source=item['source'],
            target_dir=target_dir,
            **call_kwargs
        )
            
    print(f">>> 预设 {preset_name} 执行完毕。")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="AutoDL 满血版模型下载管理器 (策略模式版)")
    
    # 模式 A: 预设批量下载
    parser.add_argument("--preset", help="运行 model_presets.yaml 中定义的预设组")
    
    # 模式 B: 单点手动下载
    parser.add_argument("--hf", nargs=2, metavar=('REPO', 'FILE'), help="下载 HF 单文件，例: --hf xinsir/controlnet model.safetensors")
    parser.add_argument("--snapshot", metavar='REPO', help="下载整个 HF 仓库快照")
    parser.add_argument("--url", nargs=1, metavar='URL', help="使用 Aria2c 下载直链")
    
    # 全局参数
    parser.add_argument("--target", default="checkpoints", help="目标目录在 YAML 中的映射名 (默认: checkpoints)")
    parser.add_argument("--allow", nargs='+', help="快照模式下的白名单过滤 (例: *.safetensors)")

    args = parser.parse_args()

    if args.preset:
        run_preset(args.preset)
    elif args.hf:
        STRATEGY_MAP['hf'].execute(source=args.hf[0], target_dir=get_target_path(args.target), type='hf', file=args.hf[1])
    elif args.snapshot:
        STRATEGY_MAP['hf_snapshot'].execute(source=args.snapshot, target_dir=get_target_path(args.target), type='hf_snapshot', allow_patterns=args.allow)
    elif args.url:
        STRATEGY_MAP['url'].execute(source=args.url[0], target_dir=get_target_path(args.target), type='url')
    else:
        parser.print_help()