#!/bin/bash
# ============================================================
# 报告生成库 — HTML 报告、系统健康评分
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
    if float_cmp "$cpu_usage" ">" "${CPU_THRESHOLD:-80}"; then
        score=$((score - ($(printf "%.0f" "$cpu_usage") - ${CPU_THRESHOLD:-80}) * 2))
    fi

    # 内存: 每超过阈值 1% 扣 1.5 分
    if float_cmp "$mem_usage" ">" "${MEM_THRESHOLD:-80}"; then
        score=$((score - ($(printf "%.0f" "$mem_usage") - ${MEM_THRESHOLD:-80}) * 3 / 2))
    fi

    # 磁盘: 每超过阈值 1% 扣 2 分
    if float_cmp "$disk_usage" ">" "${DISK_THRESHOLD:-90}"; then
        score=$((score - ($(printf "%.0f" "$disk_usage") - ${DISK_THRESHOLD:-90}) * 2))
    fi

    [[ $score -lt 0 ]] && score=0
    [[ $score -gt 100 ]] && score=100
    echo "$score"
}

health_level() {
    local score="$1"
    if [[ $score -ge 80 ]]; then echo "优秀"
    elif [[ $score -ge 60 ]]; then echo "良好"
    elif [[ $score -ge 40 ]]; then echo "一般"
    else echo "警告"
    fi
}

# ============================================================
# HTML 报告生成
# ============================================================

gen_html_report() {
    local output_file="$1"
    shift
    local sections=("$@")

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local hostname=$(hostname)
    local kernel_ver=$(uname -r)

    # 采集系统快照用于评分
    local cpu_val=$(awk '{u=$2+$4; t=$2+$4+$5; if(t>0) printf "%.1f", u*100/t; else print 0}' /proc/stat)
    local mem_val=$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf "%.1f", (t-a)*100/t}' /proc/meminfo)
    local disk_val=$(df / --output=pcent 2>/dev/null | tail -1 | tr -d ' %')
    disk_val="${disk_val:-0}"
    local health_score=$(calc_health_score "$cpu_val" "$mem_val" "$disk_val")
    local health_lvl=$(health_level "$health_score")

    local score_class
    [[ $health_score -ge 80 ]] && score_class="good" || { [[ $health_score -ge 60 ]] && score_class="warn" || score_class="bad"; }

    cat > "$output_file" << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Linux 系统运维报告 - $timestamp</title>
<style>
  body { font-family: 'Microsoft YaHei', sans-serif; font-size: 14px;
         background: #f0f2f5; color: #333; line-height: 1.8; padding: 20px; }
  .container { max-width: 900px; margin: 0 auto; }
  .header { background: #1a1a2e; color: #fff; padding: 30px;
            border-radius: 12px; margin-bottom: 20px; }
  .header h1 { font-size: 24px; margin-bottom: 8px; }
  .health-card { background: #fff; padding: 20px; border-radius: 12px;
                 margin-bottom: 20px; text-align: center; }
  .health-score { font-size: 48px; font-weight: bold; }
  .score-good { color: #27ae60; } .score-warn { color: #f39c12; } .score-bad { color: #e74c3c; }
  .section-card { background: #fff; padding: 24px; border-radius: 12px;
                  margin-bottom: 16px; }
  .section-card h2 { font-size: 18px; color: #2c3e50; border-bottom: 2px solid #3498db;
                     padding-bottom: 8px; margin-bottom: 16px; }
  pre { background: #2d3436; color: #dfe6e9; padding: 16px; border-radius: 8px;
        font-family: 'Consolas', monospace; font-size: 13px; overflow-x: auto; white-space: pre-wrap; }
  .critical { background: #fab1a0; border-left: 4px solid #e74c3c; padding: 8px 12px;
              margin: 8px 0; border-radius: 0 6px 6px 0; }
  .alert { background: #ffeaa7; border-left: 4px solid #fdcb6e; padding: 8px 12px;
           margin: 8px 0; border-radius: 0 6px 6px 0; }
  table { width: 100%; border-collapse: collapse; margin: 10px 0; }
  th { background: #3498db; color: #fff; padding: 10px; text-align: left; font-size: 13px; }
  td { padding: 8px 10px; border-bottom: 1px solid #eee; font-size: 13px; }
  .footer { text-align: center; color: #999; font-size: 12px; margin-top: 30px; padding: 16px; }
</style>
</head>
<body>
<div class="container">

<div class="header">
  <h1>Linux 系统运维巡检报告</h1>
  <p>生成时间: $timestamp | 主机名: $hostname | 内核: $kernel_ver</p>
</div>

<div class="health-card">
  <div class="health-score score-$score_class">$health_score</div>
  <p>系统健康评分 — <strong>$health_lvl</strong></p>
  <p style="font-size:12px;color:#999;">CPU: ${cpu_val}% | 内存: ${mem_val}% | 磁盘: ${disk_val}%</p>
</div>

EOF

    # 插入各模块 HTML 片段
    for section in "${sections[@]}"; do
        echo "$section" >> "$output_file"
    done

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
# HTML → PDF 转换
# ============================================================

html_to_pdf() {
    local html_file="$1"
    local pdf_file="${html_file%.html}.pdf"

    if ! command -v pandoc &>/dev/null; then
        log_warn "pandoc 未安装，跳过 PDF 生成"
        return 1
    fi

    pandoc "$html_file" -o "$pdf_file" 2>/dev/null || {
        log_warn "PDF 生成失败"
        return 1
    }

    if [[ -f "$pdf_file" ]]; then
        log_info "PDF 报告已生成: $pdf_file"
        echo "$pdf_file"
        return 0
    fi
    return 1
}

# ============================================================
# HTML 片段构建器
# ============================================================

html_section_start() {
    echo "<div class=\"section-card\"><h2>$1</h2>"
}

html_section_end() {
    echo "</div>"
}
