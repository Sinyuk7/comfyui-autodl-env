# download/strategies/base.py
from abc import ABC, abstractmethod
import os
import logging

# 配置基础日志格式
logging.basicConfig(level=logging.INFO, format='%(message)s')
logger = logging.getLogger("DownloadStrategy")

class DownloadStrategy(ABC):
    def execute(self, source: str, target_dir: str, **kwargs) -> bool:
        """
        模板方法：接管下载的完整生命周期
        """
        self.source = source
        self.target_dir = target_dir
        self.kwargs = kwargs
        self.filename = kwargs.get('file')

        # 1. 预检阶段
        if self.pre_check():
            logger.info(f"    [SKIP] 满足跳过条件，无需下载: {self.filename or self.source}")
            return True

        try:
            # 2. 执行核心下载
            success = self._do_download()
            
            # 3. 后置处理与异常恢复
            if success:
                self.post_download()
                return True
            else:
                logger.warning(f"    [WARN] 下载未成功完成，触发清理逻辑: {self.source}")
                self.cleanup()
                return False
                
        except Exception as e:
            logger.error(f"    [FATAL] 下载过程发生未捕获异常: {e}")
            self.cleanup()
            return False

    def pre_check(self) -> bool:
        """
        默认预检逻辑：检查目标文件是否已存在。
        """
        if self.filename:
            target_file = os.path.join(self.target_dir, self.filename)
            return os.path.exists(target_file)
        return False

    @abstractmethod
    def _do_download(self) -> bool:
        """核心下载逻辑，必须由子类实现"""
        pass

    def post_download(self) -> None:
        """下载成功后的可选后置处理"""
        pass

    @abstractmethod
    def cleanup(self) -> None:
        """异常发生时的清理逻辑，必须由子类实现"""
        pass