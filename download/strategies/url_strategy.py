# download/strategies/url_strategy.py
import os
import subprocess
from pathlib import Path
from .base import DownloadStrategy, logger

class UrlStrategy(DownloadStrategy):
    def pre_check(self) -> bool:
        default_name = self.source.split('/')[-1].split('?')[0]
        # 统一的重命名解析逻辑
        self.final_name = self.kwargs.get('rename') or self.kwargs.get('name') or default_name
            
        target_file = Path(self.target_dir) / self.final_name
        aria_file = Path(self.target_dir) / f"{self.final_name}.aria2"
        
        if target_file.exists() and not aria_file.exists():
            return True
        return False

    def _do_download(self) -> bool:
        os.makedirs(self.target_dir, exist_ok=True)
        logger.info(f"    [URL] 启动 Aria2 下载: {self.final_name}")
        
        cmd = [
            "aria2c", "-c", "-x", "16", "-s", "16", "-k", "1M",
            "--console-log-level=error", "--summary-interval=10",
            "-d", self.target_dir, "-o", self.final_name, self.source
        ]
        
        subprocess.run(cmd, check=True)
        return True

    def cleanup(self) -> None:
        if hasattr(self, 'final_name'):
            aria_file = Path(self.target_dir) / f"{self.final_name}.aria2"
            if aria_file.exists():
                logger.info(f"    [CLEANUP] 移除中断的进度文件: {aria_file.name}")
                aria_file.unlink()