# Arch Linux 维护脚本集 · 全面审查报告

- **审查对象**：`/home/pang/scripts/maintenance`（24 个可执行脚本 + `lib/config.sh`、`lib/ui.sh`，共 12,208 行 Bash；测试 harness `tests/run` 3,089 行）
- **审查日期**：2026-09-10
- **审查方式**：6 个并行子代理按文件域审查 + 1 个专职性能测量 + 1 个对抗性复核代理独立复现；共 120 条发现，其中 40 条断言逐条独立验证
- **是否改动代码**：否。审查期间 `git status --porcelain --ignored` 全程为空；所有实验在 `/tmp` 用桩命令完成。本目录仅为报告归档。

## 文档索引

| 文件 | 内容 | 规模 |
|---|---|---|
| `verification.md` | **对抗性复核**：40 条断言的独立复现、判决与严重度修正（先读这份） | 664 行 |
| `updates.md` | 更新/刷新链路：`checkallupdates`、`mirror-update`、`sysup`、`post-update-check` | 571 行 |
| `snapshots.md` | 快照与破坏性路径：`quickload`、`quicksave`、`clean`、`cache-clean`、`btrfs-scrub` | 159 行 |
| `menu-ui.md` | 菜单/UI 层：`term-menu`、`lib/ui.sh`、`lib/config.sh` | 292 行 |
| `backup.md` | 备份/迁移：`backup-restore`、`offsite-backup`、`offsite-backup-schedule`、`migration-pack` | 380 行 |
| `diagnostics.md` | 九个检查脚本：`hw-doctor`、`storage-health`、`gpu-check`、`check-battery`、`boot-check`、`pacnew-check`、`log-check`、`recommend-check`、`terminal-tools` | 377 行 |
| `perf.md` | 读取/刷新慢的实测基准、进程/execve 计数、可复现命令 | 164 行 |
| `perf/measure.sh` 等 | 性能测量脚本与桩（复现时写入 `/tmp/maintenance-review/perf/`） | — |

---

## 一、总体结论

工程质量明显高于普通脚本集：全库 `bash -n` 干净，`shellcheck -S warning`（乃至 `-S info`）零告警；共享锁、`set -euo pipefail`、sudo 保活、原子发布、严格模式退出码这些"容易做对但经常做错"的地方大部分是对的。审查中**没有发现无条件造成在线数据丢失的路径**。

但有三件事需要立刻知道：

1. **项目自带的测试套件现在是红的**（`not ok 46`），而文档写的是全绿。
2. 有 **6 条经复核确认的高危问题**，其中两类直接违背 README 的安全承诺：`clean all` 的回滚点保留、刷新中断后的临时文件清理——**后者在本机已经真实留下 10 个泄漏文件**。
3. `checkallupdates` 存在"缓存其实没写成，但对外宣称 ok/最新"的假健康路径。

原先被一位审查员标记为 CRITICAL 的 `post-update-check`/GRUB 问题，经 Lead 与复核代理双重验证后**判定不可通过 `sysup` 触发**，已降级（见第三节 0 条）。

---

## 二、本机测试套件当前失败

```
$ MAINTENANCE_NO_NOTIFY=1 bash tests/run     # 真实退出码 1
ok 45 - sysup completes the isolated update chain and aborts on keyring failure
not ok 46 - post-update check must fail when GRUB cannot be read
```

**根因（已独立复现并交叉验证）**：`tests/run:2402-2410` 用 `/root/maintenance-unreadable-grub.cfg` 模拟"无法读取的 GRUB 配置"，前提是测试用户无法穿越 `/root`。但本机 `/root` 为 `drwxr-x---+` 且带 ACL `group:greeter:r-x`，而 `pang` 属于 `greeter` 组，所以 `[[ -x /root ]]` 为真：

- 该 fixture **根本不存在**，程序按"文件缺失"处理（`post-update-check:38-42` → `return 1`）→ `[注意] …不存在或为空` → 非严格模式 `exit 0`；
- 换成真正不可穿越的父目录（mode 000）后，脚本**行为完全正确**：`[错误] …无法读取，GRUB 状态未完成验证`，`rc=1`。

**判定**：这是**环境依赖的测试缺陷**（fixture 不该依赖 `/root` 权限），不是产品缺陷。文档 `tests/DESTRUCTIVE-VM.md` 里"44/44 通过"的结论已过期。

### 2.1 追加发现（清理临时文件时定位）：`tests/run` 每次失败运行都会在 `/tmp` 留下 134 项夹具目录

**现象**：只要测试失败点在 `test_log_query_failure`（第 22 项）之后，`/tmp/tmp.XXXXXXXXXX` 就会永久残留（本机复现 5 次，每次 134 个条目）。失败在第 3 项时却能正常清理——这就是线索。

**根因（已用最小实验证明）**：`tests/run:8` 安装了自己的清理陷阱 `trap 'rm -rf -- "$TMP_DIR"' EXIT`，但

- `log-check:9-11` 在**顶层**无条件安装 `trap 'ui_tmp_cleanup' EXIT / INT / TERM`，而它的 `BASH_SOURCE == $0` 守卫（`log-check:185`）**只覆盖主流程**，管不到这三行；
- `tests/run:813-814` 的 `test_log_query_failure()` 在**测试套件自己的主 shell** 里 `source "$ROOT/log-check"`。

于是 `source` 一执行，套件的 `rm -rf "$TMP_DIR"` 陷阱就被 `ui_tmp_cleanup` 顶替，此后套件无论怎么退出都不再删除夹具目录：

```
$ T=$(mktemp -d /tmp/trapexp.XXXXXX)
$ bash -c 'T="$1"; trap "rm -rf -- \"\$T\"" EXIT;
    printf "source 前: %s\n" "$(trap -p EXIT)"
    source /home/pang/scripts/maintenance/log-check >/dev/null 2>&1 </dev/null
    printf "source 后: %s\n" "$(trap -p EXIT)"; exit 1' _ "$T"
source 前: trap -- 'rm -rf -- "$T"' EXIT
source 后: trap -- 'ui_tmp_cleanup' EXIT
退出码: 1
结果: 目录残留 → 陷阱被顶替，测试夹具泄漏
```

**影响**：① 每次失败的 CI/本地测试都会在 `/tmp` 留下一个 134 项的夹具树（本次清理共删除 5 个）；② 同一机制下套件的 `INT`/`TERM` 陷阱也被顶替，测试运行中 Ctrl+C 同样不再清理；③ 这是"被 source 的脚本不应在顶层安装陷阱"这一类问题，与 `menu-ui.md` L11（`term-menu` 的 `--preview` 提前退出落在 `BASH_SOURCE` 守卫之外）同源。

**修复方向**：把 `log-check:9-11`（以及其他同样在顶层设陷阱的诊断脚本）移进 `BASH_SOURCE == $0` 守卫内，或改成只在被直接执行时安装；套件侧则应在 `source` 后显式重建自己的陷阱。

---

## 三、高危问题（全部经独立复核）

### 0. 原 CRITICAL 已被推翻（说明为何）

审查员把 `post-update-check:29-43,194-202` 定为 CRITICAL，理由是"`sysup` 会把第 7 步报成 OK"。Lead 与复核代理分别验证了 `--grub-status` 全矩阵：

| GRUB 文件状态 | `success` | `failed` | `skipped` | `unknown` |
|---|---|---|---|---|
| 缺失/为空 | **rc=1** | **rc=1** | rc=0 警告 | rc=0 警告 |
| 不可读 | rc=1 | rc=1 | rc=1 | rc=1 |

`sysup` 只会传 `skipped`（初值 `sysup:322`）/`success`（`:384`）/`failed`（`:387`），而 `skipped` 只在 `grub-mkconfig` 不存在时出现，那条路径本身已置 `post_update_failed=1`（`sysup:392-395`）。**"GRUB 坏了但 sysup 报成功"不可达**。真实严重度：LOW/MEDIUM（仅独立运行且不带 `--grub-status` 时会把"缺失"说成注意项）。

### 1. `clean all` 会删掉唯一完整的回滚快照集
`clean:430-449`（批次扫描）、`clean:472-475`（保留判断）、`clean:451-488`（删除循环）

`keep_batch` 只是对所有配置取 `max`（`clean:436-444`），从不检查这个批次在**每个配置**里都存在。复现（root 有 B2 半套 + B1，home 只有 B1）：

```
INFO: 将保留最近一套回滚快照（批次 B2）。
ITEM: 保留快照 [root] ID 11 quicksave（最近回滚点）   ← 半套
ITEM: 已删除快照 [root] ID 9 quicksave
ITEM: 已删除快照 [home] ID 10 quicksave             ← 完整的那一套没了
```

而 `quickload:1227-1232` 在任一配置缺批次时拒绝成套恢复——保留下来的一半**不可用**。半套状态可达：`quicksave` 只在 `create` 报错时回滚（`quicksave:329-339`），中断时不回滚；菜单删除路径还明确允许删掉一半（README:77-78）。**直接违背 README:80 的承诺。**

### 2. `clean all` 的保留逻辑 fail-open
`clean:431-446`（`|| true`）、`clean:447-449`、`clean:472`

批次扫描查询被 `|| true` 包住，失败时静默产出空结果 → `keep_batch=""` → 保留判断短路为假 → **所有配置的所有非 `before*` 快照全部删除，且没有任何警告**。复核代理注入扫描失败后，root#11/#9 与 home#10 照常被删、`rc=0`。一次瞬时查询失败或 snapper 输出格式变化，就把"保留最近回滚点"变成"连最近回滚点一起删"。

### 3. `term-menu` 吞掉 fzf 退出码：Ctrl+C 也返回 0
`term-menu:705-707`、`1488`、`771-779`；文档在 `README:324`

所有非零 fzf 状态被折叠成 `return 1`，主菜单再转成 `exit 0`。真机 fzf 0.74.3 + PTY 实测：

```
fzf exit logged: 130      # fzf 正确报告被中断
term-menu exit=0          # 被吞掉
```

`term-menu:40-42` 的 `INT → 130` trap 不会触发（raw 模式下 Ctrl+C 由 fzf 当 abort 处理）。**影响**：niri 键位/包装脚本无法区分"用户取消"和"正常完成"，fzf 真报错（rc=2）也静默成功返回。`delete_snapshot:1137,1206,1215` 同样无法上报 fzf 错误。

### 4. `checkallupdates` 缓存"先认证成功，再写文件"
`checkallupdates:266-270`（+`296`、`325`）

per-source 状态在 `mv` 进缓存**之前**就写成 `ok`，且 `mv` 的返回值被丢弃（`_cau_settle_status` 只读状态文件）。用失败的 `mv` 复现：`refresh rc=0`、`pacman:ok`、两个时间戳都被刷新，而 `updates-repo.txt` **根本不存在**。

### 5. 缓存数据文件丢失 + 来源时间戳新鲜 ⇒ 谎报"没有待更新"
`checkallupdates:103-123`、`392-396`、`539-551`、`496`

`--refresh-stale` 认为全部新鲜 → 一次查询都不发 → 但又重新 touch `CACHE_STAMP`（`:496`）→ 列表打印 `[None] 当前没有待更新项目`。合并 4、5 两条：**"查询/落盘失败"会被系统化地表达为"一切正常且是最新的"**，这是本项目里最值得优先修的一类语义缺陷。

### 6. fzf 用不可捕获信号杀 reload 子进程 → 临时文件真实泄漏
`checkallupdates:409-427`、`838-845`；文档承诺在 `README:32-33`

真机 fzf 驱动 PTY：Esc 与 Ctrl+C 两种中断下，探针进程的 TERM/INT/HUP/EXIT trap **全部未执行**（fzf 直接 SIGKILL 整个进程组）。**这不是理论**——本机直接确认了残留（完整清单，共 **10 个**孤儿临时文件，均为 9月9日 23:32 那次被中断的刷新所留）：

```
$ ls -la ~/.cache/checkallupdates/            # 清理前，当前时间 2026-09-10
-rw------- 206  9月 9日 23:32 aur.9UD52T      ← 已完成、从未落盘的 AUR 临时文件
-rw-------   0  9月 9日 23:32 error.l5XpoF
-rw-------   0  9月 9日 23:32 error.QEYFvl
-rw-------   0  9月 9日 23:32 error.XzivVw
-rw-------   0  9月 9日 23:32 flatpak.Kgp8Xe
-rw-------   0  9月 9日 23:32 repo.wtRXoN
-rw-------   0  9月 9日 23:32 status.e3xIgT
-rw-------   0  9月 9日 23:32 status.IrxAvs
-rw-------   0  9月 9日 23:32 status.sCXqV3
-rw-------   0  9月 9日 23:32 status.V7kBwM
-rw-r--r--   0  9月 9日 21:54 last-refresh*    ← 最后一次成功刷新是 21:54
-rw-------  31  9月 9日 21:54 source-status.tsv（缓存状态，保留）
-rw------- 206  9月 9日 21:49 updates-*.txt（缓存数据，保留）
```

（这 10 个孤儿文件已于 2026-09-10 清理；`refresh.lock`、`last-refresh*`、`source-status.tsv`、`updates-*.txt` 保留。）

临时文件泄漏确凿；"锁被长期占用"与"查询树孤儿"两点复核代理**未能复现**（锁当前空闲、同进程组会一起死），属审查员过度延伸。

### 7. `offsite-backup` 同盘检查只看 `TARGET` vs `/`，不看 HOME 所在盘
`offsite-backup:81-88`、`103-106`

`HOME` 从未传给 `backing_disk`。**条件性高危**：在 HOME 独立于 `/` 的机器（独立 home 盘 / 独立 LUKS）上，指向 HOME 同盘的备份目标会被判为"异盘有效"（复核确认 `rc=0 目标磁盘 /dev/homedisk`），此时"异地备份"与唯一一份 HOME 在同一物理盘上。**本机 HOME 与 `/` 同盘，因此不受影响**；审查员延伸的"未挂载目标被误接受"一半被复核**推翻**（本机 rc=1 拒绝）。

---

## 四、中危问题（已复核）

| # | 位置 | 问题 |
|---|---|---|
| 1 | `lib/ui.sh:656-665` | `ui_confirm` 把 EOF 当默认答案；`ui_confirm "危险操作" </dev/null` → **rc=0（同意）**。危险调用方（`clean:185`、`checkallupdates:590,663`、`quicksave:195`）都传 `n` 故安全；默认 `y` 的只有 `mirror-update:271,337` 两个非破坏性提示 → 复核降级 LOW/MED |
| 2 | `storage-health:44-46,70,87-91` | `smart_value` 用 `jq '… // empty'`，而 jq 的 `//` 把布尔 `false` 也当缺失 → `.smart_status.passed=false` 取到空 → `err "SMART 总体健康检查失败"` 分支**死代码**。真实 ATA/NVMe 通常同时置 smartctl 退出位 3，`:124` 仍会报错且 `--strict` rc=1，但非严格模式下 rc=0 → MED |
| 3 | `terminal-tools:241-247` | `if ! git config … --unset-all` 后取 `rc=$?`，拿到的是**取反后的状态**（恒为 0），于是文档化的"键不存在 rc=5"分支失效：外部删过任一托管键后 `--disable` → rc=1，报错文案还写着"（退出码 0）"，状态文件残留、Fish 块已删 |
| 4 | `gpu-check:187-189`、`storage-health:138-142` 等 | 缺命令时的退出码不符 `README:323`：`gpu-check`、`storage-health` **rc=0**（静默成功），`hw-doctor`/`boot-check`/`pacnew-check`/`recommend-check`/`log-check` rc=1，只有 `check-battery:43-46` 正确返回 127。`term-menu:1469` 专门用 127 判断"命令缺失"，因此菜单也分不清"没装工具"和"系统不健康" |
| 5 | `offsite-backup:407-417`、`backup-restore:332` | `du`/`df` 直接放进 `$( )` 且未保护，`set -euo pipefail` 下 HOME 内任一不可读目录就让脚本**静默中止**（`2>/dev/null` 把原因也吞了），精心写的 `:414-417` 守卫是死代码。这是**安全中止，不丢数据**，故 MED |
| 6 | `offsite-backup:407-412` vs `429-435` | `du --exclude='.cache'` 匹配任意层级 basename，tar 的 `--exclude='./.cache'` 只锚定顶层 → 预检查低估（实测 du 0 KiB vs tar 5000 KiB），可能中途 ENOSPC |
| 7 | `btrfs-scrub:87-94` | `while read -r mountpoint source` 按空格切分：`"/run/media/pang/My Disk"` → 目标 `/run/media/pang/My`、设备 `Disk /dev/sdb1`；影响 `--status/--start/--enable` 与去重 |
| 8 | `quickload:839/850/855/865` | 快照记录用 `\|` 分隔，描述含 `\|` 时选择器列错位、该项无法选中 |
| 9 | `quickload:1020-1030,1112-1121` | 原生恢复两次 `mv` 之间无信号护栏。复核修正：bash **确实会**在未捕获的 INT/TERM/HUP 上执行 EXIT trap（rc 130/143/129），但 `cleanup()`（`:298-304`）只认 `MOUNT_DIR`，不卸载原生 `$top` 挂载 → 挂载泄漏；改名窗口为亚毫秒级，故 MED |
| 10 | `quickload:1026-1030`、`892-900` | 发布失败留下孤儿 `@quickload-restore-*` 克隆（含嵌套 `.snapshots`），且 `:1023` 分支用裸 `btrfs subvolume delete` 而不是 `delete_native_restore_clone` |
| 11 | `quicksave:329-339`、`255-279` | 无 INT trap，Ctrl+C 会留下半套批次（并喂给上面第 1、2 条）；`quicksave -del all` 不像其他路径那样设批次护栏 |
| 12 | `checkallupdates:412,791` | `flock -w … \|\| true`：等锁超时后**照样刷新**，最需要互斥时没有互斥；且该 300 秒等待发生在 fzf 阻塞式 reload 里 → 列表卡住。`QUERY_TIMEOUT` 不是硬上限：没有 `timeout -k`，实测 `timeout 1` 对忽略 TERM 的子进程耗 **5.005s**（加 `-k` 后 2.003s） |
| 13 | `lib/ui.sh:222-235,253-256` | 锁目录/文件用调用者 umask 创建、不 chmod/chown，而路径由 `SUDO_UID` 推导 → root 先跑会留下 root:root 文件，用户侧 EACCES → 退出码 **73（README 未记录）**。失败模式已复现（0400 文件 / 0555 目录 / root 0644），但"root 先跑"触发路径因本机无免密 sudo 无法实地执行 |
| 14 | `gpu-check:199-204` | 模块过滤只认 `amdgpu\|nvidia\|nouveau`，Intel `i915`/`xe`（及 `radeon`）被误报"未发现 … 模块"，`--strict` 直接失败 |
| 15 | `check-battery:48,55` | 完全不检查 `upower` 退出码：`-e` 失败 → 静默 rc=1（设计好的"无电池"文案永远打不出来）；`-i` 失败 → rc=3 无输出；`-i` 成功但空 → 满屏"未知"且 rc=0 |
| 16 | `storage-health:199-204,257`、`:243-251` | `findmnt` 无匹配返回 rc=1 被当成"查询失败"（"没有已挂载的 Btrfs 文件系统"分支不可达）；`masked`/`static` 等合法 `is-enabled` 状态被当成查询失败 |
| 17 | `recommend-check:167-172` | 无 GPU 的主机被当成"GPU 查询失败（退出码 1）" |
| 18 | `offsite-backup-schedule:407-408` | 单元被 Condition 跳过时仍打印成功，`--run` 无法发现"磁盘不在" |
| 19 | `offsite-backup:341-347,468` | 轮换删除不保护 `latest` 当前指向的集合；回拨时钟命名或同秒 PID 撞车可删掉刚发布的集合，`latest` 悬空而 rc=0（需时钟偏移，复核降级 LOW/MED） |
| 20 | `offsite-backup:273`、`migration-pack:533-539` | 用 `migration-pack --check`（与运行中系统比对）而不是 `--verify` 校验归档；发布后 `rm -rf` 旧包且无 `sync`（两道防线同时丢仅属推测 → LOW） |
| 21 | `mirror-update` M-8、`sysup` M-6、`checkallupdates` M-2/M-5 | `reflector --list-countries` 失败被读成"国家无效"并静默转全局；无 `grub-mkconfig` 时 `sysup` 恒 exit 1；未来时间戳把 3 天前的数据钉成"刚刚更新"；无 TTY 时静默降权读取 GRUB |

---

## 五、低危与文档不符

低危共 55 条，集中在：`err` 计入"缺失"计数、`hw-doctor` 缺 `lscpu` 时二次误报、`pacnew-check` 临时文件未登记清理、`terminal-tools --disable` 会新建空 `config.fish`、`storage-health` 对 `lsblk` 空 size 打印 `0.0 GiB`、`check-battery` 前导零命中八进制运算、`df` 面板纳入伪文件系统、`migration-pack` profile 不支持含空格路径、`backup-restore` 把用户取消报成成功（rc=0）等。完整清单见各域报告。

**README/实现不符（已逐条核对原文行号）**：

| 文档 | 实际情况 |
|---|---|
| `README:32-33` "中断时…清理临时文件" | **本机已残留 10 个泄漏临时文件**（9月9日 23:32，已清理） |
| `README:80` "`clean all` 保留最近一套 `maintenance_batch`" | 半套批次时保留不可用的一半、删掉完整的一套；扫描失败时完全不保留 |
| `README:323` "127 缺少命令" | 仅 `check-battery` 遵守；`gpu-check`/`storage-health` 返回 0 |
| `README:324` "130 Ctrl+C" | `term-menu` 实际 `exit 0` |
| `README:79` "批量删除只调用一次" | 对 `quicksave -del` 成立，对 `clean all` 不成立（`clean:478` 每个 ID 一次进程） |
| `tests/DESTRUCTIVE-VM.md` "44/44 通过" | 现为 45/46（第 46 条因本机 `/root` ACL 失败） |
| `README:316-324` 退出码表 | 未收录 `73`（锁文件权限失败） |

---

## 六、读取/刷新慢：实测数据

所有数字均为本机实测（strace、`EPOCHREALTIME` 微基准、确定性 fzf/命令桩），可一键复现：`bash review/perf/measure.sh`（脚本自身写入 `/tmp/maintenance-review/perf/`）。

| 排名 | 路径 | 实测成本 | 根因 |
|---|---|---|---|
| 1 | `term-menu:890-959` 快照查看 | **7.3 ms/行**；200 条/配置 **3155 ms**；500 条 **7454 ms**；`clone 2942 / wait4 5867`，**≈7.4 fork/行** | 每行 6 个 `$(ui_pad …)`（`:911-915`、`949`、`952`）+ 长描述触发**逐字符** `$(ui_dwidth "$ch")`（`:901`，30.33 ms/行）。去 fork 后 **0.09 ms/行（≈37 倍）** |
| 2 | `term-menu:990,926` 快照路径 | 墙面时间 = **3 × snapper 延迟 + ~330 ms**（0.6s 延迟 → 2166 ms） | 每个配置串行一次 `snapper list`，可并行 |
| 3 | `quickload:332,396-460` `--list/--list-all` | 673 ms / 1015 ms（@0.3s snapper）；零延迟 + 200 条/配置仍 **1183 ms** | 2-3 次串行 snapper + 3 fork/行 |
| 4 | `storage-health:44,68-76` | 12 次 `jq`/盘；同 5 KB JSON 12 次=56 ms vs 单次=3.4 ms（≈11 倍）；stub 3 盘 126 execve | 每字段重启一个 jq 重新解析整份 JSON |
| 5 | `checkallupdates:373-507` 记账 | 零延迟三来源 **71 ms / 59 execve**（10 mktemp、6 find）；`--refresh-stale` 全新鲜仍 **75 ms / 37 execve** | 无论是否需要查询都建临时文件 + 跑孤儿回收 |
| 6 | `checkupdates` 本身 | 每次刷新 **9.5 s / 11 MB**（完整 `pacman -Sy`） | 外部命令决定下限，非本脚本可控 |
| 7 | 交互小项 | `ui_status_line` 17-21 ms/次重绘；`--load-actions` 15-17 ms/次渲染；preview 22-25 ms/次方向键；`term-menu` 启动 61-69 ms/24 execve；`checkallupdates` 首屏 48 ms | 多为"整脚本重跑"式 fork |
| 8 | `cache-clean:72,118` `--list` | 679-717 ms，但进程开销仅 **22 ms（3.6%）** | **真 du 遍历（本身正确）**；要优化的是感知延迟而非 CPU |
| 9 | `term-menu:1070 warn_batch_pairs` | O(选中数 × 配置数) 次相同 snapper 查询 | 循环内重复查询同一份 userdata |

**已明确排除的假警报（不要误改）**：`--refresh` 三来源**真并行**（3×1s → 1069 ms）、`--refresh-stale` 对新鲜来源**真的 0 查询**、首屏**懒加载**确实是 48 ms、`cache-clean` 的 du 是真实遍历、`ui_pad` 纯 bash 仅 0.084 ms（只有包进 `$()` 才有 0.83 ms）、重启/UI 场景里的 `sleep` 属设计。

---

## 七、明确"没问题"的部分

复核代理专门验证了以下易误判项，确认健康：GNU tar 1.35 拒绝 `..` 成员并剥离绝对路径；生成的 systemd 单元通过 `systemd-analyze --user verify` 且 `ConditionPathIsMountPoint` 与 `mountpoint -q --` 语义一致；`tar --zstd` 已多线程；`sysup → mirror-update` 的嵌套维护锁通过 fd 继承正常工作；检查类脚本的严格模式 tally 不会丢警告；配置解析器不执行 shell 内容。全库 `shellcheck -x -S info` 零告警。

---

## 八、建议修复顺序

1. **`clean all` 两条**（第 1、2 条）——唯一涉及"回滚点被毁"的问题，改动小、收益最大，建议同时补回归测试。
2. **`checkallupdates` 假健康 + 泄漏**（第 4、5、6 条）——把"写 ok"移到 `mv` 成功之后、数据文件缺失即视为失效、刷新前先清理孤儿临时文件；顺手清掉 `~/.cache/checkallupdates` 里的孤儿临时文件（本次已代为清理 10 个）。
3. **`term-menu` 退出码**（第 3 条）——`return "$status"` 并在主菜单把 130 透传，同时更新 README 对 2/其他错误的说法。
4. **`offsite-backup` 同盘检查 + `du/df` 保护**（第 7 条、中危 5）——把 HOME 的 backing disk 纳入比较，并给所有探测加 `|| true`。
5. **缺命令退出码统一为 127**（中危 4）——`gpu-check`/`storage-health` 目前静默成功最危险。
6. **交互性能**：先修 `term-menu` 快照查看的 per-row fork，把 3 秒等待降到几十毫秒；并行化快照路径的 snapper 查询次之。
7. **文档同步**：README 的 127/130/32-33/79/80 与 `tests/DESTRUCTIVE-VM.md` 的通过率、`tests/run:2402-2410` 的 fixture 改成自建不可穿越目录。
8. **测试 harness 自身**：把 `log-check:9-11` 一类的顶层 `trap` 收进 `BASH_SOURCE == $0` 守卫（修 `tests/run` 夹具泄漏），并在 `tests/run` 的 `source` 之后重建自身 EXIT 陷阱。

---

## 九、可信度与局限

- **覆盖**：`term-menu`、`lib/ui.sh`、`lib/config.sh`、`checkallupdates`、`mirror-update`、`sysup`、`post-update-check`、`quickload`、`quicksave`、`clean`、`cache-clean`、`btrfs-scrub`、`backup-restore`、`offsite-backup`、`offsite-backup-schedule`、`migration-pack` 以及 9 个检查脚本全部逐行读过；`tests/run` 读过并在本机实跑 6 次（3 次用于定位 2.1 的陷阱泄漏）。
- **复核**：40 条断言独立复现，其中 **2 条被推翻**（含 1 条 CRITICAL）、**13 条严重度被下调**、3 组性能倍数被修正（如 65× → 37×、16× → 11×）。
- **未能验证**：真实磁盘故障/多盘场景、真实 `sysup` 端到端（会改状态）、无免密 sudo 的 root-first 锁路径、真实 loop 设备与 btrfs-assistant 映射、电源掉电窗口（仅代码路径推断）。这些在原报告中均标注为 suspected。
- **未做**：任何破坏性操作；`offsite-backup`/`--apply-home`/定时器安装器未实际运行；`clean`/`migration-pack`/`mirror-update`/`offsite-backup` 的性能数据是静态分析。

---

## 十、审查结束后的清理（2026-09-10）

各分域报告里引用的 `/tmp` 复现路径（`/tmp/maintenance-review/`、`/tmp/vf/`）已在归档本目录后删除；如需复现，`review/perf/measure.sh` 等脚本会重新在 `/tmp` 下生成。已删除的垃圾文件：

| 位置 | 内容 | 数量/体积 |
|---|---|---|
| `/tmp/maintenance-review/` | 各审查员的桩、strace 日志、夹具 | 2.0 GB |
| `/tmp/vf/` | 复核代理的实验夹具 | 27 MB |
| `/tmp/tmp.*` | **`tests/run` 泄漏的夹具树**（见 2.1，本机复现 5 次） | 5 个 × 134 项 |
| `/tmp/repro46*`、`/tmp/adj46`、`/tmp/o.txt`、`/tmp/tests-out.txt`、`/tmp/rmshim/`、`/tmp/suite*.out`、`/tmp/trace.txt` | Lead 的复现与定位产物 | — |
| `/tmp/checkup-db-1000` | 性能审查跑真实 `checkupdates` 留下的临时 pacman 数据库副本 | 11 MB |
| `~/.cache/checkallupdates/` | 被中断刷新留下的孤儿临时文件（保留锁与缓存状态） | 10 个 |

仓库自身**仍未被改动**：只新增了本 `review/` 目录，`git diff` 为空。
