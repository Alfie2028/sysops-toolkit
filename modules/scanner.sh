#!/bin/bash
# ============================================================
# 模块三：文件系统扫描仪
# 功能：磁盘空间预警 / 大文件扫描 / 旧文件清理 / 权限安全审计
# ============================================================

source "${SCRIPT_DIR:-.}/lib/common.sh" 2>/dev/null || source "$(dirname "$0")/../lib/common.sh"

# ============================================================
# 磁盘空间预警
# ============================================================

disk_usage_check() {
    echo "┌──────────────────────┬──────────┬──────────┬──────────┬──────────┐"
    printf "│ %-20s │ %8s │ %8s │ %8s │ %6s │\n" "挂载点" "总容量" "已用" "可用" "使用率"
    echo "├──────────────────────┼──────────┼──────────┼──────────┼──────────┤"

    local alerts=()

    df -h --local 2>/dev/null | tail -n +2 | while read -r fs size used avail pct mnt; do
        local pct_num="${pct%%%}"
        local status_tag=""

        if [[ "$pct_num" -ge ${DISK_THRESHOLD:-90} ]]; then
            status_tag="${COLOR_BG_RED} ⚠ ${COLOR_RESET}"
            alerts+=("$mnt:$pct_num")
        elif [[ "$pct_num" -ge 80 ]]; then
            status_tag="${COLOR_YELLOW} ⚡ ${COLOR_RESET}"
        else
            status_tag="${COLOR_GREEN} ✓ ${COLOR_RESET}"
        fi

        printf "│ %-20s │ %8s │ %8s │ %8s │ %s%5s${COLOR_RESET} │\n" \
            "$mnt" "$size" "$used" "$avail" "$status_tag" "$pct"
    done

    echo "└──────────────────────┴──────────┴──────────┴──────────┴──────────┘"

    # 打印告警
    for alert in "${alerts[@]}"; do
        local mnt="${alert%%:*}"
        local pct="${alert##*:}"
        echo -e "  ${COLOR_BG_RED} 🔴 磁盘告警: $mnt 使用率 $pct% (阈值: ${DISK_THRESHOLD:-90}%) ${COLOR_RESET}"
    done
}

# ============================================================
# du -sh 递归目录大小统计
# ============================================================

dir_usage_scan() {
    local scan_path="${1:-/home}"
    local depth="${2:-2}"
    local top_n="${3:-15}"

    echo "📂 目录空间占用 (du -sh, depth=$depth, Top $top_n)"
    echo "   扫描路径: $scan_path"
    echo ""

    echo "  ┌────────────┬──────────────────────────────────────────────────┐"
    printf "  │ %10s │ %-48s │\n" "大小" "目录"
    echo "  ├────────────┼──────────────────────────────────────────────────┤"

    # 使用 du 递归统计，取最大 Top N
    du -h --max-depth="$depth" "$scan_path" 2>/dev/null \
        | sort -rh 2>/dev/null \
        | head -"$top_n" \
        | while read -r size dir; do
            printf "  │ %10s │ %-48s │\n" "$size" "${dir:0:48}"
        done

    echo "  └────────────┴──────────────────────────────────────────────────┘"

    # 磁盘配额对比
    echo ""
    echo "  📊 磁盘配额对比:"
    df -h --local 2>/dev/null | tail -n +2 | while read -r fs size used avail pct mnt; do
        local pct_num="${pct%%%}"
        local mnt_usage=$(du -sh "$mnt" 2>/dev/null | awk '{print $1}')
        printf "    %-20s  配额: %6s  实际: %6s  使用率: %s\n" \
            "$mnt" "$size" "${mnt_usage:-N/A}" "$pct"
    done
}

# ============================================================
# 大文件扫描
# ============================================================

large_file_scan() {
    local size_threshold="${1:-${LARGE_FILE_SIZE:-+100M}}"
    local scan_path="${2:-/}"
    local top_n="${3:-20}"

    echo "🔍 扫描路径: $scan_path"
    echo "📏 大小阈值: $size_threshold"
    echo ""

    echo "┌──────────────┬──────────────────────────────────────────────────┐"
    printf "│ %12s │ %-48s │\n" "文件大小" "路径"
    echo "├──────────────┼──────────────────────────────────────────────────┤"

    # 排除 /proc, /sys, /dev (虚拟文件系统)
    find "$scan_path" -type f -size "$size_threshold" \
        -not -path "/proc/*" -not -path "/sys/*" -not -path "/dev/*" \
        -exec ls -lh {} \; 2>/dev/null | \
        awk '{printf "│ %12s │ %-48s │\n", $5, $NF}' | \
        sort -t'│' -k2 -rh 2>/dev/null | head -"$top_n"

    echo "└──────────────┴──────────────────────────────────────────────────┘"

    local total=$(find "$scan_path" -type f -size "$size_threshold" \
        -not -path "/proc/*" -not -path "/sys/*" -not -path "/dev/*" 2>/dev/null | wc -l)
    echo "  共找到 ${COLOR_YELLOW}${total}${COLOR_RESET} 个大文件"
}

# ============================================================
# 旧文件扫描 + 交互式清理
# ============================================================

old_file_scan() {
    local mtime="${1:-${OLD_FILE_MTIME:-+30}}"
    local scan_path="${2:-/var/log}"

    echo "🔍 扫描路径: $scan_path"
    echo "📅 修改时间阈值: ${mtime} 天前"
    echo ""

    local old_files=$(find "$scan_path" -type f -mtime "$mtime" 2>/dev/null)
    local count=$(echo "$old_files" | grep -c . 2>/dev/null || echo 0)

    if [[ -z "$old_files" || "$count" -eq 0 ]]; then
        echo "  ${COLOR_GREEN}✅ 未发现超过 ${mtime} 天的旧文件${COLOR_RESET}"
        return 0
    fi

    echo "  找到 ${COLOR_YELLOW}${count}${COLOR_RESET} 个旧文件:"
    echo ""

    # 列表展示
    echo "$old_files" | head -20 | while read -r f; do
        local sz=$(ls -lh "$f" 2>/dev/null | awk '{print $5}')
        local mt=$(stat -c %y "$f" 2>/dev/null | cut -d. -f1)
        printf "  %12s  %s  %s\n" "$sz" "$mt" "$f"
    done

    if [[ $count -gt 20 ]]; then
        echo "  ... 及其他 $((count - 20)) 个文件"
    fi

    echo ""
    if confirm "是否进入交互式删除模式？(将逐个确认)"; then
        local deleted=0
        echo "$old_files" | while read -r f; do
            [[ -z "$f" ]] && continue
            if confirm "删除 $f ?"; then
                rm -f "$f" && { ((deleted++)); echo "  ✓ 已删除: $f"; }
            else
                echo "  ✗ 跳过: $f"
            fi
        done
        echo "  共删除 ${deleted} 个文件"
    fi
}

# ============================================================
# 权限安全审计
# ============================================================

perm_audit() {
    local scan_dirs=("${SECURITY_SCAN_DIRS[@]:-/etc /bin /sbin /usr/bin /usr/sbin}")

    echo "🔐 安全扫描目录: ${scan_dirs[*]}"
    echo ""

    # 1. World-Writable 文件检查
    echo "  📁 全局可写文件 (World-Writable):"
    local ww_count=0
    for dir in "${scan_dirs[@]}"; do
        [[ ! -d "$dir" ]] && continue
        find "$dir" -type f -perm -o+w 2>/dev/null | while read -r f; do
            echo -e "    ${COLOR_RED}$f${COLOR_RESET}"
            ((ww_count++))
        done
    done
    if [[ $ww_count -eq 0 ]]; then
        echo "    ${COLOR_GREEN}✅ 未发现全局可写文件${COLOR_RESET}"
    fi

    echo ""

    # 2. SUID/SGID 文件检查
    echo "  🔑 SUID 文件:"
    local suid_count=0
    for dir in "${scan_dirs[@]}"; do
        [[ ! -d "$dir" ]] && continue
        find "$dir" -type f -perm -4000 2>/dev/null | while read -r f; do
            local perms=$(stat -c "%A" "$f" 2>/dev/null)
            local owner=$(stat -c "%U" "$f" 2>/dev/null)
            printf "    %s  %-10s  %s\n" "$perms" "$owner" "$f"
            ((suid_count++))
        done
    done

    echo ""
    echo "  🔑 SGID 文件:"
    local sgid_count=0
    for dir in "${scan_dirs[@]}"; do
        [[ ! -d "$dir" ]] && continue
        find "$dir" -type f -perm -2000 2>/dev/null | while read -r f; do
            local perms=$(stat -c "%A" "$f" 2>/dev/null)
            local owner=$(stat -c "%U" "$f" 2>/dev/null)
            printf "    %s  %-10s  %s\n" "$perms" "$owner" "$f"
            ((sgid_count++))
        done
    done

    echo ""
    echo "  扫描结果: World-Writable=$ww_count, SUID=$suid_count, SGID=$sgid_count"
}

# ============================================================
# 一键扫描
# ============================================================

run_scanner() {
    print_header "模块三：文件系统扫描仪"

    section "💾 磁盘空间检查"
    disk_usage_check

    echo ""
    section "📂 目录空间分析"
    dir_usage_scan "/home" 2 15

    echo ""
    section "📦 大文件扫描"
    large_file_scan "${LARGE_FILE_SIZE:-+100M}" "/" 20

    echo ""
    section "📅 旧文件扫描"
    old_file_scan "${OLD_FILE_MTIME:-+30}" "/var/log"

    echo ""
    section "🔐 权限安全审计"
    perm_audit

    print_footer
    log_info "文件系统扫描完成"
}

scanner_snapshot() {
    local disk_pct=$(df / --output=pcent 2>/dev/null | tail -1 | tr -d ' %')
    echo "DISK_USAGE=${disk_pct:-0}"
    local large_count=$(find / -type f -size "${LARGE_FILE_SIZE:-+100M}" \
        -not -path "/proc/*" -not -path "/sys/*" -not -path "/dev/*" 2>/dev/null | wc -l)
    echo "LARGE_FILES=${large_count// /}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_scanner
fi
