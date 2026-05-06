#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  sing-box 旁路由一键部署脚本
#  用法: 把所有文件上传到同一目录后执行  sudo bash deploy.sh
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "请以 root 身份运行"

WORK_DIR="$(cd "$(dirname "$0")" && pwd)"
SINGBOX_BIN="${WORK_DIR}/sing-box"
SINGBOX_CONF="${WORK_DIR}/config.json"
SERVICE_NAME="mysingbox"

# ── 校验文件 ──
[[ ! -f "$SINGBOX_BIN"  ]] && error "缺少 sing-box，请先放到 ${WORK_DIR}/"
[[ ! -f "$SINGBOX_CONF" ]] && error "缺少 config.json，请先放到 ${WORK_DIR}/"
chmod +x "$SINGBOX_BIN"
info "文件校验通过"

# ── 注册 systemd 服务 ──
info "创建服务: ${SERVICE_NAME}..."
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
info "服务已启动并设置开机自启"

# ── 内核优化（BBR + IP 转发）──
info "配置 BBR / IP 转发..."
cat > /etc/sysctl.d/99-singbox-router.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.ip_forward=1
EOF
sysctl --system > /dev/null 2>&1

# ── 禁止休眠 ──
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

# ── 日志限制 ──
info "配置日志持久化 (上限 5G)..."
mkdir -p /var/log/journal
sed -i 's/^#*Storage=.*/Storage=persistent/'   /etc/systemd/journald.conf
sed -i 's/^#*SystemMaxUse=.*/SystemMaxUse=5G/' /etc/systemd/journald.conf
systemctl restart systemd-journald

# ── 完成 ──
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
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
