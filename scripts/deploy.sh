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

# update 命令 - 更新代码
cmd_update() {
    log_info "更新代码..."

    cd "${PROJECT_DIR}"

    # 检查是否是 git 仓库
    if [[ ! -d ".git" ]]; then
        log_error "不是 git 仓库: ${PROJECT_DIR}"
        return 1
    fi

    # 检查当前分支
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    log_info "当前分支: ${current_branch}"

    # 检查是否有未提交的修改
    if git status --porcelain | grep -q .; then
        log_warning "工作区有未提交的修改:"
        git status --porcelain
        read -p "是否继续? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "已取消"
            return 1
        fi
    fi

    # 获取最新代码
    log_info "执行 git pull..."
    git pull

    # 显示最近的提交
    log_info "最近 3 次提交:"
    git log --oneline -3

    log_success "代码更新完成"
}

# 检测可用的包管理器
detect_package_manager() {
    if command -v uv &>/dev/null; then
        echo "uv"
    elif command -v pip &>/dev/null; then
        echo "pip"
    else
        echo ""
    fi
}

# install 命令 - 本地安装
cmd_install() {
    log_info "安装 nanobot..."

    cd "${PROJECT_DIR}"

    # 检测包管理器
    local pm
    pm=$(detect_package_manager)

    if [[ -z "${pm}" ]]; then
        log_error "未找到 uv 或 pip，请先安装"
        return 1
    fi

    log_info "使用包管理器: ${pm}"

    # 执行安装
    if [[ "${pm}" == "uv" ]]; then
        log_info "执行 uv sync..."
        uv sync

        log_info "安装到用户环境..."
        uv pip install -e .
    else
        log_info "执行 pip install..."
        pip install --user -e .
    fi

    # 验证安装
    if command -v nanobot &>/dev/null; then
        local nanobot_path
        nanobot_path=$(command -v nanobot)
        log_success "安装成功: ${nanobot_path}"

        # 显示版本
        log_info "nanobot 版本:"
        nanobot --help 2>&1 | head -5 || true
    else
        log_error "安装后未找到 nanobot 命令"
        log_warning "请确保 ~/.local/bin 在 PATH 中"
        return 1
    fi
}

# 使用 launchd 启动服务
start_launchd() {
    log_info "使用 launchd 启动服务..."

    # 复制 plist 文件
    if [[ ! -f "${LAUNCH_AGENTS_DIR}/${SERVICE_NAME}.plist" ]]; then
        log_info "安装 launchd plist 文件..."
        cp "${PLIST_FILE}" "${LAUNCH_AGENTS_DIR}/"
    fi

    # 加载服务
    if ! launchctl list | grep -q "${SERVICE_NAME}"; then
        log_info "加载 launchd 服务..."
        launchctl load "${LAUNCH_AGENTS_DIR}/${SERVICE_NAME}.plist"
    fi

    # 启动服务
    log_info "启动服务..."
    launchctl start "${SERVICE_NAME}"

    # 等待启动
    sleep 2

    # 检查状态
    if launchctl list | grep "${SERVICE_NAME}" | grep -q -v '"-"'; then
        log_success "launchd 服务启动成功"
        return 0
    else
        log_error "launchd 服务启动失败"
        return 1
    fi
}

# 使用 launchd 停止服务
stop_launchd() {
    log_info "停止 launchd 服务..."

    if launchctl list | grep -q "${SERVICE_NAME}"; then
        launchctl stop "${SERVICE_NAME}"
        log_success "launchd 服务已停止"
    else
        log_warning "launchd 服务未加载"
    fi
}

# 使用后台进程启动服务
start_process() {
    log_info "使用后台进程启动服务..."

    # 检查是否已在运行
    if [[ -f "${PID_FILE}" ]]; then
        local pid
        pid=$(cat "${PID_FILE}" 2>/dev/null || true)
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            log_warning "服务已在运行 (pid: ${pid})"
            return 0
        else
            log_warning "清理旧的 pid 文件"
            rm -f "${PID_FILE}"
        fi
    fi

    # 确保日志目录存在
    mkdir -p "${LOG_DIR}"

    # 启动服务
    local stdout_log="${LOG_DIR}/gateway.stdout.log"
    local stderr_log="${LOG_DIR}/gateway.stderr.log"

    log_info "启动 nanobot gateway..."
    log_info "stdout: ${stdout_log}"
    log_info "stderr: ${stderr_log}"

    # 启动到后台
    nohup nanobot gateway > "${stdout_log}" 2> "${stderr_log}" < /dev/null &
    local pid=$!

    # 保存 pid
    echo "${pid}" > "${PID_FILE}"

    # 等待启动
    sleep 3

    # 检查进程
    if kill -0 "${pid}" 2>/dev/null; then
        log_success "后台进程启动成功 (pid: ${pid})"
        return 0
    else
        log_error "后台进程启动失败"
        log_error "请查看日志: ${stderr_log}"
        tail -20 "${stderr_log}" 2>/dev/null || true
        rm -f "${PID_FILE}"
        return 1
    fi
}

# 停止后台进程
stop_process() {
    log_info "停止后台进程..."

    if [[ ! -f "${PID_FILE}" ]]; then
        log_warning "pid 文件不存在: ${PID_FILE}"
        return 0
    fi

    local pid
    pid=$(cat "${PID_FILE}" 2>/dev/null || true)

    if [[ -z "${pid}" ]]; then
        log_warning "pid 文件为空"
        rm -f "${PID_FILE}"
        return 0
    fi

    # 停止进程
    if kill -0 "${pid}" 2>/dev/null; then
        log_info "发送 SIGTERM 到进程 ${pid}..."
        kill "${pid}"

        # 等待进程结束
        local timeout=10
        while kill -0 "${pid}" 2>/dev/null && [[ ${timeout} -gt 0 ]]; do
            sleep 1
            ((timeout--))
        done

        # 如果还在运行，强制杀死
        if kill -0 "${pid}" 2>/dev/null; then
            log_warning "进程未响应，强制杀死..."
            kill -9 "${pid}"
            sleep 1
        fi

        log_success "进程已停止"
    else
        log_warning "进程 ${pid} 不存在"
    fi

    # 清理 pid 文件
    rm -f "${PID_FILE}"
}

# 检查配置
check_config() {
    if [[ ! -f "${NANOBOT_DIR}/config.json" ]]; then
        log_warning "配置文件不存在: ${NANOBOT_DIR}/config.json"
        log_info "请运行 'nanobot onboard' 初始化配置"
    fi
}

# start 命令
cmd_start() {
    log_info "启动 nanobot 服务..."

    # 先检查是否已安装
    if ! command -v nanobot &>/dev/null; then
        log_error "nanobot 未安装，请先运行: $0 install"
        return 1
    fi

    # 检查配置
    check_config

    # macOS 优先使用 launchd
    if is_macos; then
        if start_launchd; then
            return 0
        else
            log_warning "launchd 启动失败，尝试后台进程方式"
        fi
    fi

    # 使用后台进程方式
    start_process
}

# stop 命令
cmd_stop() {
    log_info "停止 nanobot 服务..."

    local success=0

    # macOS 停止 launchd
    if is_macos; then
        set +e
        stop_launchd || success=1
        set -e
    fi

    # 停止后台进程
    set +e
    stop_process || success=1
    set -e

    if [[ ${success} -eq 0 ]]; then
        log_success "服务已停止"
    else
        log_warning "部分停止操作可能失败"
    fi
}

# restart 命令
cmd_restart() {
    log_info "重启 nanobot 服务..."

    cmd_stop "$@"
    sleep 2
    cmd_start "$@"
}

# logs 命令
cmd_logs() {
    local follow=false
    local lines=100
    local log_type="all"

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--follow) follow=true; shift ;;
            -n|--lines) lines="$2"; shift 2 ;;
            --stdout) log_type="stdout"; shift ;;
            --stderr) log_type="stderr"; shift ;;
            *) log_error "未知参数: $1"; return 1 ;;
        esac
    done

    local stdout_log="${LOG_DIR}/gateway.stdout.log"
    local stderr_log="${LOG_DIR}/gateway.stderr.log"

    # 显示可用日志
    log_info "日志目录: ${LOG_DIR}"
    echo "  stdout: ${stdout_log}"
    echo "  stderr: ${stderr_log}"
    echo ""

    # tail 参数
    local tail_args="-n ${lines}"
    if ${follow}; then
        tail_args="-f ${tail_args}"
    fi

    # 根据类型显示日志
    case ${log_type} in
        stdout)
            if [[ -f "${stdout_log}" ]]; then
                log_info "显示 stdout 日志 (最后 ${lines} 行)..."
                echo "--- stdout ---"
                tail ${tail_args} "${stdout_log}"
            else
                log_warning "stdout 日志文件不存在"
            fi
            ;;
        stderr)
            if [[ -f "${stderr_log}" ]]; then
                log_info "显示 stderr 日志 (最后 ${lines} 行)..."
                echo "--- stderr ---"
                tail ${tail_args} "${stderr_log}"
            else
                log_warning "stderr 日志文件不存在"
            fi
            ;;
        all)
            # 同时显示两个日志
            if [[ -f "${stdout_log}" ]] || [[ -f "${stderr_log}" ]]; then
                log_info "显示日志 (最后 ${lines} 行)..."
                if [[ -f "${stdout_log}" ]]; then
                    echo "--- stdout ---"
                    tail -n ${lines} "${stdout_log}"
                fi
                if [[ -f "${stderr_log}" ]]; then
                    echo "--- stderr ---"
                    tail -n ${lines} "${stderr_log}"
                fi

                # 如果是 follow 模式，使用 tail -f 同时跟踪两个文件
                if ${follow}; then
                    log_info "实时跟踪日志 (Ctrl+C 退出)..."
                    tail -f "${stdout_log}" "${stderr_log}" 2>/dev/null || true
                fi
            else
                log_warning "日志文件不存在"
            fi
            ;;
    esac
}

# deploy 命令 - 完整部署
cmd_deploy() {
    log_info "开始完整部署流程..."
    echo "========================================"

    # 步骤 1: 更新代码
    echo ""
    echo "步骤 1/4: 更新代码"
    echo "----------------------------------------"
    cmd_update "$@"

    # 步骤 2: 安装
    echo ""
    echo "步骤 2/4: 安装"
    echo "----------------------------------------"
    cmd_install "$@"

    # 步骤 3: 重启服务
    echo ""
    echo "步骤 3/4: 重启服务"
    echo "----------------------------------------"
    cmd_restart "$@"

    # 步骤 4: 检查状态
    echo ""
    echo "步骤 4/4: 验证部署"
    echo "----------------------------------------"
    sleep 2
    cmd_status "$@"

    echo ""
    echo "========================================"
    log_success "部署完成！"
    echo ""
    echo "常用命令:"
    echo "  查看状态: $0 status"
    echo "  查看日志: $0 logs -f"
    echo "  停止服务: $0 stop"
    echo "  启动服务: $0 start"
}

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
