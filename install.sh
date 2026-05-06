#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  sing-box 一键安装引导（自动识别网络环境，国内自动走代理）
#  用法: bash <(curl -sL https://raw.githubusercontent.com/qq48674431/linux-May-box/main/install.sh)
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "请以 root 身份运行"

GITHUB_URL="https://github.com/qq48674431/linux-May-box.git"
PROXY_URL="https://ghfast.top/https://github.com/qq48674431/linux-May-box.git"
WORK_DIR="/opt/linux-May-box"

command -v git &>/dev/null || { info "安装 git/curl..."; apt-get update -qq && apt-get install -y -qq git curl > /dev/null 2>&1; }

# ── 检测 GitHub 连通性，不通则走代理 ──
pick_repo_url() {
    if curl -sfI --connect-timeout 5 https://github.com &>/dev/null; then
        echo "$GITHUB_URL"
    else
        warn "GitHub 直连不通，使用加速代理..."
        echo "$PROXY_URL"
    fi
}

if [[ -d "${WORK_DIR}/.git" ]]; then
    info "检测到已有仓库，拉取最新代码..."
    git -C "$WORK_DIR" pull --ff-only 2>/dev/null || {
        warn "pull 失败，重新克隆..."
        rm -rf "$WORK_DIR"
        REPO=$(pick_repo_url)
        info "克隆: ${REPO}"
        git clone "$REPO" "$WORK_DIR"
    }
else
    REPO=$(pick_repo_url)
    info "克隆仓库到 ${WORK_DIR}..."
    info "地址: ${REPO}"
    git clone "$REPO" "$WORK_DIR"
fi

chmod +x "${WORK_DIR}/deploy.sh"
exec bash "${WORK_DIR}/deploy.sh"
