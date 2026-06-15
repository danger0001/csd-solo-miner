#!/bin/bash

#############################################
# CSD SOLO 挖矿 - 一键安装脚本
#############################################

# ========== 配置区域 ==========
# 请在此处填入您的钱包地址
WALLET_ADDRESS="YOUR_WALLET_ADDRESS_HERE"

# 引导节点列表（可添加多个）
BOOTSTRAP_NODES=(
    "/ip4/35.223.117.16/tcp/30333/p2p/12D3KooWEyoppNCUx8Yx66oV9fJnriXwCcXwDDUA2kj6vnc6iDEp"
    "/ip4/35.245.161.243/tcp/30333/p2p/12D3KooWHdiAxVd8uMQR1hGWXccidmfCwLqcMpGwR6QcTP6QRMuD"
)

# 安装目录
INSTALL_DIR="$HOME/csd-solo-miner"
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

# 检查钱包地址
check_wallet() {
    if [ "$WALLET_ADDRESS" == "YOUR_WALLET_ADDRESS_HERE" ]; then
        log_error "请先在脚本中配置您的钱包地址！"
        log_info "请编辑此脚本，将 WALLET_ADDRESS 修改为您的钱包地址"
        exit 1
    fi
    log_info "钱包地址: $WALLET_ADDRESS"
}

# 检查系统要求
check_system() {
    log_info "检查系统要求..."

    # 检查操作系统
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        log_error "此脚本仅支持 Linux 系统"
        exit 1
    fi

    # 检查GPU
    if ! command -v nvidia-smi &> /dev/null; then
        log_warn "未检测到 NVIDIA GPU 或驱动未安装"
        log_warn "GPU挖矿需要安装 NVIDIA 驱动"
    else
        log_info "检测到 NVIDIA GPU:"
        nvidia-smi --query-gpu=name --format=csv,noheader
    fi

    log_info "系统检查完成"
}

# 安装依赖
install_dependencies() {
    log_info "安装系统依赖..."

    # 检测包管理器
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y curl wget git build-essential cmake \
            libssl-dev pkg-config libclang-dev clang
    elif command -v yum &> /dev/null; then
        sudo yum install -y curl wget git gcc gcc-c++ make cmake \
            openssl-devel pkgconfig clang
    else
        log_error "不支持的包管理器"
        exit 1
    fi

    log_info "依赖安装完成"
}

# 安装 Rust
install_rust() {
    if command -v rustc &> /dev/null; then
        log_info "Rust 已安装: $(rustc --version)"
        return
    fi

    log_info "安装 Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    log_info "Rust 安装完成"
}

# 安装 CUDA (可选)
install_cuda() {
    if command -v nvcc &> /dev/null; then
        log_info "CUDA 已安装: $(nvcc --version | grep release)"
        return
    fi

    log_warn "未检测到 CUDA，跳过 GPU 优化"
    log_info "如需GPU挖矿，请手动安装 CUDA Toolkit: https://developer.nvidia.com/cuda-downloads"
}

# 创建项目目录
create_directories() {
    log_info "创建项目目录: $INSTALL_DIR"

    if [ -d "$INSTALL_DIR" ]; then
        log_warn "目录已存在，将使用现有目录"
    else
        mkdir -p "$INSTALL_DIR"
    fi

    cd "$INSTALL_DIR"

    # 创建子目录
    mkdir -p bin config data logs

    log_info "项目目录创建完成"
}

# 下载或克隆项目
download_project() {
    log_info "下载 CSD Solo Miner 项目..."

    cd "$INSTALL_DIR"

    # 如果已存在源码，先清理
    if [ -d "compute-substrate" ]; then
        log_warn "清理旧的源码..."
        rm -rf compute-substrate
    fi

    # 克隆仓库
    git clone https://github.com/ComputeSubstrate/compute-substrate.git
    cd compute-substrate

    log_info "项目下载完成"
}

# 编译项目
build_project() {
    log_info "编译项目 (这可能需要较长时间)..."

    cd "$INSTALL_DIR/compute-substrate"

    # 更新 Rust 工具链
    rustup update stable
    rustup target add wasm32-unknown-unknown

    # 编译（启用 GPU 特性）
    if command -v nvcc &> /dev/null; then
        log_info "使用 GPU 特性编译..."
        cargo build --release --features gpu-mining
    else
        log_warn "使用 CPU 模式编译..."
        cargo build --release
    fi

    # 复制编译好的二进制文件
    cp target/release/compute-substrate "$INSTALL_DIR/bin/compute-substrate"

    log_info "编译完成"
}

# 生成配置文件
generate_config() {
    log_info "生成配置文件..."

    cd "$INSTALL_DIR/config"

    # 生成引导节点参数
    BOOTSTRAP_PARAMS=""
    for node in "${BOOTSTRAP_NODES[@]}"; do
        BOOTSTRAP_PARAMS="$BOOTSTRAP_PARAMS --bootnodes $node"
    done

    # 创建配置文件
    cat > miner-config.toml <<EOF
# CSD Solo Miner 配置文件

[miner]
wallet_address = "$WALLET_ADDRESS"

[network]
bootstrap_nodes = [
$(printf '    "%s",\n' "${BOOTSTRAP_NODES[@]}" | sed '$ s/,$//')
]

[mining]
# GPU 设置
use_gpu = true
gpu_device = 0

# CPU 线程数（如果不使用GPU）
cpu_threads = 4

# 最优节点模式（低带宽模式）
low_bandwidth_mode = true
use_single_best_node = true

[paths]
data_dir = "$INSTALL_DIR/data"
log_dir = "$INSTALL_DIR/logs"
EOF

    # 创建启动脚本
    cat > "$INSTALL_DIR/start-miner.sh" <<EOF
#!/bin/bash

cd "$INSTALL_DIR"

# 设置日志文件
LOG_FILE="logs/miner-\$(date +%Y%m%d-%H%M%S).log"

# 启动挖矿节点
./bin/compute-substrate \\
    --miner \\
    --miner-address $WALLET_ADDRESS \\
    --base-path ./data \\
    $BOOTSTRAP_PARAMS \\
    --enable-low-bandwidth-mode \\
    --single-best-node \\
    2>&1 | tee "\$LOG_FILE"
EOF

    chmod +x "$INSTALL_DIR/start-miner.sh"

    log_info "配置文件生成完成"
}

# 创建管理脚本
create_management_scripts() {
    log_info "创建管理脚本..."

    # 停止脚本
    cat > "$INSTALL_DIR/stop-miner.sh" <<'EOF'
#!/bin/bash
pkill -f "compute-substrate.*--miner"
echo "挖矿进程已停止"
EOF

    # 查看状态脚本
    cat > "$INSTALL_DIR/status.sh" <<'EOF'
#!/bin/bash
if pgrep -f "compute-substrate.*--miner" > /dev/null; then
    echo "✓ 挖矿进程正在运行"
    echo ""
    echo "进程信息:"
    ps aux | grep "compute-substrate.*--miner" | grep -v grep
    echo ""
    echo "最新日志:"
    tail -n 20 logs/*.log 2>/dev/null | tail -20
else
    echo "✗ 挖矿进程未运行"
fi
EOF

    # 查看日志脚本
    cat > "$INSTALL_DIR/view-logs.sh" <<'EOF'
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

    chmod +x "$INSTALL_DIR"/*.sh

    log_info "管理脚本创建完成"
}

# 显示完成信息
show_completion_info() {
    log_info "安装完成！"
    echo ""
    echo "========================================"
    echo "  CSD SOLO 挖矿安装成功"
    echo "========================================"
    echo ""
    echo "安装目录: $INSTALL_DIR"
    echo "钱包地址: $WALLET_ADDRESS"
    echo ""
    echo "使用方法："
    echo "  1. 启动挖矿: cd $INSTALL_DIR && ./start-miner.sh"
    echo "  2. 停止挖矿: cd $INSTALL_DIR && ./stop-miner.sh"
    echo "  3. 查看状态: cd $INSTALL_DIR && ./status.sh"
    echo "  4. 查看日志: cd $INSTALL_DIR && ./view-logs.sh"
    echo ""
    echo "配置文件位置: $INSTALL_DIR/config/miner-config.toml"
    echo ""
    echo "注意事项："
    echo "  - 首次启动需要同步区块链数据，可能需要一些时间"
    echo "  - 建议在 screen 或 tmux 中运行挖矿进程"
    echo "  - 低带宽模式已启用，将只使用一个最优节点"
    echo ""
    echo "========================================"
}

# 主函数
main() {
    echo "========================================"
    echo "  CSD SOLO 挖矿 - 一键安装脚本"
    echo "========================================"
    echo ""

    check_wallet
    check_system
    install_dependencies
    install_rust
    install_cuda
    create_directories
    download_project
    build_project
    generate_config
    create_management_scripts
    show_completion_info
}

# 运行主函数
main
