#!/usr/bin/env bash
# 在 WSL2 的 Ubuntu 终端里运行（不是 PowerShell）：
#   bash 1_setup_wsl_env.sh          # 默认建名为 oect 的 conda 环境
#   bash 1_setup_wsl_env.sh 其他名字
#
# 做的事：装 rsync/tmux 等工具 → 装 Miniforge（conda）→ 建环境 → 装 CUDA 版 PyTorch → 用 3090 跑一次测试。
# 可以重复运行，已经装好的步骤会跳过。
set -euo pipefail

ENV_NAME="${1:-oect}"
PY_VER="3.11"

echo "== 1/5 检查显卡驱动 =="
if [ -e /usr/lib/wsl/lib/nvidia-smi ]; then
  /usr/lib/wsl/lib/nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv
else
  echo "没找到 nvidia-smi。请先在 Windows 上装好最新的 NVIDIA 显卡驱动（WSL 里不要装驱动），然后在 PowerShell 里运行 wsl --shutdown 再重试。"
  exit 1
fi

echo "== 2/5 安装常用工具 =="
sudo apt-get update
sudo apt-get install -y rsync tmux git curl build-essential

echo "== 3/5 安装 Miniforge（conda，默认用 conda-forge 源）=="
if [ ! -d "$HOME/miniforge3" ]; then
  curl -fsSL -o /tmp/miniforge.sh \
    https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh
  bash /tmp/miniforge.sh -b -p "$HOME/miniforge3"
  rm -f /tmp/miniforge.sh
  "$HOME/miniforge3/bin/conda" init bash >/dev/null
else
  echo "已安装，跳过"
fi
# shellcheck disable=SC1091
source "$HOME/miniforge3/etc/profile.d/conda.sh"

echo "== 4/5 建 conda 环境 $ENV_NAME 并装 PyTorch =="
if ! conda env list | grep -qE "^${ENV_NAME}[[:space:]]"; then
  conda create -y -n "$ENV_NAME" "python=${PY_VER}"
fi
conda activate "$ENV_NAME"
python -m pip install --upgrade pip
# Linux 上 pip 默认的 torch 就是带 CUDA 的版本
python -m pip install torch numpy scipy pandas matplotlib scikit-learn tqdm

mkdir -p "$HOME/projects"

echo "== 5/5 测试 GPU =="
python - <<'EOF'
import torch
print("torch", torch.__version__, "| CUDA", torch.version.cuda)
ok = torch.cuda.is_available()
print("cuda available:", ok)
if ok:
    print("GPU:", torch.cuda.get_device_name(0))
    x = torch.randn(4096, 4096, device="cuda")
    torch.cuda.synchronize()
    print("矩阵乘法测试通过，结果:", float((x @ x).sum()))
else:
    raise SystemExit("CUDA 不可用：检查 Windows 显卡驱动后，在 PowerShell 运行 wsl --shutdown 再试")
EOF

echo
echo "完成。环境名：$ENV_NAME，conda 路径：~/miniforge3，项目目录：~/projects"
