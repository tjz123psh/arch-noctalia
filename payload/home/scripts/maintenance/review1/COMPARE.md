# 两套审查对照报告：`review/`（模式 A） vs `review1/`（模式 B · 本次）

- 对照对象：同一项目、同一基线 `git HEAD 10a0cdb`，同一天（2026-09-10）由两套独立流程评审
- `review/`：6 个域子代理 + 1 个专职性能测量 + 1 个对抗性复核，**120 条发现**，40 条断言独立验证（2 条被推翻、13 条降级），8 份文档 + 性能脚本/桩
- `review1/`：4 个域子代理（core-lib / update-chain / data-safety / ui-checks）+ 1 个对抗性复核，**88 条发现**，12 条关键结论独立复现（12/12 成立，0 推翻），6 份文档
- 本对照由本次 Lead 完成，并对双方分歧点做了独立裁决（下文标 ★ 的为本次现场复核过的结论）

---

## 一、总览对照

| 维度 | `review/`（模式 A） | `review1/`（模式 B） |
|---|---|---|
| 发现总数 | **120**（critical 0 / high ~9 / medium ~30 / low 55 / perf ~14） | **88**（P0 0 / P1 8→4 组 / P2 35→38 / P3 45） |
| 组织方式 | 按**领域**分文档：updates / snapshots / menu-ui / backup / diagnostics / perf / verification / README 索引 | 按**工作流**分文档：update-chain / core-lib / data-safety / ui-checks / verify / REPORT 汇总 |
| 复核机制 | 专职复核代理，40 条断言，**2 条推翻**（含 1 条 CRITICAL）、13 条降级、3 组性能倍数修正 | 专职复核代理，12 条关键结论，**0 推翻**、3 条降级、2 处影响面更正 |
| 是否跑项目测试套件 | **跑了 6 次**（发现套件当前是红的：`not ok 46`；并定位到测试夹具泄漏） | **未跑**（依据 `tests/DESTRUCTIVE-VM.md` 的破坏性提示采取保守策略），仅静态评估 + 指出会污染真实 HOME 的用例 |
| 性能测量手段 | strace 系统调用计数（clone/wait4/execve）、真实 fzf PTY、真机 `~/.cache` 证据、一键复现脚本 `review/perf/measure.sh` | 命令桩 + 沙箱计数（clone 计数、子进程计数）、`EPOCHREALTIME` 式微基准、逐条复现命令 |
| 真机证据 | 强：`~/.cache/checkallupdates` 里 10 个真实孤儿临时文件；测出套件红 | 中：全部在 /tmp 沙箱（含合成 snapper/归档夹具）；未触碰真实用户态数据 |
| 是否改动仓库 | 否（只新增 `review/`） | 否（只新增 `review1/`） |
| 结论基调 | 工程质量高；**3 类问题必须立刻知道**：clean all 回滚点、刷新假健康 + 临时文件泄漏、测试套件已红 | 工程质量高；**4 组 P1**：terminal-tools 软链 0777、刷新假健康、mirror 回滚覆盖、clean 批次不成套 |
| 一致的顶层判断 | **无 P0 / 无"无条件在线数据丢失"路径**；`shellcheck` 全库零告警；并行刷新与锁继承等设计是真的 | 同 |

---

## 二、两套审查互相印证的问题（可信度最高，建议优先采信）

| # | 问题 | `review/` 位置 | `review1/` 位置 | 备注 |
|---|---|---|---|---|
| 1 | `clean all` 保留批次不校验"每配置都有" | README 三.1 / snapshots H1 | P1-4 / DS-01 | 双方独立确认；A 方额外给出"半套不可用 + quickload 拒绝成套恢复"的闭环 |
| 2 | `checkallupdates` 先写 ok 状态再 `mv`、`mv` 失败被吞 → 假健康 | README 三.4/三.5 | P1-2 / F-01,F-02 | 同一根因；B 方复核还发现 `CACHE_STAMP` 被 touch → 标签显示"刚刚更新" ★ |
| 3 | 缓存数据缺失/为空 + 时间戳新鲜 ⇒ 谎报"没有待更新" | README 三.5 | F-04（空文件覆盖上次好列表） | 双方一致，B 方补了"27B→0B"的实测 |
| 4 | `flock -w … \|\| true`：等锁超时仍继续刷新 | README 中危12 | F-08 | 一致（A 方补充"300 秒等待发生在 fzf 阻塞 reload 里会更卡"） |
| 5 | `terminal-tools:241-247` `if ! cmd; then rc=$?` 恒 0 | README 中危3 | P1-1 → 复核降 P2 | **A 方定级更准**（MED）；B 方复核后也下调为 P2 |
| 6 | `terminal-tools` 把**符号链接**的 config.fish 换成常规文件 | diagnostics L4（标 "suspected"，未实测） | P1-3（沙箱端到端实测） | **B 方补上了 A 方未完成的验证**；B 方还发现权限是 **0777**（A 方只提到"常规文件"）★ |
| 7 | `ui_confirm` 在 EOF/`</dev/null` 时按默认值回答（默认 y 即同意） | README 中危1 | core-lib P2-3 | 完全一致；双方都指出危险调用点都传 `n`，只有 `mirror-update:271,337` 默认 y ★ |
| 8 | `ui_dwidth/ui_pad` 在非 UTF-8 locale 下按字节计宽 | menu-ui M2 | core-lib P2-2 | 完全一致；B 方额外确认 `mirror-update:31 export LC_ALL=C` 会实际触发卡片错位（实测顶/底边差 7 列）★ |
| 9 | `$(ui_pad)`/`$(ui_dwidth)` 子 shell 化让缓存失效 | perf #1、menu-ui P1 | core-lib P2-6、ui-checks P2-8 | 一致（成本数字见第四节） |
| 10 | `term-menu` 快照列表逐行 fork → 秒级卡顿 | perf #1 | ui-checks P2-8 | 一致，量化口径不同但结论相同 |
| 11 | `warn_batch_pairs` O(选中×配置) 次 snapper | perf #9 | ui-checks P2-11 | 一致 |
| 12 | `storage-health` 每字段重启 jq 解析同一份 JSON | perf #4 | ui-checks P3 | 一致（A 方还给出 11× 的实测倍率） |
| 13 | 缺命令退出码不符 README（0/1 混用，只有 check-battery 是 127） | README 中危4、diagnostics M? | ui-checks P2-1（"查询失败"两派） | 角度不同但同源；A 方按"缺命令"、B 方按"查询失败"分别举了实例，**合并后更完整** |
| 14 | `check-battery` 不检查 upower 退出码，与"无电池"混淆 | README 中危15 | ui-checks P2-4 | 一致 |
| 15 | `btrfs-scrub` 用空白拆分 `findmnt -r`，含空格挂载点错乱 | README 中危7 | DS-06 | 一致 |
| 16 | `offsite-backup-schedule` 被 Condition 跳过仍报"完成" | README 中危18 | DS-07 | 一致 |
| 17 | `log-check` 每次运行写 `~/log-check-<ts>.md` 且从不清理 | diagnostics L5/355 | ui-checks P2-3 | 一致 |
| 18 | `err` 计入"缺失"统计（`ui_panel_stat`） | README 低危列表 | ui-checks P3、core-lib P2-5 | 一致 |
| 19 | `pacnew-check` 等临时文件未登记清理 | diagnostics L2 | ui-checks P3 | 一致 |
| 20 | 环境变量覆盖绕过配置校验 | snapshots:132（clean/cache-clean 场景：伪失败） | core-lib P2-4（sysup 场景：`$(( ))` 展开**执行命令**） | 同一类根因、不同调用点；**B 方的后果更严重**（可执行命令），但需能设置环境变量 ★ |
| 21 | `backup-restore` 对同一归档反复完整读取 | backup.md:318-335 | DS-03 | 双方独立发现，行号几乎一致 |
| 22 | 检查脚本"查询失败" vs "缺失/没有"语义混淆 | diagnostics M4/M5/M6 | ui-checks P2-2 等 | 同主题，各自列举不同实例 |

## 三、仅 `review/` 发现（review1 未覆盖，已由我现场复核的标 ★）

1. `clean all` 保留逻辑 **fail-open** ★：批次扫描 `… \|\| true`（clean:434），失败 → `keep_batch=""` → 删除循环的保留条件短路 → **所有非 before\* 快照全删且无警告**。我已直接读码确认，与 A 方描述一致；这是两套审查里**最严重的单点缺陷**，B 方只覆盖了"批次不成套"，没覆盖"扫描失败"。
2. **项目测试套件当前是红的** ★：`not ok 46`，根因是测试用 `/root/maintenance-unreadable-grub.cfg` 造"不可读"场景，而本机 `/root` 是 `drwxr-x---+` 且 ACL 授予 `greeter` 组 r-x、`pang` 属于该组（我已验证：`/root` 可穿越、fixture 不存在）→ 测试前提失效。属环境依赖的测试缺陷，非产品缺陷；`tests/DESTRUCTIVE-VM.md` 的"44/44"已过期。
3. **`log-check` 顶层 trap 顶替测试套件的 EXIT trap → 夹具泄漏** ★：我用最小实验复现——在自己设了 EXIT trap 的 shell 里 `source log-check` 后，`trap -p EXIT` 变成 `ui_tmp_cleanup`。与 A 方 2.1 节结论完全一致。
4. **`~/.cache/checkallupdates` 真实孤儿临时文件 10 个**（fzf 用 SIGKILL 杀 reload 子进程，trap 全部不执行）。我现场查看：A 方已代为清理（当前目录只剩 lock/时间戳/缓存），这是**唯一一处真机用户态证据**。
5. `offsite-backup` 同盘检查只比 `TARGET` vs `/`，**从不计算 HOME 所在盘** ★：我读码确认（`offsite-backup:81-88` 只算 ROOT_DISK/TARGET_DISK，`HOME_REAL` 仅用于"目标不能位于 HOME 内"）。HOME 独立成盘的机器上，"异盘备份"会与唯一一份 HOME 同盘。
6. `term-menu` **吞掉 fzf 退出码** ★：`[ "$status" -eq 0 ] || return 1`（term-menu:705-708）→ 主菜单 `exit_menu` → 中断/报错都变 `exit 0`。我确认了代码路径；A 方有真实 fzf 0.74.3 + PTY 实测（fzf 130 → term-menu 0）。
7. `quickload`：选择器记录用 `|` 分隔，描述含 `|` 时错位不可选；原生恢复信号护栏缺失导致挂载泄漏；发布失败留 `@quickload-restore-*` 孤儿克隆。
8. `storage-health smart_value` 用 `jq // empty` 把布尔 `false` 当缺失 → SMART 失败分支死代码。
9. `storage-health` 把 `findmnt` rc=1（无匹配）当查询失败；`masked/static` 等合法 `is-enabled` 状态被当失败。
10. `gpu-check` 模块过滤漏 `i915/xe/radeon` → Intel 机器误报"未发现模块"，`--strict` 失败。
11. `offsite-backup`：`du` vs `tar` 的 `--exclude` 语义不一致（`*` vs `./` 锚定）导致空间低估；`du/df` 未保护会静默中止；轮换可能删掉 `latest` 指向的集合。
12. `migration-pack` 用 `--check`（与运行中系统比对）而非 `--verify` 校验归档。
13. 锁目录/文件用调用者 umask 创建、不 chmod/chown → root 先跑留下 root:root，用户侧 EACCES（退出码 73，README 未记录）。
14. `timeout` 无 `-k`：忽略 TERM 的子进程让"90 秒超时"变成无界（实测 `timeout 1` 耗时 5.005s，加 `-k` 后 2.003s）。
15. 若干低危：`check-battery` 前导零命中八进制、`storage-health` 对空 size 打印 0.0 GiB、`df` 面板纳入伪文件系统、`migration-pack` profile 不支持含空格路径、`backup-restore` 把用户取消报成 rc=0、`terminal-tools --disable` 会新建空 config.fish 等（55 条低危）。
16. A 方还完成了几处**排除性验证**（避免误改）：tar 1.35 拒绝 `..`、生成的 systemd unit 通过 `systemd-analyze --user verify`、`tar --zstd` 已多线程、嵌套维护锁 fd 继承正常、富文本 tally 不丢警告。

## 四、仅 `review1/` 发现（review 未覆盖）

1. **`mirror-update` 回滚覆盖当前 mirrorlist**（P1-3）：无 `^Server = ` 行时 `BACKUP_PATH` 指向历史旧备份，失败/中断时 trap 把旧配置 `sudo cp` 覆盖回去，且**当前文件从未被备份**。A 方的 updates.md 只覆盖"mirrorlist 写不进去"（L-6），没有 this 分支。我已读码确认（`mirror-update:352-372` + `:112-121`），B 方另有端到端复现。
2. **`sysup` 在 TERM 未设置/dumb 时构建失败**（F-06）：`clear` rc=1 + `set -e` → `--yes` 非交互路径不可用。我用 `env -u TERM` 与 `TERM=dumb` 独立确认 rc=1。A 方 updates.md 未覆盖 `clear`。
3. **`terminal-tools --enable` 在用户没有 `~/.gitconfig` 时恒失败**（P1-2 → 复核降 P2）：A 方只验证了"键不存在时 git 返回 5"的场景，没有覆盖"整个全局配置不存在（rc=128）"这条新装机路径。
4. **`ui_*` 把消息当 printf 格式串**（core-lib P2-1）：消息含裸 `%` 时输出截断，且 22 个 `set -e` 调用方会**整脚本中止**（我实测 `ui_info "进度 100% 完成"` → 截断 + rc=1）。当前仓库内消息恰好都用 `%s`，属待引爆隐患。
5. **`backup-restore --apply-home` 修改 `$HOME` 自身的权限与 mtime**（DS-02）：staging 目录是 mktemp 的 0700，`rsync -a` 会把 HOME 从 755 改成 700 并改时间戳。
6. **`storage-health` 含空格挂载点**（P2-6）：`df` 解析截断 + `findmnt -r` 的 `\x20` 转义路径原样传给 btrfs/systemd-escape → Btrfs 段整段误报失败。A 方只覆盖了 `btrfs-scrub` 的同类问题。
7. **`offsite-backup-schedule` 单元文件未转义 `$`**（DS-08）：systemd 会做变量展开，目标含 `$` 时定时备份静默跑空。A 方验证的是 unit 语法（`systemd-analyze verify` 通过），不覆盖该语义。
8. **锁文件名带 uid**（core-lib P2-7）：root 直连（uid 0）与普通用户（uid 1000）用**两把不同的锁**、可同时维护，README"共享同一把 flock"不成立。A 方的锁问题聚焦 umask/root-first 的 EACCES(73)——**两者互补**，是锁子系统两处不同的真实缺陷。
9. **`tests/run` 自身**（ui-checks P2-9/P3）：PTY 端到端用例不隔离 HOME，跑一次就在真实 `$HOME` 留 `log-check-*.md`；`test_syntax` 的 `find` 会下钻到 `review/`（做目录隔离时要显式排除）；无单项过滤/超时，`fail()` 直接退出不输出 TAP plan；覆盖缺口（先造 gitconfig、只测 `--strict`）正好放过本次多个 P1。
10. **`migration-pack` 每个 include 各整包解压一次**（DS-03 的另一半）：v2 `--check` 6 次、v1 9 次；A 方只量化了 backup-restore 的成员查询，未量化此项。
11. **`checkallupdates` 孤儿回收按 mtime 删并发刷新的临时文件**（F-03）、**中断时已完成来源不打时间戳**（F-09）、**`--refresh/--refresh-stale` 机器契约未文档化**（F-11）、**reload 子进程删掉不属于它的 pending 标记**（F-12）等 checkallupdates 细节，A 方未逐条覆盖。
12. **`clean` 逐条 `sudo snapper delete` 且丢弃 stderr → 误报"已删除"**（DS-04）；**`offsite-backup --check` 在"已初始化但无集合"时静默 exit 1**（DS-09，死代码）；**`migration-pack` 两次 rename 之间 SIGKILL 留隐藏目录**（DS-11）。

## 五、同一问题、判断不同的裁决

| 问题 | `review/` | `review1/` | 裁决（含本次现场复核） |
|---|---|---|---|
| `terminal-tools` `$?` 恒 0 | MED（中危3） | P1 → 复核 P2 | **A 方更准**。B 方复核还发现"先 --enable 再 --disable"可完整回退，B 方原报告"只能手工补键"过重 |
| 符号链接 config.fish | "suspected"（未实测） | P1（端到端实测） | **B 方更强**（证据完整），且发现 0777 权限这一 A 方遗漏的安全面；级别 P1 合理 |
| 缓存假健康 | high（2 条） | P1（1 组 2 机制） | 同级；A 方证据含真实孤儿文件与"缺文件 + 新鲜时间戳"闭环，B 方含"标签显示刚刚更新"（复核补充） |
| `clean` 批次 | high（2 条：不成套 + fail-open） | P1（1 条：不成套） | **A 方覆盖更全**（fail-open 是更严重的一半，我已读码确认） |
| 刷新超时 | "不是硬上限"（忽略 TERM 的子进程实测 5.005s） | "超时生效且无孤儿"（协作式桩） | **两者都对但适用场景不同**：协作式子进程下 B 方结论成立；恶意/卡死子进程下 A 方结论更接近真实。合并表述应为"超时对合作进程有效，对忽略 TERM 的进程无界" |
| `offsite-backup` 同盘判定 | 条件性高危（HOME 独立成盘时失效） | 判定"实测正确"（本机 HOME 与 / 同盘） | **A 方更深**：本机确实正确，但 A 方指出了条件失效场景，我读码确认其成立 |
| 测试套件 | 实跑 6 次 → 红（`not ok 46`），根因 /root ACL | 未跑（安全策略），只做静态评估 | **互补**：A 方拿到事实状态，B 方守住不触碰破坏性测试的边界；我已独立确认 A 方根因 |
| 日志/临时文件泄漏 | 真机 10 个孤儿文件 + 套件夹具泄漏机制 | 只在静态/桩层面覆盖清理路径 | **A 方更强**（真机证据） |
| 性能数字口径 | 7.3 ms/行、7.4 fork/行、200 条 3155ms（strace + 真实快照） | 300 行 1.9–7.6s、≈15 fork/行（长中文逐字符时） | 不矛盾：**长描述会触发逐字符 `$(ui_dwidth)`，fork/行成倍上升**；双方都指向同一根因，A 方的 `clone/wait4` 计数与 `fork-free 0.09ms/行` 基准更具决定性 ★ |

## 六、性能数据并排

| 路径 | `review/`（strace/真机） | `review1/`（桩/沙箱） |
|---|---|---|
| term-menu 快照查看 | 10 条/配置 364ms；**200 条 3155ms**；500 条 7454ms；≈7.3ms/行；clone 2942 / wait4 5867；去 fork 后 0.09ms/行（≈37×） | 300 行 **1.9–7.6s**；clone +4500（≈15/行）；子 shell 0.69ms vs 同进程 0.035ms（20×） |
| backup-restore | 800MB 归档：一次全量列清单 0.33s；同一文件被读多遍（`:250/:252/:257/:316/:325/:328/:341` + 2 次 rsync） | 同一归档完整读 **9 次**；101MB `tar -tf` 53ms → 25GB HOME 单次 ≈13s |
| storage-health | 12 次 jq/盘，56ms vs 单次 3.4ms（≈11×），3 盘 126 execve | 2 盘 15 次 jq |
| checkallupdates 记账 | 零延迟三来源 **71ms / 59 execve**（10 mktemp + 6 find）；`--refresh-stale` 全新鲜 75ms/37 execve | 每次刷新 6 次 find 回收 |
| quickload `--list` | **673ms / 1015ms**；零延迟 200 条/配置仍 1183ms（3 fork/行） | 未量化 |
| hw-doctor | perf.md 有专节 | 86 子进程/次（17 tput、7 expand、11 systemctl） |
| 三来源并行 | 3×1s 桩 → **1069ms**（真并行） | 3062ms vs 串行 ≈9000ms |
| 外部下限 | `checkupdates` 本身 9.5s / 11MB（每次 `pacman -Sy`） | — |
| 排除的假警报 | `cache-clean` 的 `du` 是真实遍历；`ui_pad` 纯 bash 仅 0.084ms；重启/UI 的 `sleep` 属设计 | 脚本启动 1.0–2.2ms，无启动瓶颈 |

## 七、方法论差异带来的风险对比

| 维度 | `review/` | `review1/` |
|---|---|---|
| 覆盖广度 | 更广（120 条，含 55 条低危细节、`cache-clean`/`quickload` 深挖） | 较窄（88 条，但每条都带行号 + 触发 + 影响 + 修法） |
| 真机证据 | 强（孤儿文件、套件红、fzf PTY、strace） | 弱（不触碰真实用户态），靠合成夹具补足 |
| 破坏性边界 | 跑过测试套件（安全的 stub 化套件），代价是留下过 5 个 /tmp 夹具树 + 10 个缓存孤儿（已清理） | **未跑任何套件**，零副作用 |
| 复核强度 | 40 条断言、2 条被推翻（含 CRITICAL 误报被拦下） | 12 条关键结论 12/12 成立，含 3 条自我降级 |
| 误报倾向 | 曾有 1 条 CRITICAL 被自己推翻、3 组性能倍数被修正 → 复核机制有效但初审噪声略高 | 误报少，但**漏检**较多（clean fail-open、fzf 退出码、测试套件状态、quickload 多项） |
| 可复现性 | 提供 `review/perf/measure.sh` 与桩；但 /tmp 复现材料已清理（2GB） | 提供每条命令；/tmp 沙箱保留（大夹具已清） |

## 八、合并后的结论（两套报告如何一起用）

1. **共识清单最值得先修**（第二节 22 条）：clean 批次、刷新假健康、缓存空覆盖、锁超时、locale 宽度、子 shell 宽度开销、快照列表 fork、缺命令退出码、EOF 确认、空间挂载点、jq 逐字段等。
2. **各自独有的高价值补充**：
   - 采信 `review/`：clean fail-open、测试套件已红 + 夹具泄漏、offsite HOME 同盘、fzf 退出码被吞、quickload 的 `|`/挂载泄漏、storage-health 的 jq/分支死代码、`timeout` 无 `-k`、锁 umask/73。
   - 采信 `review1/`：mirror-update 回滚覆盖、sysup TERM/clear、terminal-tools 软链 0777 与无 gitconfig、env 覆盖 → `$(( ))` 执行命令、`ui_*` printf 副作用、apply-home 改 HOME 权限、storage-health 空格路径、unit `$` 转义、锁 uid 不互斥、append 型 tests 缺口（HOME 污染 / 扫到 review/）。
3. **互相修正后的最终定级建议**（本次裁决）：
   - 最高优先：`clean all`（fail-open + 不成套，P1）、`checkallupdates` 假健康（P1）、`mirror-update` 回滚覆盖（P1）、`terminal-tools` 软链与权限（P1）。
   - 次高：`term-menu` 快照列表 fork 化（体感最大，去 fork 可 37×–215×）、fzf 退出码契约、测试套件与环境夹具、refresh 孤儿清理、HOME 同盘判定。
   - 其余 P2/P3 按两套报告合并清单执行即可，双方无实质冲突。
4. **数量口径说明**：两套总数（120 vs 88）不可直接相加——口径不同（A 把每条独立断言/低危细节都计数，B 按问题分组计数）。按问题去重后，**双方共同指向 ~22 个问题簇，A 独有约 14 个（其中 3 个高价值），B 独有约 20 个（其中 3 个 P1）**；合并去重后**实际待修问题约 45–55 项**，其中真正需要优先处理的 **4 项 P1 + 约 10 项 P2**。
5. **可信度最高的问题集** = 两套都独立确认者（第二节），这些应直接进入修复计划；仅单方发现的，本次已对关键条目做了第三方复核（★），复核结论见第五节。

---

*本对照报告由 review1 侧 Lead 撰写；双方仓库均只新增各自目录，项目代码零改动。*
