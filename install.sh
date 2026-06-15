#!/usr/bin/env bash
# install.sh — CSD 单机 GPU 矿工 · 一键安装脚本
# 用法：curl -fsSL https://raw.githubusercontent.com/danger0001/solo-miner/main/install.sh | bash
set -euo pipefail

log_info()  { echo "[信息] $*"; }
log_ok()    { echo "[完成] $*"; }
log_warn()  { echo "[警告] $*"; }
log_step()  { echo ""; echo "==== $* ===="; }
log_err()   { echo "[错误] $*" >&2; exit 1; }

CSD_BASE_URL="https://computesubstrate.org/downloads"

MAINNET_NODES=(
    "/ip4/151.240.121.186/tcp/17999"
    "/ip4/151.240.121.220/tcp/17999"
    "/ip4/151.240.121.187/tcp/17999"
    "/ip4/158.69.116.36/tcp/17999"
    "/ip4/145.239.0.111/tcp/17999"
    "/ip4/151.240.121.189/tcp/17999"
)

# ── 欢迎界面 ──────────────────────────────────────────────────────────────────
clear || true
echo ""
echo "=================================================="
echo "     CSD 单机 GPU 矿工  ·  一键安装程序"
echo "     Compute Substrate Solo GPU Miner"
echo "=================================================="
echo ""
echo "  本脚本将自动完成以下操作："
echo "  1. 检测运行环境（Python、NVIDIA GPU、CUDA）"
echo "  2. 下载 csd 节点程序和 genesis 文件"
echo "  3. 安装 Python 依赖（含 GPU 支持）"
echo "  4. 生成配置文件"
echo "  5. 引导填写钱包地址"
echo "  6. 启动挖矿"
echo ""
read -rp "  按回车键开始安装，或按 Ctrl+C 退出... "

# ── 第一步：检测运行环境 ──────────────────────────────────────────────────────
log_step "第一步：检测运行环境"

log_info "检测 Python 版本..."
python3 --version >/dev/null 2>&1 || log_err "未找到 Python 3，请先安装 Python 3.9 及以上版本"
PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
log_ok "Python $PY_VER"

GPU_AVAILABLE=false
log_info "检测 NVIDIA GPU..."
if command -v nvidia-smi &>/dev/null; then
    GPU_LIST=$(nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader)
    GPU_COUNT=$(echo "$GPU_LIST" | wc -l)
    log_ok "检测到 ${GPU_COUNT} 块 NVIDIA 显卡："
    while IFS= read -r LINE; do
        echo "        -> $LINE"
    done <<< "$GPU_LIST"
    GPU_AVAILABLE=true

    if command -v nvcc &>/dev/null; then
        CUDA_VER=$(nvcc --version | grep -oP 'release \K[0-9]+\.[0-9]+')
        log_ok "CUDA $CUDA_VER"
    else
        log_warn "nvcc 未找到，将尝试自动匹配 CUDA 包"
    fi
else
    log_warn "未检测到 NVIDIA 显卡，将使用 CPU 模式运行（速度较慢）"
    log_warn "如需 GPU 加速，请安装 NVIDIA 驱动和 CUDA Toolkit"
fi

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_TAG="amd64" ;;
    aarch64) ARCH_TAG="arm64" ;;
    *)       log_err "不支持的系统架构：$ARCH" ;;
esac
log_info "系统：$OS / $ARCH"

# ── 第二步：下载 csd 节点程序和 genesis 文件 ─────────────────────────────────
log_step "第二步：下载 csd 节点程序和 genesis 文件"

CSD_BIN="csd-${OS}-${ARCH_TAG}"

if [[ ! -f "csd" ]]; then
    log_info "下载 csd 节点程序（$CSD_BIN）..."
    curl -#fSL "${CSD_BASE_URL}/${CSD_BIN}" -o csd || log_err "下载 csd 程序失败，请检查网络连接"
    chmod +x csd
    log_ok "csd 程序下载完成"
else
    log_ok "csd 程序已存在，跳过下载"
fi

if [[ ! -f "genesis.bin" ]]; then
    log_info "下载 genesis.bin 创世文件..."
    curl -#fSL "${CSD_BASE_URL}/genesis.bin" -o genesis.bin || log_err "下载 genesis.bin 失败"
    log_ok "genesis.bin 下载完成"
else
    log_ok "genesis.bin 已存在，跳过下载"
fi

if [[ ! -f "checksums.txt" ]]; then
    log_info "下载校验文件..."
    curl -fsSL "${CSD_BASE_URL}/checksums.txt" -o checksums.txt 2>/dev/null || \
        log_warn "无法下载 checksums.txt，跳过文件校验"
fi
if [[ -f "checksums.txt" ]]; then
    log_info "校验文件完整性..."
    sha256sum -c checksums.txt --ignore-missing && log_ok "文件校验通过" || \
        log_warn "校验不匹配，建议重新运行安装脚本"
fi

# ── 第三步：安装 Python 依赖 ──────────────────────────────────────────────────
log_step "第三步：安装 Python 依赖"

# 确保 pip 可用，兼容所有系统
if ! python3 -m pip --version &>/dev/null; then
    log_info "pip 未安装，正在尝试安装..."
    if python3 -m ensurepip --upgrade &>/dev/null 2>&1; then
        log_ok "pip 已通过 ensurepip 安装"
    else
        log_info "通过 get-pip.py 安装 pip..."
        curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
        python3 /tmp/get-pip.py -q
        rm -f /tmp/get-pip.py
        log_ok "pip 安装完成"
    fi
fi
# root 用户需加 --break-system-packages 避免系统包冲突
PIP_OPTS="-q"
if [[ "$(id -u)" == "0" ]]; then
    PIP_OPTS="-q --break-system-packages"
fi
PIP="python3 -m pip"

log_info "升级 pip..."
$PIP install $PIP_OPTS --upgrade pip

log_info "安装基础依赖（aiohttp, PyYAML, numpy）..."
$PIP install $PIP_OPTS aiohttp PyYAML numpy
log_ok "基础依赖安装完成"

if [[ "$GPU_AVAILABLE" == "true" ]]; then
    log_info "安装 GPU（CUDA）支持库..."
    if command -v nvcc &>/dev/null; then
        # 只取主版本号：CUDA 12.x → cupy-cuda12x，CUDA 11.x → cupy-cuda11x
        CUDA_MAJOR=$(nvcc --version | grep -oP 'release \K[0-9]+' | head -1)
        CUPY_PKG="cupy-cuda${CUDA_MAJOR}x"
        log_info "检测到 CUDA $CUDA_MAJOR，安装 $CUPY_PKG..."
        $PIP install $PIP_OPTS "$CUPY_PKG" && log_ok "CuPy GPU 库安装完成" || {
            log_warn "CuPy 安装失败，尝试安装 pycuda..."
            $PIP install $PIP_OPTS pycuda && log_ok "pycuda 安装完成" || \
                log_warn "GPU 库安装失败，将使用 CPU 模式"
        }
    else
        log_info "nvcc 未找到，安装 cupy-cuda12x（默认 CUDA 12）..."
        $PIP install $PIP_OPTS cupy-cuda12x && log_ok "CuPy GPU 库安装完成" || \
            log_warn "GPU 库安装失败，将使用 CPU 模式"
    fi
else
    log_warn "跳过 GPU 库安装（无显卡）"
fi

# ── 第四步：下载矿工程序 ──────────────────────────────────────────────────────
log_step "第四步：下载矿工程序"

REPO_RAW="https://raw.githubusercontent.com/danger0001/solo-miner/main"
for FILE in miner.py gpu_worker.py node_selector.py start.sh config.yaml.example requirements.txt; do
    if [[ ! -f "$FILE" ]]; then
        log_info "下载 $FILE ..."
        curl -fsSL "${REPO_RAW}/${FILE}" -o "$FILE" || log_warn "下载 $FILE 失败，请手动获取"
    else
        log_ok "$FILE 已存在，跳过"
    fi
done
chmod +x start.sh 2>/dev/null || true

# ── 第五步：生成配置文件 ──────────────────────────────────────────────────────
log_step "第五步：配置挖矿参数"

echo ""
echo "  请选择引导节点配置："
echo "  1) 使用全部 6 个主网引导节点（推荐，连接最稳定）"
echo "  2) 手动输入自定义引导节点"
echo ""
read -rp "  请输入选项 [1/2，默认 1]：" NODE_CHOICE
NODE_CHOICE=${NODE_CHOICE:-1}

if [[ "$NODE_CHOICE" == "2" ]]; then
    echo ""
    echo "  格式：/ip4/IP地址/tcp/端口"
    echo "  多个节点用逗号分隔"
    read -rp "  引导节点：" CUSTOM_NODES
    BN_YAML=""
    IFS=',' read -ra NODE_ARR <<< "$CUSTOM_NODES"
    for N in "${NODE_ARR[@]}"; do
        N=$(echo "$N" | xargs)
        BN_YAML="${BN_YAML}  - \"$N\"\n"
    done
else
    BN_YAML=""
    for N in "${MAINNET_NODES[@]}"; do
        BN_YAML="${BN_YAML}  - \"$N\"\n"
    done
    log_info "已选择全部 ${#MAINNET_NODES[@]} 个主网引导节点"
fi

GPU_DEVICE=0
if [[ "$GPU_AVAILABLE" == "true" ]] && [[ $(nvidia-smi --query-gpu=index --format=csv,noheader | wc -l) -gt 1 ]]; then
    echo ""
    log_info "检测到多块显卡，请选择用于挖矿的显卡编号（从 0 开始）："
    nvidia-smi --query-gpu=index,name --format=csv,noheader | while IFS=, read -r IDX NAME; do
        echo "      [$IDX] $NAME"
    done
    read -rp "  显卡编号 [默认 0]：" GPU_DEVICE
    GPU_DEVICE=${GPU_DEVICE:-0}
fi

echo ""
echo "  重要：请输入你的 CSD 钱包地址（用于接收挖矿奖励）"
read -rp "  钱包地址：" WALLET
WALLET=${WALLET:-"YOUR_WALLET_ADDRESS_HERE"}

read -rp "  工作器名称 [默认 worker-01]：" WORKER_NAME
WORKER_NAME=${WORKER_NAME:-worker-01}

cat > config.yaml << YAML_EOF
# CSD 单机 GPU 矿工配置文件

miner:
  wallet_address: "${WALLET}"
  domain: "compute"
  worker_name: "${WORKER_NAME}"

node:
  datadir: "./cs.db"
  rpc_host: "0.0.0.0"
  rpc_port: 8789
  p2p_host: "0.0.0.0"
  p2p_port: 18007
  genesis: "./genesis.bin"

gpu:
  device_id: ${GPU_DEVICE}
  threads_per_block: 256
  max_blocks: 4096
  batch_size: 65536

mining:
  proposal_interval: 12
  attestation_interval: 6
  max_retries: 5
  difficulty_target: "0x00000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"

bootnodes:
$(echo -e "$BN_YAML")
YAML_EOF

log_ok "配置文件 config.yaml 已生成"

# ── 完成 ──────────────────────────────────────────────────────────────────────
echo ""
echo "=================================================="
echo "  安装成功！"
echo "=================================================="
echo ""
echo "  配置摘要："
echo "  · 钱包地址  : $WALLET"
echo "  · 工作器    : $WORKER_NAME"
echo "  · 显卡设备  : $GPU_DEVICE"
echo "  · 带宽检测  : 启动时自动检测，低于 5 Mbps 仅使用最优单节点"
echo "  · 监控面板  : http://127.0.0.1:9090/stats"
echo ""

if [[ "$WALLET" == "YOUR_WALLET_ADDRESS_HERE" ]]; then
    log_warn "钱包地址尚未设置！请编辑 config.yaml 后再次运行："
    echo "      nano config.yaml          # 修改 wallet_address"
    echo "      ./start.sh                # 启动挖矿"
    echo ""
    exit 0
fi

read -rp "  按回车键启动挖矿，或按 Ctrl+C 退出... "
echo ""

exec ./start.sh
