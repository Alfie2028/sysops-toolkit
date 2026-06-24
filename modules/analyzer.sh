#!/bin/bash
# ============================================================
# 模块四：日志分析引擎
# 功能：实时日志追踪 / 智能归类统计(时间戳+主机名+服务名) / 日志归档压缩
# ============================================================

source "${SCRIPT_DIR:-.}/lib/common.sh" 2>/dev/null || source "$(dirname "$0")/../lib/common.sh"

# ============================================================
# 实时日志追踪
# ============================================================

log_watch() {
    local logfile="$1"
    local filter="${2:-ERROR|FAIL|CRITICAL|WARN}"

    if [[ ! -f "$logfile" ]]; then
        log_error "日志文件不存在: $logfile"
        return 1
    fi

    echo "🔍 实时追踪: $logfile"
    echo "🎯 过滤关键字: $filter"
    echo "   按 Ctrl+C 停止追踪"
    echo "──────────────────────────────────────────────────────"

    trap 'echo ""; echo "追踪停止"; return 0' SIGINT SIGTERM

    tail -n 5 -f "$logfile" 2>/dev/null | while read -r line; do
        if echo "$line" | grep -qE "$filter" 2>/dev/null; then
            if echo "$line" | grep -q "ERROR\|CRITICAL\|FATAL"; then
                echo -e "${COLOR_RED}$line${COLOR_RESET}"
            elif echo "$line" | grep -q "WARN\|WARNING"; then
                echo -e "${COLOR_YELLOW}$line${COLOR_RESET}"
            else
                echo -e "${COLOR_CYAN}$line${COLOR_RESET}"
            fi
        else
            echo "$line"
        fi
    done
}

# ============================================================
# 日志智能归类（含时间戳/主机名/服务名提取）
# ============================================================

log_classify() {
    local logfile="$1"

    if [[ ! -f "$logfile" ]]; then
        log_error "日志文件不存在: $logfile"
        return 1
    fi

    local total_lines=$(wc -l < "$logfile" 2>/dev/null || echo 0)

    echo "📊 日志分类统计: $logfile"
    echo "   总行数: ${COLOR_BOLD}${total_lines}${COLOR_RESET}"
    echo ""

    # --- 按日志级别分类 ---
    echo "  ┌──────────┬────────┬──────────────┐"
    printf "  │ %-8s │ %6s │ %-12s │\n" "级别" "数量" "占比"
    echo "  ├──────────┼────────┼──────────────┤"

    local error_count=$(grep -ciE "ERROR|CRITICAL|FATAL" "$logfile" 2>/dev/null || true)
    error_count="${error_count:-0}"
    local warn_count=$(grep -ciE "WARN|WARNING" "$logfile" 2>/dev/null || true)
    warn_count="${warn_count:-0}"
    local info_count=$(grep -ciE "INFO|NOTICE" "$logfile" 2>/dev/null || true)
    info_count="${info_count:-0}"
    local debug_count=$(grep -ciE "DEBUG|TRACE" "$logfile" 2>/dev/null || true)
    debug_count="${debug_count:-0}"

    if [[ $total_lines -gt 0 ]]; then
        printf "  │ ${COLOR_RED}%-8s${COLOR_RESET} │ ${COLOR_RED}%6s${COLOR_RESET} │ ${COLOR_RED}%11s%%${COLOR_RESET} │\n" \
            "ERROR" "$error_count" "$(awk "BEGIN { printf \"%.1f\", $error_count*100/$total_lines }")"
        printf "  │ ${COLOR_YELLOW}%-8s${COLOR_RESET} │ ${COLOR_YELLOW}%6s${COLOR_RESET} │ ${COLOR_YELLOW}%11s%%${COLOR_RESET} │\n" \
            "WARN" "$warn_count" "$(awk "BEGIN { printf \"%.1f\", $warn_count*100/$total_lines }")"
        printf "  │ ${COLOR_GREEN}%-8s${COLOR_RESET} │ ${COLOR_GREEN}%6s${COLOR_RESET} │ ${COLOR_GREEN}%11s%%${COLOR_RESET} │\n" \
            "INFO" "$info_count" "$(awk "BEGIN { printf \"%.1f\", $info_count*100/$total_lines }")"
        printf "  │ ${COLOR_CYAN}%-8s${COLOR_RESET} │ ${COLOR_CYAN}%6s${COLOR_RESET} │ ${COLOR_CYAN}%11s%%${COLOR_RESET} │\n" \
            "DEBUG" "$debug_count" "$(awk "BEGIN { printf \"%.1f\", $debug_count*100/$total_lines }")"
    fi

    echo "  └──────────┴────────┴──────────────┘"

    # 简要提取主机名和服务名（各取前5）
    local hosts=$(awk '{
        for(i=1;i<=NF;i++) {
            if($i~/^[0-9]{2}:[0-9]{2}:[0-9]{2}$/ && i<NF) { h=$(i+1); if(h!="" && h!~/^\[/) hosts[h]++ } break
        }
    } END { for(h in hosts) print h }' "$logfile" 2>/dev/null | head -5 | tr '\n' ' ')
    local svcs=$(awk '{
        for(i=1;i<=NF;i++) {
            if($i~/^[a-zA-Z_-]+\[[0-9]+\]:?$/) { s=$i; sub(/\[[0-9]+\].*/, "", s); if(s!="") services[s]++ } break
        }
    } END { for(s in services) print s }' "$logfile" 2>/dev/null | head -5 | tr '\n' ' ')
    echo "  🖥️  来源主机: ${hosts:-无}"
    echo "  ⚙️  涉及服务: ${svcs:-无}"
}

# ============================================================
# 日志归档压缩
# ============================================================

log_rotate() {
    local log_dir="${1:-/var/log}"
    local days="${LOG_RETENTION_DAYS:-7}"
    local archive_dir="${SCRIPT_DIR:-.}/logs/archive"

    mkdir -p "$archive_dir"

    echo "📦 日志归档"
    echo "   源目录: $log_dir"
    echo "   归档条件: ${days} 天前"
    echo "   归档目标: $archive_dir"
    echo ""

    local old_logs=$(find "$log_dir" -name "*.log" -mtime "+$days" -type f 2>/dev/null)
    local count=$(echo "$old_logs" | grep -c . 2>/dev/null || echo 0)

    if [[ -z "$old_logs" || "$count" -eq 0 ]]; then
        echo "  ${COLOR_GREEN}✅ 无需归档的日志${COLOR_RESET}"
        return 0
    fi

    echo "  找到 ${COLOR_YELLOW}${count}${COLOR_RESET} 个待归档日志"

    local archive_name="log_archive_$(date +%Y%m%d_%H%M%S).tar.gz"
    local archive_path="$archive_dir/$archive_name"

    echo "$old_logs" | xargs tar -czf "$archive_path" 2>/dev/null && {
        local sz=$(ls -lh "$archive_path" | awk '{print $5}')
        echo "  ${COLOR_GREEN}✅ 归档完成: $archive_name ($sz)${COLOR_RESET}"
        log_info "日志归档: $archive_path ($sz, $count 个文件)"

        if confirm "是否删除已归档的原始日志文件？"; then
            echo "$old_logs" | xargs rm -f 2>/dev/null
            echo "  ✓ 已清理原始日志"
            log_info "已清理 $count 个原始日志文件"
        fi
    } || {
        log_error "归档失败"
    }
}

# ============================================================
# 一键分析
# ============================================================

run_analyzer() {
    print_header "模块四：日志分析引擎"

    # 自动检测系统日志
    local target_log="/var/log/syslog"
    [[ ! -f "$target_log" ]] && target_log="/var/log/messages"
    [[ ! -f "$target_log" ]] && { log_error "未找到系统日志文件"; return 1; }

    echo "  日志文件: $target_log"
    echo ""

    section "📊 日志分类统计"
    log_classify "$target_log"

    echo ""
    if confirm "是否启动实时追踪？(Ctrl+C 停止)"; then
        log_watch "$target_log" "ERROR|FAIL|CRITICAL|WARN"
    fi

    print_footer
    log_info "日志分析完成"
}

