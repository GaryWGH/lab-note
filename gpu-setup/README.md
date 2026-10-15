# 用 Windows 的 3090 跑程序（Mac 上的 Claude 通过 SSH 远程调试）

结构：Claude 只在 **Mac** 上运行和登录。Windows 只当一台通过 SSH 连接的 GPU 服务器，**不安装、不登录任何 Claude 产品**。

```
Mac（Claude Code，改代码）──ssh / rsync──▶ Windows → WSL2 Ubuntu（conda + PyTorch + RTX 3090）
```

## 文件

| 文件 | 在哪运行 | 作用 |
|---|---|---|
| `windows/1_setup_wsl_env.sh` | Windows 上的 **Ubuntu (WSL) 终端** | 装工具、conda、CUDA 版 PyTorch，测试 GPU |
| `windows/2_setup_ssh.ps1` | Windows 上的 **管理员 PowerShell** | 开 SSH 服务、放 Mac 公钥、防休眠 |
| `mac/run_remote.sh` | Mac 上的项目根目录 | 同步代码并在 3090 上运行 |
| `mac/CLAUDE.md.example` | Mac 上的项目根目录（改名为 `CLAUDE.md`） | 告诉 Claude Code 怎么用远端 GPU |

把文件拿到 Windows 上最简单的办法：在本仓库的 GitHub 页面点 **Code → Download ZIP**，解压到比如 `下载\gpu-setup`。

---

## 第 0 步：Mac 上生成密钥（如果还没有）

```bash
ls ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519      # 一路回车
cat ~/.ssh/id_ed25519.pub                                # 复制这一整行，第 3 步要用
```

## 第 1 步：Windows 装 WSL2

1. 先装好最新的 **NVIDIA 显卡驱动**（Windows 这边装；WSL 里不要装驱动）。
2. 右键开始菜单 → **终端(管理员)**，运行：
   ```powershell
   wsl --install
   ```
3. 重启电脑。开机后会自动弹出 Ubuntu 窗口，设置一个 Linux 用户名和密码（密码输入时不显示，正常）。

## 第 2 步：在 Ubuntu 里配环境

打开开始菜单里的 **Ubuntu**，进入解压的目录运行脚本（Windows 的 C 盘在 WSL 里是 `/mnt/c`）：

```bash
cd "/mnt/c/Users/<你的Windows用户名>/Downloads/gpu-setup/windows"   # 换成实际解压位置
bash 1_setup_wsl_env.sh
```

最后看到 `cuda available: True` 和 `NVIDIA GeForce RTX 3090` 就成功了。

## 第 3 步：开 SSH 服务

在 **终端(管理员)** 里（PowerShell），进入解压目录运行，`-PubKey` 后面粘贴第 0 步复制的那一行：

```powershell
cd "$env:USERPROFILE\Downloads\gpu-setup\windows"     # 换成实际解压位置
powershell -ExecutionPolicy Bypass -File .\2_setup_ssh.ps1 -PubKey "ssh-ed25519 AAAA...（整行）"
```

脚本最后会打印 **Windows 用户名** 和 **IP 地址**，记下来。

## 第 4 步：Mac 上连接

1. 编辑 `~/.ssh/config`（没有就新建），加入：
   ```
   Host gpu
       HostName 192.168.x.x          # 第 3 步打印的 IP
       User 你的Windows用户名          # 第 3 步打印的用户名
       ServerAliveInterval 30
   ```
2. 测试：
   ```bash
   ssh gpu "uname -a && nvidia-smi"
   ```
   显示 Linux 信息和 3090 就配好了。第一次会问是否信任主机，输入 `yes`。
3. 把 `mac/run_remote.sh` 和 `mac/CLAUDE.md.example` 复制到 Mac 上项目的根目录：
   ```bash
   mv CLAUDE.md.example CLAUDE.md
   chmod +x run_remote.sh
   ./run_remote.sh "python -c 'import torch; print(torch.cuda.get_device_name(0))'"
   ```

之后在这个项目里用 Claude Code，它会读 `CLAUDE.md`，自己把代码同步到 3090 上运行、看报错、改代码。

---

## 常见问题

**`ssh gpu` 卡住然后超时**
- 两台电脑要在同一个网络里。不在同一网络（比如一个在家一个在实验室）可以两边都装 Tailscale，`HostName` 换成 Tailscale 的 IP（**不要**开 Exit Node）。
- Mac 开着 VPN 的 TUN/增强模式时，运行 `route get <Windows的IP>`，如果 `interface` 是 `utun...`，在 VPN 里把局域网网段（`192.168.0.0/16`、`10.0.0.0/8` 等）设为直连。
- Windows 网络被设成"公用网络"时防火墙可能拦截，可以在设置里改成"专用网络"。

**要求输入密码 / `Permission denied (publickey)`**
- 重新运行第 3 步的脚本，确认 `-PubKey` 粘贴的是完整一行（以 `ssh-ed25519` 开头）。

**`rsync` 报错**
- 确认第 2 步装了 rsync：`ssh gpu "which rsync"`。
- 还是报错的话，把完整报错信息贴给 Claude。

**断开 SSH 后后台任务被停掉**
- 第 3 步的脚本建了一个 "WSL keep-alive" 计划任务来防止这个问题，它在登录 Windows 后自动运行。需要 Windows 处于登录状态（锁屏可以，注销不行）。

**CUDA 不可用**
- 更新 Windows 上的 NVIDIA 驱动，然后在 PowerShell 运行 `wsl --shutdown`，重新打开 Ubuntu 再试。
