# ==========================================
# AutoDL 效率增强 Aliases (2026 满血版)
# ==========================================

# GPU 监控
alias gpu="watch -n 1 nvidia-smi"

# 快速跳转
alias cdcomfy="cd /root/autodl-tmp/ComfyUI"
alias cdmodels="cd /root/autodl-tmp/shared_models"

# 存储分析
alias dus="du -h --max-depth=1 /root/autodl-tmp | sort -hr"

# 插件管理
alias gpull="git pull origin main --rebase"

# --- 网络与工具 ---
alias turbo='source /etc/network_turbo && echo ">>> 已开启 AutoDL 学术加速"'
alias unturbo='unset http_proxy https_proxy all_proxy && echo ">>> 已关闭学术加速"'

# --- 缓存清理 (关键更新) ---
# 清理 Pip 缓存
alias piclean="pip cache purge"

# 一键清理所有 Hugging Face 缓存 (不影响已落地的模型)
alias hfclean='hf cache rm $(hf cache ls --quiet) --yes 2>/dev/null || echo ">>> HF 缓存已经是空的"'

# 手动触发模型路径对齐 (当 GUI 找不到模型时运行)
alias hfsync='python /root/autodl-tmp/comfyui-autodl-env/setup_models.py'

# 快速登录
alias hflogin="hf auth login"