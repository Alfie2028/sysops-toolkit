#!/bin/bash
# ============================================================
# 模块二：用户活动追踪器
# 功能：当前登录会话 / 登录失败统计 / 暴力破解检测 / sudo 审计
# ============================================================

source "${SCRIPT_DIR:-.}/lib/common.sh" 2>/dev/null || source "$(dirname "$0")/../lib/common.sh"

# ============================================================
# 当前登录会话
# ============================================================

# ============================================================
# 当前登录会话
# ============================================================

active_sessions() {
    echo "┌──────────┬───────┬──────────────────────┬──────────────────┐"
    printf "│ %-8s │ %-5s │ %-20s │ %-16s │\n" "用户" "终端" "登录时间" "来源IP"
    echo "├──────────┼───────┼──────────────────────┼──────────────────┤"

    local count=0
    local has_data=0

    # 首选 who -u (标准 Linux)
    while read -r user tty date time _ pid _ ip; do
        [[ -z "$user" ]] && continue
        has_data=1
        local ip_clean="${ip#(}"; ip_clean="${ip_clean%)}"
        [[ -z "$ip_clean" ]] && ip_clean="本地"
        printf "│ %-8s │ %-5s │ %s %s │ %-16s │\n" "$user" "$tty" "$date" "$time" "$ip_clean"
        ((count++))
    done < <(who -u 2>/dev/null)

    # WSL 降级：w 命令通常能拿到当前用户
    if [[ $has_data -eq 0 ]]; then
        while read -r user tty _ _ _ login rest; do
            [[ -z "$user" ]] && continue
            has_data=1
            printf "│ %-8s │ %-5s │ %-20s │ %-16s │\n" "$user" "$tty" "$login" "本地(WSL)"
            ((count++))
        done < <(w -hi 2>/dev/null)
    fi

    # 最终降级：至少显示当前用户
    if [[ $has_data -eq 0 ]]; then
        printf "│ %-8s │ %-5s │ %-20s │ %-16s │\n" "${USER:-root}" "pts/0" "$(date '+%Y-%m-%d %H:%M')" "本地(WSL)"
        count=1
    fi

    echo "└──────────┴───────┴──────────────────────┴──────────────────┘"
    echo -e "  当前在线用户: ${COLOR_BOLD}${count}${COLOR_RESET} 人"

    # WSL 提示
    if [[ ! -f /var/run/utmp ]]; then
        echo -e "  ${COLOR_YELLOW}⚠ WSL 环境: /var/run/utmp 不可用，已使用替代方式获取${COLOR_RESET}"
    fi
}

# ============================================================
# 登录历史分析 (last 命令 / wtmp 解析)
# ============================================================

# ============================================================
# 登录历史分析 (last 命令 / wtmp 解析)
# ============================================================

login_history() {
    echo "📜 历史登录记录 (最近 20 条):"

    # WSL 通常没有 wtmp
    if [[ ! -f /var/log/wtmp ]]; then
        echo -e "  ${COLOR_YELLOW}⚠ WSL 环境: /var/log/wtmp 不存在，无登录历史记录${COLOR_RESET}"
        return 0
    fi

    echo "  ┌─────────────────────┬──────────┬──────────────────────────────┐"
    printf "  │ %-19s │ %-8s │ %-28s │\n" "登录时间" "用户" "来源"
    echo "  ├─────────────────────┼──────────┼──────────────────────────────┤"

    local has_data=0
    last -n 20 2>/dev/null | head -20 | while read -r user tty ip rest; do
        [[ -z "$user" || "$user" == "reboot" || "$user" == "wtmp" ]] && continue
        local login_time="$rest"
        [[ -z "$login_time" ]] && login_time="$ip $rest"
        ip="${ip:-本地}"; ip="${ip:0:28}"
        printf "  │ %-19s │ %-8s │ %-28s │\n" "${login_time:0:19}" "$user" "$ip"
        has_data=1
    done

    echo "  └─────────────────────┴──────────┴──────────────────────────────┘"

    if [[ $has_data -eq 0 ]]; then
        echo -e "  ${COLOR_YELLOW}  wtmp 文件存在但无有效登录记录${COLOR_RESET}"
    fi
}

# ============================================================
# 登录失败统计
# ============================================================

failed_logins() {
    local auth_log=""
    [[ -f /var/log/auth.log ]] && auth_log="/var/log/auth.log"
    [[ -f /var/log/secure ]] && auth_log="/var/log/secure"

    if [[ -z "$auth_log" ]]; then
        echo -e "  ${COLOR_YELLOW}⚠ WSL 环境: 未找到认证日志 (auth.log / secure)${COLOR_RESET}"
        return 0
    fi

    local total_fail=$(grep -c "Failed password" "$auth_log" 2>/dev/null || true)
    total_fail="${total_fail:-0}"

    echo "🔍 分析: $auth_log"

    if [[ "$total_fail" -eq 0 ]]; then
        echo -e "  ${COLOR_GREEN}✅ 未发现登录失败记录${COLOR_RESET} (历史总失败: 0)"
        return 0
    fi

    echo ""
    echo "  📉 近期登录失败统计 (前 10 IP):"
    echo "  ┌────────────────┬───────┬──────────────────────────────┐"
    printf "  │ %-14s │ %5s │ %-28s │\n" "IP地址" "次数" "最近时间"
    echo "  ├────────────────┼───────┼──────────────────────────────┤"

    grep "Failed password" "$auth_log" 2>/dev/null | \
        awk '{
            for(i=1;i<=NF;i++) { if($i=="from") { ip=$(i+1); break } }
            if(ip) { count[ip]++; last_time[ip]=$1" "$2" "$3 }
        }
        END { for(ip in count) print count[ip], last_time[ip], ip }' | \
        sort -rn | head -10 | \
        awk '{printf "  │ %-14s │ %5s │ %-28s │\n", $3, $1, $2}'

    echo "  └────────────────┴───────┴──────────────────────────────┘"
    echo -e "  历史总失败次数: ${COLOR_RED}${total_fail}${COLOR_RESET}"
}

# ============================================================
# 暴力破解检测
# ============================================================

brute_force_detect() {
    local auth_log=""
    [[ -f /var/log/auth.log ]] && auth_log="/var/log/auth.log"
    [[ -f /var/log/secure ]] && auth_log="/var/log/secure"

    if [[ -z "$auth_log" ]]; then
        echo -e "  ${COLOR_YELLOW}⚠ WSL 环境: 无认证日志，跳过暴力破解检测${COLOR_RESET}"
        return 0
    fi

    local window="${BRUTE_FORCE_WINDOW:-300}"
    local threshold="${BRUTE_FORCE_THRESHOLD:-5}"

    echo "🔴 暴力破解检测 (窗口: ${window}s, 阈值: ${threshold} 次)"
    echo ""

    local detected=0
    grep "Failed password" "$auth_log" 2>/dev/null | \
        awk -v now="$(date +%s)" -v window="$window" -v threshold="$threshold" '
        {
            month_str=$1; day=$2; time_str=$3
            cmd="date -d \"" month_str " " day " " time_str "\" +%s 2>/dev/null"
            cmd | getline ts; close(cmd)
            if(ts > 0 && (now - ts) <= window) {
                for(i=1;i<=NF;i++) { if($i=="from") { ip=$(i+1); count[ip]++; break } }
            }
        }
        END { for(ip in count) if(count[ip] >= threshold) printf "%d %s\n", count[ip], ip }
        ' | while read -r cnt ip; do
            detected=1
            echo -e "  ${COLOR_BG_RED} 🚨 暴力破解告警 ${COLOR_RESET}"
            echo "     IP: $ip  —  失败 $cnt 次 (${window}s 内)"
            echo ""
        done

    [[ $detected -eq 0 ]] && echo -e "  ${COLOR_GREEN}✅ 未检测到暴力破解行为${COLOR_RESET}"
}

# ============================================================
# Sudo 审计
# ============================================================

sudo_audit() {
    local auth_log=""
    [[ -f /var/log/auth.log ]] && auth_log="/var/log/auth.log"
    [[ -f /var/log/secure ]] && auth_log="/var/log/secure"

    echo "🛡️  近期 sudo 操作记录:"

    if [[ -z "$auth_log" ]]; then
        echo -e "  ${COLOR_YELLOW}⚠ WSL 环境: 无认证日志，无法审计 sudo 操作${COLOR_RESET}"
        return 0
    fi

    local sudo_count=$(grep -c "sudo.*COMMAND" "$auth_log" 2>/dev/null || true)
    sudo_count="${sudo_count:-0}"

    if [[ "$sudo_count" -eq 0 ]]; then
        echo -e "  ${COLOR_GREEN}✅ 无 sudo 操作记录${COLOR_RESET}"
        return 0
    fi

    echo "  ┌─────────────────────┬──────────┬────────────────────────────────────┐"
    printf "  │ %-19s │ %-8s │ %-34s │\n" "时间" "用户" "命令"
    echo "  ├─────────────────────┼──────────┼────────────────────────────────────┤"

    grep "sudo" "$auth_log" 2>/dev/null | grep "COMMAND" | tail -20 | \
        awk '{
            time=$1" "$2" "$3; user=""; cmd=""
            for(i=1;i<=NF;i++) {
                if($i=="USER=") user=$(i+1)
                if($i=="COMMAND=") { cmd=substr($(i+1),1,34); break }
            }
            printf "  │ %-19s │ %-8s │ %-34s │\n", time, user, cmd
        }'

    echo "  └─────────────────────┴──────────┴────────────────────────────────────┘"
    echo -e "  sudo 历史操作总数: ${COLOR_YELLOW}${sudo_count}${COLOR_RESET}"
}

# ============================================================
# 权限检查
# ============================================================

# 检查 sudoers 中的高权限用户
sudoers_check() {
    echo "🛡️  sudo 特权用户:"
    local found=0
    if [[ -f /etc/sudoers ]]; then
        while read -r line; do
            [[ -n "$line" ]] && { echo "    $line"; found=1; }
        done < <(grep -E '^[^#].*ALL=' /etc/sudoers 2>/dev/null)
    fi
    if [[ -d /etc/sudoers.d ]]; then
        while read -r line; do
            [[ -n "$line" ]] && { echo "    $line"; found=1; }
        done < <(grep -rE '^[^#].*ALL=' /etc/sudoers.d/ 2>/dev/null)
    fi
    [[ $found -eq 0 ]] && echo "    (未找到显式 ALL= 条目，sudo 权限可能通过组继承)"
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

