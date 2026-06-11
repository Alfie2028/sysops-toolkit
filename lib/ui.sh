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

# 消息框
ui_msgbox() {
    local title="$1"
    local msg="$2"
    local height="${3:-15}"
    local width="${4:-60}"

    if [[ "$UI_TOOL" == "dialog" ]]; then
        dialog --title "$title" --msgbox "$msg" "$height" "$width"
    elif [[ "$UI_TOOL" == "whiptail" ]]; then
        whiptail --title "$title" --msgbox "$msg" "$height" "$width"
    else
        echo -e "\n===== $title =====\n$msg\n==================\n"
    fi
}

# 是/否确认框
ui_yesno() {
    local title="$1"
    local msg="$2"
    local height="${3:-10}"
    local width="${4:-60}"

    if [[ "$UI_TOOL" == "dialog" ]]; then
        dialog --title "$title" --yesno "$msg" "$height" "$width"
    elif [[ "$UI_TOOL" == "whiptail" ]]; then
        whiptail --title "$title" --yesno "$msg" "$height" "$width"
    else
        confirm "$msg" && return 0 || return 1
    fi
}

# 消息框（带滚动条，用于长文本）
ui_scrollbox() {
    local title="$1"
    local msg="$2"
    local height="${3:-20}"
    local width="${4:-70}"

    if [[ "$UI_TOOL" == "dialog" ]]; then
        dialog --title "$title" --scrollbox "$msg" "$height" "$width" 2>/dev/null
        # 将内容写入临时文件
        local tmpfile="/tmp/sysops_scroll_$$.tmp"
        echo "$msg" > "$tmpfile"
        dialog --title "$title" --textbox "$tmpfile" "$height" "$width" 2>/dev/null
        rm -f "$tmpfile"
    elif [[ "$UI_TOOL" == "whiptail" ]]; then
        local tmpfile="/tmp/sysops_scroll_$$.tmp"
        echo "$msg" > "$tmpfile"
        whiptail --title "$title" --textbox "$tmpfile" "$height" "$width" 2>/dev/null
        rm -f "$tmpfile"
    else
        echo -e "\n===== $title =====\n$msg\n==================\n"
    fi
}

# 输入框
ui_inputbox() {
    local title="$1"
    local prompt="$2"
    local default="$3"
    local height="${4:-10}"
    local width="${5:-60}"

    if [[ "$UI_TOOL" == "dialog" ]]; then
        dialog --title "$title" --inputbox "$prompt" "$height" "$width" "$default" 2>&1
    elif [[ "$UI_TOOL" == "whiptail" ]]; then
        whiptail --title "$title" --inputbox "$prompt" "$height" "$width" "$default" 3>&1 1>&2 2>&3
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
    local height="${4:-8}"
    local width="${5:-60}"

    if [[ "$UI_TOOL" == "dialog" ]]; then
        dialog --title "$title" --gauge "$msg" "$height" "$width" "$percent"
    elif [[ "$UI_TOOL" == "whiptail" ]]; then
        whiptail --title "$title" --gauge "$msg" "$height" "$width" "$percent"
    else
        echo -e "[$percent%] $msg"
    fi
}

# 菜单 (返回选项编号)
ui_menu() {
    local title="$1"
    local prompt="$2"
    local height="$3"
    local width="$4"
    local menu_height="$5"
    shift 5
    # 剩余参数: "tag1" "item1" "tag2" "item2" ...

    if [[ "$UI_TOOL" == "dialog" ]]; then
        dialog --clear --title "$title" --menu "$prompt" "$height" "$width" "$menu_height" "$@" 2>&1
    elif [[ "$UI_TOOL" == "whiptail" ]]; then
        whiptail --clear --title "$title" --menu "$prompt" "$height" "$width" "$menu_height" "$@" 3>&1 1>&2 2>&3
    else
        # 纯文本菜单
        echo -e "\n${COLOR_BOLD}===== $title =====${COLOR_RESET}"
        echo "$prompt"
        echo ""
        local tags=()
        local items=()
        local i=0
        while [[ $# -gt 0 ]]; do
            if [[ $((i % 2)) -eq 0 ]]; then
                tags+=("$1")
            else
                items+=("$1")
                echo "  ${tags[-1]}) ${items[-1]}"
            fi
            shift
            ((i++))
        done
        echo "  0) 返回"
        read -r -p "请选择: " choice
        echo "$choice"
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

# 分节标题
section() {
    echo -e "\n${COLOR_BOLD}${COLOR_BLUE}▸ $*${COLOR_RESET}"
}

# 检查 UI 工具是否可用
has_ui() {
    [[ -n "$UI_TOOL" ]]
}
