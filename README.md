# linux-May-box

基于定制版 [sing-box](https://sing-box.sagernet.org/) 的 Linux 旁路由透明代理方案，sing-box 自带 Web 管理面板（端口 8080），支持多协议代理导入、设备分流、一键测速。

## 目录结构

```
linux-May-box/
├── deploy.sh           # 部署脚本（注册服务 + 内核优化）
├── install.sh          # 在线安装引导（需能访问 GitHub）
├── config.json         # sing-box 配置
├── index.html          # Web 管理面板前端
├── proxy-parser.js     # 代理链接解析库
├── check.sh            # 运行状态巡检
├── enable-root-ssh.sh  # 开启 Root SSH
└── README.md
```

> `sing-box` 二进制在 [Release v1.0](https://github.com/qq48674431/linux-May-box/releases/tag/v1.0) 中下载。

## 安装方式

### 方式一：Xftp 手动上传（推荐，国内 VPS 必用）

1. 从 [Release](https://github.com/qq48674431/linux-May-box/releases/tag/v1.0) 下载 `sing-box`
2. 用 Xftp 将整个项目上传到 VPS 的 `/root/` 目录（确保 `sing-box`、`config.json`、`index.html`、`proxy-parser.js`、`deploy.sh` 在同一目录）
3. SSH 登录 root 执行：

```bash
cd /root
chmod +x deploy.sh
bash deploy.sh
```

### 方式二：一键安装（需能访问 GitHub）

```bash
bash <(curl -sL https://raw.githubusercontent.com/qq48674431/linux-May-box/main/install.sh)
```

## 安装完成后

浏览器访问 **`http://<机器IP>:8080`** 打开管理面板。

## 日常运维

```bash
systemctl status mysingbox      # 查看状态
systemctl restart mysingbox     # 重启
systemctl stop mysingbox        # 停止
journalctl -u mysingbox -f      # 实时日志
```

## Web 管理面板

| 功能 | 说明 |
|------|------|
| 仪表盘 | CPU / 内存实时监控 |
| 代理管理 | 导入 Socks5、智能解析加密链接、导出、测速、批量删除 |
| 设备管理 | 添加设备 IP/网段、切换归属代理 |
| 系统设置 | DNS 服务器配置 |

## License

MIT
