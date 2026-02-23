# ==========================================
# AutoDL 效率增强 Aliases
# ==========================================

# GPU 监控 (高亮显示显存和使用率)
alias gpu="watch -n 1 nvidia-smi"

# 快速跳转到 ComfyUI 根目录
alias cdcomfy="cd /root/autodl-tmp/ComfyUI"

# 快速跳转到模型目录
alias cdmodels="cd /root/autodl-tmp/shared_models"

# 快速查看数据盘占用 (只看第一层目录，按大小排序)
alias dus="du -h --max-depth=1 /root/autodl-tmp | sort -hr"

# Git 快速拉取更新
alias gpull="git pull origin main --rebase"

# --- 网络与工具增强 ---

# 开启学术加速
alias turbo='source /etc/network_turbo && echo ">>> 已开启 AutoDL 学术加速 (代理模式)"'

# 关闭学术加速
alias unturbo='unset http_proxy https_proxy all_proxy && echo ">>> 已关闭学术加速"'

# 快速进行 Hugging Face 登录
alias hflogin="huggingface-cli login"

# 自动清理 pip 缓存
alias piclean="pip cache purge"