#!/bin/bash
# ============================================================
# 模块五：主控与调度中心 — Linux 系统运维工具箱
# ============================================================
# 用法:
#   ./sysops.sh                 交互式主菜单
#   ./sysops.sh --auto          一键巡检 (所有模块, 文本输出)
#   ./sysops.sh --auto --html   一键巡检 + 生成 HTML 报告
#   ./sysops.sh --module 1      单独运行模块 1 (1-4)
#   ./sysops.sh --daemon        守护进程模式
#   ./sysops.sh --cron-setup    配置 crontab 定时任务
#   ./sysops.sh --help          帮助信息
# ============================================================

set -o pipefail  # 管道中任一命令失败则整体失败

# --- 项目根目录 ---
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROOT_DIR

# --- 加载公共库 ---
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/ui.sh"
source "$ROOT_DIR/lib/report.sh"

# ============================================================
# 帮助信息
# ============================================================

show_help() {
    cat << EOF
${COLOR_BOLD}Linux 系统运维工具箱 v1.0${COLOR_RESET}

用法: $0 [选项]

选项:
  --auto              一键巡检模式 (文本输出)
  --auto --html       一键巡检 + 生成 HTML 报告
  --module <1-4>      单独运行指定模块
  --daemon            启动守护进程模式 (后台定时巡检)
  --daemon-stop       停止守护进程
  --cron-setup        配置 crontab 定时任务
  --cron-remove       移除 crontab 定时任务
  --report            生成最新 HTML 报告
  --help              显示此帮助信息

模块:
  1 — 系统性能监控仪 (CPU/内存/进程)
  2 — 用户活动追踪器 (登录/审计/暴力破解检测)
  3 — 文件系统扫描仪 (磁盘/大文件/权限)
  4 — 日志分析引擎   (实时追踪/归类/归档)

示例:
  ./sysops.sh                        # 交互式菜单
  ./sysops.sh --auto                 # 自动巡检
  ./sysops.sh --module 1             # 仅运行模块一
  ./sysops.sh --auto --html          # 巡检并生成 HTML 报告
EOF
}

# ============================================================
# 运行单个模块
# ============================================================

run_module() {
    local module_id="$1"

    case "$module_id" in
        1)
            source "$ROOT_DIR/modules/monitor.sh"
            run_monitor
            ;;
        2)
            source "$ROOT_DIR/modules/tracker.sh"
            run_tracker
            ;;
        3)
            source "$ROOT_DIR/modules/scanner.sh"
            run_scanner
            ;;
        4)
            source "$ROOT_DIR/modules/analyzer.sh"
            run_analyzer
            ;;
        *)
            log_error "无效模块编号: $module_id (可选: 1-4)"
            return 1
            ;;
    esac
}

# ============================================================
# 一键巡检（所有模块）
# ============================================================

run_all_modules() {
    echo ""
    echo -e "${COLOR_BOLD}${COLOR_CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║        🔍  Linux 系统运维工具箱 — 一键巡检             ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${COLOR_RESET}"
    echo "  开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  主机名:   $(hostname)"
    echo "  内核:     $(uname -r)"
    echo ""

    # --- 模块一 ---
    echo -e "\n${COLOR_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
    echo -e "${COLOR_BOLD}  模块一：系统性能监控${COLOR_RESET}"
    echo -e "${COLOR_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
    source "$ROOT_DIR/modules/monitor.sh"

    local cpu_val=$(cpu_usage)
    local cores=$(cpu_cores)
    read -r load1 load5 load15 <<< "$(cpu_loadavg)"
    read -r mt mu ma mp st su sf sp <<< "$(mem_info)"

    echo "  CPU:  使用率 $(draw_bar "${cpu_val%.*}" 30) (核心: $cores, 负载: $load1/$load5/$load15)"
    echo "  各核心: $(cpu_per_core 2>/dev/null | while read -r c u; do printf '%s:%.1f%% ' "$c" "$u"; done)"
    echo "  内存: 使用率 $(draw_bar "${mp%.*}" 30) ($(human_size $((mu * 1024))) / $(human_size $((mt * 1024))))"
    if [[ "$st" -gt 0 ]]; then
        echo "  Swap: 使用率 $(draw_bar "${sp%.*}" 30) ($(human_size $((su * 1024))) / $(human_size $((st * 1024))))"
    fi
    echo ""
    echo "  Top 5 进程 (按CPU):"
    top_procs cpu 2>/dev/null

    # --- 模块二 ---
    echo -e "\n${COLOR_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
    echo -e "${COLOR_BOLD}  模块二：用户活动追踪${COLOR_RESET}"
    echo -e "${COLOR_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
    source "$ROOT_DIR/modules/tracker.sh"
    active_sessions
    echo ""
    login_history 2>/dev/null
    echo ""
    brute_force_detect 2>/dev/null

    # --- 模块三 ---
    echo -e "\n${COLOR_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
    echo -e "${COLOR_BOLD}  模块三：文件系统扫描${COLOR_RESET}"
    echo -e "${COLOR_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
    source "$ROOT_DIR/modules/scanner.sh"
    disk_usage_check

    # --- 模块四 ---
    echo -e "\n${COLOR_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
    echo -e "${COLOR_BOLD}  模块四：日志分析${COLOR_RESET}"
    echo -e "${COLOR_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
    local syslog="/var/log/syslog"
    [[ ! -f "$syslog" ]] && syslog="/var/log/messages"
    if [[ -f "$syslog" ]]; then
        local total_lines=$(wc -l < "$syslog" 2>/dev/null || echo 0)
        local errors=$(grep -ciE "ERROR|CRITICAL|FATAL" "$syslog" 2>/dev/null || echo 0)
        echo "  系统日志: $syslog"
        echo "  总行数: $total_lines  |  错误数: ${COLOR_RED}$errors${COLOR_RESET}"
    else
        echo "  ⚠ 系统日志文件不存在"
    fi

    # --- 健康评分 ---
    echo -e "\n${COLOR_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
    local disk_pct=$(df / --output=pcent 2>/dev/null | tail -1 | tr -d ' %')
    disk_pct="${disk_pct:-0}"
    local health_score=$(calc_health_score "${cpu_val%.*}" "${mp%.*}" "$disk_pct")
    local health_lvl=$(health_level "$health_score")

    echo -e "  ${COLOR_BOLD}系统健康评分: ${COLOR_BOLD}"
    if [[ $health_score -ge 80 ]]; then
        echo -e "  ${COLOR_GREEN}$health_score / 100 — $health_lvl${COLOR_RESET}"
    elif [[ $health_score -ge 60 ]]; then
        echo -e "  ${COLOR_YELLOW}$health_score / 100 — $health_lvl${COLOR_RESET}"
    else
        echo -e "  ${COLOR_RED}$health_score / 100 — $health_lvl${COLOR_RESET}"
    fi

    echo ""
    echo -e "${COLOR_CYAN}  结束时间: $(date '+%Y-%m-%d %H:%M:%S')${COLOR_RESET}"
    echo ""

    log_info "一键巡检完成 — 健康评分: $health_score/100 ($health_lvl)"
}

# ============================================================
# 生成 HTML 报告
# ============================================================

gen_full_report() {
    log_info "正在生成 HTML 巡检报告..."

    # 收集 CPU 数据
    source "$ROOT_DIR/modules/monitor.sh"
    local cpu_val=$(cpu_usage)
    read -r mt mu ma mp st su sf sp <<< "$(mem_info)"
    read -r load1 load5 load15 <<< "$(cpu_loadavg)"
    local cores=$(cpu_cores)

    # HTML 片段：模块一
    local s1=""
    s1+=$(html_section_start "📊 系统性能监控")
    s1+="<table><tr><th>指标</th><th>数值</th><th>状态</th></tr>"
    s1+="<tr><td>CPU 使用率</td><td>${cpu_val}%</td><td>$([[ ${cpu_val%.*} -ge ${CPU_THRESHOLD:-80} ]] && echo '<span style=\"color:red\">⚠ 告警</span>' || echo '<span style=\"color:green\">✓ 正常</span>')</td></tr>"
    s1+="<tr><td>CPU 核心数</td><td>$cores</td><td></td></tr>"
    s1+="<tr><td>系统负载</td><td>${load1} / ${load5} / ${load15}</td><td></td></tr>"
    s1+="<tr><td>物理内存</td><td>$(human_size $((mu * 1024))) / $(human_size $((mt * 1024))) (${mp}%)</td><td>$([[ ${mp%.*} -ge ${MEM_THRESHOLD:-80} ]] && echo '<span style=\"color:red\">⚠ 告警</span>' || echo '<span style=\"color:green\">✓ 正常</span>')</td></tr>"
    if [[ "$st" -gt 0 ]]; then
        s1+="<tr><td>Swap</td><td>$(human_size $((su * 1024))) / $(human_size $((st * 1024))) (${sp}%)</td><td></td></tr>"
    fi
    s1+="</table>"
    s1+=$(html_section_end)

    # HTML 片段：模块二
    source "$ROOT_DIR/modules/tracker.sh"
    local s2=""
    s2+=$(html_section_start "👤 用户活动追踪")
    local online=$(who -q 2>/dev/null | tail -1 | awk '{print $1}')
    [[ -z "$online" ]] && online=$(who 2>/dev/null | wc -l)
    s2+="<p>当前在线用户: <strong>$online</strong> 人</p>"
    s2+="<pre>$(who -u 2>/dev/null || who 2>/dev/null)</pre>"
    s2+=$(html_section_end)

    # HTML 片段：模块三
    source "$ROOT_DIR/modules/scanner.sh"
    local s3=""
    s3+=$(html_section_start "💾 文件系统扫描")
    s3+="<pre>$(df -h --local 2>/dev/null)</pre>"
    local disk_pct=$(df / --output=pcent 2>/dev/null | tail -1 | tr -d ' %')
    if [[ "${disk_pct:-0}" -ge ${DISK_THRESHOLD:-90} ]]; then
        s3+="<div class=\"critical\">🔴 磁盘使用率 ${disk_pct}% 超过阈值 ${DISK_THRESHOLD:-90}%</div>"
    fi
    s3+=$(html_section_end)

    # HTML 片段：模块四
    local s4=""
    s4+=$(html_section_start "📋 日志分析")
    local syslog="/var/log/syslog"
    [[ ! -f "$syslog" ]] && syslog="/var/log/messages"
    if [[ -f "$syslog" ]]; then
        local tl=$(wc -l < "$syslog" 2>/dev/null || echo 0)
        local errs=$(grep -ciE "ERROR|CRITICAL|FATAL" "$syslog" 2>/dev/null || echo 0)
        s4+="<p>系统日志: <code>$syslog</code></p>"
        s4+="<p>总行数: <strong>$tl</strong> | 错误数: <strong style=\"color:red\">$errs</strong></p>"
    fi
    s4+=$(html_section_end)

    # 生成报告
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local report_file="$ROOT_DIR/reports/sysops_report_${timestamp}.html"

    gen_html_report "$report_file" "$s1" "$s2" "$s3" "$s4"

    echo ""
    echo -e "${COLOR_GREEN}✅ HTML 报告已生成${COLOR_RESET}"
    echo "   📄 $report_file"
    echo ""
    echo "   在 Windows 资源管理器可访问:"
    echo "   $(wslpath -w "$report_file" 2>/dev/null || echo "$report_file")"

    log_info "HTML 报告已生成: $report_file"
}

# ============================================================
# 守护进程模式
# ============================================================

start_daemon() {
    local interval="${1:-${DAEMON_INTERVAL:-300}}"

    if [[ -f "$ROOT_DIR/$PID_FILE" ]]; then
        local old_pid=$(cat "$ROOT_DIR/$PID_FILE")
        if kill -0 "$old_pid" 2>/dev/null; then
            log_warn "守护进程已在运行 (PID: $old_pid)"
            echo "  如需停止: $0 --daemon-stop"
            return 1
        else
            rm -f "$ROOT_DIR/$PID_FILE"
        fi
    fi

    log_info "启动守护进程模式 (间隔: ${interval}s)"

    # 后台运行
    nohup bash -c "
        echo \$\$ > '$ROOT_DIR/$PID_FILE'
        while true; do
            '$ROOT_DIR/sysops.sh' --auto >> '$ROOT_DIR/logs/daemon_$(date +%Y%m%d).log' 2>&1
            sleep $interval
        done
    " &>/dev/null &

    local daemon_pid=$!
    echo "$daemon_pid" > "$ROOT_DIR/$PID_FILE"

    echo -e "${COLOR_GREEN}✅ 守护进程已启动${COLOR_RESET}"
    echo "   PID: $daemon_pid"
    echo "   巡检间隔: ${interval}s"
    echo "   日志: $ROOT_DIR/logs/daemon_$(date +%Y%m%d).log"
    echo "   停止: $0 --daemon-stop"

    log_info "守护进程启动 (PID: $daemon_pid, 间隔: ${interval}s)"
}

stop_daemon() {
    if [[ ! -f "$ROOT_DIR/$PID_FILE" ]]; then
        echo "守护进程未运行 (未找到 PID 文件)"
        return 1
    fi

    local pid=$(cat "$ROOT_DIR/$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        sleep 1
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null
        fi
        rm -f "$ROOT_DIR/$PID_FILE"
        echo -e "${COLOR_GREEN}✅ 守护进程已停止 (PID: $pid)${COLOR_RESET}"
        log_info "守护进程已停止 (PID: $pid)"
    else
        echo "守护进程未运行 (PID $pid 不存在)"
        rm -f "$ROOT_DIR/$PID_FILE"
    fi
}

# ============================================================
# Crontab 管理
# ============================================================

cron_setup() {
    local interval="${1:-5}"  # 默认每 5 分钟

    echo "⏰ 配置 crontab 定时任务"
    echo "   当前脚本: $ROOT_DIR/sysops.sh"
    echo "   巡检间隔: 每 ${interval} 分钟"
    echo ""

    # 检查 crontab 是否可用
    if ! command -v crontab &>/dev/null; then
        log_error "crontab 命令不可用，请安装 cron"
        return 1
    fi

    # 备份现有 crontab
    crontab -l 2>/dev/null > /tmp/sysops_cron_backup.tmp

    # 追加新任务
    local cron_entry="*/$interval * * * * $ROOT_DIR/sysops.sh --auto >> $ROOT_DIR/logs/cron_$(date +\%Y\%m\%d).log 2>&1"
    (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -

    echo -e "${COLOR_GREEN}✅ crontab 已配置${COLOR_RESET}"
    echo "   任务: $cron_entry"
    echo ""
    echo "   当前 crontab:"
    crontab -l 2>/dev/null | tail -5
    echo ""
    echo "   移除定时任务: $0 --cron-remove"

    log_info "crontab 定时任务已配置 (每 ${interval} 分钟)"
}

cron_remove() {
    if crontab -l 2>/dev/null | grep -q "sysops.sh"; then
        crontab -l 2>/dev/null | grep -v "sysops.sh" | crontab -
        echo -e "${COLOR_GREEN}✅ sysops 定时任务已移除${COLOR_RESET}"
        log_info "crontab 定时任务已移除"
    else
        echo "未找到 sysops 定时任务"
    fi
}

# ============================================================
# 交互式主菜单
# ============================================================

main_menu() {
    while true; do
        clear 2>/dev/null || printf "\033c"

        echo -e "${COLOR_CYAN}${COLOR_BOLD}"
        echo "╔══════════════════════════════════════════════════════╗"
        echo "║     🐧 Linux 系统运维工具箱 v1.0                    ║"
        echo "╠══════════════════════════════════════════════════════╣"
        echo "║  主机: $(printf '%-43s' "$(hostname)")║"
        echo "║  时间: $(printf '%-43s' "$(date '+%Y-%m-%d %H:%M:%S')")║"
        echo "╚══════════════════════════════════════════════════════╝"
        echo -e "${COLOR_RESET}"
        echo ""

        local choice

        if has_ui; then
            # 使用 dialog/whiptail 图形菜单
            choice=$(ui_menu \
                "Linux 系统运维工具箱" \
                "请选择操作:" \
                18 60 10 \
                "1"  "📊 系统性能监控仪  — CPU/内存/进程" \
                "2"  "👤 用户活动追踪器  — 登录/审计/安全" \
                "3"  "💾 文件系统扫描仪  — 磁盘/大文件/权限" \
                "4"  "📋 日志分析引擎    — 追踪/归类/归档" \
                "5"  "🔍 一键全面巡检    — 运行所有模块" \
                "6"  "📄 生成巡检报告    — HTML 格式" \
                "7"  "⏰ 配置定时任务    — crontab 自动巡检" \
                "8"  "👻 守护进程模式    — 后台持续监控" \
                "9"  "🛑 停止守护进程" \
                "0"  "退出")
        else
            # 纯文本菜单
            echo "  ${COLOR_BOLD}请选择操作:${COLOR_RESET}"
            echo ""
            echo "  1) 📊 系统性能监控仪  — CPU/内存/进程实时监控"
            echo "  2) 👤 用户活动追踪器  — 登录会话/审计/安全检测"
            echo "  3) 💾 文件系统扫描仪  — 磁盘空间/大文件/权限审计"
            echo "  4) 📋 日志分析引擎    — 实时追踪/智能归类/归档"
            echo "  5) 🔍 一键全面巡检    — 运行所有模块"
            echo "  6) 📄 生成巡检报告    — HTML 格式报告"
            echo "  7) ⏰ 配置定时任务    — 设置 crontab 自动巡检"
            echo "  8) 👻 守护进程模式    — 后台持续监控"
            echo "  9) 🛑 停止守护进程"
            echo "  0) 退出"
            echo ""
            read -r -p "  输入选项 [0-9]: " choice
        fi

        echo ""

        case "$choice" in
            1) run_module 1 ;;
            2) run_module 2 ;;
            3) run_module 3 ;;
            4) run_module 4 ;;
            5) run_all_modules ;;
            6) gen_full_report ;;
            7)
                read -r -p "巡检间隔 (分钟, 默认5): " interval
                cron_setup "${interval:-5}"
                ;;
            8)
                read -r -p "巡检间隔 (秒, 默认300): " interval
                start_daemon "${interval:-${DAEMON_INTERVAL:-300}}"
                ;;
            9) stop_daemon ;;
            0)
                echo -e "${COLOR_GREEN}再见! 👋${COLOR_RESET}"
                log_info "工具箱退出"
                exit 0
                ;;
            *)
                echo -e "${COLOR_RED}无效选项，请重试${COLOR_RESET}"
                ;;
        esac

        # 非 UI 模式：操作完成后暂停
        if ! has_ui && [[ -n "$choice" ]] && [[ "$choice" != "0" ]]; then
            echo ""
            read -r -p "按 Enter 返回主菜单..."
        fi
    done
}

# ============================================================
# 入口
# ============================================================

main() {
    # 解析命令行参数
    case "${1:-}" in
        --auto)
            shift
            init_sysops
            run_all_modules
            if [[ "${1:-}" == "--html" ]]; then
                gen_full_report
            fi
            ;;
        --module)
            shift
            init_sysops
            run_module "${1:-1}"
            ;;
        --daemon)
            shift
            init_sysops
            start_daemon "${1:-${DAEMON_INTERVAL:-300}}"
            ;;
        --daemon-stop)
            init_sysops
            stop_daemon
            ;;
        --cron-setup)
            shift
            init_sysops
            cron_setup "${1:-5}"
            ;;
        --cron-remove)
            init_sysops
            cron_remove
            ;;
        --report)
            init_sysops
            gen_full_report
            ;;
        --help|-h|help)
            show_help
            ;;
        "")
            # 无参数 → 交互式菜单
            init_sysops
            main_menu
            ;;
        *)
            echo -e "${COLOR_RED}未知选项: $1${COLOR_RESET}"
            echo "使用 --help 查看帮助"
            exit 1
            ;;
    esac
}

main "$@"
