#!/bin/bash

#############################################
# CSD SOLO GPU 挖矿 - 多合一管理脚本 v5.2.1
# 功能：安装、启动、停止、状态、日志等一键管理
# 修复：配置文件键名统一为英文
#############################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 安装目录
SOLO_DIR="$HOME/solo"
MINER_PID_FILE="$SOLO_DIR/.miner.pid"

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

log_success() {
    echo -e "${CYAN}[成功]${NC} $1"
}

# 显示标题
show_header() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   CSD SOLO GPU 挖矿 - 管理工具 v5.2.1  ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
}

# 检查是否已安装
check_installation() {
    if [ ! -d "$SOLO_DIR" ] || [ ! -f "$SOLO_DIR/miner.py" ]; then
        return 1
    fi
    return 0
}

# 检查挖矿进程状态
check_miner_status() {
    if [ -f "$MINER_PID_FILE" ]; then
        PID=$(cat "$MINER_PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            return 0
        fi
    fi

    # 检查是否有 miner.py 进程
    if pgrep -f "python3.*miner.py" > /dev/null; then
        return 0
    fi

    return 1
}

# ========== 安装功能 ==========
do_install() {
    show_header
    echo -e "${CYAN}===== 开始安装 CSD SOLO GPU 挖矿 =====${NC}"
    echo ""

    if check_installation; then
        log_warn "检测到已存在安装目录: $SOLO_DIR"
        read -p "是否重新安装（会覆盖现有配置）? (y/n): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            log_info "安装已取消"
            return
        fi
    fi

    # 创建安装目录
    log_info "创建安装目录..."
    mkdir -p "$SOLO_DIR"
    cd "$SOLO_DIR"

    # 下载安装脚本
    log_info "下载安装脚本..."
    if curl -fsSL https://raw.githubusercontent.com/danger0001/solo-miner/main/solo-miner-install.sh -o solo-install.sh; then
        chmod +x solo-install.sh
        log_success "安装脚本下载成功"
    else
        log_error "下载失败，请检查网络连接"
        return 1
    fi

    # 运行安装脚本
    log_info "运行安装脚本..."
    echo ""
    ./solo-install.sh

    log_success "安装完成！"
    echo ""
    read -p "按回车键返回主菜单..."
}

# ========== 启动挖矿 ==========
do_start() {
    show_header
    echo -e "${CYAN}===== 启动挖矿 =====${NC}"
    echo ""

    if ! check_installation; then
        log_error "未检测到安装，请先运行安装"
        echo ""
        read -p "按回车键返回主菜单..."
        return 1
    fi

    if check_miner_status; then
        log_warn "挖矿进程已在运行中"
        echo ""
        read -p "按回车键返回主菜单..."
        return
    fi

    cd "$SOLO_DIR"

    # 检查配置文件
    if [ ! -f "config.yaml" ]; then
        log_error "未找到配置文件，请先完成安装"
        echo ""
        read -p "按回车键返回主菜单..."
        return 1
    fi

    # 创建日志目录
    mkdir -p logs
    LOG_FILE="logs/miner-$(date +%Y%m%d-%H%M%S).log"

    log_info "启动挖矿程序..."
    log_info "日志文件: $LOG_FILE"
    echo ""

    # 后台启动挖矿
    nohup python3 miner.py > "$LOG_FILE" 2>&1 &
    MINER_PID=$!
    echo "$MINER_PID" > "$MINER_PID_FILE"

    sleep 2

    if check_miner_status; then
        log_success "挖矿已启动！PID: $MINER_PID"
        echo ""
        log_info "查看实时日志: tail -f $SOLO_DIR/$LOG_FILE"
        log_info "或使用菜单选项 [5] 查看日志"
    else
        log_error "启动失败，请查看日志: $LOG_FILE"
    fi

    echo ""
    read -p "按回车键返回主菜单..."
}

# ========== 停止挖矿 ==========
do_stop() {
    show_header
    echo -e "${CYAN}===== 停止挖矿 =====${NC}"
    echo ""

    if ! check_miner_status; then
        log_warn "挖矿进程未运行"
        echo ""
        read -p "按回车键返回主菜单..."
        return
    fi

    log_info "正在停止挖矿进程..."

    # 尝试从 PID 文件停止
    if [ -f "$MINER_PID_FILE" ]; then
        PID=$(cat "$MINER_PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            kill "$PID" 2>/dev/null || true
            sleep 2
        fi
        rm -f "$MINER_PID_FILE"
    fi

    # 强制停止所有 miner.py 进程
    pkill -f "python3.*miner.py" 2>/dev/null || true

    sleep 1

    if check_miner_status; then
        log_error "停止失败，正在强制终止..."
        pkill -9 -f "python3.*miner.py" 2>/dev/null || true
        sleep 1
    fi

    if ! check_miner_status; then
        log_success "挖矿已停止"
    else
        log_error "停止失败，请手动检查进程"
    fi

    echo ""
    read -p "按回车键返回主菜单..."
}

# ========== 重启挖矿 ==========
do_restart() {
    show_header
    echo -e "${CYAN}===== 重启挖矿 =====${NC}"
    echo ""

    log_info "正在重启挖矿..."

    # 停止
    if check_miner_status; then
        log_info "停止当前进程..."
        pkill -f "python3.*miner.py" 2>/dev/null || true
        rm -f "$MINER_PID_FILE"
        sleep 2
    fi

    # 启动
    if ! check_installation; then
        log_error "未检测到安装"
        echo ""
        read -p "按回车键返回主菜单..."
        return 1
    fi

    cd "$SOLO_DIR"
    mkdir -p logs
    LOG_FILE="logs/miner-$(date +%Y%m%d-%H%M%S).log"

    log_info "启动挖矿程序..."
    nohup python3 miner.py > "$LOG_FILE" 2>&1 &
    MINER_PID=$!
    echo "$MINER_PID" > "$MINER_PID_FILE"

    sleep 2

    if check_miner_status; then
        log_success "重启成功！PID: $MINER_PID"
    else
        log_error "重启失败，请查看日志"
    fi

    echo ""
    read -p "按回车键返回主菜单..."
}

# ========== 查看状态 ==========
do_status() {
    show_header
    echo -e "${CYAN}===== 挖矿状态 =====${NC}"
    echo ""

    if ! check_installation; then
        log_error "未检测到安装"
        echo ""
        read -p "按回车键返回主菜单..."
        return
    fi

    # 检查进程状态
    if check_miner_status; then
        echo -e "${GREEN}✓ 挖矿进程正在运行${NC}"
        echo ""

        # 显示进程信息
        echo -e "${YELLOW}进程信息:${NC}"
        ps aux | grep "python3.*miner.py" | grep -v grep
        echo ""

        # 显示GPU状态
        if command -v nvidia-smi &> /dev/null; then
            echo -e "${YELLOW}GPU 状态:${NC}"
            nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.total --format=csv,noheader,nounits | awk -F', ' '{printf "  GPU %s: %s | 温度: %s°C | GPU使用: %s%% | 显存使用: %s%% (%sMB/%sMB)\n", $1, $2, $3, $4, $5, $6, $7}'
            echo ""
        fi

        # 显示最新日志
        echo -e "${YELLOW}最新日志（最后 15 行）:${NC}"
        LATEST_LOG=$(ls -t "$SOLO_DIR"/logs/*.log 2>/dev/null | head -1)
        if [ -n "$LATEST_LOG" ]; then
            tail -n 15 "$LATEST_LOG" | sed 's/^/  /'
        else
            echo "  未找到日志文件"
        fi

    else
        echo -e "${RED}✗ 挖矿进程未运行${NC}"
    fi

    echo ""
    read -p "按回车键返回主菜单..."
}

# ========== 查看日志 ==========
do_logs() {
    show_header
    echo -e "${CYAN}===== 查看日志 =====${NC}"
    echo ""

    if ! check_installation; then
        log_error "未检测到安装"
        echo ""
        read -p "按回车键返回主菜单..."
        return
    fi

    cd "$SOLO_DIR"

    LATEST_LOG=$(ls -t logs/*.log 2>/dev/null | head -1)
    if [ -z "$LATEST_LOG" ]; then
        log_error "未找到日志文件"
        echo ""
        read -p "按回车键返回主菜单..."
        return
    fi

    log_info "实时日志（按 Ctrl+C 退出）: $LATEST_LOG"
    echo ""
    sleep 1

    tail -f "$LATEST_LOG"
}

# ========== 更新程序 ==========
do_update() {
    show_header
    echo -e "${CYAN}===== 更新程序 =====${NC}"
    echo ""

    if ! check_installation; then
        log_error "未检测到安装，请先运行安装"
        echo ""
        read -p "按回车键返回主菜单..."
        return
    fi

    log_info "正在检查更新..."
    echo ""

    # 停止挖矿
    if check_miner_status; then
        log_info "停止挖矿进程..."
        pkill -f "python3.*miner.py" 2>/dev/null || true
        rm -f "$MINER_PID_FILE"
        sleep 2
    fi

    cd "$SOLO_DIR"

    # 备份配置
    if [ -f "config.yaml" ]; then
        log_info "备份配置文件..."
        cp config.yaml config.yaml.backup
    fi

    # 下载最新文件
    log_info "下载最新版本..."
    local base_url="https://raw.githubusercontent.com/danger0001/solo-miner/main"

    curl -fsSL "$base_url/miner.py" -o miner.py.new
    curl -fsSL "$base_url/gpu_worker.py" -o gpu_worker.py.new
    curl -fsSL "$base_url/node_selector.py" -o node_selector.py.new
    curl -fsSL "$base_url/requirements.txt" -o requirements.txt.new

    # 替换文件
    mv miner.py.new miner.py
    mv gpu_worker.py.new gpu_worker.py
    mv node_selector.py.new node_selector.py
    mv requirements.txt.new requirements.txt

    chmod +x miner.py

    # 更新依赖
    log_info "更新 Python 依赖..."
    pip3 install -r requirements.txt --upgrade --quiet

    # 恢复配置
    if [ -f "config.yaml.backup" ]; then
        log_info "恢复配置文件..."
        mv config.yaml.backup config.yaml
    fi

    log_success "更新完成！"
    echo ""
    log_info "提示: 使用菜单选项 [2] 启动挖矿"

    echo ""
    read -p "按回车键返回主菜单..."
}

# ========== 编辑配置 ==========
do_config() {
    show_header
    echo -e "${CYAN}===== 编辑配置 =====${NC}"
    echo ""

    if ! check_installation; then
        log_error "未检测到安装"
        echo ""
        read -p "按回车键返回主菜单..."
        return
    fi

    CONFIG_FILE="$SOLO_DIR/config.yaml"

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "未找到配置文件"
        echo ""
        read -p "按回车键返回主菜单..."
        return
    fi

    log_info "配置文件路径: $CONFIG_FILE"
    echo ""

    # 尝试使用不同的编辑器
    if command -v nano &> /dev/null; then
        nano "$CONFIG_FILE"
    elif command -v vim &> /dev/null; then
        vim "$CONFIG_FILE"
    elif command -v vi &> /dev/null; then
        vi "$CONFIG_FILE"
    else
        log_error "未找到文本编辑器（nano/vim/vi）"
        log_info "请手动编辑: $CONFIG_FILE"
        echo ""
        read -p "按回车键返回主菜单..."
        return
    fi
}

# ========== 卸载 ==========
do_uninstall() {
    show_header
    echo -e "${CYAN}===== 卸载程序 =====${NC}"
    echo ""

    if ! check_installation; then
        log_error "未检测到安装"
        echo ""
        read -p "按回车键返回主菜单..."
        return
    fi

    log_warn "此操作将删除所有文件和数据！"
    echo ""
    read -p "确认卸载? (输入 YES 确认): " confirm

    if [ "$confirm" != "YES" ]; then
        log_info "已取消卸载"
        echo ""
        read -p "按回车键返回主菜单..."
        return
    fi

    # 停止挖矿
    if check_miner_status; then
        log_info "停止挖矿进程..."
        pkill -f "python3.*miner.py" 2>/dev/null || true
        rm -f "$MINER_PID_FILE"
        sleep 2
    fi

    # 删除目录
    log_info "删除安装目录..."
    rm -rf "$SOLO_DIR"

    log_success "卸载完成"
    echo ""
    echo "感谢使用 CSD SOLO GPU 挖矿！"
    echo ""
    exit 0
}

# ========== 显示主菜单 ==========
show_menu() {
    show_header

    # 显示安装状态
    if check_installation; then
        echo -e "${GREEN}✓ 已安装${NC} - 安装目录: $SOLO_DIR"
    else
        echo -e "${YELLOW}✗ 未安装${NC}"
    fi

    # 显示运行状态
    if check_miner_status; then
        echo -e "${GREEN}✓ 运行中${NC}"
    else
        echo -e "${RED}✗ 未运行${NC}"
    fi

    echo ""
    echo "────────────────────────────────────────"
    echo ""
    echo "  [1] 安装/重新安装"
    echo "  [2] 启动挖矿"
    echo "  [3] 停止挖矿"
    echo "  [4] 重启挖矿"
    echo "  [5] 查看状态"
    echo "  [6] 查看日志（实时）"
    echo "  [7] 更新程序"
    echo "  [8] 编辑配置"
    echo "  [9] 卸载"
    echo "  [0] 退出"
    echo ""
    echo "────────────────────────────────────────"
    echo ""
}

# ========== 主程序 ==========
main() {
    while true; do
        show_menu
        read -p "请选择操作 [0-9]: " choice

        case $choice in
            1) do_install ;;
            2) do_start ;;
            3) do_stop ;;
            4) do_restart ;;
            5) do_status ;;
            6) do_logs ;;
            7) do_update ;;
            8) do_config ;;
            9) do_uninstall ;;
            0)
                clear
                echo "感谢使用 CSD SOLO GPU 挖矿！"
                echo ""
                exit 0
                ;;
            *)
                log_error "无效的选择，请输入 0-9"
                sleep 1
                ;;
        esac
    done
}

# 运行主程序
main
