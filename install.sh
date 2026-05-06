#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  sing-box 旁路由一键部署脚本
#  适用系统: Debian / Ubuntu (x86_64 / arm64)
#  一键安装: bash <(curl -sL https://raw.githubusercontent.com/qq48674431/linux-May-box/main/install.sh)
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "请以 root 身份运行: sudo bash install.sh"

REPO_URL="https://github.com/qq48674431/linux-May-box.git"
WORK_DIR="/opt/linux-May-box"
SINGBOX_BIN="${WORK_DIR}/sing-box"
SINGBOX_CONF="${WORK_DIR}/config.json"
SERVICE_NAME="mysingbox"

# ============================================================
#  阶段一: 安装依赖 + 克隆仓库
# ============================================================
info "安装基础依赖..."
apt-get update -qq && apt-get install -y -qq git curl tar jq python3 python3-pip python3-venv > /dev/null 2>&1

if [[ -d "${WORK_DIR}/.git" ]]; then
    info "检测到已有仓库，拉取最新代码..."
    git -C "$WORK_DIR" pull --ff-only
else
    info "克隆仓库到 ${WORK_DIR}..."
    git clone "$REPO_URL" "$WORK_DIR"
fi

cd "$WORK_DIR"

# ============================================================
#  阶段二: 自动下载 sing-box（如本地没有则下载最新版）
# ============================================================
if [[ -f "$SINGBOX_BIN" ]]; then
    info "sing-box 已存在，跳过下载"
else
    info "正在获取 sing-box 最新版本号..."
    LATEST_VER=$(curl -sL "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | jq -r '.tag_name')
    [[ -z "$LATEST_VER" || "$LATEST_VER" == "null" ]] && error "无法获取 sing-box 最新版本，请检查网络"
    VER_NUM="${LATEST_VER#v}"

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  SB_ARCH="amd64" ;;
        aarch64) SB_ARCH="arm64" ;;
        armv7l)  SB_ARCH="armv7" ;;
        *)       error "不支持的架构: $ARCH" ;;
    esac

    DL_URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST_VER}/sing-box-${VER_NUM}-linux-${SB_ARCH}.tar.gz"
    info "下载 sing-box ${LATEST_VER} (${SB_ARCH})..."
    info "地址: ${DL_URL}"

    TMP_DIR=$(mktemp -d)
    curl -sL "$DL_URL" -o "${TMP_DIR}/sing-box.tar.gz" || error "下载失败，请检查网络"
    tar -xzf "${TMP_DIR}/sing-box.tar.gz" -C "$TMP_DIR"
    cp "${TMP_DIR}/sing-box-${VER_NUM}-linux-${SB_ARCH}/sing-box" "$SINGBOX_BIN"
    rm -rf "$TMP_DIR"

    info "sing-box ${LATEST_VER} 下载完成"
fi

chmod +x "$SINGBOX_BIN"
[[ ! -f "$SINGBOX_CONF" ]] && error "缺少 config.json"
info "sing-box 已就绪"

# ============================================================
#  阶段三: 创建 systemd 服务（含高并发优化）
# ============================================================
info "创建 systemd 服务: ${SERVICE_NAME}..."

cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Sing-box Router Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${WORK_DIR}
ExecStart=${SINGBOX_BIN} run -c ${SINGBOX_CONF}
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ${SERVICE_NAME}
info "sing-box 服务已启动并设置开机自启"

# ============================================================
#  阶段四: 部署 Web 管理面板（Python + Flask）
# ============================================================
WEB_SERVICE="singbox-web"

info "安装 Python 依赖..."
python3 -m venv "${WORK_DIR}/venv"
"${WORK_DIR}/venv/bin/pip" install -q -r "${WORK_DIR}/requirements.txt"

info "创建 Web 面板服务: ${WEB_SERVICE}..."

cat > /etc/systemd/system/${WEB_SERVICE}.service <<EOF
[Unit]
Description=Sing-box Web Panel
After=network.target ${SERVICE_NAME}.service

[Service]
Type=simple
User=root
WorkingDirectory=${WORK_DIR}
ExecStart=${WORK_DIR}/venv/bin/python ${WORK_DIR}/server.py
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ${WEB_SERVICE}
info "Web 面板已启动 → http://0.0.0.0:8080"

# ============================================================
#  阶段五: 内核网络优化（BBR + IP 转发）
# ============================================================
info "配置内核参数 (BBR / IP 转发)..."

cat > /etc/sysctl.d/99-singbox-router.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.ip_forward=1
EOF

sysctl --system > /dev/null 2>&1
info "BBR 与 IP 转发已生效"

# ============================================================
#  阶段六: 禁止系统休眠（工控机专属）
# ============================================================
info "屏蔽休眠/挂起..."

systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target > /dev/null 2>&1

mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/no-sleep.conf <<'EOF'
[Login]
HandleSuspendKey=ignore
HandleLidSwitch=ignore
IdleAction=ignore
EOF

systemctl restart systemd-logind
info "休眠已屏蔽"

# ============================================================
#  阶段七: 日志持久化 + 限制空间（防爆满）
# ============================================================
info "配置日志持久化 (上限 5G)..."

mkdir -p /var/log/journal
sed -i 's/^#*Storage=.*/Storage=persistent/'   /etc/systemd/journald.conf
sed -i 's/^#*SystemMaxUse=.*/SystemMaxUse=5G/' /etc/systemd/journald.conf
systemctl restart systemd-journald

info "日志已持久化，最大 5G"

# ============================================================
#  完成
# ============================================================
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')

echo ""
echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo -e "${GREEN}  部署完成！所有服务已在后台运行${NC}"
echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo ""
echo -e "  Web 面板:  ${YELLOW}http://${LOCAL_IP:-<本机IP>}:8080${NC}"
echo ""
echo "  项目目录:  ${WORK_DIR}"
echo "  sing-box:  systemctl status ${SERVICE_NAME}"
echo "  Web 面板:  systemctl status ${WEB_SERVICE}"
echo "  重启全部:  systemctl restart ${SERVICE_NAME} ${WEB_SERVICE}"
echo "  查看日志:  journalctl -u ${SERVICE_NAME} -f"
echo "  一键巡检:  ${WORK_DIR}/check.sh"
echo ""
