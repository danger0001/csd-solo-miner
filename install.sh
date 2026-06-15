#!/usr/bin/env bash
# install.sh — CSD 单机 GPU 矿工 · 一键安装启动脚本
# 用法：chmod +x install.sh && ./install.sh
set -euo pipefail

# ── 颜色定义 ────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

信息()  { echo -e "${CYAN}[信息]${RESET} $*"; }
成功()  { echo -e "${GREEN}[完成]${RESET} $*"; }
警告()  { echo -e "${YELLOW}[警告]${RESET} $*"; }
错误()  { echo -e "${RED}[错误]${RESET} $*"; exit 1; }
步骤()  { echo -e "\n${BOLD}${BLUE}▶ $*${RESET}"; }

CSD_BASE_URL="https://computesubstrate.org/downloads"

# ── 主网引导节点 ──────────────────────────────────────────────────────────────
主网引导节点=(
    "/ip4/151.240.121.186/tcp/17999"
    "/ip4/151.240.121.220/tcp/17999"
    "/ip4/151.240.121.187/tcp/17999"
    "/ip4/158.69.116.36/tcp/17999"
    "/ip4/145.239.0.111/tcp/17999"
    "/ip4/151.240.121.189/tcp/17999"
)

# ── 欢迎界面 ──────────────────────────────────────────────────────────────────
clear
echo -e "${粗}${蓝}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║        CSD 单机 GPU 矿工  ·  一键安装程序        ║"
echo "  ║         Compute Substrate Solo GPU Miner         ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${重置}"
echo "  本脚本将自动完成以下操作："
echo "  1. 检测运行环境（Python、NVIDIA GPU、CUDA）"
echo "  2. 下载 csd 节点程序和 genesis 文件"
echo "  3. 安装 Python 依赖（含 GPU 支持）"
echo "  4. 生成配置文件"
echo "  5. 引导填写钱包地址"
echo "  6. 启动挖矿"
echo ""
read -rp "  按回车键开始安装，或按 Ctrl+C 退出... "

# ── 第一步：环境检测 ──────────────────────────────────────────────────────────
步骤 "第一步：检测运行环境"

# Python 版本
信息 "检测 Python 版本..."
python3 --version >/dev/null 2>&1 || 错误 "未找到 Python 3，请先安装 Python 3.9 及以上版本"
PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
成功 "Python $PY_VER"

# GPU 检测
GPU_可用=false
信息 "检测 NVIDIA GPU..."
if command -v nvidia-smi &>/dev/null; then
    GPU_列表=$(nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader)
    GPU_数量=$(echo "$GPU_列表" | wc -l)
    成功 "检测到 ${GPU_数量} 块 NVIDIA 显卡："
    while IFS= read -r 行; do
        echo "        → $行"
    done <<< "$GPU_列表"
    GPU_可用=true

    # CUDA 版本
    if command -v nvcc &>/dev/null; then
        CUDA_版本=$(nvcc --version | grep -oP 'release \K[0-9]+\.[0-9]+')
        成功 "CUDA $CUDA_版本"
    else
        警告 "nvcc 未找到，将尝试自动匹配 CUDA 包"
    fi
else
    警告 "未检测到 NVIDIA 显卡，将使用 CPU 模式运行（速度较慢）"
    警告 "如需 GPU 加速，请安装 NVIDIA 驱动和 CUDA Toolkit"
fi

# 系统架构
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  架构标签="amd64" ;;
    aarch64) 架构标签="arm64" ;;
    *)       错误 "不支持的系统架构：$ARCH" ;;
esac
信息 "系统：$OS / $ARCH"

# ── 第二步：下载文件 ──────────────────────────────────────────────────────────
步骤 "第二步：下载 csd 节点程序和 genesis 文件"

CSD_二进制="csd-${OS}-${架构标签}"

if [[ ! -f "csd" ]]; then
    信息 "下载 csd 节点程序（$CSD_二进制）..."
    curl -#fSL "${CSD_BASE_URL}/${CSD_二进制}" -o csd || 错误 "下载 csd 程序失败，请检查网络连接"
    chmod +x csd
    成功 "csd 程序下载完成"
else
    成功 "csd 程序已存在，跳过下载"
fi

if [[ ! -f "genesis.bin" ]]; then
    信息 "下载 genesis.bin 创世文件..."
    curl -#fSL "${CSD_BASE_URL}/genesis.bin" -o genesis.bin || 错误 "下载 genesis.bin 失败"
    成功 "genesis.bin 下载完成"
else
    成功 "genesis.bin 已存在，跳过下载"
fi

# 校验文件
if [[ ! -f "checksums.txt" ]]; then
    信息 "下载校验文件..."
    curl -fsSL "${CSD_BASE_URL}/checksums.txt" -o checksums.txt 2>/dev/null || \
        警告 "无法下载 checksums.txt，跳过文件校验"
fi
if [[ -f "checksums.txt" ]]; then
    信息 "校验文件完整性..."
    sha256sum -c checksums.txt --ignore-missing && 成功 "文件校验通过" || \
        警告 "校验不匹配，文件可能已损坏，建议重新运行安装脚本"
fi

# ── 第三步：安装 Python 依赖 ──────────────────────────────────────────────────
步骤 "第三步：安装 Python 依赖"

信息 "升级 pip..."
pip3 install -q --upgrade pip

信息 "安装基础依赖（aiohttp, PyYAML, numpy）..."
pip3 install -q aiohttp PyYAML numpy
成功 "基础依赖安装完成"

if [[ "$GPU_可用" == "true" ]]; then
    信息 "安装 GPU（CUDA）支持库..."
    if command -v nvcc &>/dev/null; then
        CUDA_主版本=$(nvcc --version | grep -oP 'release \K[0-9]+' | head -1)
        CUDA_次版本=$(nvcc --version | grep -oP 'release [0-9]+\.\K[0-9]+' | head -1)
        CUPY包="cupy-cuda${CUDA_主版本}${CUDA_次版本}x"
        信息 "安装 $CUPY包..."
        pip3 install -q "$CUPY包" && 成功 "CuPy GPU 库安装完成" || {
            警告 "CuPy 安装失败，尝试安装 pycuda..."
            pip3 install -q pycuda && 成功 "pycuda 安装完成" || \
                警告 "GPU 库安装失败，将使用 CPU 模式"
        }
    else
        信息 "安装 cupy-cuda12x（默认 CUDA 12）..."
        pip3 install -q cupy-cuda12x && 成功 "CuPy GPU 库安装完成" || \
            警告 "GPU 库安装失败，将使用 CPU 模式"
    fi
else
    警告 "跳过 GPU 库安装（无显卡）"
fi

# ── 第四步：生成配置文件 ──────────────────────────────────────────────────────
步骤 "第四步：配置挖矿参数"

# 引导节点选择
echo ""
echo "  请选择引导节点配置："
echo "  1) 使用全部 6 个主网引导节点（推荐，连接最稳定）"
echo "  2) 手动输入自定义引导节点"
echo ""
read -rp "  请输入选项 [1/2，默认 1]：" 节点选择
节点选择=${节点选择:-1}

if [[ "$节点选择" == "2" ]]; then
    echo ""
    echo "  请输入引导节点，格式：/ip4/IP地址/tcp/端口"
    echo "  多个节点用逗号分隔，例如：/ip4/1.2.3.4/tcp/17999,/ip4/5.6.7.8/tcp/17999"
    read -rp "  引导节点：" 自定义节点
    # 转为 YAML 列表
    引导节点_yaml=""
    IFS=',' read -ra 节点数组 <<< "$自定义节点"
    for 节点 in "${节点数组[@]}"; do
        节点=$(echo "$节点" | xargs)
        引导节点_yaml+="  - \"$节点\"\n"
    done
else
    引导节点_yaml=""
    for 节点 in "${主网引导节点[@]}"; do
        引导节点_yaml+="  - \"$节点\"\n"
    done
    信息 "已选择全部 ${#主网引导节点[@]} 个主网引导节点"
fi

# GPU 设备选择
GPU_设备=0
if [[ "$GPU_可用" == "true" ]] && [[ $(nvidia-smi --query-gpu=index --format=csv,noheader | wc -l) -gt 1 ]]; then
    echo ""
    信息 "检测到多块显卡，请选择用于挖矿的显卡编号（从 0 开始）："
    nvidia-smi --query-gpu=index,name --format=csv,noheader | while IFS=, read -r 编号 名称; do
        echo "      [$编号] $名称"
    done
    read -rp "  显卡编号 [默认 0]：" GPU_设备
    GPU_设备=${GPU_设备:-0}
fi

# 钱包地址
echo ""
echo -e "  ${黄}重要：请输入你的 CSD 钱包地址${重置}"
echo "  （钱包地址用于接收挖矿奖励，留空则稍后手动编辑 config.yaml）"
read -rp "  钱包地址：" 钱包地址
钱包地址=${钱包地址:-"YOUR_WALLET_ADDRESS_HERE"}

# 工作器名称
read -rp "  工作器名称 [默认 worker-01]：" 工作器名称
工作器名称=${工作器名称:-worker-01}

# 写入配置文件
cat > config.yaml << YAML_EOF
# CSD 单机 GPU 矿工配置文件
# 由安装脚本自动生成，可手动编辑

miner:
  wallet_address: "${钱包地址}"
  domain: "compute"
  worker_name: "${工作器名称}"

node:
  datadir: "./cs.db"
  rpc_host: "0.0.0.0"
  rpc_port: 8789
  p2p_host: "0.0.0.0"
  p2p_port: 18007
  genesis: "./genesis.bin"

gpu:
  device_id: ${GPU_设备}
  threads_per_block: 256
  max_blocks: 4096
  batch_size: 65536

mining:
  proposal_interval: 12
  attestation_interval: 6
  max_retries: 5
  difficulty_target: "0x00000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"

bootnodes:
$(echo -e "$引导节点_yaml")
YAML_EOF

成功 "配置文件 config.yaml 已生成"

# ── 第五步：完成 ─────────────────────────────────────────────────────────────
步骤 "安装完成"

echo ""
echo -e "${绿}╔══════════════════════════════════════════════════╗${重置}"
echo -e "${绿}║              安装成功，即将启动挖矿              ║${重置}"
echo -e "${绿}╚══════════════════════════════════════════════════╝${重置}"
echo ""
echo "  配置摘要："
echo "  · 钱包地址  : $钱包地址"
echo "  · 工作器    : $工作器名称"
echo "  · 显卡设备  : $GPU_设备"
echo "  · GPU 模式  : $( [[ "$GPU_可用" == "true" ]] && echo "已启用" || echo "CPU 回退模式" )"
echo "  · 监控面板  : http://127.0.0.1:9090/stats"
echo "  · 带宽检测  : 启动时自动检测，低于 5 Mbps 则仅使用最优单节点"
echo ""

if [[ "$钱包地址" == "YOUR_WALLET_ADDRESS_HERE" ]]; then
    警告 "钱包地址尚未设置！请编辑 config.yaml 后再次运行："
    echo "      nano config.yaml          # 修改 wallet_address"
    echo "      ./start.sh                # 启动挖矿（自动带宽检测）"
    echo "      ./start.sh --跳过带宽检测  # 跳过检测，使用全部节点"
    echo ""
    exit 0
fi

read -rp "  按回车键启动挖矿，或按 Ctrl+C 退出... "
echo ""

exec ./start.sh
