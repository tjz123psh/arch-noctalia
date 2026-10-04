# 维护脚本项目全面审查报告（只读审查 · 未修改任何文件）

- 项目：`/home/pang/scripts/maintenance`（Arch Linux / Btrfs / Snapper / systemd 的 Bash 维护脚本集，23 个可执行脚本 + lib 2 个库 + tests/run 测试套件，约 12.2k 行）
- 审查基线与环境：git HEAD `10a0cdb`（工作区干净），bash 5.3.15，shellcheck 0.11.0，Arch + Btrfs，非 root
- 方法：4 路并行只读深度审查 + 1 路对抗性复核；所有实测在 /tmp 沙箱用命令桩/合成夹具完成
- **隔离声明**：全程未读取、未列举、未修改 `review/`；收工复核 `review/` 目录 mtime 仍为 `2026-09-10 19:45:31`、大小 180（与开工一致）；`git status` 只有原有的 `?? review/`，无任何新增/修改文件
- 详细证据（每条含行号、触发命令、原始输出、修法建议）：`/tmp/maintenance-review/{ui-checks,core-lib,update-chain,data-safety,verify}.md`

---

## 1. 结论速览

| 维度 | 结果 |
|---|---|
| P0（直接毁数据/毁系统） | **0 条**（4 份报告独立确认无默认即破坏的路径） |
| P1（严重） | 原 8 条 → 对抗性复核后 **4 组**（3 条降级为 P2） |
| P2 | 35 条 + 降级 3 条 = 38 条 |
| P3 | 45 条 |
| 合计 | **88 条发现**（已确认 79 / 高度可疑 9；复核 12 条关键结论：CONFIRMED 12、REFUTED 0） |
| 静态检查 | 24 个脚本 shellcheck 0 告警、`bash -n` 全通过 → 问题都在语义/契约/性能层，不在语法层 |
| 总体判断 | 工程质量高于同类脚本：并行刷新、超时、锁继承、trap 清理、strict 契约基本都是真的；但**失败路径**（刷新失败、查询失败、非交互、中断、软链/空格路径）与**"每秒一次的 UI 渲染"**是主要问题集中区 |

主要文件热点：term-menu 9、lib/ui.sh 16、checkallupdates 9、terminal-tools 6、clean 3、storage-health 3、log-check 3、mirror-update 4、sysup 3、tests/run 4。

---

## 2. P1（严重，建议第一批修）

### P1-1 · terminal-tools：软链 Fish 配置被替换成 0777 常规文件
- 位置：`terminal-tools:87-90`（`stat -c '%a'`）、`:129-130`（`chmod`+`mv -f`）
- 触发：用 dotfiles 管理 `~/.config/fish/config.fish`（符号链接）后执行 `terminal-tools --enable`（`--disable` 同样会重写）
- 证据（沙箱端到端复核）：软链被替换为 `-rwxrwxrwx` 常规文件；dotfiles 目标文件不再接收改动。GNU stat 不加 `-L` 取的是 lstat，软链权限恒 777；`mv -f` 换掉的是链接本身
- 影响：dotfiles 工作流被静默破坏；**world-writable 的 Fish 启动配置 = 本地提权面**（Fish 会执行该文件）
- 修法：`[[ -L "$FISH_CONFIG" ]]` 时拒绝或先 `readlink -f` 落到真实文件；权限用 `stat -Lc '%a'`；补软链回归测试
- 复核：CONFIRMED，维持 P1

### P1-2 · checkallupdates：整轮刷新彻底失败却返回 0，并把旧缓存当"刷新结果"（两条机制）
- 位置：`checkallupdates:415-427`（`mktemp` 失败不检查）、`:487-499`（失败判定只读合并状态文件）、`:266-279/459-499`（状态先写 ok 再 `mv` 数据，`mv` 失败被忽略）、`:712-720`（`|| refresh_status=$?` 让函数体内 errexit 失效）
- 触发：缓存目录不可写（ENOSPC、权限被改、只读挂载）
- 证据（独立复现）：`chmod 500` 缓存目录后 10 个 `mktemp` 全失败、桩调用 **0 次**，但 `--refresh` **exit 0** 并打印上一轮缓存；复核补充发现的更坏版本：**`CACHE_STAMP` 仍被 touch → 列表标签显示"刚刚更新"**。另一条：`mv` 失败时状态已是 ok、时间戳已刷新 → UI 显示"当前没有待更新项目"
- 影响：`sysup:406` 会把"刷新成功"当事实；自动化拿退出码判断也会误判；用户看到的是"没有更新"而不是"查询没跑"
- 修法：检查每个 `mktemp`；先落数据再写 ok 状态；`mv`/`cat` 失败置 `refresh_failed`；失败时返回非 0 且不 touch `CACHE_STAMP`、不把旧缓存标注为最新
- 复核：CONFIRMED（原报告 F-01/F-02），维持 P1

### P1-3 · mirror-update：无 `^Server = ` 行时，失败回滚会用历史旧备份覆盖当前 mirrorlist
- 位置：`mirror-update:352-372`（else 分支把 `BACKUP_PATH` 指向 `$BACKUP_DIR` 里最新的历史备份，且**当前文件从未被备份**）、`:112-121`（cleanup 里 `sudo cp "$BACKUP_PATH" "$MIRRORLIST"`）
- 触发：mirrorlist 只有 `Include = ...` 或写作 `Server=https://...`（pacman 语法有效，但 `grep '^Server = '` 匹配不到）→ 三次 reflector 全失败或 Ctrl+C → trap 把历史备份（实测 2020 年那份）覆盖到当前文件
- 证据：端到端复现（mirrorlist 与备份目录均指向 /tmp 夹具）确认覆盖发生、当前内容无任何副本；对照组的正常路径（有 Server 行）回滚正确
- 影响：用户当前（可能有效）的镜像配置被旧配置替换且不可恢复
- 修法：else 分支先 `cp` 当前文件到新备份再允许回滚；解析用宽松匹配（`^[[:space:]]*Server[[:space:]]*=`）并支持 `Include`；回滚前比对目标是否仍为"无效"
- 复核：CONFIRMED，维持 P1（触发面较窄，需三者同时成立，但后果是配置丢失）

### P1-4 · clean：深度清理"保留最近一套批次"不校验成套，可能删掉真正的回滚点
- 位置：`clean:427-478`（取全局最大 batch，无"root+home 成对"校验）；`:478-485` 逐条 `sudo snapper delete` 且丢弃 stderr
- 触发：存在一个更新的单配置批次（例如只对 root 跑 `quicksave`）或人为删掉半套 → 深度清理把真正成对的 rollback 点当"旧批次"删掉
- 证据：用 clean 真实逻辑 + snapper 桩复现：保留集选错，root 完整对被杀，只剩 home 单边，仍打印"清理完成"
- 影响：升级失败时失去成套回滚点（默认 quicksave 流程不触发，但"单配置 quicksave"是脚本自身提供的路径）
- 修法：复用 `quickload:565-622` 的成套判定（`maintenance_batch` 必须覆盖全部配置）；找不到成套批次就中止；`snapper delete` 批量传 ID 并检查实际结果
- 复核：CONFIRMED，维持 P1

### 原 P1 降级（复核结论）
| 原编号 | 位置 | 复核判定 |
|---|---|---|
| ui-checks P1-1 | terminal-tools:241-247（`if ! cmd; then rc=$?` 恒 0） | 降 P2：确认 bug（--disable 误报失败、半恢复、状态文件残留、重跑不自愈），但复核发现 core.pager/interactive.diffFilter **已正确恢复**，且"先 --enable 再 --disable"是脚本内可用的完整回退路径——原报告影响面描述过重 |
| ui-checks P1-2 | terminal-tools:149-154（无 `~/.gitconfig` 时 `--enable` 失败） | 降 P2：确认 100% 失败（git 返回 128），但失败干净、有中文报错、未写任何文件；属"新装机不可用"，非损坏 |
| update-chain F-06 | sysup:183（`TERM` 未设置/dumb 时 `clear` 让 `set -e` 终止） | 降 P2：确认 `clear` rc=1（Lead 亦独立验证），但失败安全、有可见报错；属"文档化的 --yes 路径不可用" |

---

## 3. 性能专项：读取/刷新慢（用户重点关注）

### 3.1 实测数字

| 场景 | 实测 | 根因 |
|---|---|---|
| term-menu 快照列表（300 行） | 短描述 **1.9–2.1s**；132 列长中文描述 **6.6–7.6s** | 每行 4 次 `$(ui_pad)` + 长描述逐字符 `$(ui_dwidth)`；clone 计数 2138→6638（+4500 ≈ 300 行 × 15 次） |
| `ui_dwidth` 调用成本 | 子 shell 0.69ms vs 同进程 0.035ms（20×） | 宽度 API 只能 `$(ui_dwidth)` 取值，memo 缓存被架空（lib/ui.sh:463-466） |
| backup-restore | 同一归档被**完整读取 9 次**（复验 6 + 清单 1 + 估算 1 + 解包 1）；101MB `tar -tf` 53ms → 25GB HOME 单次约 13s → `--check` ≈2.5min、恢复预览 ≈3min | 每次要一个字段就整体再读一遍 |
| migration-pack | 每个 include 各整包解压一次（`--check` 6 次）；v1 清单每行一次（9 次） | N+1 解压 |
| term-menu 批量删除确认 | 20 个 ID = **41 次 snapper 调用** | 每个 ID 重查所有配置 |
| clean 深度清理 | 每条快照 1 次 `sudo snapper delete` | N+1 进程 + 丢弃 stderr |
| hw-doctor 单次检查 | **86 个子进程**（17×tput、7×expand、11×systemctl） | tput 每张卡片取一次宽度 |
| storage-health | 2 块盘 15 次 jq（JSON 已整体拿到内存） | 按字段 fork jq |
| `ui_status_line` | 每次 8 个外部进程 | 每次开列表都跑 |
| 脚本启动 | 19 个脚本 `--help` 均 1.0–2.2ms | 启动无瓶颈，慢的都在渲染/IO |

### 3.2 已确认做得好的部分（别改坏）
- checkallupdates 三来源并行：**实测 3062ms（串行约 9000ms，约 3×）**；单来源超时生效且无孤儿；Ctrl+C/SIGHUP → exit 130/129，临时文件与子进程全清、已完成来源数据保留
- 缓存优先 + 后台刷新 + 陈旧数据原地替换的设计目标成立；`--refresh-stale` 只补查失败来源

### 3.3 优化方向（不动语义）
1. 宽度计算批量化：给 `ui_pad`/`ui_wrap` 提供"一次调用处理多行/整表"的接口（或把表格渲染交给一次 awk），把 300 行的 15 次/行 fork 压到 1–2 次
2. backup-restore / migration-pack：归档只读一次 → 生成 `tar -tv` 清单一遍，后续全部基于清单比对
3. term-menu `warn_batch_pairs`：一次 `snapper list-configs` + 一次按 batch 查询替代每 ID 重查
4. `snapper delete` 批量传 ID（上游支持多 ID，已核对）；`tput`/`ui_cols` 结果进程内缓存；jq 一次取多字段；systemctl 结果复用
5. checkallupdates 每轮 6 次 `find` 回收临时文件 → 一次 `find` + 存活判断（同时修 F-03 误删并发临时文件）

---

## 4. 边界与一致性缺陷（P2 汇总）

### 4.1 退出码契约
| 位置 | 问题 |
|---|---|
| hw-doctor:435 / boot-check:290 / pacnew-check:117 **vs** storage-health:264 / gpu-check:275 | "查询失败"两派语义相反：前者无 `--strict` 也返回 1，后者只 warn 返回 0 → 同一菜单里有的提示"无法检查"、有的静默（沙箱实测 5 组码） |
| pacnew-check:60-64 / log-check:163-168 | 缺 pacdiff/systemctl 返回 **1**，文档契约是 **127**；pacnew 还用 `exit` 跳过面板收尾 |
| quicksave:267,287 / clean:182,185 / cache-clean:161 | 非交互且无 `--yes` 时返回 **0**（应为 2）→ 自动化把"什么都没做"当成功；btrfs-scrub/offsite-backup-schedule/backup-restore 是正确的 2（三条均实测） |
| check-battery:48,55 | upower 查询失败在 `set -e` 下静默退出，rc 1/3 与"没有电池=1"无法区分 |

### 4.2 "查询失败" ≠ "没有/缺失"
- gpu-check:232-233：lspci 失败后仍断言"未检测到 NVIDIA 显卡，本节不适用"
- post-update-check:15-27,83-100：非 TTY 无 sudo 时静默降级为非特权 pacdiff，"看不到"与"未发现"混淆
- lib/ui.sh:619 + 636-639：`ui_panel_stat err` 计入 `UI_N_MISS`，汇总把"错误"并进"缺失"（5 个脚本受影响）
- boot-check/pacnew-check 的 `request_read_access`：非 TTY 直接跳过提权，报告里无"本次未检查"标记

### 4.3 路径/字符边界
- storage-health:176-181,205-213：含空格挂载点 `df` 解析被截断（`/run/media/x/My Passport` → `.../My`）；`findmnt -r` 的 `\x20` 转义路径原样传给 btrfs/systemd-escape → Btrfs 段整段误报失败（实测）
- btrfs-scrub:83-94：同样用空白拆分 `findmnt -r` 输出 → 含空格挂载点目标错乱、无法 scrub
- offsite-backup-schedule:90-96,316：生成的 unit 未转义 `$`，systemd 会展开变量 → 目标含 `$` 时定时备份静默跑空
- 核心库：`$HOME` 未设置时 `set -u` 直接 unbound；断链的配置软链被当作"没有配置"静默忽略

### 4.4 交互/终端环境
- term-menu:40-42：叶子子工具运行中按 Ctrl+C，父菜单 INT trap 直接 `exit 130` 关掉整个菜单，"子工具 130=返回父菜单"契约被抢跑（进程组 SIGINT 实测）
- sysup:183（降级 P2）：`TERM` 未设置/dumb 时 `clear` 失败 → `set -e` 终止，`--yes` 非交互路径 stdout 0 字节、exit 1（Lead 独立验证：`env -u TERM` 与 `TERM=dumb` 下 clear rc=1）
- mirror-update:31：`export LC_ALL=C` 后仍用卡片组件 → `ui_dwidth` 按字节计宽，中文标题宽度 13→20，顶边框比底边框短 7 列（Lead 独立实测 62 vs 55 个破折号）——任何 `LC_ALL=C`/`POSIX` 环境（cron、systemd、`ssh` 无 locale）都会错位
- log-check:170-172：**只读检查默认写 `$HOME/log-check-<ts>.md`**，每次一个新文件；HOME 不可写时裸报错（测试夹具也会污染真实 HOME，见 4.7）
- lib/ui.sh:197-207：`ui_info/ui_ok/ui_warn/ui_err/ui_miss` 把消息当 printf 格式串。Lead 实测：`ui_info "进度 100% 完成"` 在 `set -e` 下**截断输出并让整个脚本以 1 退出**（22 个调用方都是 `set -euo pipefail`）。当前仓库内消息串恰好不含裸 `%`（161 处都用了 `%s`/`%d`），属"随时会被动态文本引爆"的隐患
- lib/ui.sh:656-665：`ui_confirm` 把 EOF/读错误当"回车"——`</dev/null` 时默认 y 直接算同意（Lead 实测 `RESULT=YES(auto)`）；实际默认 y 的调用点：mirror-update:271、337（其余都用 `n`/`ui_confirm_word`，设计正确）
- lib/config.sh:101-109：环境变量覆盖**完全绕过校验**（空值也算已设置）。Lead 实测确认：`SYSUP_MIRROR_MAX_AGE_DAYS='a[$(touch /tmp/x)]'` 在 `sysup:226` 的 `$(( ))` 里**真的执行了命令**（需攻击者/用户能设置该环境变量，故 P2）；`abc` 则静默变阈值 0

### 4.5 锁与并发
- lib/ui.sh:217,230：锁文件名带 uid（`maintenance-<uid>.lock`）→ **以 root 直连运行（uid 0）与普通用户（uid 1000）用两把锁、可同时持锁**，README"共享同一把 flock"不成立（Lead 读码确认）
- checkallupdates:222-229：孤儿回收只按 `mtime>60min` 删除、无存活判断 → 会删掉正在运行的并发刷新的临时文件（与 P1-2 组合造成错误显示）
- checkallupdates:409-413：`flock -w UPDATE_LOCK_WAIT || true` 超时后无视锁继续刷新（实测来源查询翻倍）
- lib/ui.sh:161-188：`ui_tmp_register` 在子 shell/`$()`/管道里登记会丢，子 shell 的 `ui_tmp_cleanup` 被 BASHPID 守卫跳过（现有 3 个调用点都在主 shell，暂无真实泄漏）
- lib/ui.sh:118-137：sudo 保活无自终止，父进程被 SIGKILL 后孤儿 subshell 每 60s 继续 `sudo -n true`（实测调用数持续增长）

### 4.6 数据/持久化边界（P2 部分）
- checkallupdates:272-273,300-301,331-332：某来源查询失败时用**空文件覆盖它上一次成功列表**（实测 27B→0B）——最后一次已知好数据被销毁
- checkallupdates:447-485：中断时已完成来源只落盘、不打新鲜时间戳 → 下次打开重查
- offsite-backup-schedule:404-409：目标未挂载（条件跳过）时 `--run` 仍打印"备份服务已完成"
- backup-restore:339,518：`--apply-home` 会把 `$HOME` 自身 `chmod 0700` 并改 mtime（等价 `rsync -a` 实测 755→700）
- clean:478-485：snapper 对不可删快照静默跳过仍返回 0，stderr 被丢弃 → 误报"已删除快照"
- offsite-backup:354：`--check` 在"已初始化但还没有集合"时静默 `exit 1`（预期告警是死代码，实测无提示）
- migration-pack:533-539：两次 rename 之间被 SIGKILL 会留下隐藏旧包目录；`:723-732` v1 校验"关键内容缺失"只 warn，仍报"校验有效"（实测 exit 0）

### 4.7 工程与测试
- `tests/run`（单文件 129KB、59 个用例）：无单项过滤、无超时；`fail()` 直接 `exit` 不输出 TAP plan；**PTY 端到端用例 tests/run:298-316 未隔离 HOME，每次跑套件都会在真实 `$HOME` 留下 `log-check-*.md`**（代码铁证，未运行）；**`test_syntax` 的 `find`（tests/run:29）会下钻到 `review/`**——若希望隔离该目录，需在测试里显式排除
- 覆盖缺口正好放过本次 P1：terminal-tools 用例先造了 `~/.gitconfig`（漏掉无配置路径）、只测 `--strict` 成功路径、没有"查询失败"的退出码矩阵
- 重复实现（当前语义一致、漂移风险）：`usage`×11、`main`×10、`have`×8、`panel`/`panel_end`×5、`fzf_colors`/`cancel_to_parent`×2；死代码 `cache-clean:253 target_paths`、`migration-pack:91 guard_backup_dir`
- 文档漂移：README"参数错误=2"vs `mirror-update -c` exit 1；"缺依赖=127"vs 实际 1；"非交互=2"vs 实际 0；lib/ui.sh:376 注释写"仅依赖 awk"（实现已是纯 bash）；config.example 未说明不支持行内注释

---

## 5. 已核对、确认设计正确的部分（避免误改/重复劳动）

- **更新链路**：三来源真并行、单来源超时与无孤儿、Ctrl+C/SIGHUP 清理与已完成来源落盘、`--refresh-stale` 只补查失败来源、非 TTY 拒绝、fzf load/Ctrl+R 绑定、维护锁继承与嵌套（sysup 持锁下 `checkallupdates --refresh` 无死锁）、sysup 7 步顺序与失败累计、mirror-update 备份轮换与正常路径回滚
- **核心库**：`set -e` 下 `cond && action` 惯用法安全；含空格/换行临时路径处理正确；锁幂等/继承/防伪/释放正确；配置解析器不执行命令，引号/重复键/CRLF/未知键/未知格式边界正确（失败即报错退出）；非 TTY 关色、pty 正常
- **数据路径**：`snapper delete` 确实支持多 ID（批量删除没问题）；`create -p` 只输出数字；btrfs-scrub 的 `systemd-escape` 实例名与 btrfs-progs 模板一致；`ui_confirm_word` 在 EOF 下正确拒绝；bash 在 SIGINT/SIGTERM 下会执行 EXIT trap（130/143）；offsite-backup 同盘拒绝与边界校验、migration-pack 输出目录边界、backup-restore 不用 `rsync --delete`
- **静态层**：24 个脚本 shellcheck（0.11.0，`-x`）零告警；所有脚本 `bash -n` 通过；19 个脚本启动 <2.2ms

---

## 6. 建议修复顺序

**第一批（P1，正确性/安全）**
1. terminal-tools 软链与权限（P1-1）：`-L` 检测 + `stat -Lc`，拒绝或写真实目标
2. checkallupdates 刷新失败判定（P1-2）：`mktemp` 检查、先数据后状态、`mv` 失败计入失败、失败不 touch 时间戳且返回非 0
3. mirror-update else 分支（P1-3）：先备份当前文件，宽松解析 Server/Include，回滚前复核
4. clean 深度清理（P1-4）：成套校验（复用 quickload 判定）+ 批量 delete + 校验实际结果

**第二批（P2，体感与契约）**
5. term-menu 快照表宽度批量化（用户最大体感：6.6s → 目标 <0.5s）；backup-restore/migration-pack 归档只读一次；warn_batch_pairs 去 N+1
6. 统一退出码契约（0/1/2/127）与非交互返回 2；"查询失败"独立于"缺失"，统一不静默
7. 含空格挂载点（`findmnt -J`/`%p` + 解码；`df --target`）；unit 里 `$` 转义
8. 锁按 HOME 而非 uid（或 root 与用户共用同一路径）；env 覆盖统一走校验（sysup 里先做整数校验再做算术）
9. `ui_confirm` 默认改 `n`、EOF 视为拒绝；`ui_*` 统一 `printf '%s'` 包裹；query 失败状态不覆盖上次好数据；中断时补时间戳；并发临时文件回收加存活判断

**第三批（P3/工程）**
10. 去重 helper（usage/main/have/panel）、清理死代码、临时文件全部登记、sudo 保活自终止、测试隔离 HOME + 加过滤/超时 + 排除 `review/`、文档与注释校准、补本次发现的回归用例

---

## 7. 复核与合规说明

- 复核员独立重做了 12 条关键结论：**CONFIRMED 12 / REFUTED 0 / UNVERIFIABLE 0**；其中 3 条级别下调（P1→P2）、2 处影响面描述更正（terminal-tools 半恢复范围；checkallupdates 时间戳实际是"被刷新成刚刚更新"，比原报告更严重）
- 全程只读：未修改工作区任何文件（`git diff` 为空、无新增未跟踪文件）；未访问 `review/`（mtime/size 与开工一致）；未执行任何破坏性命令（reviewers 对 `btrfs-scrub start` 等被脚本自身的"非交互必须 --yes"拒绝，实测输出 `[错误] 非交互操作必须指定 --yes`）
- 复现材料：`/tmp/maintenance-review/sandbox/`、`/tmp/vsbx/`、`/tmp/mr-sandbox/`、`/var/tmp/maintenance-review/`（两个 ~95MB 大夹具已清理以释放 tmpfs 内存，可按 findings 中的命令重新生成）

## 8. 附：详细子报告
| 文件 | 范围 | 发现 |
|---|---|---|
| `/tmp/maintenance-review/ui-checks.md` | term-menu、检查类脚本、tests/run | 27 |
| `/tmp/maintenance-review/core-lib.md` | lib/config.sh、lib/ui.sh、示例配置 | 23 |
| `/tmp/maintenance-review/update-chain.md` | checkallupdates、mirror-update、sysup、post-update-check、recommend-check | 19 |
| `/tmp/maintenance-review/data-safety.md` | 快照/备份/清理/迁移 | 19 |
| `/tmp/maintenance-review/verify.md` | 对抗性复核 12 条关键结论 | 12/12 成立 |
