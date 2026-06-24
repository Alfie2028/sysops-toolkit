#!/bin/bash
# ============================================================
# UI 封装库 — dialog/whiptail 包装、菜单构建
# ============================================================

[[ -n "$_UI_SH_LOADED" ]] && return
_UI_SH_LOADED=1

# --- 检测可用的 UI 工具 ---
UI_TOOL=""
if command -v dialog &>/dev/null; then
    UI_TOOL="dialog"
elif command -v whiptail &>/dev/null; then
    UI_TOOL="whiptail"
fi

# ============================================================
# 对话框封装
# ============================================================

# 菜单（返回选项编号）
ui_menu() {
    local title="$1"
    local prompt="$2"
    local height="$3"
    local width="$4"
    local menu_height="$5"
    shift 5

    if [[ "$UI_TOOL" == "dialog" ]]; then
        dialog --clear --title "$title" --menu "$prompt" "$height" "$width" "$menu_height" "$@" 2>&1
    elif [[ "$UI_TOOL" == "whiptail" ]]; then
        whiptail --clear --title "$title" --menu "$prompt" "$height" "$width" "$menu_height" "$@" 3>&1 1>&2 2>&3
    else
        echo -e "\n${COLOR_BOLD}===== $title =====${COLOR_RESET}"
        echo "$prompt"
        echo ""
        local i=0
        while [[ $# -gt 0 ]]; do
            if [[ $((i % 2)) -eq 0 ]]; then
                echo "  $1) $2"
            fi
            shift
            ((i++))
        done
        echo "  0) 返回"
        read -r -p "请选择: " choice
        echo "$choice"
    fi
}

# 输入框
ui_inputbox() {
    local title="$1"
    local prompt="$2"
    local default="$3"

    if [[ "$UI_TOOL" == "dialog" ]]; then
        dialog --title "$title" --inputbox "$prompt" 10 60 "$default" 2>&1
    elif [[ "$UI_TOOL" == "whiptail" ]]; then
        whiptail --title "$title" --inputbox "$prompt" 10 60 "$default" 3>&1 1>&2 2>&3
    else
        read -r -p "$prompt [$default]: " result
        echo "${result:-$default}"
    fi
}

# 进度条
ui_gauge() {
    local title="$1"
    local msg="$2"
    local percent="$3"

    if [[ "$UI_TOOL" == "dialog" ]]; then
        dialog --title "$title" --gauge "$msg" 8 60 "$percent"
    elif [[ "$UI_TOOL" == "whiptail" ]]; then
        whiptail --title "$title" --gauge "$msg" 8 60 "$percent"
    else
        echo -e "[$percent%] $msg"
    fi
}

# ============================================================
# 文本模式 Header / Footer
# ============================================================

print_header() {
    local title="$1"
    echo -e "${COLOR_CYAN}${COLOR_BOLD}"
    echo "╔══════════════════════════════════════════════════════╗"
    printf "║  %-50s  ║\n" "$title"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${COLOR_RESET}"
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')    主机: $(hostname)"
    echo "──────────────────────────────────────────────────────"
}

print_footer() {
    echo "──────────────────────────────────────────────────────"
    echo -e "${COLOR_CYAN}操作完成 — $(date '+%H:%M:%S')${COLOR_RESET}"
}

section() {
    echo -e "\n${COLOR_BOLD}${COLOR_BLUE}▸ $*${COLOR_RESET}"
}
