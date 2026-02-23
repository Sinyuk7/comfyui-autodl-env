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
            # 【修复 1】严格移除 name 的干扰。优先用 rename，否则取原文件名。
            self.final_name = self.kwargs.get('rename') or os.path.basename(self.filename)
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
            
            # 【修复 2】移除已被 HF 弃用的参数 (resume_download, local_dir_use_symlinks)
            snapshot_download(
                repo_id=self.source,
                local_dir=self.target_dir,
                allow_patterns=allow,
                ignore_patterns=ignore,
                max_workers=16
            )
        else:
            logger.info(f"    [HF-FILE] 同步: {self.source}/{self.filename} -> {self.final_name}")
            
            returned_path = hf_hub_download(
                repo_id=self.source,
                filename=self.filename,
                local_dir=self.target_dir
            )
            
            final_path = os.path.join(self.target_dir, self.final_name)
            
            # 【修复 3】下载完成后的展平与重命名逻辑
            if os.path.abspath(returned_path) != os.path.abspath(final_path):
                shutil.move(returned_path, final_path)
                logger.info(f"    [FLATTEN] 已展平嵌套目录并重命名至: {self.final_name}")
                
                # 递归向上清理由于 HF API 强制产生的空文件夹
                parent_dir = os.path.dirname(returned_path)
                while os.path.abspath(parent_dir) != os.path.abspath(self.target_dir):
                    try:
                        os.rmdir(parent_dir)
                        parent_dir = os.path.dirname(parent_dir)
                    except OSError:
                        break # 目录不为空或权限受限则停止
        return True

    def cleanup(self) -> None:
        """异常中断时的清理逻辑"""
        self._clear_locks()
        
        # 【修复 4】如果你中途 Ctrl+C 强杀了，顺手清理掉 HF 产生的临时嵌套空目录
        if self.kwargs.get('type') == 'hf' and self.filename:
            # 找到 HF 创建的那个子目录第一层
            first_sub_dir = self.filename.split('/')[0]
            nested_dir_path = os.path.join(self.target_dir, first_sub_dir)
            if os.path.exists(nested_dir_path) and os.path.isdir(nested_dir_path):
                try:
                    # 强杀清理（只清理目标相关的，避免误伤）
                    shutil.rmtree(nested_dir_path, ignore_errors=True)
                    logger.info("    [CLEANUP] 已清理中断残留的嵌套文件夹。")
                except:
                    pass