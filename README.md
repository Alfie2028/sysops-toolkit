# Linux 系统运维工具箱 — 用户使用手册

## 一、环境要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Ubuntu 22.04 LTS Server（推荐）或 CentOS Stream 8/9 |
| 运行环境 | VMware / VirtualBox 虚拟机，桥接网络 |
| Shell | Bash 4.0+ |
| 必要命令 | `ps` `df` `du` `find` `awk` `grep` `tar` `who` `last`（系统自带） |

### 安装可选增强

```bash
sudo apt update
sudo apt install -y dialog pandoc cron
```

| 包 | 作用 | 缺失时 |
|----|------|--------|
| `dialog` | 图形化菜单界面 | 自动降级为纯文本菜单 |
| `pandoc` | HTML 转 PDF 报告 | 只生成 HTML，不生成 PDF |
| `cron` | 定时任务 | `--cron-setup` 不可用 |

### 日志权限

模块二需要读取 `/var/log/auth.log`（登录日志），确保当前用户在 `adm` 组：

```bash
groups | grep adm || sudo usermod -a -G adm $USER
# 如果执行了 usermod，需要退出重新登录
```

---

## 二、部署

```bash
# 1. 克隆或复制项目到虚拟机任意目录
cd ~ && git clone <仓库地址> sysops-toolkit
cd sysops-toolkit

# 2. 加执行权限
chmod +x sysops.sh
```

---

## 三、运行方式

### 3.1 交互式主菜单（推荐）

```bash
./sysops.sh
```

进入后可选择：

```
  1) 📊 系统性能监控仪  — CPU/内存/进程
  2) 👤 用户活动追踪器  — 登录/审计/安全
  3) 💾 文件系统扫描仪  — 磁盘/大文件/权限
  4) 📋 日志分析引擎    — 追踪/归类/归档
  5) 🔍 一键全面巡检    — 运行所有模块
  6) 📄 生成巡检报告    — HTML 格式
  7) ⏰ 配置定时任务    — crontab 自动巡检
  8) 👻 守护进程模式    — 后台持续监控
  9) 🛑 停止守护进程
  0) 退出
```

### 3.2 命令行模式

| 命令 | 作用 |
|------|------|
| `./sysops.sh --auto` | 一键巡检，终端文本输出 |
| `./sysops.sh --auto --html` | 巡检 + 生成 HTML 报告 |
| `./sysops.sh --module 1` | 仅运行模块一（1-4 可选） |
| `./sysops.sh --report` | 单独生成最新的 HTML 报告 |
| `./sysops.sh --daemon` | 启动后台守护进程（默认每 5 分钟巡检） |
| `./sysops.sh --daemon-stop` | 停止守护进程 |
| `./sysops.sh --cron-setup` | 配置 crontab 定时巡检 |
| `./sysops.sh --cron-remove` | 移除 crontab 定时任务 |
| `./sysops.sh --help` | 显示帮助 |

---

## 四、各模块功能说明

### 模块一：系统性能监控仪

**功能**：实时监控 CPU、内存、进程资源。

**输出内容**：
- CPU 整体使用率 + 各核心使用率
- 1/5/15 分钟平均负载
- 物理内存 + Swap 使用量及百分比
- 超过阈值时（CPU > 80%、内存 > 80%）红色告警
- CPU/内存消耗 Top 5 进程
- 可选：ASCII 负载趋势图（需 10 秒采集）

**数据来源**：`/proc/stat` `/proc/meminfo` `/proc/loadavg` `/proc/cpuinfo` `ps aux`

---

### 模块二：用户活动追踪器

**功能**：审计系统用户登录活动与权限操作。

**输出内容**：
- 当前在线用户及登录会话详情（用户、终端、登录时间、来源 IP）
- 最近 20 条历史登录记录
- 登录失败次数统计（失败来源 IP 排行）
- 暴力破解检测（时间窗口内失败次数超过阈值则告警）
- sudo 操作审计（最近 20 条 sudo 命令执行记录）
- sudoers 特权用户列表

**数据来源**：`/var/run/utmp` `/var/log/wtmp` `/var/log/auth.log` `/etc/sudoers`

---

### 模块三：文件系统扫描仪

**功能**：磁盘空间管理、大文件查找、安全权限审计。

**输出内容**：
- 所有挂载点磁盘使用情况（容量、已用、可用、使用率）
- 超过阈值（默认 90%）红色告警
- 目录空间占用分析（`du -sh` 递归，深度 2，Top 15）
- 磁盘配额对比
- 大文件扫描（> 100M，排除 /proc /sys /dev）
- 旧文件扫描（> 30 天未修改）+ 交互式删除确认
- 安全审计：World-Writable 文件、SUID/SGID 异常文件

**数据来源**：`df` `du` `find` `stat` `/etc` `/bin` `/sbin`

---

### 模块四：日志分析引擎

**功能**：系统日志的统计分析、实时追踪、归档管理。

**输出内容**：
- 按错误级别（ERROR/WARN/INFO/DEBUG）分类统计
- 日志来源主机名、涉及服务名提取
- 可选：实时日志追踪（`tail -f` + 关键字高亮，Ctrl+C 停止）
- 可选：日志归档压缩（打包超过 7 天的 `.log` 为 `.tar.gz`）

**数据来源**：`/var/log/syslog`

---

### 模块五：主控与调度中心

**功能**：统一入口、自动化调度、报告生成。

**一键巡检**（选项 5 或 `--auto`）：依次运行模块一~四，最后给出系统健康评分（0-100 分）。

**系统健康评分**：
- 初始 100 分
- CPU 超过阈值每 1% 扣 2 分
- 内存超过阈值每 1% 扣 1.5 分
- 磁盘超过阈值每 1% 扣 2 分

| 分数 | 等级 |
|------|------|
| ≥ 80 | 优秀 |
| 60-79 | 良好 |
| 40-59 | 一般 |
| < 40 | 警告 |

**报告生成**（选项 6 或 `--auto --html`）：生成 HTML 格式巡检报告，保存至 `reports/` 目录。若已安装 pandoc，自动附带 PDF 版本。

**守护进程**（选项 8 或 `--daemon`）：后台定时巡检，日志写入 `logs/daemon_YYYYMMDD.log`。

**crontab 定时任务**（选项 7 或 `--cron-setup`）：写入系统 crontab，按指定周期自动巡检。

---

## 五、典型使用场景

### 场景一：日常巡检

```bash
./sysops.sh --auto
```

1 分钟内跑完四个模块，输出系统健康评分，适合每日手动检查。

### 场景二：生成巡检报告

```bash
./sysops.sh --auto --html
```

跑完巡检后自动生成 HTML 报告，保存在 `reports/sysops_report_时间戳.html`。

### 场景三：后台持续监控

```bash
./sysops.sh --daemon        # 启动守护进程（每 5 分钟巡检）
./sysops.sh --daemon-stop   # 停止
```

守护进程日志：`logs/daemon_YYYYMMDD.log`

### 场景四：定时自动巡检

```bash
./sysops.sh --cron-setup    # 配置 crontab（默认每 5 分钟）
./sysops.sh --cron-remove   # 移除
```

### 场景五：单项深度检查

```bash
./sysops.sh --module 2      # 只看用户活动追踪
./sysops.sh --module 3      # 只看文件系统扫描
```

---

## 六、配置修改

编辑 `etc/config.conf` 可调整告警阈值和扫描参数：

```bash
CPU_THRESHOLD=80           # CPU 告警阈值 (%)
MEM_THRESHOLD=80           # 内存告警阈值 (%)
DISK_THRESHOLD=90          # 磁盘告警阈值 (%)
LARGE_FILE_SIZE="+100M"    # 大文件阈值
OLD_FILE_MTIME="+30"       # 旧文件阈值（天）
LOG_RETENTION_DAYS=7       # 日志保留天数
BRUTE_FORCE_WINDOW=300     # 暴力破解检测窗口（秒）
BRUTE_FORCE_THRESHOLD=5    # 暴力破解告警阈值（次）
DAEMON_INTERVAL=300        # 守护进程巡检间隔（秒）
```

修改后无需重启，下次运行自动生效。

---

## 七、目录结构

```
sysops-toolkit/
├── sysops.sh              # 主入口
├── lib/
│   ├── common.sh          # 公共函数库
│   ├── ui.sh              # UI 封装（dialog/whiptail）
│   └── report.sh          # 报告生成（HTML/PDF + 健康评分）
├── modules/
│   ├── monitor.sh         # 模块一：系统性能监控仪
│   ├── tracker.sh         # 模块二：用户活动追踪器
│   ├── scanner.sh         # 模块三：文件系统扫描仪
│   └── analyzer.sh        # 模块四：日志分析引擎
├── etc/
│   └── config.conf        # 全局配置文件
├── logs/                  # 运行日志（自动创建）
├── reports/               # 巡检报告（自动创建）
└── USER_GUIDE.md          # 本手册
```
