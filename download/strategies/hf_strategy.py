# download/strategies/hf_strategy.py
import os
import shutil
from pathlib import Path
from .base import DownloadStrategy, logger
from huggingface_hub import hf_hub_download, snapshot_download

class HfStrategy(DownloadStrategy):
    def _clear_locks(self):
        """清理 HF 锁文件，防止死锁"""
        hf_home = os.getenv("HF_HOME", "/root/autodl-tmp/.cache/huggingface")
        lock_dir = Path(hf_home) / "hub" / ".locks"
        if lock_dir.exists():
            shutil.rmtree(lock_dir, ignore_errors=True)

    def pre_check(self) -> bool:
        self._clear_locks()
        dl_type = self.kwargs.get('type', 'hf')
        
        if dl_type == 'hf' and self.filename:
            # 核心逻辑：优先使用 rename 字段，其次是 name，最后回退到原文件名
            self.final_name = self.kwargs.get('rename') or self.kwargs.get('name') or os.path.basename(self.filename)
            target_file = Path(self.target_dir) / self.final_name
            return target_file.exists()
            
        return False

    def _do_download(self) -> bool:
        dl_type = self.kwargs.get('type', 'hf')
        os.makedirs(self.target_dir, exist_ok=True)

        if dl_type == 'hf_snapshot':
            allow = self.kwargs.get('allow_patterns')
            ignore = self.kwargs.get('ignore_patterns')
            logger.info(f"    [HF-REPO] 同步快照: {self.source}")
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
            logger.info(f"    [HF-FILE] 同步: {self.source}/{self.filename} -> {self.final_name}")
            # 第一步：让 HF API 按它的规矩下载并验证
            returned_path = hf_hub_download(
                repo_id=self.source,
                filename=self.filename,
                local_dir=self.target_dir,
                local_dir_use_symlinks=False,
                resume_download=True
            )
            
            final_path = os.path.join(self.target_dir, self.final_name)
            
            # 第二步：如果发现路径或名称不一致，执行移动/重命名
            if os.path.abspath(returned_path) != os.path.abspath(final_path):
                shutil.move(returned_path, final_path)
                logger.info(f"    [RENAME] 已重命名并展平路径至: {self.final_name}")
                
                # 第三步：清理 HF 遗留的空子目录 (例如 target_dir/vae/)
                parent_dir = os.path.dirname(returned_path)
                while os.path.abspath(parent_dir) != os.path.abspath(self.target_dir):
                    try:
                        os.rmdir(parent_dir)  # 只有空目录才能被删掉
                        parent_dir = os.path.dirname(parent_dir)
                    except OSError:
                        break  # 如果目录里还有其他文件，或者已经到顶了，就停止
        return True

    def cleanup(self) -> None:
        self._clear_locks()