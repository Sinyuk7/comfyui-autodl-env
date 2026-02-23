# download/strategies/hf_strategy.py
import os
import shutil
from pathlib import Path
from .base import DownloadStrategy, logger
from huggingface_hub import hf_hub_download, snapshot_download

class HfStrategy(DownloadStrategy):
    def _clear_locks(self):
        """清理 HF 锁文件，防止 AutoDL 实例强杀导致的死锁"""
        hf_home = os.getenv("HF_HOME", "/root/autodl-tmp/.cache/huggingface")
        lock_dir = Path(hf_home) / "hub" / ".locks"
        if lock_dir.exists():
            logger.info("    [CLEANUP] 检测到 HF 锁文件残留，正在重置锁状态...")
            shutil.rmtree(lock_dir, ignore_errors=True)

    def pre_check(self) -> bool:
        """下载前强制进行一次锁状态巡检"""
        self._clear_locks()
        
        # 针对单文件的快速存在性校验
        if self.kwargs.get('type') == 'hf' and self.filename:
            target_file = Path(self.target_dir) / self.filename
            return target_file.exists()
            
        # 快照模式交由 HF API 内部机制进行断点续传检查
        return False

    def _do_download(self) -> bool:
        dl_type = self.kwargs.get('type', 'hf')
        os.makedirs(self.target_dir, exist_ok=True)

        if dl_type == 'hf_snapshot':
            allow = self.kwargs.get('allow_patterns')
            ignore = self.kwargs.get('ignore_patterns')
            logger.info(f"    [HF-REPO] 同步快照: {self.source} (规则: {allow})")
            
            snapshot_download(
                repo_id=self.source,
                local_dir=self.target_dir,
                local_dir_use_symlinks=False,
                allow_patterns=allow,
                ignore_patterns=ignore,
                resume_download=True,
                max_workers=16
            )
        else:
            if not self.filename:
                logger.error("    [ERROR] HF 单文件模式需指定 file 参数。")
                return False
                
            logger.info(f"    [HF-FILE] 同步文件: {self.source} -> {self.filename}")
            hf_hub_download(
                repo_id=self.source,
                filename=self.filename,
                local_dir=self.target_dir,
                local_dir_use_symlinks=False,
                resume_download=True
            )
        return True

    def cleanup(self) -> None:
        """异常发生时释放可能残留的锁"""
        self._clear_locks()