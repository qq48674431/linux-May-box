#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  sing-box 旁路由一键部署脚本（由 install.sh 引导调用）
#  sing-box 为定制版，自带 Web 管理面板（端口 8080）
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "请以 root 身份运行"

WORK_DIR="$(cd "$(dirname "$0")" && pwd)"
SINGBOX_BIN="${WORK_DIR}/sing-box"
SINGBOX_CONF="${WORK_DIR}/config.json"
SERVICE_NAME="mysingbox"
SINGBOX_DL_URL="https://github.com/qq48674431/linux-May-box/releases/download/v1.0/sing-box"

# ============================================================
#  阶段一: 下载 sing-box（定制版，自带 Web 面板）
# ============================================================
if [[ -f "$SINGBOX_BIN" ]]; then
    info "sing-box 已存在，跳过下载"
else
    info "下载 sing-box..."
    info "地址: ${SINGBOX_DL_URL}"
    curl -fSL --retry 3 "$SINGBOX_DL_URL" -o "$SINGBOX_BIN" || error "下载失败，请检查网络"

    FILE_SIZE=$(stat -c%s "$SINGBOX_BIN" 2>/dev/null || echo 0)
    [[ "$FILE_SIZE" -lt 1000000 ]] && { rm -f "$SINGBOX_BIN"; error "下载文件异常（仅 ${FILE_SIZE} 字节），请重试"; }
    info "sing-box 下载完成 ($(( FILE_SIZE / 1024 / 1024 )) MB)"
fi

chmod +x "$SINGBOX_BIN"
[[ ! -f "$SINGBOX_CONF" ]] && error "缺少 config.json"
info "sing-box 已就绪"

# ============================================================
#  阶段二: 创建 systemd 服务
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
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')

echo ""
echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo -e "${GREEN}  部署完成！sing-box 已在后台运行${NC}"
echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo ""
echo -e "  Web 面板:  ${YELLOW}http://${LOCAL_IP:-<本机IP>}:8080${NC}"
echo ""
echo "  项目目录:  ${WORK_DIR}"
echo "  查看状态:  systemctl status ${SERVICE_NAME}"
echo "  查看日志:  journalctl -u ${SERVICE_NAME} -f"
echo "  重启服务:  systemctl restart ${SERVICE_NAME}"
echo "  停止服务:  systemctl stop ${SERVICE_NAME}"
echo "  一键巡检:  ${WORK_DIR}/check.sh"
echo ""
