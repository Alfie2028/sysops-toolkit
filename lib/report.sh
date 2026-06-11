#!/bin/bash
# ============================================================
# 报告生成库 — HTML/文本报告拼接、系统健康评分
# ============================================================

[[ -n "$_REPORT_SH_LOADED" ]] && return
_REPORT_SH_LOADED=1

# ============================================================
# 系统健康评分 (0-100)
# ============================================================

calc_health_score() {
    local cpu_usage="$1"
    local mem_usage="$2"
    local disk_usage="$3"
    local score=100

    # CPU: 每超过阈值 1% 扣 2 分
    if float_cmp "$cpu_usage" ">" "$CPU_THRESHOLD"; then
        score=$((score - ($(printf "%.0f" "$cpu_usage") - CPU_THRESHOLD) * 2))
    fi

    # 内存: 每超过阈值 1% 扣 1.5 分
    if float_cmp "$mem_usage" ">" "$MEM_THRESHOLD"; then
        score=$((score - ($(printf "%.0f" "$mem_usage") - MEM_THRESHOLD) * 3 / 2))
    fi

    # 磁盘: 每超过阈值 1% 扣 2 分
    if float_cmp "$disk_usage" ">" "$DISK_THRESHOLD"; then
        score=$((score - ($(printf "%.0f" "$disk_usage") - DISK_THRESHOLD) * 2))
    fi

    # 限制范围
    [[ $score -lt 0 ]] && score=0
    [[ $score -gt 100 ]] && score=100

    echo "$score"
}

health_level() {
    local score="$1"
    if [[ $score -ge 80 ]]; then
        echo "优秀"
    elif [[ $score -ge 60 ]]; then
        echo "良好"
    elif [[ $score -ge 40 ]]; then
        echo "一般"
    else
        echo "警告"
    fi
}

# ============================================================
# HTML 报告生成
# ============================================================

gen_html_report() {
    local output_file="$1"
    shift
    local sections=("$@")  # 各模块返回的 HTML 片段

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local hostname=$(hostname)
    local kernel_ver=$(uname -r)

    # 收集系统快照用于评分
    local cpu_val=$(awk '{u=$2+$4; t=$2+$4+$5; if(t>0) printf "%.1f", u*100/t; else print 0}' /proc/stat)
    local mem_val=$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf "%.1f", (t-a)*100/t}' /proc/meminfo)
    local disk_val=$(df / --output=pcent 2>/dev/null | tail -1 | tr -d ' %')
    disk_val="${disk_val:-0}"
    local health_score=$(calc_health_score "$cpu_val" "$mem_val" "$disk_val")
    local health_lvl=$(health_level "$health_score")

    cat > "$output_file" << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Linux 系统运维报告 - $timestamp</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: 'Microsoft YaHei', 'Segoe UI', sans-serif; font-size: 14px;
         background: #f0f2f5; color: #333; line-height: 1.8; padding: 20px; }
  .container { max-width: 900px; margin: 0 auto; }
  .header { background: linear-gradient(135deg, #1a1a2e, #16213e); color: #fff;
             padding: 30px; border-radius: 12px; margin-bottom: 20px; }
  .header h1 { font-size: 24px; margin-bottom: 8px; }
  .header p { opacity: 0.85; font-size: 13px; }
  .health-card { background: #fff; padding: 20px; border-radius: 12px;
                 margin-bottom: 20px; text-align: center; box-shadow: 0 2px 8px rgba(0,0,0,0.08); }
  .health-score { font-size: 48px; font-weight: bold; }
  .score-good { color: #27ae60; } .score-warn { color: #f39c12; } .score-bad { color: #e74c3c; }
  .section-card { background: #fff; padding: 24px; border-radius: 12px;
                  margin-bottom: 16px; box-shadow: 0 2px 8px rgba(0,0,0,0.08); }
  .section-card h2 { font-size: 18px; color: #2c3e50; border-bottom: 2px solid #3498db;
                     padding-bottom: 8px; margin-bottom: 16px; }
  pre { background: #2d3436; color: #dfe6e9; padding: 16px; border-radius: 8px;
        font-family: 'Consolas', 'Courier New', monospace; font-size: 13px;
        overflow-x: auto; white-space: pre-wrap; }
  .alert { background: #ffeaa7; border-left: 4px solid #fdcb6e; padding: 8px 12px;
           margin: 8px 0; border-radius: 0 6px 6px 0; }
  .critical { background: #fab1a0; border-left: 4px solid #e74c3c; padding: 8px 12px;
              margin: 8px 0; border-radius: 0 6px 6px 0; }
  .footer { text-align: center; color: #999; font-size: 12px; margin-top: 30px; padding: 16px; }
  table { width: 100%; border-collapse: collapse; margin: 10px 0; }
  th { background: #3498db; color: #fff; padding: 10px; text-align: left; font-size: 13px; }
  td { padding: 8px 10px; border-bottom: 1px solid #eee; font-size: 13px; }
  tr:hover { background: #f8f9fa; }
</style>
</head>
<body>
<div class="container">

<div class="header">
  <h1>🖥 Linux 系统运维巡检报告</h1>
  <p>生成时间: $timestamp &nbsp;|&nbsp; 主机名: $hostname &nbsp;|&nbsp; 内核: $kernel_ver</p>
</div>

<div class="health-card">
  <div class="health-score score-$([[ $health_score -ge 80 ]] && echo "good" || [[ $health_score -ge 60 ]] && echo "warn" || echo "bad")">
    $health_score
  </div>
  <p>系统健康评分 — <strong>$health_lvl</strong></p>
  <p style="font-size:12px;color:#999;">CPU: ${cpu_val}% | 内存: ${mem_val}% | 磁盘: ${disk_val}%</p>
</div>

EOF

    # 插入各模块内容
    for section in "${sections[@]}"; do
        echo "$section" >> "$output_file"
    done

    # 尾部
    cat >> "$output_file" << EOF

<div class="footer">
  <p>Linux 系统运维工具箱 v1.0 | 自动生成报告 | $timestamp</p>
</div>

</div>
</body>
</html>
EOF

    log_info "HTML 报告已生成: $output_file"
    echo "$output_file"
}

# ============================================================
# 文本报告生成
# ============================================================

gen_text_report() {
    local output_file="$1"
    local content="$2"

    {
        echo "========================================"
        echo "  Linux 系统运维巡检报告"
        echo "  生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "  主机名: $(hostname)"
        echo "  内核: $(uname -r)"
        echo "========================================"
        echo ""
        echo "$content"
        echo ""
        echo "========================================"
        echo "  报告结束 — $(date '+%Y-%m-%d %H:%M:%S')"
        echo "========================================"
    } > "$output_file"

    log_info "文本报告已生成: $output_file"
}

# ============================================================
# HTML 片段构建器（各模块调用）
# ============================================================

html_section_start() {
    local title="$1"
    echo "<div class=\"section-card\"><h2>$title</h2>"
}

html_section_end() {
    echo "</div>"
}

html_pre_block() {
    local content="$1"
    echo "<pre>$(echo "$content" | sed 's/</\&lt;/g; s/>/\&gt;/g')</pre>"
}

html_alert() {
    local level="$1"  # warn / critical
    local msg="$2"
    if [[ "$level" == "critical" ]]; then
        echo "<div class=\"critical\">🔴 $msg</div>"
    else
        echo "<div class=\"alert\">⚠️ $msg</div>"
    fi
}

html_table_row() {
    echo "<tr>"
    for cell in "$@"; do
        echo "<td>$cell</td>"
    done
    echo "</tr>"
}
