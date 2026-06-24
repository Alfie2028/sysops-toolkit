# Linux 系统运维工具箱 — 操作系统课程设计

## 项目简介

本项目是《操作系统》课程设计的实现，基于 Linux Shell 脚本开发一个功能完整的 **系统监控与自动化运维工具包**。

## 模块架构

```
sysops-toolkit/
├── sysops.sh              # 主入口（模块五：主控调度中心）
├── lib/
│   ├── common.sh           # 公共函数库
│   ├── ui.sh               # UI 封装（dialog/whiptail）
│   └── report.sh           # 报告生成（HTML/文本）
├── modules/
│   ├── monitor.sh          # 模块一：系统性能监控仪
│   ├── tracker.sh          # 模块二：用户活动追踪器
│   ├── scanner.sh          # 模块三：文件系统扫描仪
│   └── analyzer.sh         # 模块四：日志分析引擎
├── etc/
│   └── config.conf         # 全局配置文件
├── reports/                # 报告输出
├── logs/                   # 运行日志
└── docs/                   # 设计文档
```

## 快速开始

### 环境要求
- **WSL2** / Ubuntu 22.04+ 或 CentOS Stream 8/9
- 必要工具: `whiptail`, `shellcheck`(推荐), `git`, `pandoc`(可选)

### 安装依赖
```bash
sudo apt update && sudo apt install -y whiptail shellcheck git pandoc
```

### 使用方式
```bash
# 交互式主菜单
./sysops.sh

# 一键自动巡检
./sysops.sh --auto

# 巡检 + 生成 HTML 报告
./sysops.sh --auto --html

# 运行单个模块
./sysops.sh --module 1    # 系统性能监控仪
./sysops.sh --module 2    # 用户活动追踪器
./sysops.sh --module 3    # 文件系统扫描仪
./sysops.sh --module 4    # 日志分析引擎

# 守护进程模式
./sysops.sh --daemon

# 定时任务
./sysops.sh --cron-setup 5   # 每 5 分钟自动巡检

# 帮助
./sysops.sh --help
```

## 技术要点

| 模块 | 关键技术 |
|------|---------|
| 模块一 | `/proc` 文件系统解析、`awk` 数值计算、`sleep` 循环控制 |
| 模块二 | `who`/`last` 命令、正则表达式 `grep`/`sed`、日志解析 |
| 模块三 | `find` 高级用法、`df`/`du` 磁盘分析、文件权限八进制 |
| 模块四 | `tail -f` 实时监控、管道通信、`tar` 归档压缩、`trap` 信号捕获 |
| 模块五 | `dialog`/`whiptail` 图形化、`crontab` 调度、守护进程、HTML 报告 |

## 代码质量
```bash
# 运行 ShellCheck 检查
shellcheck sysops.sh lib/*.sh modules/*.sh
```
