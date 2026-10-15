# 第二台机器（RTX 4090）配置：加速版

3090 那台的配置见 [README.md](README.md)。这份文档是给 **4090 那台 Windows 电脑**用的，步骤一样，但把上次容易卡住的地方都换成了更快的办法：

| 上次卡住的地方 | 这次的做法 |
|---|---|
| `wsl --install` 报 403 | 直接加 `--web-download`，从 GitHub 下载 |
| Miniforge / PyTorch 下载很慢 | 脚本默认用清华镜像 |
| 安装 OpenSSH Server 要等很久（Windows Update） | 直接下载官方 MSI 安装包，几十秒装完 |

完成后，Mac 上会有两台机器可用：`gpu`（3090）和 `gpu4090`（4090）。Windows 上同样**不安装、不登录任何 Claude 产品**。

> **再加更多机器（比如 RTX A5000）也照这份文档做**，差别只有几处，见文末"[再加一台机器（A5000 等）](#再加一台机器a5000-等)"。

---

## 第 0 步：把文件拿到 4090 电脑上

在本仓库 GitHub 页面点 **Code → Download ZIP**，解压，比如到 `下载\gpu-setup`。
如果这台电脑访问 GitHub 很慢，直接从 3090 那台电脑用 U 盘拷过来也行，但要换成最新版（`windows\0_install_openssh_msi.ps1` 是这次新加的）。

同时在 Mac 上准备好公钥，**用和 3090 那台同一个**，不用重新生成：

```bash
cat ~/.ssh/id_ed25519.pub
```

把这一整行发到 4090 电脑上（公钥可以公开，用微信、邮件、备忘录都行；**不要**发 `id_ed25519` 这个没有 `.pub` 的私钥）。

## 第 1 步：装 WSL2（直接用 GitHub 下载）

1. 先装好最新的 **NVIDIA 显卡驱动**（Windows 这边装；WSL 里不要装驱动）。
2. 右键开始菜单 → **终端(管理员)**：
   ```powershell
   wsl --install --web-download
   ```
3. 重启。开机后自动弹出 Ubuntu 窗口，设置 Linux 用户名和密码。
   如果重启后没有弹出 Ubuntu，或者 `wsl -l -v` 里没有 Ubuntu，再运行一次：
   ```powershell
   wsl --install -d Ubuntu --web-download
   ```

> 还是失败：开启功能后手动装 WSL 安装包。
> ```powershell
> dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
> dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
> ```
> 重启后从 https://github.com/microsoft/WSL/releases 下载最新的 `wsl.x.x.x.x64.msi` 双击安装，再运行 `wsl --install -d Ubuntu --web-download`。

## 第 2 步：在 Ubuntu 里配环境（默认走清华镜像）

打开开始菜单里的 **Ubuntu**：

```bash
cd "/mnt/c/Users/<你的Windows用户名>/Downloads/gpu-setup/windows"   # 换成实际解压位置
bash 1_setup_wsl_env.sh
```

看到 `cuda available: True` 和 `NVIDIA GeForce RTX 4090` 就成功了。
中途卡住就 `Ctrl+C`，直接重新运行，已经装好的部分会跳过。

> 第 2 步和第 3 步互不影响。第 2 步在下载 PyTorch（2GB 多）的时候，可以同时开一个管理员终端去做第 3 步。

## 第 3 步：开 SSH 服务（直接下载安装包，不走 Windows Update）

在 **终端(管理员)** 里，进入解压目录，依次运行两个脚本：

```powershell
cd "$env:USERPROFILE\Downloads\gpu-setup\windows"     # 换成实际解压位置

# 3a. 下载并安装 OpenSSH Server（官方 MSI，几十秒）
powershell -ExecutionPolicy Bypass -File .\0_install_openssh_msi.ps1

# 3b. 配置 SSH（-PubKey 后面粘贴第 0 步那一整行）
powershell -ExecutionPolicy Bypass -File .\2_setup_ssh.ps1 -PubKey "ssh-ed25519 AAAA...（整行）"
```

3b 结束时会打印 **Windows 用户名** 和 **IP 地址**，记下来。

> **3a 下载失败**：在浏览器里打开
> https://github.com/PowerShell/Win32-OpenSSH/releases/latest ，下载 `OpenSSH-Win64-v….msi`
> （这台电脑下载慢，就在 Mac 上下载再拷过来），然后指定文件运行：
> ```powershell
> powershell -ExecutionPolicy Bypass -File .\0_install_openssh_msi.ps1 -MsiPath "$env:USERPROFILE\Downloads\OpenSSH-Win64-v10.0.0.0.msi"
> ```
> 也可以直接双击 MSI 安装，然后接着运行 3b。

## 第 4 步：Mac 上加入第二台机器

1. 在 `~/.ssh/config` 末尾**追加**一段（原来 3090 的 `Host gpu` 不要动），IP 和用户名换成第 3 步打印的：
   ```bash
   cat >> ~/.ssh/config <<'EOF'

   Host gpu4090
       HostName 10.x.x.x
       User 你的Windows用户名
       ServerAliveInterval 30
   EOF
   ```
2. 测试（第一次会问是否信任，输入 `yes`）：
   ```bash
   ssh gpu4090 "uname -a && nvidia-smi"
   ```
3. 在 Mac 的项目文件夹里，**更新** `run_remote.sh`（新版支持选择机器），并换成两台机器版本的 `CLAUDE.md`：
   ```bash
   cd ~/你的项目文件夹
   curl -fsSLO https://raw.githubusercontent.com/GaryWGH/lab-note/main/gpu-setup/mac/run_remote.sh
   curl -fsSL -o CLAUDE.md https://raw.githubusercontent.com/GaryWGH/lab-note/main/gpu-setup/mac/CLAUDE.md.two-gpus.example
   chmod +x run_remote.sh
   GPU_HOST=gpu4090 ./run_remote.sh "python -c 'import torch; print(torch.cuda.get_device_name(0))'"
   ```
   输出 `NVIDIA GeForce RTX 4090` 就完成了。

## 两台机器怎么用

- 不写 `GPU_HOST` 时默认用 3090：`./run_remote.sh "python train.py"`
- 用 4090：`GPU_HOST=gpu4090 ./run_remote.sh "python train.py"`
- 两台的 `data/` 各自独立，在 4090 上跑之前先传一次数据：
  ```bash
  rsync -az data/ gpu4090:~/projects/<项目名>/data/
  ```
- Claude Code 会读 `CLAUDE.md`：正式训练优先放 4090，3090 用来调试或同时跑另一组实验。
- 不建议两台合起来训练同一个模型（多机分布式），网络带宽会成为瓶颈，通常还不如单张 4090 快。

## 常见问题

- **`ssh gpu4090` 超时**：确认两台在同一网络；Windows 网络改成"专用网络"；Mac 开 VPN 的 TUN 模式时，把局域网网段设为直连。
- **IP 变了**：Windows 上 `ipconfig` 查新 IP，改 `~/.ssh/config` 里 `gpu4090` 的 `HostName`。
- **要求输入密码**：重新运行 3b，确认粘贴的是完整一行公钥。
- **SSH 登录后报 `execvpe(/bin/bash) failed: No such file or directory`**：SSH 进入的是**默认** WSL 发行版，而默认的不是 Ubuntu（常见于装过 Docker Desktop 的电脑，默认成了 `docker-desktop`）。在 Windows 上：
  ```powershell
  wsl -l -v                    # 带 * 的是当前默认
  wsl --set-default Ubuntu     # 换成你实际用的 Ubuntu 名字
  ```
  要用 SSH 登录的那个 Windows 账户运行，默认设置是按用户保存的。
- **电脑上已有一个 Ubuntu，但不知道密码**：不用删，以 root 进去重设：
  ```powershell
  wsl -d Ubuntu -u root        # 不需要密码
  ```
  然后 `ls /home` 看用户名，`passwd 用户名` 设新密码。
  确定不要了才删（**会永久删除里面所有文件**，可先 `wsl --export Ubuntu D:\ubuntu-backup.tar` 备份）：
  `wsl --unregister Ubuntu`，再 `wsl --install -d Ubuntu --web-download`。
  不确定是不是别人的，就另装一个 `wsl --install -d Ubuntu-24.04 --web-download`，再 `wsl --set-default Ubuntu-24.04`。
- 其他问题见 [README.md](README.md) 的"常见问题"。

---

## 再加一台机器（A5000 等）

步骤和上面完全一样，只有这几处不同：

1. **显卡驱动**：RTX A5000 这类专业卡要装 **RTX 企业版驱动**，不是游戏卡的 Game Ready 驱动。
   在 NVIDIA 驱动下载页选：产品类型 **NVIDIA RTX / Quadro** → 系列 **NVIDIA RTX Series** → 产品 **RTX A5000**。
   WSL 里同样不要装驱动。
2. **ssh 名称换一个**，比如 `gpua5000`：
   ```bash
   cat >> ~/.ssh/config <<'EOF'

   Host gpua5000
       HostName 10.x.x.x
       User 你的Windows用户名
       ServerAliveInterval 30
   EOF
   ssh gpua5000 "uname -a && nvidia-smi"
   ```
   之后用 `GPU_HOST=gpua5000 ./run_remote.sh "..."` 选择这台。
3. **公钥**：继续用 Mac 上同一个 `~/.ssh/id_ed25519.pub`。
4. **CLAUDE.md**：换成三台机器的版本，让 Claude Code 知道有这台备用机：
   ```bash
   curl -fsSL -o CLAUDE.md https://raw.githubusercontent.com/GaryWGH/lab-note/main/gpu-setup/mac/CLAUDE.md.three-gpus.example
   ```
5. **数据**：这台的 `data/` 也是独立的，要在它上面跑时先传一份过去。

A5000 是 24GB 显存（带 ECC），速度大致和 3090 相当或略慢，功耗更低，适合长时间跑任务。
