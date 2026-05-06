#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  sing-box 一键安装（需能访问 GitHub）
#  用法: bash <(curl -sL https://raw.githubusercontent.com/qq48674431/linux-May-box/main/install.sh)
#
#  如果网络不通，请手动用 Xftp 上传所有文件后执行:  sudo bash deploy.sh
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "请以 root 身份运行"

WORK_DIR="/opt/linux-May-box"

command -v git &>/dev/null || { info "安装 git/curl..."; apt-get update -qq && apt-get install -y -qq git curl > /dev/null 2>&1; }

if [[ -d "${WORK_DIR}/.git" ]]; then
    info "拉取最新代码..."
    git -C "$WORK_DIR" pull --ff-only
else
    info "克隆仓库..."
    git clone https://github.com/qq48674431/linux-May-box.git "$WORK_DIR"
fi

# 下载 sing-box
if [[ ! -f "${WORK_DIR}/sing-box" ]]; then
    info "下载 sing-box..."
    curl -fSL --retry 3 https://github.com/qq48674431/linux-May-box/releases/download/v1.0/sing-box -o "${WORK_DIR}/sing-box"
fi

chmod +x "${WORK_DIR}/deploy.sh"
exec bash "${WORK_DIR}/deploy.sh"
