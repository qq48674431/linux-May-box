#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  sing-box 旁路由一键部署脚本
#  适用系统: Debian / Ubuntu (x86_64 工控机 / VPS)
#  用法:     chmod +x install.sh && sudo ./install.sh
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "请以 root 身份运行: sudo ./install.sh"

WORK_DIR="$(cd "$(dirname "$0")" && pwd)"
SINGBOX_BIN="${WORK_DIR}/sing-box"
SINGBOX_CONF="${WORK_DIR}/config.json"
SERVICE_NAME="mysingbox"

# ============================================================
#  阶段一: 校验核心文件
# ============================================================
info "检查核心文件..."
[[ ! -f "$SINGBOX_BIN"  ]] && error "缺少 sing-box 可执行文件，请先放到 ${WORK_DIR}/ 目录"
[[ ! -f "$SINGBOX_CONF" ]] && error "缺少 config.json，请先放到 ${WORK_DIR}/ 目录"

chmod +x "$SINGBOX_BIN"
info "sing-box 已赋予执行权限"

# ============================================================
#  阶段二: 创建 systemd 服务（含高并发优化）
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
info "服务已启动并设置开机自启"

# ============================================================
#  阶段三: 内核网络优化（BBR + IP 转发）
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
#  阶段四: 禁止系统休眠（工控机专属）
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
#  阶段五: 日志持久化 + 限制空间（防爆满）
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
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  部署完成！sing-box 已在后台运行${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  查看状态:  systemctl status ${SERVICE_NAME}"
echo "  查看日志:  journalctl -u ${SERVICE_NAME} -f"
echo "  重启服务:  systemctl restart ${SERVICE_NAME}"
echo "  停止服务:  systemctl stop ${SERVICE_NAME}"
echo ""
