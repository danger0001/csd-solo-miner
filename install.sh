#!/bin/bash

#############################################
# CSD SOLO 挖矿 - 一键安装引导脚本 v5.2.1
# GPU 优先，自动检测并配置 CUDA
# 修复：配置文件键名统一为英文
# 推荐使用 solo.sh 多合一管理脚本
#############################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 安装目录
INSTALL_DIR="$HOME/solo"

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

# 显示欢迎信息
show_welcome() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}   CSD SOLO GPU 挖矿 - 一键安装 v5.2.0${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""
    echo "安装目录: $INSTALL_DIR"
    echo ""
}

# 创建安装目录
create_install_dir() {
    log_info "创建安装目录..."

    if [ -d "$INSTALL_DIR" ]; then
        log_warn "目录 $INSTALL_DIR 已存在"
        read -p "是否继续？这将覆盖现有安装 (y/n): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            log_info "安装已取消"
            exit 0
        fi
    else
        mkdir -p "$INSTALL_DIR"
        log_info "目录创建成功"
    fi
}

# 下载主安装脚本
download_installer() {
    log_info "下载主安装脚本..."

    cd "$INSTALL_DIR"

    # 下载脚本
    if curl -fsSL https://raw.githubusercontent.com/danger0001/solo-miner/main/solo-miner-install.sh -o solo-install.sh; then
        chmod +x solo-install.sh
        log_info "安装脚本下载成功"
    else
        log_error "下载失败，请检查网络连接"
        exit 1
    fi
}

# 运行主安装脚本
run_installer() {
    log_info "开始运行安装程序..."
    echo ""

    cd "$INSTALL_DIR"
    ./solo-install.sh
}

# 主函数
main() {
    show_welcome
    create_install_dir
    download_installer
    run_installer
}

# 运行主函数
main
