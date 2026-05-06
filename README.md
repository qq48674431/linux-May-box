# linux-May-box

基于定制版 [sing-box](https://sing-box.sagernet.org/) 的 Linux 旁路由透明代理方案，sing-box 自带 Web 管理面板（端口 8080），支持多协议代理导入、设备分流、一键测速。

## 目录结构

```
linux-May-box/
├── sing-box            # 定制版 sing-box（自带 Web 面板 8080）
├── config.json         # sing-box 配置
├── index.html          # Web 管理面板前端
├── proxy-parser.js     # 代理链接解析库
├── deploy.sh           # 部署脚本
├── install.sh          # 在线一键安装
├── check.sh            # 运行状态巡检
├── enable-root-ssh.sh  # 开启 Root SSH
└── README.md
```

## 安装

### 方式一：一键安装（需能访问 GitHub）

```bash
bash <(curl -sL https://raw.githubusercontent.com/qq48674431/linux-May-box/main/install.sh)
```

### 方式二：手动上传（国内 VPS）

1. 用 Xftp 将整个项目上传到 VPS
2. SSH 执行：

```bash
chmod +x deploy.sh && bash deploy.sh
```

### 安装完成后

浏览器访问 **`http://<机器IP>:8080`**

## 日常运维

```bash
systemctl status mysingbox      # 查看状态
systemctl restart mysingbox     # 重启
systemctl stop mysingbox        # 停止
journalctl -u mysingbox -f      # 实时日志
```

## License

MIT
