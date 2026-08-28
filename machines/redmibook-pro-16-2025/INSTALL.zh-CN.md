# REDMI Book Pro 16 2025 → Ubuntu 26.04

[English version](INSTALL.md)

这是一条**推荐安装路线**：把 REDMI Book Pro 16 2025 安装成 Ubuntu 26.04 的 Linux 开发 / CI 节点。

如果实际界面和这里明显不一样，**先停下来，拍照，然后视频/微信确认**。尤其不要在不确定时乱改 BIOS/UEFI 或磁盘设置。

## 需要准备

- REDMI Book 和电源；
- **8 GB 或更大的 U 盘**（制作安装盘会清空 U 盘）；
- 另一台 Windows 电脑；
- 网络；
- 大约 45–90 分钟，大部分时间是在等下载和安装。

## 0. 删除 Windows 之前先检查一下

第一次先正常进入 Windows，花 5 分钟确认：

- 屏幕、键盘、触控板、Wi-Fi 正常；
- Windows 显示大约 **32 GB 内存**；
- 内置 SSD 大约 **1 TB**；
- 充电正常。

### 可选：先领取预装 Office

部分中国大陆版本会附带 Office 家庭和学生版。如果 Windows 里显示有随机器附送的 Office，而且以后可能会用，建议**在删除 Windows 之前**先绑定/激活到准备长期使用的 Microsoft 账号。

不需要花时间个性化 Windows。这里主要是确认机器没有硬件问题，以及保留想要的附带软件权益。

## 1. 下载 Ubuntu 26.04 LTS

只用 Ubuntu 官方网站：

https://ubuntu.com/download/desktop

选择：

**Ubuntu 26.04 LTS — Intel or AMD 64-bit**

下载文件名应该类似：

```text
ubuntu-26.04-desktop-amd64.iso
```

Ubuntu 官方完整安装说明：

https://ubuntu.com/desktop/docs/en/26.04/tutorial/install-ubuntu-desktop/

## 2. 在 Windows 上制作 U 盘

Rufus 官方网站：

https://rufus.ie/

Ubuntu 官方 Rufus 说明：

https://ubuntu.com/desktop/docs/en/26.04/how-to/create-a-bootable-usb-stick/#using-rufus

简单步骤：

1. 插入 U 盘。
2. 打开 Rufus。
3. 确认 **Device / 设备** 选的是准备清空的 U 盘。
4. 点 **SELECT / 选择**，选择 `ubuntu-26.04-desktop-amd64.iso`。
5. 其他常规选项保持默认。
6. 点 **START / 开始**。
7. 如果提示 ISOHybrid，选择 **Write in ISO Image mode**。
8. 再确认一次要清空的是这个 U 盘。
9. 等状态显示 **READY**，然后关闭 Rufus。

> Ubuntu 当前 26.04 文档里的 Rufus 截图还显示旧的 24.04 文件名。实际下载的文件应该写 **26.04**。

## 3. 从 U 盘启动 REDMI Book

1. 电脑完全关机。
2. 插入 Ubuntu U 盘。
3. 开机后连续按 **F12**，进入一次性启动菜单。
4. 选择 USB / U 盘启动。

如果 F12 被当成功能快捷键，可以试 **Fn+F12**。

**第一次先保持 Secure Boot 开启。** Ubuntu 官方安装镜像可以在 Secure Boot 开启的情况下启动。没有必要为了第一次安装去设置 UEFI 密码或关闭 Secure Boot。

如果启动菜单里完全看不到 U 盘，先停下来确认，不要随便改固件设置。

## 4. 先试用 Ubuntu，再删除任何东西

按语言、键盘、网络走到下面这个界面：

![Ubuntu 26.04 Try or install](https://raw.githubusercontent.com/ubuntu/ubuntu-desktop-documentation/b8ac89eb51c82da87875ab4d65469f5615f0afd6/docs/images/installer/try-or-install-ubuntu.png)

先选 **Try Ubuntu / 试用 Ubuntu**。

简单检查：

- 屏幕显示正常；
- 键盘和触控板正常；
- Wi-Fi 能看到并连接网络；
- 扬声器正常；
- 没有异常卡死或重启。

确认以后，从桌面打开 **Install Ubuntu**。

## 5. 安装选项

使用普通的交互式安装。

### Applications

选择 **Default selection**，CI 机器不需要额外办公软件。

![Ubuntu 26.04 applications](https://raw.githubusercontent.com/ubuntu/ubuntu-desktop-documentation/b8ac89eb51c82da87875ab4d65469f5615f0afd6/docs/images/installer/applications.png)

如果安装程序询问第三方驱动/媒体格式支持，保留推荐选项即可。

## 6. 磁盘设置 —— 这里会真正删除 Windows

选择：

**Erase disk and install Ubuntu / 清除磁盘并安装 Ubuntu**

![Ubuntu 26.04 disk setup](https://raw.githubusercontent.com/ubuntu/ubuntu-desktop-documentation/b8ac89eb51c82da87875ab4d65469f5615f0afd6/docs/images/installer/disk-setup.png)

继续之前，确认目标是电脑内部的 **约 1 TB SSD**。

### 磁盘加密

这台机器准备长期作为无人值守 CI 节点。第一次安装建议**不启用全盘加密**，这样断电重启后不会卡在必须现场输入磁盘密码的界面。以后如果需要加密，可以和远程解锁方案一起设计。

### 如果看不到内部 SSD，马上停

如果安装程序找不到约 1 TB 的内部 SSD，**先停下来确认**。部分 Intel 电脑可能涉及 RST/VMD/存储控制器设置，不要靠猜去改。

Ubuntu 参考：

https://ubuntu.com/desktop/docs/en/26.04/reference/intel-rst-during-ubuntu-installation/

## 7. 创建本地账号

安装程序会要求姓名、电脑名、用户名和密码：

![Ubuntu 26.04 account](https://raw.githubusercontent.com/ubuntu/ubuntu-desktop-documentation/b8ac89eb51c82da87875ab4d65469f5615f0afd6/docs/images/installer/create-your-account.png)

建议电脑名：

```text
redmi-01
```

创建普通管理员账号和强密码。用户名和密码只通过私下方式发送，**绝对不要写进这个公开 GitHub 仓库**。

保留 **Require my password to log in**。

## 8. 最后检查

最后确认页面大致如下：

![Ubuntu 26.04 ready to install](https://raw.githubusercontent.com/ubuntu/ubuntu-desktop-documentation/b8ac89eb51c82da87875ab4d65469f5615f0afd6/docs/images/installer/ready-to-install.png)

重点确认：

- **Erase disk and install Ubuntu**；
- **Default selection**；
- **Disk encryption: None**；
- 根文件系统是 **ext4**；
- 安装目标是内部 SSD。

确认以后点 **Install**。

## 9. 安装完成并重启

完成以后会看到：

![Ubuntu 26.04 installation complete](https://raw.githubusercontent.com/ubuntu/ubuntu-desktop-documentation/b8ac89eb51c82da87875ab4d65469f5615f0afd6/docs/images/installer/installation-complete.png)

点 **Restart now**。提示拔 U 盘时拔掉 U 盘，然后按 Enter。

进入新的 Ubuntu 桌面后先联网。

## 10. 把机器交给远程操作

打开 Terminal（`Ctrl` + `Alt` + `T`），执行：

```bash
curl -fsSLO https://raw.githubusercontent.com/teamleaderleo/compute-node-bootstrap/main/scripts/bootstrap-ubuntu.sh
bash bootstrap-ubuntu.sh
```

然后：

```bash
curl -fsSLO https://raw.githubusercontent.com/teamleaderleo/compute-node-bootstrap/main/scripts/host-report.sh
bash host-report.sh
```

第一个脚本会安装并启动 SSH，同时显示局域网 IP。做到这里以后，现场安装工作就完成了；后续远程接入、GitHub Runner、Glaeda 等可以由远程操作方继续配置。

## 遇到这些情况就停下来确认

- 启动菜单看不到 Ubuntu U 盘；
- 安装程序看不到约 1 TB 的内部 SSD；
- 安装程序准备清除一个看起来不对的磁盘；
- BIOS/UEFI 要求输入不知道的密码；
- Ubuntu 试用环境反复死机/重启；
- 安装后无法正常启动；
- 任何看起来有风险、又不确定是什么意思的界面。

**拍照比猜更有用。**

## 这款机器的 Linux 支持

当前 ArchWiki 对 REDMI Book Pro 16 2025 的记录显示：GPU、Wi-Fi、蓝牙、摄像头、触控板、键盘、TPM、指纹、音频和环境光传感器都可用；另外还记录了 Linux 下的充电上限控制和 `fwupd` 支持：

https://wiki.archlinux.org/title/Xiaomi_RedmiBook_Pro_16_2025
