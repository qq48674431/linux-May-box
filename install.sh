#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  sing-box 一键安装（下载所有文件 + 部署）
#  用法: bash <(curl -sL https://raw.githubusercontent.com/qq48674431/linux-May-box/main/install.sh)
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "请以 root 身份运行"

WORK_DIR="/opt/linux-May-box"
SERVICE_NAME="mysingbox"
BASE_URL="https://raw.githubusercontent.com/qq48674431/linux-May-box/main"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# ============================================================
#  下载核心文件
# ============================================================
dl() {
    local file="$1"
    if [[ -f "${WORK_DIR}/${file}" ]]; then
        info "${file} 已存在，跳过"
    else
        info "下载 ${file}..."
        curl -fSL --retry 3 "${BASE_URL}/${file}" -o "${WORK_DIR}/${file}" || error "下载 ${file} 失败"
    fi
}

dl sing-box
dl config.json
dl index.html
dl proxy-parser.js

chmod +x "${WORK_DIR}/sing-box"

FILE_SIZE=$(stat -c%s "${WORK_DIR}/sing-box" 2>/dev/null || echo 0)
[[ "$FILE_SIZE" -lt 1000000 ]] && { rm -f "${WORK_DIR}/sing-box"; error "sing-box 文件异常，请重试"; }
info "所有文件就绪 (sing-box $(( FILE_SIZE / 1024 / 1024 )) MB)"

# ============================================================
#  注册 systemd 服务
# ============================================================
info "创建服务: ${SERVICE_NAME}..."
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Sing-box Router Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${WORK_DIR}
ExecStart=${WORK_DIR}/sing-box run -c ${WORK_DIR}/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ${SERVICE_NAME}
info "服务已启动并设置开机自启"

# ============================================================
#  内核优化（BBR + IP 转发）
# ============================================================
info "配置 BBR / IP 转发..."
cat > /etc/sysctl.d/99-singbox-router.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.ip_forward=1
EOF
sysctl --system > /dev/null 2>&1

# ============================================================
#  禁止休眠
# ============================================================
info "屏蔽休眠..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target > /dev/null 2>&1
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/no-sleep.conf <<'EOF'
[Login]
HandleSuspendKey=ignore
HandleLidSwitch=ignore
IdleAction=ignore
EOF
systemctl restart systemd-logind

# ============================================================
#  日志限制
# ============================================================
info "配置日志持久化 (上限 5G)..."
mkdir -p /var/log/journal
sed -i 's/^#*Storage=.*/Storage=persistent/'   /etc/systemd/journald.conf
sed -i 's/^#*SystemMaxUse=.*/SystemMaxUse=5G/' /etc/systemd/journald.conf
systemctl restart systemd-journald

# ============================================================
#  完成
# ============================================================
LOCAL_IP=$(curl -s4 --connect-timeout 3 ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  部署完成！${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo -e "  Web 面板:  ${YELLOW}http://${LOCAL_IP:-<本机IP>}:8080${NC}"
echo ""
echo "  查看状态:  systemctl status ${SERVICE_NAME}"
echo "  重启服务:  systemctl restart ${SERVICE_NAME}"
echo "  查看日志:  journalctl -u ${SERVICE_NAME} -f"
echo ""
