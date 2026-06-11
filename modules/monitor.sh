#!/bin/bash
# ============================================================
# 模块一：系统性能监控仪
# 功能：CPU/内存/进程监控 + ASCII 负载趋势图
# ============================================================

source "${SCRIPT_DIR:-.}/lib/common.sh" 2>/dev/null || source "$(dirname "$0")/../lib/common.sh"

# ============================================================
# CPU 监控
# ============================================================

# 读取单次 /proc/stat CPU 数据
_cpu_read() {
    awk 'NR==1 {
        user=$2; nice=$3; sys=$4; idle=$5; iowait=$6; irq=$7; softirq=$8; steal=$9
        total=user+nice+sys+idle+iowait+irq+softirq+steal
        idle_total=idle+iowait
        print total, idle_total
    }' /proc/stat
}

# 计算 CPU 使用率（两次采样间差值）
cpu_usage() {
    local sample1 sample2 total1 idle1 total2 idle2

    sample1=$(_cpu_read)
    read -r total1 idle1 <<< "$sample1"
    sleep 0.5
    sample2=$(_cpu_read)
    read -r total2 idle2 <<< "$sample2"

    local delta_total=$((total2 - total1))
    local delta_idle=$((idle2 - idle1))

    if [[ $delta_total -le 0 ]]; then
        echo "0.0"
    else
        awk "BEGIN { printf \"%.1f\", ($delta_total - $delta_idle) * 100.0 / $delta_total }"
    fi
}

# 获取 1/5/15 分钟平均负载
cpu_loadavg() {
    awk '{printf "%.2f %.2f %.2f", $1, $2, $3}' /proc/loadavg
}

# 获取 CPU 核心数
cpu_cores() {
    nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1
}

# 获取各核心 CPU 使用率（两次采样取差值）
cpu_per_core() {
    # 第一次采样保存到临时文件
    awk '/^cpu[0-9]/ { print $1, $2, $3, $4, $5, $6, $7, $8, $9 }' /proc/stat > /tmp/sysops_cpu_snap1.tmp
    sleep 0.5
    # 第二次采样并计算差值
    awk 'NR==FNR {
        prev[$1]=$2+$3+$4+$5+$6+$7+$8+$9
        prev_idle[$1]=$5+$6
        next
    }
    /^cpu[0-9]/ {
        total=$2+$3+$4+$5+$6+$7+$8+$9
        idle=$5+$6
        d_total=total-prev[$1]
        d_active=d_total-(idle-prev_idle[$1])
        if(d_total>0) printf "%s %.1f\n", $1, d_active*100.0/d_total
        else printf "%s 0.0\n", $1
    }' /tmp/sysops_cpu_snap1.tmp /proc/stat | sort -t'p' -k2 -n
    rm -f /tmp/sysops_cpu_snap1.tmp
}

# ============================================================
# 内存监控
# ============================================================

mem_info() {
    local mem_total mem_avail mem_used mem_pct
    local swap_total swap_free swap_used swap_pct

    mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    mem_avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
    swap_total=$(awk '/SwapTotal/ {print $2}' /proc/meminfo)
    swap_free=$(awk '/SwapFree/ {print $2}' /proc/meminfo)

    mem_used=$((mem_total - mem_avail))
    mem_pct=$(awk "BEGIN { printf \"%.1f\", $mem_used * 100.0 / $mem_total }")

    if [[ $swap_total -gt 0 ]]; then
        swap_used=$((swap_total - swap_free))
        swap_pct=$(awk "BEGIN { printf \"%.1f\", $swap_used * 100.0 / $swap_total }")
    else
        swap_used=0
        swap_pct="0.0"
    fi

    echo "$mem_total $mem_used $mem_avail $mem_pct $swap_total $swap_used $swap_free $swap_pct"
}

# ============================================================
# 进程排行
# ============================================================

top_procs() {
    local sort_by="${1:-cpu}"  # cpu 或 mem
    local top_n="${TOP_N_PROCS:-5}"

    echo "┌────────┬──────────────────────┬──────────┬──────────┐"
    printf "│ %-6s │ %-20s │ %8s │ %8s │\n" "PID" "进程名" "CPU%" "MEM%"
    echo "├────────┼──────────────────────┼──────────┼──────────┤"

    if [[ "$sort_by" == "cpu" ]]; then
        ps aux --sort=-%cpu --no-headers 2>/dev/null | head -"$top_n" | \
            awk '{printf "│ %-6s │ %-20s │ %8s │ %8s │\n", $2, substr($11,1,20), $3, $4}'
    else
        ps aux --sort=-%mem --no-headers 2>/dev/null | head -"$top_n" | \
            awk '{printf "│ %-6s │ %-20s │ %8s │ %8s │\n", $2, substr($11,1,20), $3, $4}'
    fi

    echo "└────────┴──────────────────────┴──────────┴──────────┘"
}

# ============================================================
# ASCII 负载趋势图
# ============================================================

load_chart() {
    local samples="${1:-10}"   # 采集样本数
    local interval="${2:-1}"   # 采集间隔 (秒)
    local data=()

    echo "[*] 正在采集 ${samples} 个样本 (间隔 ${interval}s) ..."

    for ((i=0; i<samples; i++)); do
        local load1=$(awk '{print $1}' /proc/loadavg)
        data+=("$load1")
        sleep "$interval"
    done

    echo ""
    echo "  CPU 负载趋势 (1分钟平均)"
    echo "  ┌────────────────────────────────────────────┐"

    local max_load=0
    for val in "${data[@]}"; do
        float_cmp "$val" ">" "$max_load" && max_load="$val"
    done
    max_load=$(awk "BEGIN { printf \"%.2f\", $max_load + 0.1 }")
    [[ "$max_load" == "0.00" ]] && max_load="1.00"

    local height=10
    for ((row=height; row>=0; row--)); do
        local level=$(awk "BEGIN { printf \"%.2f\", $max_load * $row / $height }")
        printf "  │"
        for val in "${data[@]}"; do
            if float_cmp "$val" ">=" "$level"; then
                echo -n "█"
            else
                echo -n " "
            fi
        done
        printf "│ %.2f\n" "$level"
    done

    echo "  └────────────────────────────────────────────┘"
    printf "  "
    for ((i=0; i<samples; i++)); do
        printf "▔"
    done
    echo ""
}

# ============================================================
# 一键监控（完整输出）
# ============================================================

run_monitor() {
    print_header "模块一：系统性能监控仪"

    # --- CPU ---
    section "📊 CPU 状态"
    local cpu_usage_val=$(cpu_usage)
    local cores=$(cpu_cores)
    local load1 load5 load15
    read -r load1 load5 load15 <<< "$(cpu_loadavg)"

    echo "  CPU 使用率:   $(draw_bar "${cpu_usage_val%.*}" 30)"
    echo "  核心数:       $cores"
    echo "  平均负载:     1min=${load1}  5min=${load5}  15min=${load15}"
    echo "  负载/核心比:  $(awk "BEGIN { printf \"%.2f\", $load1 / $cores }")"

    local cpu_int=${cpu_usage_val%.*}
    if [[ $cpu_int -ge ${CPU_THRESHOLD:-80} ]]; then
        echo -e "  ${COLOR_BG_RED} ⚠ CPU 使用率超过阈值 (${CPU_THRESHOLD:-80}%) ${COLOR_RESET}"
    fi

    # --- 各核心 CPU ---
    echo ""
    echo "  🔢 各核心使用率:"
    echo "  $(cpu_per_core | while read -r core usage; do
        local pct=${usage%.*}
        printf '%s:%s%% ' "$core" "$usage"
    done)"

    # --- 内存 ---
    section "🧠 内存状态"
    read -r mt mu ma mp st su sf sp <<< "$(mem_info)"
    echo "  物理内存: $(human_size $((mu * 1024))) / $(human_size $((mt * 1024)))  $(draw_bar "${mp%.*}" 30)"
    echo "  Swap:     $(human_size $((su * 1024))) / $(human_size $((st * 1024)))  $(draw_bar "${sp%.*}" 30)"

    local mp_int=${mp%.*}
    if [[ $mp_int -ge ${MEM_THRESHOLD:-80} ]]; then
        echo -e "  ${COLOR_BG_RED} ⚠ 内存使用率超过阈值 (${MEM_THRESHOLD:-80}%) ${COLOR_RESET}"
    fi

    # --- 进程排行 ---
    section "📋 CPU Top ${TOP_N_PROCS:-5}"
    top_procs cpu

    echo ""
    section "📋 内存 Top ${TOP_N_PROCS:-5}"
    top_procs mem

    # --- 负载趋势（可选，耗时） ---
    if confirm "是否绘制 CPU 负载趋势图？(约需 10 秒)"; then
        load_chart 10 1
    fi

    print_footer
    log_info "系统性能监控完成"
}

# 获取监控数据（JSON-like 输出，供主控脚本采集）
monitor_snapshot() {
    local cpu_val=$(cpu_usage)
    read -r mt mu ma mp st su sf sp <<< "$(mem_info)"
    echo "CPU_USAGE=$cpu_val"
    echo "MEM_USAGE=$mp"
    echo "SWAP_USAGE=$sp"
    echo "LOAD1=$(awk '{print $1}' /proc/loadavg)"
    echo "PROCS=$(ps aux --no-headers | wc -l)"
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_monitor
fi
