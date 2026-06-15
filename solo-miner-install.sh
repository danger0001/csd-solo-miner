#!/bin/bash

#############################################
# CSD SOLO GPU 挖矿 - 一键安装脚本 v5.2.1
# GPU 优先，自动检测并配置 CUDA 支持
# 修复：配置文件键名统一为英文
# 推荐使用 solo.sh 多合一管理脚本
#############################################

# ========== 配置区域 ==========
# 引导节点列表（可添加多个）
BOOTSTRAP_NODES=(
    "/ip4/35.223.117.16/tcp/30333/p2p/12D3KooWEyoppNCUx8Yx66oV9fJnriXwCcXwDDUA2kj6vnc6iDEp"
    "/ip4/35.245.161.243/tcp/30333/p2p/12D3KooWHdiAxVd8uMQR1hGWXccidmfCwLqcMpGwR6QcTP6QRMuD"
)

# 安装目录（当前目录，由install.sh创建）
INSTALL_DIR="$(pwd)"

# 钱包地址（运行时输入）
WALLET_ADDRESS=""
# ========== 配置区域结束 ==========

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 交互式输入钱包地址
read_wallet_address() {
    echo ""
    echo "========================================="
    echo "  请输入您的 CSD 钱包地址"
    echo "========================================="
    echo ""
    echo "提示: 钱包地址通常以 0x 开头"
    echo ""

    while true; do
        read -p "钱包地址: " WALLET_ADDRESS

        if [ -z "$WALLET_ADDRESS" ]; then
            log_error "钱包地址不能为空"
            echo ""
        else
            echo ""
            echo "您输入的钱包地址是:"
            echo "$WALLET_ADDRESS"
            echo ""
            read -p "确认无误? (y/n): " confirm

            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                log_info "钱包地址已确认"
                break
            else
                echo ""
                log_warn "请重新输入钱包地址"
                echo ""
            fi
        fi
    done
}

# 检查系统要求
check_system() {
    log_info "检查系统要求..."

    # 检查操作系统
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        log_error "此脚本仅支持 Linux 系统"
        exit 1
    fi

    # 检查Python
    if ! command -v python3 &> /dev/null; then
        log_error "未找到 Python3，请先安装 Python 3.9+"
        exit 1
    fi

    PY_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
    log_info "Python 版本: $PY_VERSION"

    # 检查GPU（推荐但非必需）
    echo ""
    if ! command -v nvidia-smi &> /dev/null; then
        log_warn "⚠️  未检测到 NVIDIA GPU 或驱动未安装"
        log_warn "⚠️  GPU 算力是 CPU 的 100-1000 倍，强烈推荐使用 GPU 挖矿"
        log_warn "⚠️  继续安装将使用 CPU 模式（收益极低）"
        echo ""
        read -p "是否继续安装? (y/n): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            log_info "安装已取消。请先安装 NVIDIA 驱动后再运行此脚本。"
            exit 0
        fi
    else
        log_info "✓ 检测到 NVIDIA GPU:"
        nvidia-smi --query-gpu=name,memory.total --format=csv,noheader | while read line; do
            log_info "  - $line"
        done
    fi

    log_info "系统检查完成"
}


# 创建项目子目录
create_directories() {
    log_info "创建项目子目录..."

    # 创建子目录
    mkdir -p bin config data logs

    log_info "项目目录创建完成: $INSTALL_DIR"
}

# 下载项目文件
download_project() {
    log_info "下载 CSD Solo Miner 项目文件..."

    cd "$INSTALL_DIR"

    # 下载挖矿程序和相关文件
    local base_url="https://raw.githubusercontent.com/danger0001/solo-miner/main"

    log_info "下载挖矿程序..."
    curl -fsSL "$base_url/miner.py" -o miner.py
    curl -fsSL "$base_url/gpu_worker.py" -o gpu_worker.py
    curl -fsSL "$base_url/node_selector.py" -o node_selector.py
    curl -fsSL "$base_url/requirements.txt" -o requirements.txt

    chmod +x miner.py

    log_info "项目文件下载完成"
}

# 安装Python依赖
install_python_deps() {
    log_info "安装 Python 依赖..."

    cd "$INSTALL_DIR"

    # 检查Python版本
    if ! command -v python3 &> /dev/null; then
        log_error "未找到 Python3，请先安装 Python 3.9+"
        exit 1
    fi

    # 安装pip（如果需要）
    if ! command -v pip3 &> /dev/null; then
        log_info "安装 pip..."
        python3 -m ensurepip --upgrade || curl -sS https://bootstrap.pypa.io/get-pip.py | python3
    fi

    # 安装核心依赖
    log_info "安装基础 Python 包（aiohttp, PyYAML, numpy）..."
    pip3 install -r requirements.txt

    # 检测GPU并安装相应的CuPy版本
    echo ""
    if command -v nvidia-smi &> /dev/null; then
        log_info "检测到 GPU，正在安装 CUDA 支持..."

        # 检测CUDA版本
        if command -v nvcc &> /dev/null; then
            CUDA_VERSION=$(nvcc --version | grep "release" | sed 's/.*release \([0-9]*\)\..*/\1/')
            log_info "检测到 CUDA $CUDA_VERSION"

            if [ "$CUDA_VERSION" = "12" ]; then
                log_info "安装 cupy-cuda12x..."
                pip3 install cupy-cuda12x --no-cache-dir || log_warn "CuPy 安装失败，将使用 CPU 模式"
            elif [ "$CUDA_VERSION" = "11" ]; then
                log_info "安装 cupy-cuda11x..."
                pip3 install cupy-cuda11x --no-cache-dir || log_warn "CuPy 安装失败，将使用 CPU 模式"
            else
                log_warn "不支持的 CUDA 版本: $CUDA_VERSION，尝试安装通用版本..."
                pip3 install cupy --no-cache-dir || log_warn "CuPy 安装失败，将使用 CPU 模式"
            fi
        else
            log_warn "未找到 nvcc 命令，尝试自动检测..."
            pip3 install cupy-cuda12x --no-cache-dir || pip3 install cupy-cuda11x --no-cache-dir || log_warn "CUDA 支持安装失败，将使用 CPU 模式"
        fi

        log_info "✓ GPU 支持安装完成"
    else
        log_warn "未检测到 GPU，将使用 CPU 模式（收益极低）"
    fi

    log_info "Python 依赖安装完成"
}

# 生成配置文件
generate_config() {
    log_info "生成配置文件..."

    cd "$INSTALL_DIR"

    # 生成引导节点列表（YAML格式）
    BOOTSTRAP_LIST=""
    for node in "${BOOTSTRAP_NODES[@]}"; do
        BOOTSTRAP_LIST="${BOOTSTRAP_LIST}  - \"$node\"\n"
    done

    # 创建配置文件（使用英文键名以匹配代码）
    cat > config.yaml <<EOF
# CSD Solo Miner 配置文件 v5.2.1

miner:
  wallet_address: "$WALLET_ADDRESS"
  worker_name: "solo-worker-01"

mining:
  domain: "compute"
  proposal_interval: 12
  attestation_interval: 6
  difficulty_target: "0x00000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"

node:
  datadir: "./data"
  rpc_host: "0.0.0.0"
  rpc_port: 8789
  p2p_host: "0.0.0.0"
  p2p_port: 18007
  genesis: "./genesis.bin"

gpu:
  device_id: 0
  threads_per_block: 256
  max_blocks: 4096
  batch_size: 65536

bootnodes:
$(echo -e "$BOOTSTRAP_LIST")
EOF

    # 创建启动脚本
    cat > start.sh <<'STARTEOF'
#!/bin/bash

cd "$(dirname "$0")"

# 设置日志文件
mkdir -p logs
LOG_FILE="logs/miner-$(date +%Y%m%d-%H%M%S).log"

echo "启动 CSD Solo Miner..."
echo "日志文件: $LOG_FILE"
echo ""

# 启动挖矿程序
python3 miner.py 2>&1 | tee "$LOG_FILE"
STARTEOF

    chmod +x start.sh

    log_info "配置文件生成完成"
}

# 创建管理脚本
create_management_scripts() {
    log_info "创建管理脚本..."

    cd "$INSTALL_DIR"

    # 停止脚本
    cat > stop.sh <<'EOF'
#!/bin/bash
pkill -f "python3.*miner.py"
echo "挖矿进程已停止"
EOF

    # 查看状态脚本
    cat > status.sh <<'EOF'
#!/bin/bash
if pgrep -f "python3.*miner.py" > /dev/null; then
    echo "✓ 挖矿进程正在运行"
    echo ""
    echo "进程信息:"
    ps aux | grep "python3.*miner.py" | grep -v grep
    echo ""
    echo "最新日志:"
    tail -n 20 logs/*.log 2>/dev/null | tail -20
else
    echo "✗ 挖矿进程未运行"
fi
EOF

    # 查看日志脚本
    cat > view-logs.sh <<'EOF'
#!/bin/bash
if [ -z "$1" ]; then
    # 查看最新日志
    LATEST_LOG=$(ls -t logs/*.log 2>/dev/null | head -1)
    if [ -n "$LATEST_LOG" ]; then
        tail -f "$LATEST_LOG"
    else
        echo "没有找到日志文件"
    fi
else
    tail -f "logs/$1"
fi
EOF

    chmod +x *.sh

    log_info "管理脚本创建完成"
}

# 显示完成信息
show_completion_info() {
    log_info "安装完成！"
    echo ""
    echo "========================================"
    echo "  CSD SOLO GPU 挖矿安装成功 v5.2.1"
    echo "========================================"
    echo ""
    echo "安装目录: $INSTALL_DIR"
    echo "钱包地址: $WALLET_ADDRESS"
    echo ""
    echo "使用方法："
    echo "  1. 启动挖矿: ./start.sh"
    echo "  2. 停止挖矿: ./stop.sh"
    echo "  3. 查看状态: ./status.sh"
    echo "  4. 查看日志: ./view-logs.sh"
    echo ""
    echo "配置文件: ./config.yaml"
    echo ""
    echo "注意事项："
    echo "  - v5.2.0 提供多合一管理脚本，建议使用 solo.sh"
    echo "  - GPU 挖矿优先，自动配置 CUDA"
    echo "  - 首次启动会自动测试引导节点并选择最优节点"
    echo "  - GPU 算力是 CPU 的 100-1000 倍"
    echo "  - 建议在 screen 或 tmux 中后台运行"
    echo ""
    echo "快速启动："
    echo "  cd ~/solo && ./start.sh"
    echo ""
    echo "后台运行："
    echo "  screen -S solo-miner"
    echo "  cd ~/solo && ./start.sh"
    echo "  # 按 Ctrl+A 然后按 D 离开"
    echo ""
    echo "========================================"
}

# 主函数
main() {
    echo "========================================"
    echo "  CSD SOLO GPU 挖矿 - 一键安装 v5.2.1"
    echo "  GPU 优先 | 自动配置 CUDA"
    echo "========================================"
    echo ""

    read_wallet_address
    check_system
    create_directories
    download_project
    install_python_deps
    generate_config
    create_management_scripts
    show_completion_info
}

# 运行主函数
main
