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
├── install.sh          # 一键部署脚本（服务注册 + 内核优化）
├── check.sh            # 运行状态巡检脚本
├── enable-root-ssh.sh  # 开启 Root SSH（新系统仅需执行一次）
├── config.json         # sing-box 基础配置（TUN 模式）
├── index.html          # Web 管理面板前端
├── proxy-parser.js     # 代理链接解析/还原库
└── README.md
```

## 快速部署

### 前置条件

- Debian / Ubuntu 系统（x86_64）
- 已下载 [sing-box](https://github.com/SagerNet/sing-box/releases) 对应架构的可执行文件

### 步骤

```bash
# 1. 克隆仓库
git clone https://github.com/<你的用户名>/linux-May-box.git
cd linux-May-box

# 2. 将 sing-box 可执行文件放到本目录下
#    （从 GitHub Releases 下载后复制过来）
cp /path/to/sing-box ./

# 3. 一键部署
chmod +x install.sh
sudo ./install.sh
```

部署完成后 sing-box 会以 systemd 服务自动运行。

### 新系统首次连接（可选）

如果系统刚装好、还没开启 root SSH，先用普通用户登录后执行：

```bash
su -
bash enable-root-ssh.sh
```

## 日常运维

```bash
# 查看服务状态
systemctl status mysingbox

# 重启服务（修改 config.json 后）
systemctl restart mysingbox

# 停止服务
systemctl stop mysingbox

# 查看实时日志
journalctl -u mysingbox -f

# 一键巡检系统状态
sudo ./check.sh
```

## Web 管理面板

面板由后端 API 驱动（需配合后端服务），提供以下功能：

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
