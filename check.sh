#!/usr/bin/env bash
# ============================================================
#  sing-box 运行状态一键巡检脚本
#  用法: sudo ./check.sh
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
SERVICE_NAME="mysingbox"

divider() { echo -e "\n${CYAN}── $1 ──${NC}"; }

divider "系统运行时间 & 最近重启"
uptime
who -b 2>/dev/null
last -x reboot 2>/dev/null | head -3

divider "磁盘使用"
df -h / /var/log 2>/dev/null | awk 'NR==1||/\/$|\/var\/log/'

divider "内存使用"
free -h

divider "SSH 服务状态"
systemctl is-active ssh 2>/dev/null && echo -e "${GREEN}SSH 正常${NC}" || echo -e "${RED}SSH 异常${NC}"

divider "${SERVICE_NAME} 服务状态"
systemctl status ${SERVICE_NAME} --no-pager -l 2>/dev/null | head -15
echo ""
echo "开机自启: $(systemctl is-enabled ${SERVICE_NAME} 2>/dev/null)"

divider "sing-box 进程"
ps -eo pid,user,%cpu,%mem,args | head -1
ps -eo pid,user,%cpu,%mem,args | grep 'sing-box' | grep -v grep || echo -e "${RED}未检测到 sing-box 进程${NC}"

divider "最近 20 条服务日志"
journalctl -u ${SERVICE_NAME} -n 20 --no-pager 2>/dev/null

divider "内核优化验证"
echo "队列调度:   $(sysctl -n net.core.default_qdisc 2>/dev/null)"
echo "拥塞控制:   $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
echo "IP 转发:    $(sysctl -n net.ipv4.ip_forward 2>/dev/null)"

divider "休眠屏蔽状态"
for t in sleep.target suspend.target hibernate.target hybrid-sleep.target; do
    state=$(systemctl is-enabled "$t" 2>/dev/null)
    if [[ "$state" == "masked" ]]; then
        echo -e "  $t  ${GREEN}已屏蔽${NC}"
    else
        echo -e "  $t  ${YELLOW}${state}${NC}"
    fi
done

echo ""
echo -e "${GREEN}巡检完成${NC}"
