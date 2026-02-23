#!/bin/bash
# nanobot 服务部署脚本
# 功能：检查服务状态、更新代码、本地安装、重启服务、后台启动、日志管理

set -euo pipefail

# 配置变量
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NANOBOT_DIR="${HOME}/.nanobot"
LOG_DIR="${NANOBOT_DIR}/logs"
PID_FILE="${NANOBOT_DIR}/nanobot.pid"
SERVICE_NAME="com.nanobot.gateway"
PLIST_FILE="${PROJECT_DIR}/com.nanobot.service.plist"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 确保目录存在
ensure_dirs() {
    mkdir -p "${LOG_DIR}"
    mkdir -p "${NANOBOT_DIR}"
}

# 显示帮助
show_help() {
    cat <<EOF
nanobot 服务部署脚本

用法: $0 [命令]

命令:
    status      检查服务状态
    update      更新代码 (git pull)
    install     本地安装 (uv sync / pip install)
    start       启动服务 (后台运行)
    stop        停止服务
    restart     重启服务 (stop + start)
    logs        查看日志
    deploy      完整部署 (update + install + restart)
    help        显示此帮助

示例:
    $0 status          # 检查服务状态
    $0 deploy          # 完整部署流程
    $0 logs -f         # 实时查看日志
EOF
}

# 检测操作系统
is_macos() {
    [[ "$(uname)" == "Darwin" ]]
}

# 检查 launchd 服务状态
check_launchd_status() {
    if launchctl list | grep -q "${SERVICE_NAME}"; then
        local pid
        pid=$(launchctl list | grep "${SERVICE_NAME}" | awk '{print $1}')
        if [[ "${pid}" != "-" ]]; then
            echo "running (pid: ${pid})"
            return 0
        else
            echo "loaded but not running"
            return 1
        fi
    else
        echo "not loaded"
        return 2
    fi
}

# 检查通用后台进程状态
check_process_status() {
    if [[ -f "${PID_FILE}" ]]; then
        local pid
        pid=$(cat "${PID_FILE}" 2>/dev/null || true)
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            echo "running (pid: ${pid})"
            return 0
        else
            echo "pid file exists but process not running"
            return 1
        fi
    else
        echo "not running"
        return 2
    fi
}

# status 命令
cmd_status() {
    log_info "检查 nanobot 服务状态..."

    local launchd_code=2
    local proc_code=2

    if is_macos; then
        log_info "检测到 macOS 系统"
        local launchd_status
        # 禁用 set -e 以捕获退出码
        set +e
        launchd_status=$(check_launchd_status)
        launchd_code=$?
        set -e

        echo "  launchd 服务: ${launchd_status}"

        if [[ -f "${LAUNCH_AGENTS_DIR}/${SERVICE_NAME}.plist" ]]; then
            echo "  plist 文件: 已安装"
        else
            echo "  plist 文件: 未安装"
        fi
    fi

    # 检查通用进程状态
    local proc_status
    set +e
    proc_status=$(check_process_status)
    proc_code=$?
    set -e

    echo "  后台进程: ${proc_status}"

    # 检查日志文件
    if [[ -d "${LOG_DIR}" ]]; then
        local log_count
        log_count=$(ls -1 "${LOG_DIR}"/*.log 2>/dev/null | wc -l | tr -d ' ')
        echo "  日志目录: ${LOG_DIR} (${log_count} 个日志文件)"
    else
        echo "  日志目录: 不存在"
    fi

    # 检查可执行文件
    if command -v nanobot &>/dev/null; then
        local nanobot_path
        nanobot_path=$(command -v nanobot)
        echo "  可执行文件: ${nanobot_path}"
    else
        echo "  可执行文件: 未找到"
    fi

    # 总体状态
    if [[ ${launchd_code:-2} -eq 0 ]] || [[ ${proc_code:-2} -eq 0 ]]; then
        log_success "服务正在运行"
        return 0
    else
        log_warning "服务未运行"
        return 1
    fi
}

# 命令函数占位符（后续实现）
cmd_update() { log_info "update 命令待实现"; }
cmd_install() { log_info "install 命令待实现"; }
cmd_start() { log_info "start 命令待实现"; }
cmd_stop() { log_info "stop 命令待实现"; }
cmd_restart() { log_info "restart 命令待实现"; }
cmd_logs() { log_info "logs 命令待实现"; }
cmd_deploy() { log_info "deploy 命令待实现"; }

# 主命令分发
main() {
    ensure_dirs
    local cmd="${1:-help}"
    shift || true

    case "${cmd}" in
        status) cmd_status "$@" ;;
        update) cmd_update "$@" ;;
        install) cmd_install "$@" ;;
        start) cmd_start "$@" ;;
        stop) cmd_stop "$@" ;;
        restart) cmd_restart "$@" ;;
        logs) cmd_logs "$@" ;;
        deploy) cmd_deploy "$@" ;;
        help) show_help ;;
        *) log_error "未知命令: ${cmd}"; show_help; exit 1 ;;
    esac
}

# 如果直接执行此脚本，运行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
