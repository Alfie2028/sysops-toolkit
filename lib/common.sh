#!/bin/bash
# ============================================================
# 公共函数库 — 工具函数、日志、配置加载
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
fi

# --- 确保必要目录存在 ---
mkdir -p "$SCRIPT_DIR/logs" "$SCRIPT_DIR/reports" "$SCRIPT_DIR/logs/archive"

# ============================================================
# 日志（简化为终端输出）
# ============================================================

log_info()  { echo -e "[INFO]  $*"; }
log_warn()  { echo -e "${COLOR_YELLOW}[WARN]  $*${COLOR_RESET}"; }
log_error() { echo -e "${COLOR_RED}[ERROR] $*${COLOR_RESET}"; }

# ============================================================
# 系统检查
# ============================================================

check_linux() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        echo "[ERROR] 本工具仅支持 Linux 环境，当前系统: $(uname -s)"
        exit 1
    fi
}

require_cmd() {
    command -v "$1" &>/dev/null || { log_error "缺少必要命令: $1"; return 1; }
}

# ============================================================
# 初始化（主脚本启动时调用）
# ============================================================

init_sysops() {
    check_linux
    log_info "Linux 系统运维工具箱 v1.0 启动 — $(uname -r)"
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

# 绘制进度条: draw_bar percent [width]
draw_bar() {
    local percent="$1"
    local width="${2:-20}"
    local full_char="${3:-█}"
    local empty_char="${4:-░}"
    local filled=$(( percent * width / 100 ))
    local empty=$(( width - filled ))

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

# 确认操作
confirm() {
    local prompt="$1"
    local yn
    read -r -p "$prompt [y/N]: " yn
    [[ "$yn" =~ ^[Yy]$ ]]
}
