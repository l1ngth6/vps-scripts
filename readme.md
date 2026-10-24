# VPS 自用常用脚本

支持 Debian 12/13 和使用 OpenRC 的 Alpine Linux，继续使用 Bash 运行：

```sh
bash init/main.sh
```

Alpine 请先以 root 安装依赖，再运行脚本：

```sh
apk add bash wget ca-certificates openssh openssh-keygen
bash init/main.sh
```

脚本不会自动安装依赖。SSH 功能要求已经安装并运行 OpenSSH；Alpine
使用 `rc-service sshd reload`，Debian 使用 systemd 重新加载配置。
不适配 Dropbear 或 Alpine diskless 模式。Debian 如缺少命令，可安装
`bash wget ca-certificates openssh-server util-linux procps`。

- BBR+FQ：保存到 `/etc/sysctl.d/99-vps-scripts-bbr.conf`，立即加载并检查结果。
  是否可用取决于当前内核；新连接使用新设置，已有连接不会强制切换。
- swap：容量单位为 MiB，只管理 `/swapfile`，保留其他交换设备和配置。
  优先使用 `fallocate`，没有该命令时使用 `dd`；Alpine 会启用 OpenRC 的
  swap 启动服务。面向常见的 ext4/XFS VPS，Btrfs 等需要额外设置的文件系统
  请自行配置 swap。
- SSH：为当前 sudo 用户（直接以 root 运行时为 root）添加公钥，可选择禁用
  密码登录。脚本验证公钥与实际配置后重新加载服务，应用失败恢复配置备份。
  请保留当前会话，并新开终端确认密钥登录正常。
- 探针：Debian 沿用 ServerStatus-Rust 上游安装脚本；Alpine 暂不支持，
  选择后提示并返回。远程脚本通过 HTTPS 下载到临时文件后执行。

BBR 和 swap 需要 root 权限。菜单遇到输入结束（EOF）会退出。
