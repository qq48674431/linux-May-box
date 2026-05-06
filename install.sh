#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  sing-box 一键安装引导脚本（仅负责克隆仓库，然后执行本地 deploy.sh）
#  用法: bash <(curl -sL https://raw.githubusercontent.com/qq48674431/linux-May-box/main/install.sh)
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "请以 root 身份运行: sudo bash install.sh"

REPO_URL="https://github.com/qq48674431/linux-May-box.git"
WORK_DIR="/opt/linux-May-box"

# ── 安装 git ──
command -v git &>/dev/null || { info "安装 git..."; apt-get update -qq && apt-get install -y -qq git > /dev/null 2>&1; }

# ── 克隆 / 更新仓库 ──
if [[ -d "${WORK_DIR}/.git" ]]; then
    info "检测到已有仓库，拉取最新代码..."
    git -C "$WORK_DIR" pull --ff-only
else
    info "克隆仓库到 ${WORK_DIR}..."
    git clone "$REPO_URL" "$WORK_DIR"
fi

# ── 执行仓库内的真正部署脚本 ──
chmod +x "${WORK_DIR}/deploy.sh"
exec bash "${WORK_DIR}/deploy.sh"
