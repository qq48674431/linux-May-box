# linux-May-box

基于 [sing-box](https://sing-box.sagernet.org/) 的 Linux 旁路由透明代理方案，附带 Web 管理面板，支持多协议代理导入、设备分流、一键测速。

## 功能概览

- **Web 管理面板** — Vue 3 + Tailwind CSS 单页面，通过浏览器管理代理节点和设备分流
- **多协议支持** — VMess / VLESS / Trojan / Shadowsocks / Hysteria2 / Socks5 链接的解析与导出
- **设备分流** — 按 IP/网段 将不同设备绑定到不同代理出口
- **一键测速** — 批量检测节点延迟
- **系统优化** — BBR 拥塞控制、IP 转发、高并发文件描述符、禁止休眠（工控机场景）

## 目录结构

```
linux-May-box/
├── install.sh          # 一键安装引导（克隆仓库 → 执行 deploy.sh）
├── deploy.sh           # 完整部署脚本（sing-box + Web面板 + 内核优化）
├── server.py           # Web 管理面板后端（Flask API，端口 8080）
├── requirements.txt    # Python 依赖
├── config.json         # sing-box 基础配置（TUN 模式）
├── index.html          # Web 管理面板前端（Vue 3 + Tailwind）
├── proxy-parser.js     # 代理链接解析/还原库
├── check.sh            # 运行状态巡检脚本
├── enable-root-ssh.sh  # 开启 Root SSH（新系统仅需执行一次）
└── README.md
```

## 一键安装

SSH 登录 root 后，粘贴以下命令即可完成全部部署（自动克隆仓库 + 下载 sing-box + 注册服务 + 内核优化）：

```bash
bash <(curl -sL https://raw.githubusercontent.com/qq48674431/linux-May-box/main/install.sh)
```

脚本会自动：
1. 克隆仓库到 `/opt/linux-May-box`
2. 从仓库 Release 下载 sing-box 二进制文件
3. 注册 sing-box systemd 服务并启动
4. 部署 Web 管理面板（Flask），监听 `http://<机器IP>:8080`
5. 开启 BBR + IP 转发 + 禁止休眠 + 日志限制

> 再次执行同一命令即可**更新**（会 `git pull` 最新代码，已有的 sing-box 不会重复下载）。

### 新系统首次连接（可选）

如果系统刚装好、还没开启 root SSH，先用普通用户登录后执行：

```bash
su -
bash enable-root-ssh.sh
```

## 日常运维

```bash
# 查看 sing-box 状态
systemctl status mysingbox

# 查看 Web 面板状态
systemctl status singbox-web

# 重启全部服务
systemctl restart mysingbox singbox-web

# 停止全部服务
systemctl stop mysingbox singbox-web

# 查看实时日志
journalctl -u mysingbox -f

# 一键巡检系统状态
sudo /opt/linux-May-box/check.sh
```

## Web 管理面板

安装完成后浏览器访问 `http://<机器IP>:8080` 即可打开管理面板。功能如下：

| 功能 | 说明 |
|------|------|
| 仪表盘 | CPU / 内存实时监控 |
| 代理管理 | 导入 Socks5、智能解析加密链接、导出、测速、批量删除 |
| 设备管理 | 添加设备 IP/网段、切换归属代理 |
| 系统设置 | DNS 服务器配置 |

## 配置说明

`config.json` 默认为 TUN 模式旁路由配置：

- **入站**: TUN (`tun0`, 地址 `172.19.0.1/30`, MTU 9000)
- **DNS**: 阿里云 `223.5.5.5`
- **路由**: 自动嗅探 + DNS 劫持，默认阻断未分配设备流量

## License

MIT
