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