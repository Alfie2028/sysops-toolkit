#!/bin/bash
# ============================================================
# 模块二：用户活动追踪器
# 功能：当前登录会话 / 登录失败统计 / 暴力破解检测 / sudo 审计
# ============================================================

source "${SCRIPT_DIR:-.}/lib/common.sh" 2>/dev/null || source "$(dirname "$0")/../lib/common.sh"

# ============================================================
# 当前登录会话
# ============================================================

active_sessions() {
    echo "┌──────────┬───────┬──────────────────────┬──────────────────┐"
    printf "│ %-8s │ %-5s │ %-20s │ %-16s │\n" "用户" "终端" "登录时间" "来源IP"
    echo "├──────────┼───────┼──────────────────────┼──────────────────┤"

    # 使用 who -u 获取详细会话信息
    who -u 2>/dev/null | while read -r user tty date time _ pid _ ip; do
        local ip_clean="${ip#(}"
        ip_clean="${ip_clean%)}"
        [[ -z "$ip_clean" ]] && ip_clean="本地"
        printf "│ %-8s │ %-5s │ %s %s │ %-16s │\n" \
            "$user" "$tty" "$date" "$time" "$ip_clean"
    done

    echo "└──────────┴───────┴──────────────────────┴──────────────────┘"

    local count=$(who 2>/dev/null | wc -l)
    echo -e "  当前在线用户: ${COLOR_BOLD}${count}${COLOR_RESET} 人"
}

# ============================================================
# 登录历史分析 (last 命令 / wtmp 解析)
# ============================================================

login_history() {
    echo "📜 历史登录记录 (最近 20 条):"
    echo "  ┌─────────────────────┬──────────┬──────────────────────────────┐"
    printf "  │ %-19s │ %-8s │ %-28s │\n" "登录时间" "用户" "来源"
    echo "  ├─────────────────────┼──────────┼──────────────────────────────┤"

    # last 命令解析 /var/log/wtmp
    last -n 20 2>/dev/null | head -20 | while read -r user tty ip rest; do
        # 过滤空行和特殊行 (wtmp begins, reboot, 空行)
        [[ -z "$user" ]] && continue
        [[ "$user" == "reboot" ]] && continue
        [[ "$user" == "wtmp" ]] && continue

        local login_time="$rest"
        [[ -z "$login_time" ]] && login_time="$ip $rest"
        ip="${ip:-本地}"
        # 截断过长的 IP
        ip="${ip:0:28}"
        printf "  │ %-19s │ %-8s │ %-28s │\n" "${login_time:0:19}" "$user" "$ip"
    done

    echo "  └─────────────────────┴──────────┴──────────────────────────────┘"

    # 统计: 各用户登录次数排名
    echo ""
    echo "  📊 用户登录次数统计 (历史):"
    echo "  ┌──────────┬────────┬──────────────────────────────────────────┐"
    printf "  │ %-8s │ %6s │ %-40s │\n" "用户" "次数" "分布"
    echo "  ├──────────┼────────┼──────────────────────────────────────────┤"

    local max_count=0
    local -A user_counts
    local users=() counts=()

    while read -r count user; do
        [[ -z "$user" || "$user" == "reboot" || "$user" == "wtmp" ]] && continue
        users+=("$user")
        counts+=("$count")
        [[ $count -gt $max_count ]] && max_count=$count
    done < <(last 2>/dev/null | awk '{print $1}' | grep -vE '^(wtmp|reboot|$)' | sort | uniq -c | sort -rn | head -10)

    for ((i=0; i<${#users[@]}; i++)); do
        local bar_len=$(( counts[i] * 40 / (max_count + 1) ))
        [[ $bar_len -gt 40 ]] && bar_len=40
        local bar=""
        for ((j=0; j<bar_len; j++)); do bar+="█"; done
        printf "  │ %-8s │ %6s │ %-40s │\n" "${users[i]:0:8}" "${counts[i]}" "$bar"
    done

    echo "  └──────────┴────────┴──────────────────────────────────────────┘"

    # 统计: 登录来源 IP 分布
    echo ""
    echo "  🌐 登录来源分布 (Top 10):"
    last -i 2>/dev/null | awk '{print $3}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort | uniq -c | sort -rn | head -10 | \
        awk '{printf "    %-16s  %s 次\n", $2, $1}'
}

# ============================================================
# 登录失败统计
# ============================================================

failed_logins() {
    local auth_log=""

    # 检测认证日志路径
    if [[ -f /var/log/auth.log ]]; then
        auth_log="/var/log/auth.log"
    elif [[ -f /var/log/secure ]]; then
        auth_log="/var/log/secure"
    else
        log_warn "未找到认证日志文件"
        echo "  ⚠ 未找到 /var/log/auth.log 或 /var/log/secure"
        return 1
    fi

    echo "🔍 分析: $auth_log"
    echo ""

    # 统计登录失败
    echo "  📉 近期登录失败统计 (前 10 IP):"
    echo "  ┌────────────────┬───────┬──────────────────────────────┐"
    printf "  │ %-14s │ %5s │ %-28s │\n" "IP地址" "次数" "最近时间"
    echo "  ├────────────────┼───────┼──────────────────────────────┤"

    # Ubuntu: "Failed password for"
    # CentOS: "Failed password for"
    grep "Failed password" "$auth_log" 2>/dev/null | \
        awk '{
            for(i=1;i<=NF;i++) {
                if($i=="from") { ip=$(i+1); break }
            }
            if(ip) {
                count[ip]++
                last_time[ip]=$1" "$2" "$3
            }
        }
        END {
            for(ip in count) print count[ip], last_time[ip], ip
        }' | sort -rn | head -10 | \
        awk '{printf "  │ %-14s │ %5s │ %-28s │\n", $3, $1, $2}'

    echo "  └────────────────┴───────┴──────────────────────────────┘"

    local total_fail=$(grep -c "Failed password" "$auth_log" 2>/dev/null || true)
    total_fail="${total_fail:-0}"
    echo -e "  历史总失败次数: ${COLOR_RED}${total_fail}${COLOR_RESET}"
}

# ============================================================
# 暴力破解检测
# ============================================================

brute_force_detect() {
    local auth_log=""
    [[ -f /var/log/auth.log ]] && auth_log="/var/log/auth.log"
    [[ -f /var/log/secure ]] && auth_log="/var/log/secure"
    [[ -z "$auth_log" ]] && { echo "  ⚠ 未找到认证日志"; return 1; }

    local window="${BRUTE_FORCE_WINDOW:-300}"
    local threshold="${BRUTE_FORCE_THRESHOLD:-5}"
    local now=$(date +%s)

    echo "🔴 暴力破解检测 (窗口: ${window}s, 阈值: ${threshold} 次)"
    echo ""

    # 取最近一段时间的失败记录，统计 IP
    local detected=0
    grep "Failed password" "$auth_log" 2>/dev/null | \
        awk -v now="$now" -v window="$window" -v threshold="$threshold" '
        {
            # 解析时间戳 (假设 syslog 格式: "Mon DD HH:MM:SS")
            month_str=$1; day=$2; time_str=$3
            cmd="date -d \"" month_str " " day " " time_str "\" +%s 2>/dev/null"
            cmd | getline ts
            close(cmd)
            if(ts > 0 && (now - ts) <= window) {
                for(i=1;i<=NF;i++) {
                    if($i=="from") { ip=$(i+1); count[ip]++; break }
                }
            }
        }
        END {
            for(ip in count)
                if(count[ip] >= threshold)
                    printf "%d %s\n", count[ip], ip
        }' | while read -r cnt ip; do
            detected=1
            echo -e "  ${COLOR_BG_RED} 🚨 暴力破解告警 ${COLOR_RESET}"
            echo "     IP: $ip  —  失败 $cnt 次 (${window}s 内)"
            echo "     建议: sudo ufw deny from $ip"
            echo ""
        done

    if [[ $detected -eq 1 ]]; then
        log_warn "检测到暴力破解尝试"
    else
        echo "  ${COLOR_GREEN}✅ 未检测到暴力破解行为${COLOR_RESET}"
    fi
}

# ============================================================
# Sudo 审计
# ============================================================

sudo_audit() {
    local auth_log=""
    [[ -f /var/log/auth.log ]] && auth_log="/var/log/auth.log"
    [[ -f /var/log/secure ]] && auth_log="/var/log/secure"
    [[ -z "$auth_log" ]] && { echo "  ⚠ 未找到认证日志"; return 1; }

    echo "🛡️  近期 sudo 操作记录 (最近 20 条):"
    echo "  ┌─────────────────────┬──────────┬────────────────────────────────────┐"
    printf "  │ %-19s │ %-8s │ %-34s │\n" "时间" "用户" "命令"
    echo "  ├─────────────────────┼──────────┼────────────────────────────────────┤"

    grep "sudo" "$auth_log" 2>/dev/null | grep "COMMAND" | tail -20 | \
        awk '{
            time=$1" "$2" "$3
            user=""
            cmd=""
            for(i=1;i<=NF;i++) {
                if($i=="USER=") user=$(i+1)
                if($i=="COMMAND=") {
                    cmd=substr($(i+1),1,34)
                    break
                }
            }
            printf "  │ %-19s │ %-8s │ %-34s │\n", time, user, cmd
        }'

    echo "  └─────────────────────┴──────────┴────────────────────────────────────┘"

    local sudo_count=$(grep -c "sudo.*COMMAND" "$auth_log" 2>/dev/null || true)
    sudo_count="${sudo_count:-0}"
    echo -e "  sudo 历史操作总数: ${COLOR_YELLOW}${sudo_count}${COLOR_RESET}"
}

# ============================================================
# 权限检查
# ============================================================

# 检查 sudoers 中的高权限用户
sudoers_check() {
    echo "🛡️  sudo 特权用户:"
    if [[ -f /etc/sudoers ]]; then
        grep -E '^[^#].*ALL=' /etc/sudoers 2>/dev/null | while read -r line; do
            echo "    $line"
        done
    fi
    # 检查 sudoers.d 目录
    if [[ -d /etc/sudoers.d ]]; then
        grep -rE '^[^#].*ALL=' /etc/sudoers.d/ 2>/dev/null | while read -r line; do
            echo "    $line"
        done
    fi
}

# ============================================================
# 一键追踪
# ============================================================

run_tracker() {
    print_header "模块二：用户活动追踪器"

    section "👤 当前登录会话"
    active_sessions

    echo ""
    section "📜 登录历史记录"
    login_history

    echo ""
    section "🔐 登录失败分析"
    failed_logins

    echo ""
    section "🚨 暴力破解检测"
    brute_force_detect

    echo ""
    section "🛡️ Sudo 操作审计"
    sudo_audit

    echo ""
    section "🔑 Sudoers 权限配置"
    sudoers_check

    print_footer
    log_info "用户活动追踪完成"
}

# 快照数据供报告使用
tracker_snapshot() {
    local online=$(who -q 2>/dev/null | tail -1 | awk '{print $1}')
    [[ -z "$online" ]] && online=$(who 2>/dev/null | wc -l)
    echo "ONLINE_USERS=$online"
    local auth_log=""
    [[ -f /var/log/auth.log ]] && auth_log="/var/log/auth.log"
    [[ -f /var/log/secure ]] && auth_log="/var/log/secure"
    if [[ -n "$auth_log" ]]; then
        echo "FAILED_LOGINS=$(grep -c "Failed password" "$auth_log" 2>/dev/null || echo 0)"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_tracker
fi
