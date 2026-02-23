# download/strategies/url_strategy.py
import os
import subprocess
from pathlib import Path
from .base import DownloadStrategy, logger

class UrlStrategy(DownloadStrategy):
    def pre_check(self) -> bool:
        # 解析默认文件名
        if not self.filename:
            self.filename = self.source.split('/')[-1].split('?')[0]
            
        target_file = Path(self.target_dir) / self.filename
        aria_file = Path(self.target_dir) / f"{self.filename}.aria2"
        
        # 仅当实体文件存在且没有 aria2 临时文件时，才判断为已完成
        if target_file.exists() and not aria_file.exists():
            return True
        return False

    def _do_download(self) -> bool:
        os.makedirs(self.target_dir, exist_ok=True)
        logger.info(f"    [URL] 正在启动 Aria2 下载: {self.filename}")
        
        cmd = [
            "aria2c", "-c", "-x", "16", "-s", "16", "-k", "1M",
            "--console-log-level=error", "--summary-interval=10",
            "-d", self.target_dir, "-o", self.filename, self.source
        ]
        
        subprocess.run(cmd, check=True)
        return True

    def cleanup(self) -> None:
        """清理损坏的实体文件与 aria2 进度文件"""
        if not self.filename:
            return
            
        target_file = Path(self.target_dir) / self.filename
        aria_file = target_file.with_suffix(target_file.suffix + ".aria2")
        
        if aria_file.exists():
            logger.info(f"    [CLEANUP] 移除中断的进度文件: {aria_file.name}")
            aria_file.unlink()