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

    # --- 提取 Top 主机名 ---
    echo ""
    echo "  🖥️  日志来源主机 Top 10 (syslog 格式):"
    # syslog: "Mon DD HH:MM:SS hostname service[PID]: message"
    awk '{
        for(i=1;i<=NF;i++) {
            if($i~/^[0-9]{2}:[0-9]{2}:[0-9]{2}$/ && i<NF) {
                host=$(i+1)
                if(host!="" && host!~/^\[/) { hosts[host]++ }
                break
            }
        }
    }
    END {
        for(h in hosts) print hosts[h], h
    }' "$logfile" 2>/dev/null | sort -rn | head -10 | \
        awk '{printf "    %-20s  %s 条\n", $2, $1}'

    # --- 提取 Top 服务名 ---
    echo ""
    echo "  ⚙️  服务/进程 Top 10:"
    awk '{
        for(i=1;i<=NF;i++) {
            # 匹配 service[PID]: 模式
            if($i~/^[a-zA-Z_-]+\[[0-9]+\]:?$/) {
                svc=$i
                sub(/\[[0-9]+\].*/, "", svc)
                if(svc!="") services[svc]++
                break
            }
        }
    }
    END {
        for(s in services) print services[s], s
    }' "$logfile" 2>/dev/null | sort -rn | head -10 | \
        awk '{printf "    %-25s  %s 条\n", $2, $1}'

    # --- 按小时分布 ---
    echo ""
    echo "  ⏰ 时间分布 (按小时):"
    echo "  ┌──────┬────────┬──────────────────────────────────────────┐"
    printf "  │ %4s │ %6s │ %-40s │\n" "小时" "数量" "分布"
    echo "  ├──────┼────────┼──────────────────────────────────────────┤"

    grep -oE '[0-9]{2}:[0-9]{2}:[0-9]{2}' "$logfile" 2>/dev/null | \
        cut -d: -f1 | sort | uniq -c | sort -k2 -n | head -24 | \
        while read -r cnt hour; do
            local bar_len=$(( cnt * 40 / (total_lines / 24 + 1) ))
            [[ $bar_len -gt 40 ]] && bar_len=40
            local bar=""
            for ((i=0; i<bar_len; i++)); do bar+="█"; done
            printf "  │ %4s │ %6s │ %-40s │\n" "$hour" "$cnt" "$bar"
        done

    echo "  └──────┴────────┴──────────────────────────────────────────┘"
}

# ============================================================
# 日志归档压缩
# ============================================================

log_rotate() {
    local log_dir="${1:-/var/log}"
    local days="${2:-${LOG_RETENTION_DAYS:-7}}"
    local archive_dir="${3:-${SCRIPT_DIR:-.}/${LOG_ARCHIVE_DIR:-./logs/archive}}"

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
# 日志搜索
# ============================================================

log_search() {
    local logfile="$1"
    local pattern="$2"
    local context="${3:-0}"

    if [[ ! -f "$logfile" ]]; then
        log_error "日志文件不存在: $logfile"
        return 1
    fi

    echo "🔍 搜索: \"$pattern\" 于 $logfile"
    echo ""

    if [[ $context -gt 0 ]]; then
        grep -n -C "$context" "$pattern" "$logfile" 2>/dev/null | head -50
    else
        grep -n "$pattern" "$logfile" 2>/dev/null | head -50
    fi

    local total=$(grep -c "$pattern" "$logfile" 2>/dev/null || echo 0)
    echo ""
    echo "  共匹配 ${COLOR_BOLD}${total}${COLOR_RESET} 条"
}

# ============================================================
# 一键分析
# ============================================================

run_analyzer() {
    print_header "模块四：日志分析引擎"

    echo "可选日志文件:"
    echo "  1) /var/log/syslog     (系统主日志)"
    echo "  2) /var/log/auth.log   (认证日志)"
    echo "  3) /var/log/kern.log   (内核日志)"
    echo "  4) /var/log/dpkg.log   (软件包日志)"
    echo "  5) 自定义路径"
    echo ""

    local choice
    read -r -p "请选择 [1-5]: " choice

    local target_log=""
    case "$choice" in
        1) target_log="/var/log/syslog" ;;
        2) target_log="/var/log/auth.log" ;;
        3) target_log="/var/log/kern.log" ;;
        4) target_log="/var/log/dpkg.log" ;;
        5) read -r -p "输入日志路径: " target_log ;;
        *) target_log="/var/log/syslog" ;;
    esac

    [[ ! -f "$target_log" ]] && {
        log_error "日志文件不存在: $target_log"
        return 1
    }

    echo ""

    section "📊 日志分类统计"
    log_classify "$target_log"

    echo ""
    if confirm "是否启动实时追踪？(Ctrl+C 停止)"; then
        log_watch "$target_log" "ERROR|FAIL|CRITICAL|WARN"
    fi

    echo ""
    if confirm "是否执行日志归档？"; then
        log_rotate "/var/log" "${LOG_RETENTION_DAYS:-7}"
    fi

    print_footer
    log_info "日志分析完成"
}

analyzer_snapshot() {
    local syslog="/var/log/syslog"
    [[ ! -f "$syslog" ]] && syslog="/var/log/messages"
    if [[ -f "$syslog" ]]; then
        echo "SYSLOG_LINES=$(wc -l < "$syslog" 2>/dev/null || echo 0)"
        echo "SYSLOG_ERRORS=$(grep -ciE "ERROR|CRITICAL|FATAL" "$syslog" 2>/dev/null || echo 0)"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_analyzer
fi
