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

# 命令函数占位符（后续实现）
cmd_status() { log_info "status 命令待实现"; }
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
