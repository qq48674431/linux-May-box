# Linux 本地手动安装指南

适用于无法访问 GitHub 的内网环境，通过手动上传文件完成部署。

---

## 阶段一：打通 Root 权限

> 仅限刚装好系统执行一次，已有 Root SSH 权限可跳过。

登入普通用户后切换到 root：

```bash
su -
```

开启 Root SSH 登录：

```bash
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl restart ssh
```

---

## 阶段二：上传核心文件

使用 Xftp / SCP 以 root 登录，将以下文件上传到 `/root` 目录：

| 文件 | 说明 |
|------|------|
| `sing-box` | 定制版 sing-box 二进制 |
| `config.json` | sing-box 配置文件 |
| `index.html` | Web 管理面板前端 |
| `proxy-parser.js` | 代理链接解析库 |

---

## 阶段三：一键部署

以下命令可全选复制，在终端一次性粘贴执行。

### 1. 赋予执行权限

```bash
chmod +x /root/sing-box
```

### 2. 创建 systemd 服务

```bash
cat <<'EOF' > /etc/systemd/system/mysingbox.service
[Unit]
Description=Custom Sing-box Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=/root/sing-box run -c /root/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now mysingbox
```

### 3. 内核网络优化（BBR + IP 转发）

```bash
cat <<'EOF' > /etc/sysctl.d/99-singbox-router.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.ip_forward=1
EOF

sysctl --system
```

### 4. 禁止系统休眠（工控机专属）

```bash
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

mkdir -p /etc/systemd/logind.conf.d
cat <<'EOF' > /etc/systemd/logind.conf.d/no-sleep.conf
[Login]
HandleSuspendKey=ignore
HandleLidSwitch=ignore
IdleAction=ignore
EOF

systemctl restart systemd-logind
```

### 5. 日志持久化（限制最大 5G）

```bash
mkdir -p /var/log/journal
sed -i 's/^#*Storage=.*/Storage=persistent/' /etc/systemd/journald.conf
sed -i 's/^#*SystemMaxUse=.*/SystemMaxUse=5G/' /etc/systemd/journald.conf
systemctl restart systemd-journald
```

---

## 运行状态巡检

```bash
# 系统状态
uptime
who -b
last -x | head

# 磁盘/内存
df -h
free -h

# SSH 服务
systemctl status ssh --no-pager

# sing-box 服务
systemctl status mysingbox --no-pager
systemctl is-enabled mysingbox
journalctl -u mysingbox -n 50 --no-pager

# 进程确认
ps -ef | grep sing-box | grep -v grep

# 内核优化验证
sysctl net.core.default_qdisc
sysctl net.ipv4.tcp_congestion_control
sysctl net.ipv4.ip_forward

# 休眠屏蔽验证
systemctl status sleep.target suspend.target hibernate.target hybrid-sleep.target --no-pager
```

---

## 日常管理

```bash
# 停止服务
systemctl stop mysingbox

# 启动服务
systemctl start mysingbox

# 重启服务（配置变更后使用）
systemctl restart mysingbox

# 实时查看日志
journalctl -u mysingbox -f
```

<!-- CHECKPOINT id="ckpt_mowg0tlc_7wjg7u" time="2026-05-08T04:56:56.016Z" note="auto" fixes=0 questions=0 highlights=0 sections="" -->
