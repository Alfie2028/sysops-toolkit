#!/bin/bash
# ============================================================
# 公共函数库 — 日志、工具函数、配置加载
# ============================================================

# 防止重复加载
[[ -n "$_COMMON_SH_LOADED" ]] && return
_COMMON_SH_LOADED=1

# --- 获取脚本所在目录（项目根目录） ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCRIPT_DIR

# --- 加载配置 ---
if [[ -f "$SCRIPT_DIR/etc/config.conf" ]]; then
    source "$SCRIPT_DIR/etc/config.conf"
else
    echo "[WARN] 配置文件未找到: $SCRIPT_DIR/etc/config.conf，使用默认值"
fi

# --- 确保必要目录存在 ---
mkdir -p "$SCRIPT_DIR/logs" "$SCRIPT_DIR/reports" "$SCRIPT_DIR/logs/archive"

# ============================================================
# 日志函数
# ============================================================

# 写日志 (同时输出到终端和日志文件)
log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_line="[$timestamp] [$level] $msg"

    echo "$log_line" >> "$SCRIPT_DIR/$LOG_FILE"

    case "$level" in
        ERROR)  echo -e "${COLOR_RED}$log_line${COLOR_RESET}" ;;
        WARN)   echo -e "${COLOR_YELLOW}$log_line${COLOR_RESET}" ;;
        INFO)   echo -e "${COLOR_GREEN}$log_line${COLOR_RESET}" ;;
        DEBUG)  echo -e "${COLOR_CYAN}$log_line${COLOR_RESET}" ;;
        *)      echo "$log_line" ;;
    esac
}

# 便捷日志函数
log_info()  { log INFO "$@"; }
log_warn()  { log WARN "$@"; }
log_error() { log ERROR "$@"; }
log_debug() { log DEBUG "$@"; }

# ============================================================
# 系统检查函数
# ============================================================

# 检查是否在 Linux 环境运行
check_linux() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        log_error "本工具仅支持 Linux 环境，当前系统: $(uname -s)"
        exit 1
    fi
}

# 检查命令是否存在
require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "缺少必要命令: $cmd，请先安装"
        return 1
    fi
    return 0
}

# 检查所有必要命令
check_dependencies() {
    local missing=0
    local cmds=("ps" "df" "du" "find" "awk" "sed" "grep" "tar" "who" "last")
    for cmd in "${cmds[@]}"; do
        if ! require_cmd "$cmd"; then
            ((missing++))
        fi
    done
    if [[ $missing -gt 0 ]]; then
        log_error "缺少 $missing 个必要命令，请安装后重试"
        return 1
    fi
    return 0
}

# 检查 /proc 文件系统是否可访问
check_proc() {
    if [[ ! -f /proc/stat ]] || [[ ! -f /proc/meminfo ]]; then
        log_error "/proc 文件系统不可访问，无法获取系统信息"
        return 1
    fi
    return 0
}

# ============================================================
# 数值与格式化工具
# ============================================================

# 浮点数比较: float_cmp a op b (op: >, <, >=, <=, ==)
float_cmp() {
    awk -v a="$1" -v b="$3" "BEGIN { exit !(a $2 b) }"
}

# 字节转人类可读
human_size() {
    local bytes="$1"
    if [[ "$bytes" -ge 1073741824 ]]; then
        awk "BEGIN { printf \"%.2f GB\", $bytes/1073741824 }"
    elif [[ "$bytes" -ge 1048576 ]]; then
        awk "BEGIN { printf \"%.2f MB\", $bytes/1048576 }"
    elif [[ "$bytes" -ge 1024 ]]; then
        awk "BEGIN { printf \"%.2f KB\", $bytes/1024 }"
    else
        echo "${bytes} B"
    fi
}

# 绘制进度条: draw_bar percent [width] [char_full] [char_empty]
draw_bar() {
    local percent="$1"
    local width="${2:-20}"
    local full_char="${3:-█}"
    local empty_char="${4:-░}"
    local filled=$(( percent * width / 100 ))
    local empty=$(( width - filled ))

    # 颜色：>80% 红色, >60% 黄色, 否则绿色
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="$full_char"; done
    for ((i=0; i<empty; i++)); do bar+="$empty_char"; done

    if [[ "$percent" -ge 80 ]]; then
        echo -e "${COLOR_RED}[${bar}]${COLOR_RESET} ${percent}%"
    elif [[ "$percent" -ge 60 ]]; then
        echo -e "${COLOR_YELLOW}[${bar}]${COLOR_RESET} ${percent}%"
    else
        echo -e "${COLOR_GREEN}[${bar}]${COLOR_RESET} ${percent}%"
    fi
}

# 带颜色状态标签
status_tag() {
    local val="$1"
    local threshold="$2"
    if [[ "$val" -ge "$threshold" ]]; then
        echo -e "${COLOR_BG_RED} ALERT ${COLOR_RESET}"
    else
        echo -e "${COLOR_GREEN} OK ${COLOR_RESET}"
    fi
}

# ============================================================
# 安全与容错
# ============================================================

# 安全执行命令，捕获错误
safe_run() {
    local desc="$1"
    shift
    local output
    output=$("$@" 2>&1)
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        log_warn "[$desc] 执行失败 (rc=$rc): $output"
        return $rc
    fi
    echo "$output"
    return 0
}

# 确认操作
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local yn
    read -r -p "$prompt [y/N]: " yn
    yn="${yn:-$default}"
    [[ "$yn" =~ ^[Yy]$ ]]
}

# 信号捕获 — 优雅退出
trap_cleanup() {
    log_info "收到退出信号，正在清理..."
    # 清理临时文件
    rm -f /tmp/sysops_*.tmp
    log_info "清理完成，退出。"
    exit 0
}

# 安装信号处理器
setup_traps() {
    trap trap_cleanup SIGINT SIGTERM
}

# ============================================================
# 初始化
# ============================================================

# 项目初始化（在主脚本启动时调用）
init_sysops() {
    check_linux
    check_dependencies
    check_proc
    setup_traps
    log_info "========================================="
    log_info "Linux 系统运维工具箱 v1.0 启动"
    log_info "运行环境: $(uname -a)"
    log_info "========================================="
}
