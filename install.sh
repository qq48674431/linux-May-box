#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  sing-box 一键安装 / 升级（下载所有文件 + 部署）
#  用法: bash <(curl -sL https://raw.githubusercontent.com/qq48674431/linux-May-box/main/install.sh)
#
#  升级老机器：直接重跑同一条命令即可。
#    程序文件（sing-box / index.html / proxy-parser.js）按 sha256 比对，
#    与线上不一致才覆盖，旧文件自动备份为 *.bak-<时间戳>；
#    config.json 属于你的节点配置，已存在时一律保留不覆盖。
#
#  可选环境变量：
#    WORK_DIR=/opt/linux-May-box   部署目录
#    FILES_ONLY=1                  只同步文件，不改 systemd / sysctl / journald
#    BASE_URL=...                  主下载源（默认 raw.githubusercontent.com）
#    FALLBACK_URL=...              备用源（默认 jsDelivr CDN）
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "请以 root 身份运行"

WORK_DIR="${WORK_DIR:-/opt/linux-May-box}"
SERVICE_NAME="mysingbox"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/qq48674431/linux-May-box/main}"
FALLBACK_URL="${FALLBACK_URL:-https://cdn.jsdelivr.net/gh/qq48674431/linux-May-box@main}"
FILES_ONLY="${FILES_ONLY:-0}"
TS=$(date +%Y%m%d-%H%M%S)

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
short() { local s; s=$(sha "$1"); echo "${s:0:12}"; }

# ============================================================
#  下载（主源失败自动换备用源）
# ============================================================
fetch() {
    local file="$1" dest="$2" base url ok=0
    for base in "$BASE_URL" "$FALLBACK_URL"; do
        [[ -z "$base" ]] && continue
        url="${base%/}/${file}"
        info "下载 ${url}"
        if curl -fsSL --retry 2 --retry-delay 2 --connect-timeout 15 --max-time 600 --progress-bar "$url" -o "$dest"; then
            ok=1
            break
        fi
        warn "从 ${base%/} 下载 ${file} 失败，换下一个源"
    done
    [[ "$ok" -eq 1 ]] || error "下载 ${file} 失败（所有源都不可用）"
}

# 程序文件：先下到临时文件，sha256 与现有文件一致就跳过，不一致才备份后覆盖
dl_update() {
    local file="$1"
    local tmp="${WORK_DIR}/.${file}.download"
    info "检查 ${file}..."
    fetch "$file" "$tmp"
    if [[ -f "${WORK_DIR}/${file}" ]]; then
        local old new
        old=$(sha "${WORK_DIR}/${file}")
        new=$(sha "$tmp")
        if [[ -n "$old" && "$old" == "$new" ]]; then
            rm -f "$tmp"
            info "${file} 已是最新（sha256 ${new:0:12}...），跳过"
            return 0
        fi
        cp -a "${WORK_DIR}/${file}" "${WORK_DIR}/${file}.bak-${TS}"
        warn "${file} 有更新，旧文件已备份为 ${file}.bak-${TS}"
    fi
    mv -f "$tmp" "${WORK_DIR}/${file}"
    info "${file} 已更新（sha256 $(short "${WORK_DIR}/${file}")...）"
}

# 配置文件：老机器上一般已按实际节点改过，绝不覆盖；仅在缺失时下载
dl_keep() {
    local file="$1"
    if [[ -f "${WORK_DIR}/${file}" ]]; then
        info "${file} 已存在，保留不覆盖（升级不动节点配置）"
        return 0
    fi
    fetch "$file" "${WORK_DIR}/${file}"
    info "${file} 已下载"
}

dl_update sing-box
dl_keep config.json
dl_update index.html
dl_update proxy-parser.js

chmod +x "${WORK_DIR}/sing-box"

FILE_SIZE=$(stat -c%s "${WORK_DIR}/sing-box" 2>/dev/null || echo 0)
[[ "$FILE_SIZE" -lt 1000000 ]] && { rm -f "${WORK_DIR}/sing-box"; error "sing-box 文件异常，请重试"; }
info "所有文件就绪 (sing-box $(( FILE_SIZE / 1024 / 1024 )) MB, sha256 $(short "${WORK_DIR}/sing-box")...)"

if [[ "$FILES_ONLY" == "1" ]]; then
    info "FILES_ONLY=1：跳过 systemd / sysctl / journald 配置"
    echo ""
    info "完成：文件已就绪于 ${WORK_DIR}"
    exit 0
fi

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
systemctl enable ${SERVICE_NAME} > /dev/null 2>&1 || true
if systemctl is-active --quiet ${SERVICE_NAME}; then
    systemctl restart ${SERVICE_NAME}
    info "服务已重启（加载新程序）"
else
    systemctl start ${SERVICE_NAME}
    info "服务已启动并设置开机自启"
fi

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
