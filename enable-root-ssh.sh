#!/usr/bin/env bash
# ============================================================
#  开启 Root SSH 登录（仅需在新装系统后执行一次）
#  用法: su - 后执行  bash enable-root-ssh.sh
# ============================================================

set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "请以 root 身份运行"; exit 1; }

sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl restart ssh

echo "✓ Root SSH 登录已开启，现在可以用 root 直接连接。"
