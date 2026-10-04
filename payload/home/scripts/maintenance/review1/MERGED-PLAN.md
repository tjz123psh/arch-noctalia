# 合并修复计划（review/ × review1/ 去重后）

- 生成时间：2026-09-10　基线：git HEAD `10a0cdb`（工作区仅新增 review/、review1/）
- 备份：`/home/pang/backups/maintenance-2026-09-10/`（`maintenance-2026-09-10.tar.zst` 736K / `maintenance-2026-09-10.bundle` 232K 全历史 / MANIFEST.txt / SHA256SUMS，均已校验通过）
- 回归基线（隔离副本 /tmp/maintenance-baseline 实跑）：**45 ok / not ok 46 / EXIT=1**；第 46 条是环境依赖（本机 /root 带 ACL 使 greeter 组可穿越，测试 fixture 前提失效），非产品缺陷。每批修复后必须复跑并保持 ≥45 ok。
- 写者规则：同一时刻一个文件只有一个写者；每批结束由 Lead 跑 `bash -n` + `shellcheck -x -S warning` + `tests/run` + 端到端验证。

## 批次 A：P1（数据/安全）

| # | 文件 | 问题 | 修复要点 | 状态 |
|---|---|---|---|---|
| A1 | `clean` | 深度清理保留逻辑 **fail-open**（批次扫描 `|| true` → keep_batch 为空 → 全删）且不校验批次"每配置都有" | 扫描失败即报错中止；保留批次必须覆盖全部配置，否则不删任何维护批次快照；`snapper delete` 批量传 ID 并校验结果 | ✅ 已完成 |
| A2 | `checkallupdates` | 刷新假健康：`mktemp` 失败不检查、状态先写 ok 后 `mv`、`mv` 失败被吞、失败仍 touch 时间戳、失败来源用空文件覆盖上次好数据、孤儿回收可能删并发临时文件 | 见 A2 细则 | ✅ 已完成 |
| A3 | `mirror-update` | 无 `^Server = ` 行时回滚用历史旧备份覆盖当前 mirrorlist（当前文件从未备份） | 先备份当前文件再允许回滚；放宽 Server/Include 识别 | ✅ 已完成 |
| A4 | `terminal-tools` | 软链 config.fish 被换成 0777 常规文件；`$?` 取在 `!` 之后恒 0；无 `~/.gitconfig` 时 `--enable` 恒失败 | 见 A4 细则 | ✅ 已完成 |

### A2 细则（checkallupdates）
1. 每个 `mktemp` 失败必须检出并计入失败（不静默继续）。
2. 来源状态改为"数据 `mv` 成功后"再写 ok；`mv`/`cat` 失败 → 该来源 error。
3. 刷新失败（任一来源失败或落盘失败）→ 非 0 退出、不 `touch CACHE_STAMP`、不把旧缓存标注为最新。
4. 查询失败的来源不得用空文件覆盖它上一次成功列表（保留上次好数据并标注 stale）。
5. 孤儿回收加存活判断（或只在持锁成功后回收），避免删掉并发刷新的临时文件。
6. 锁等待超时（`UPDATE_LOCK_WAIT`）后不得无视锁继续刷新：要么报错退出，要么明确告知用户。
7. 中断时已完成的来源同时落盘数据与 `last-refresh-<source>`。
8. fzf reload 子进程不得删除继承来的 pending 标记。

### A4 细则（terminal-tools）
1. 软链：`[[ -L ]]` → `readlink -f` 落到真实目标，临时文件建在同目录，权限用 `stat -Lc` 取，软链保留、权限绝不为 0777。
2. `$?`：先捕获真实退出码再判断（5 = 键原本不存在）。
3. 无全局 gitconfig（rc=128）视为空状态继续；真正的不可读仍报错。
4. 临时文件登记清理；`--disable` 不能新建空 config.fish；状态文件只在全部恢复成功后删除。

## 批次 B：P2 正确性/契约

| # | 文件 | 问题 | 状态 |
|---|---|---|---|
| B1 | `sysup` | `TERM` 未设置/dumb 时 `clear` + `set -e` 让 `--yes` 路径直接失败；env 覆盖绕过校验（`$(( ))` 可执行命令） | ✅ 已完成 |
| B2 | 检查类脚本 | 退出码契约统一：0=健康 / 1=发现问题或无法检查 / 2=用法或非交互 / 127=缺命令（`gpu-check`、`storage-health`、`hw-doctor`、`boot-check`、`pacnew-check`、`log-check`、`recommend-check`、`check-battery`、`btrfs-scrub`） | ✅ 已完成 |
| B3 | 检查类脚本 + `lib/ui.sh` | "查询失败"必须独立于"缺失"：`ui_panel_stat err` 独立计数（`UI_N_ERR`）；`gpu-check` lspci 失败不得断言"无 N 卡"；`post-update-check` 非 TTY 降权必须可见；`storage-health` `findmnt` rc=1 语义 | ✅ 已完成 |
| B4 | `storage-health` / `btrfs-scrub` / `offsite-backup-schedule` | 含空格挂载点（`df` 截断、`findmnt -r` 的 `\x20` → 反转义）、unit 未转义 `$`（`$$` + systemd-analyze verify） | ✅ 已完成 |
| B5 | `term-menu` / `log-check` | `term-menu` 保留真实 fzf 退出码（130/1 取消、≥2 报错退出）、叶子子工具运行中 Ctrl+C 只打断本次操作并回父菜单；`log-check` 默认不写文件、`--save` 生成报告 | ✅ 已完成 |
| B6 | `lib/ui.sh` / `lib/config.sh` | `ui_confirm` EOF 视为未确认；`ui_*` 格式串安全（含裸 `%` 不再截断/中止）；locale 无关宽度（C/POSIX 下同样 7 列）；锁按操作者 uid + chmod/chown 防 EACCES(73)；`declare -gA` 修复函数内 source 的缓存失效 | ✅ 已完成 |
| B7 | `backup-restore` / `offsite-backup` | `--apply-home` 恢复 `$HOME` mode/mtime；`du/df` 失败明确报错；`du` 与 `tar` 排除规则一致；同盘检查纳入 HOME 所在盘；轮换保护 `latest` | ✅ 已完成 |

## 批次 C：P2 性能（读取/刷新慢）

| # | 文件 | 问题 | 状态 |
|---|---|---|---|
| C1 | `term-menu` | 快照列表去 fork（`_tm_pad_into`/`_tm_fit_into`，实测 **300 行 6370ms → 316ms**；1000 行 21995ms → 657ms）；`warn_batch_pairs` 每配置只查一次（61 → 4 次 snapper）；快照查询仍串行（2 次查询仅 14–32ms，收益不足未做） | ✅ 已完成 |
| C2 | `backup-restore` / `migration-pack` | 同一归档只列一次清单后复用（offsite 集合 tar 全量读 4→2 次、v2 迁移包 6→3 次；migration-pack v2 `--verify` tar 读 7→1、v1 10→1） | ✅ 已完成 |
| C3 | `lib/ui.sh` / `hw-doctor` / `storage-health` / `log-check` | `ui_cols` 进程内缓存（5 次卡片渲染 1 次 tput）、`ui_status_line` execve 13→3、hw-doctor 子进程 86→55、storage-health jq 26→4、log-check 去掉重复 `systemctl --failed` | ✅ 已完成 |
| C4 | `clean` / `cache-clean` | 逐条 `snapper delete` → 按配置批量（20 个 ID 从 20 次调用降到 1 次/配置）；`cache-clean` 死代码标注保留 | ✅ 已完成 |

## 批次 D：P3 工程/文档

| # | 内容 | 状态 |
|---|---|---|
| D1 | `tests/run`：PTY 用例隔离 HOME（不再污染真实 `$HOME`）、`test_syntax` 排除 `review*/`、新增 `TESTS_FILTER` 正则过滤；`log-check` 顶层 trap 收进 `BASH_SOURCE == $0` 守卫（夹具泄漏已修）；`post-update-check` 的 GRUB 不可读夹具改为自建 000 目录，不再依赖 `/root` 权限 → 套件由 45/46 变为 **46/46** | ✅ 已完成 |
| D2 | 临时文件全登记（mirror-update/terminal-tools）、sudo 保活自终止（父进程消失/凭据过期即退出）、`migration-pack` 崩溃窗口回收隐藏包目录、`cache-clean` 死代码标注 | ✅ 已完成 |
| D3 | README 契约同步（统一退出码 0/1/2/127、"无法检查≠健康"、非交互需 `--yes`、锁按操作者、刷新失败语义、`log-check --save`、`TESTS_FILTER`）| ✅ 已完成 |
| D4 | helper 去重（`usage`×11、`main`×10、`have`×8、`panel`×5）收敛到 `lib/` | ⏸ 有意不做（低优先、改动面大、当前副本语义一致；已在报告中说明） |

## 验收门（每批）
1. `bash -n` 全部脚本通过；`shellcheck -x -S warning` 零告警。
2. `tests/run` 复跑：≥45 ok，且除第 46 条（环境依赖）外无新增失败。
3. 每条修复必须有可复现的沙箱验证（含修复前失败/修复后通过的对照）。
4. 不修改与该项无关的行；每批结束记录 diff 摘要与验证输出。
---

## 进度记录（2026-09-10）

### 批次 A 已全部完成并通过回归

| 项 | 改动文件 | 关键改动 | 验证 |
|---|---|---|---|
| A1 clean | `clean` | 批次扫描失败不再静默（fail-open → 中止且不删任何快照）；"最近一套批次"改为**每个配置都存在的成套批次**，无成套时保守保留全部维护批次；`snapper delete` 改为按配置批量传 ID（N+1 → 1 次/配置），批量失败逐条重试并保留错误输出 | `review1/evidence/clean-sandbox.sh` 四场景（ok / partial / allpartial / fail）全 PASS；`tests/run` 第 47 项 clean CSV 用例通过 |
| A2 checkallupdates | `checkallupdates` | ① 10 个 `mktemp` 全部检查，失败即中止且不动缓存；② 先落盘数据、成功后才写 `ok`；③ 查询失败**不再用空文件覆盖上次成功列表**；④ 时间戳由子进程在落盘成功后立即打（中断不丢新鲜度）；⑤ 状态文件写失败按刷新失败处理；⑥ 锁等待超时改为**放弃并明确提示**（不再无视锁并发刷新）；⑦ 孤儿回收移到持锁之后；⑧ fzf 子进程不再误删父进程 pending 标记 | `review1/evidence/checkallupdates-sandbox.sh` 三场景全 PASS（失败不覆盖旧列表/目录不可写非 0 退出/持锁超时取消） |
| A3 mirror-update | `mirror-update` | 只要当前 mirrorlist 非空就先备份现状并作为回滚源，**不再把 BACKUP_PATH 指向历史旧备份**；可用源判断放宽到 `Server`/`Include` 合法语法；mktemp 纳入 `ui_tmp_cleanup`；`MIRROR_THREADS` 越界不再静默回落 | 子代理 28 项沙箱断言全 PASS，并用 HEAD 版复现了"被 2020 旧备份覆盖" |
| A4 terminal-tools | `terminal-tools` | 软链 → 改写真实目标（`readlink -f` + 同目录原子 mv + `stat -Lc` 权限），不再产生 0777 常规文件；`--disable` 的 `$?` 取反缺陷修正（可自愈）；无全局 gitconfig 视为空状态；临时文件登记；无文件时 `--disable` 不建空文件 | 子代理 65 项断言全 PASS，并用 HEAD 版复现了 0777 替换、状态残留、`--enable` 恒失败 |
| B1 sysup | `sysup` | `clear` 改为仅 TTY 且失败不致命（修复 `--yes` 在 TERM=dumb/非 TTY 下直接失败）；三个数值配置在进入 `$(( ))` 前强制校验 | `TERM` 未设置/dumb 下脚本可继续；全库 lint 通过 |
| B6a lib/config.sh | `lib/config.sh` | 环境变量覆盖现在同样走 `maintenance_config_validate`，非法值回落默认并明确报错（根因：旧实现绕过校验，非法值可在 `sysup` 的 `$(( ))` 里展开成命令） | 复现测试：`SYSUP_MIRROR_MAX_AGE_DAYS='a[$(touch /tmp/x)]'` 注入**不再执行**；合法覆盖 7 仍生效；非法值回落 30 |

### 回归基线对比

| 运行 | 结果 |
|---|---|
| 改动前（/tmp/maintenance-baseline） | 45 ok / `not ok 46` / EXIT=1 |
| 批次 A 后（/tmp/maintenance-check2） | **45 ok / `not ok 46` / EXIT=1**（无新增失败；第 46 项仍是 /root ACL 环境依赖） |
| 全库 lint | 24 个文件 `shellcheck -x -S warning` **零告警**；`bash -n` 全部通过 |

### 变更清单（本批共 6 文件，+348/−112）
`clean` · `checkallupdates` · `mirror-update` · `terminal-tools` · `sysup` · `lib/config.sh`（均有备份：`/home/pang/backups/maintenance-2026-09-10/`）
---

## ✅ 完成总结（2026-09-10）

| 指标 | 结果 |
|---|---|
| 改动文件 | **26 个**（25 个脚本/库 + `tests/run`），`+1843 / −647` |
| 静态检查 | 25 个文件 `shellcheck -x -S warning` **零告警**；`bash -n` 全部通过（含 `tests/run`） |
| 测试套件 | 基线 **45 ok / not ok 46 / EXIT=1** → 现在 **59 ok / 0 失败 / EXIT=0**（`1..59`） |
| 备份 | `/home/pang/backups/maintenance-2026-09-10/`（tar.zst + git bundle，SHA256 已校验） |
| `review/` 隔离 | 全程未读未改，mtime 与会话开始时一致，0 处修改 |

### 关键收益（实测）

- **term-menu 快照列表**：300 行 6370ms → **316ms**；1000 行 21995ms → 657ms；`warn_batch_pairs` snapper 调用 61 → 4 次。
- **失败不再被说成成功**：`checkallupdates --refresh` 缓存不可写 → 非 0 退出且保留旧列表（旧实现 exit 0 并显示旧数据）；失败来源不再被空文件覆盖。
- **clean 深度清理**：批次扫描失败不再静默全删；保留集改为"每个配置都有的成套批次"；`snapper delete` 批量调用。
- **mirror-update**：回滚不再用历史旧备份覆盖当前 mirrorlist（先备份现状）。
- **terminal-tools**：软链 config.fish 不再被换成 0777 常规文件；`--disable` 可自愈；无 `~/.gitconfig` 时 `--enable` 可用。
- **安全**：环境变量覆盖不再绕过校验（`SYSUP_*` 注入不再执行命令）；锁按操作者 uid 且纠正权限；`ui_*` 含裸 `%` 不再截断/中止脚本。
- **一致性**：检查脚本统一 0/1/2/127（"无法检查≠健康"）；非交互高风险操作返回 2；含空格挂载点可用；unit 里的 `$` 正确转义。
- **性能**：`ui_status_line` execve 13→3；hw-doctor 子进程 86→55；storage-health jq 26→4；归档只列一次清单（offsite tar 全读 4→2、v1 10→1）。

### 有意不做 / 已知残留

- helper 去重（`usage`×11、`main`×10 等）：语义目前一致，改动面大、收益低，留作后续重构。
- `show_snapshots` 各配置的 snapper 查询仍串行（夹具中 2 次查询仅 14–32ms，收益不足）。
- `offsite-backup` 仍只比对磁盘、未校验"目标当前确实是挂载点"；`btrfs-scrub` 的 scrub 历史读取在无 sudo 时会报"查询失败"（契约要求的行为）。
- `$HOME` 里 7 个历史 `log-check-*.md`（旧默认行为 + 未隔离 HOME 的测试留下）未删除，可自行 `rm ~/log-check-*.md`。