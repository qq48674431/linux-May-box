# linux-May-box

基于定制版 [sing-box](https://sing-box.sagernet.org/) 的 Linux 旁路由透明代理方案，sing-box 自带 Web 管理面板（端口 8080），支持多协议代理导入、设备分流、一键测速。

## 目录结构

```
linux-May-box/
├── sing-box            # 定制版 sing-box（自带 Web 面板 8080）
├── config.json         # sing-box 配置
├── index.html          # Web 管理面板前端
├── proxy-parser.js     # 代理链接解析库
├── install.sh          # 在线一键安装
├── local-install.md    # 内网手动安装说明
└── README.md
```

## 安装

### 方式一：一键安装（需能访问 GitHub）

```bash
bash <(curl -sL https://raw.githubusercontent.com/qq48674431/linux-May-box/main/install.sh)
```

### 方式二：手动上传（无法访问 GitHub 的主机）

1. 将 `install.sh`、`sing-box`、`config.json`、`index.html`、`proxy-parser.js` 上传到主机的同一目录。
2. 在该目录以 root 身份执行；脚本会使用已存在的文件，不再下载它们：

```bash
bash install.sh
```

脚本文件需采用 Unix LF 换行。默认配置保留直连出口，且不开启自动路由；确认代理节点、管理连接和回滚方式后，再按需启用透明代理。更多手动部署细节见 `local-install.md`。

### 安装完成后

浏览器访问 **`http://<机器IP>:8080`**

面板目前从外部 CDN 加载 Vue 和 Tailwind；访问面板的浏览器需要能连接这些 CDN，主机本身的离线安装不依赖它们。

## 日常运维

```bash
systemctl status mysingbox      # 查看状态
systemctl restart mysingbox     # 重启
systemctl stop mysingbox        # 停止
journalctl -u mysingbox -f      # 实时日志
```

## License

MIT
