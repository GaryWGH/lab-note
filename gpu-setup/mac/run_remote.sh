#!/usr/bin/env bash
# 在 Windows(WSL2) 的 3090 上运行命令。代码以 Mac 为准，每次运行前自动同步过去。
# 放在 Mac 上项目的根目录，chmod +x run_remote.sh 后使用。
#
# 用法：
#   ./run_remote.sh "python train.py --epochs 2"        # 前台运行，直接看输出（适合调试）
#   ./run_remote.sh -b exp1 "python train.py"          # 后台运行（tmux），日志写到 logs/exp1.log
#   ./run_remote.sh -f                                  # 把远端 outputs/ 和 logs/ 拉回 Mac
#
# 有多台 GPU 机器时，用 GPU_HOST 选择（不写默认 gpu，即 3090）：
#   GPU_HOST=gpu4090 ./run_remote.sh "python train.py"
#   GPU_HOST=gpu4090 ./run_remote.sh -f
#
# 需要改的只有下面三行。
HOST="${GPU_HOST:-gpu}"                           # 对应 ~/.ssh/config 里的 Host
ENV=oect                                          # 远端 conda 环境名
CONDA_SH='~/miniforge3/etc/profile.d/conda.sh'    # 远端 conda 路径（1_setup_wsl_env.sh 装在这里）

set -euo pipefail
PROJ="$(basename "$PWD")"
REMOTE_DIR='~/projects/'"$PROJ"    # ~ 在远端展开，即 WSL 的 /home/<用户名>/projects/<项目名>

sync_up() {
  ssh "$HOST" "mkdir -p $REMOTE_DIR/logs $REMOTE_DIR/outputs $REMOTE_DIR/data"
  # data/ outputs/ logs/ 只留在远端，不会被 --delete 删掉
  rsync -az --delete \
    --exclude '.git/' --exclude 'data/' --exclude 'outputs/' --exclude 'logs/' \
    --exclude '__pycache__/' --exclude '.DS_Store' \
    ./ "$HOST:$REMOTE_DIR/"
}

PREFIX="cd $REMOTE_DIR && source $CONDA_SH && conda activate $ENV"

case "${1:-}" in
  -f)
    mkdir -p outputs logs
    rsync -az "$HOST:$REMOTE_DIR/outputs/" ./outputs/ || true
    rsync -az "$HOST:$REMOTE_DIR/logs/" ./logs/ || true
    echo "已拉回 outputs/ 和 logs/"
    ;;
  -b)
    NAME="$2"; shift 2
    sync_up
    ssh "$HOST" "tmux new-session -d -s $NAME \"$PREFIX && ($*) 2>&1 | tee logs/$NAME.log\""
    echo "后台任务 $NAME 已启动。查看进度：ssh $HOST 'tail -n 50 $REMOTE_DIR/logs/$NAME.log'"
    ;;
  "")
    echo "用法见脚本开头注释"; exit 1
    ;;
  *)
    sync_up
    ssh -t "$HOST" "$PREFIX && $*"
    ;;
esac
