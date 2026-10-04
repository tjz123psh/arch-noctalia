# 核心层审查：`lib/config.sh` + `lib/ui.sh`（task-1 / core-lib）

- 审查范围：`lib/config.sh`（110 行）、`lib/ui.sh`（811 行）、`config.example`、`migration-profile.example`；按需读取调用方（sysup / clean / term-menu / checkallupdates / quickload / cache-clean / log-check / mirror-update / backup-restore / post-update-check 等）用于确定语义与影响。
- 只读约束：未修改工作区任何文件；未访问 `review/`；未运行任何写系统状态的命令。所有实测都在 `/tmp/maintenance-review/sandbox/` 的 **lib 副本**上进行，外部命令（sudo/sleep/id 等）用 PATH 桩替换，未触碰真实系统状态。
- 实测环境：Arch Linux，bash 5.x，ambient `NO_COLOR=1 TERM=dumb LANG=zh_CN.UTF-8`（因此非 pty 测试全部落在“无颜色”分支；pty 测试显式 `env -u NO_COLOR`）。
- 复现脚本：`/tmp/maintenance-review/sandbox/t1_sete.sh t2_mode.sh t3_config.sh t4_dwidth.sh t5_tmp.sh t6_lock.sh t7_perf.sh t8_sigint.sh t9_misc.sh t10b_keepalive.sh t11b_pty.sh t12_edge.sh`。

统计：**23 条发现**（P2×9、P3×14；已确认 22、高度可疑 1）。按文件：`lib/ui.sh` 16、`lib/config.sh` 6、`config.example` 1、`migration-profile.example` 0。

---

## P2 级

### P2-1 `ui_info/ui_ok/ui_warn/ui_err/ui_miss` 把消息当 printf 格式串；errexit 下消息含 `%` 会中止脚本

- 位置：`lib/ui.sh:197-207`（`ui_die` 见 204）
- 触发条件：任何 `ui_info/ui_ok/ui_warn/ui_err/ui_miss` 的**消息本身**含裸 `%`。23 个入口里 22 个是 `set -euo pipefail`（例外：`term-menu:5` 只有 `set -uo pipefail`）。
- 证据：

```bash
# lib/ui.sh:197
ui_info() { local fmt="${1:-}"; shift 2>/dev/null || true; printf "${UI_C_SAPPHIRE}${UI_ICON_INFO}${UI_RESET} ${fmt}\n" "$@"; }
# lib/ui.sh:203
ui_err()  { local fmt="${1:-}"; shift 2>/dev/null || true; printf "${UI_C_RED}${UI_ICON_ERR}${UI_RESET} ${fmt}\n" "$@" >&2; }
```

实测（sandbox）：

```text
$ bash -c 'set -e; . lib/ui.sh; ui_info "完成 50%"; echo "rc=$?"'
lib/ui.sh: 第 197 行：printf: "\": 无效的格式字符
[消息] 完成 50            <- 消息被截断
[outer=1]                 <- set -e 让整脚本以 1 退出，后面的步骤全部不执行
$ bash -c 'set -e; . lib/ui.sh; ui_info "进度 %s 完成"'
[消息] 进度  完成          <- %s 被当成占位符吃掉，rc=0，静默丢字
```

- 影响：消息里的 `%` 有两个后果：(1) 文本损坏/丢字；(2) 在条件上下文之外调用时 **errexit 直接结束整个脚本**（例如升级/清理进行到一半）。`ui_panel_*`/`ui_panel_kv`/`ui_panel_line`/`ui_panel_stat`/`ui_working` 都是 `%s` 形式，**安全**；危险的只有徽章/纯日志族。当前仓库里没有字面含 `%` 的 `ui_*` 消息（已全库扫描），但动态数据会被拼进格式串，例如 `clean:139 _warn "拒绝清理越界或符号链接缓存目录：$path"`（`_warn` = `ui_warn "$@"`，见 `clean:122-125`）、`clean:225/238`、`sysup:203/217/258`（`_log/_warn/_error` 同样裸转发）。缓存目录名、systemd 单元名、命令 stderr 都可能含 `%`。
- 建议：把徽章族统一改成固定格式串，例如 `printf '%s %s\n' "${UI_ICON_INFO}" "$msg"`，或让函数签名固定为 `ui_info "%s" "$msg"`；同时把“消息不得含裸 %”从注释里的口头约定变成实现保证。
- 确认度：**已确认**（机制实测；触发需要消息含 `%`）

### P2-2 `ui_dwidth/ui_pad` 在非 UTF-8 locale 下按字节计宽，中文/全角/emoji 宽度翻倍

- 位置：`lib/ui.sh:435-457`（`_ui_is_ascii` 385-388、`_ui_strip_ansi` 391-411、`_ui_dwidth_calc` 414-461）
- 触发条件：任何非 UTF-8 生效 locale 的会话，例如 `LC_ALL=C term-menu`、`LANG=C`、`LC_ALL=POSIX`、locale 未配置的 ssh/cron/systemd 环境。C locale 下 bash 的 `${#s}` / `${s:i:1}` 按字节工作，`printf -v code '%d' "'$ch"` 取到的是字节值。
- 证据：实测三组 locale（`t4_dwidth.sh`）：

```text
默认（zh_CN.UTF-8）: 中文=4  🎉=2  👨‍👩‍👧=8  ✔️=2  OSC=8    pad "中文" 6 -> [中文  ]
LC_ALL=C           : 中文=6  🎉=4  👨‍👩‍👧=18 ✔️=6  OSC=8    pad "中文" 6 -> [中文]   <- 少补 2 列
```

对照代码：`lib/ui.sh:439-455` 逐“字符”循环，完全依赖调用方 locale；同库的 `_ui_is_ascii` 与 `_ui_strip_ansi` 反而显式 `local LC_ALL=C`。仓库里 `mirror-update:31` 就有 `export LC_ALL=C`（当前未调用 ui_pad，但同一环境变量会传染给后续所有 `lib/ui.sh` 调用）。
- 影响：`ui_pad`/`ui_panel_kv`/`ui_panel_open`/`ui_wait_key`/`ui_section` 的列对齐全部错位——正是 HANDOFF 第一节要求“只用 ui_pad 对齐”想要避免的问题。
- 建议：在 `_ui_dwidth_calc` 里显式固定 UTF-8 语义：手动按 UTF-8 前导字节解码（不依赖 `${#}`），或临时切到确定的 UTF-8 locale（`local LC_ALL=C.UTF-8`，失败时回退）；并加一条“非 UTF-8 locale”测试。
- 确认度：**已确认**（实测）

### P2-3 `ui_confirm` 在 EOF / 读错误时把空答案当默认值，默认 `y` 即自动同意

- 位置：`lib/ui.sh:656-665`
- 触发条件：非 TTY 或 stdin 被重定向后运行任何默认 y 的确认；`script </dev/null`、cron/systemd/CI 里没有 TTY、以及 `exec 0<&-`。
- 证据：

```bash
# lib/ui.sh:661-664
printf "${UI_YELLOW}%s${UI_RESET} %s " "$prompt" "$hint"
read -r answer || true          # EOF/读错误都被吞掉
answer="${answer:-$default}"   # 空答案 = 回车 = 默认值
[[ "$answer" =~ ^[yY]$ ]]
```

实测：

```text
$ bash -c '. lib/ui.sh; ui_confirm "是否继续?"; echo rc=$?' </dev/null
是否继续? [Y/n] rc=0                       <- 从没读到任何答案，仍然“确认”
$ bash -c '. lib/ui.sh; exec 0<&-; ui_confirm "是否继续?"; echo rc=$?'
lib/ui.sh: 第 662 行：read: 0: 读取错误: 错误的文件描述符   <- 还往 stderr 抛噪声
是否继续? [Y/n] rc=0
$ bash -c '. lib/ui.sh; ui_confirm "是否继续?" n; echo rc=$?' </dev/null
是否继续? [y/N] rc=1                       <- 默认 n 时行为正确
# ui_confirm_word 在 EOF 下返回 1（拒绝），行为正确
```

仓库内默认 `y` 的调用点：`mirror-update:271`、`mirror-update:337`（clean/checkallupdates/quicksave 用的是 n）。EOF 下 `mirror-update:337` 会直接采用探测到的国家并继续 `sudo reflector`，`mirror-update:271` 会 `return 1` 触发全局回退。当前没有“默认 y 守卫高危删除”的调用点，所以还不是 P1，但这是很容易被后续改动引爆的契约。
- 影响：交互式确认在非交互执行时变成自动同意；read 失败还把 bash 错误信息混进界面。
- 建议：`read` 返回非 0 时直接 `return 1`（按未确认处理），或函数入口加 `[[ -t 0 ]] || return 1`。
- 确认度：**已确认**（实测）。附带一条**未确认**观察：带软 INT trap 的脚本里 `read` 是否会被 SIGINT 打断（进而走同一条默认值路径），在 FIFO/pty 沙箱里没能稳定复现（`t8_sigint.sh` 在 `wait` 处超时）；仓库内所有 INT trap 都是 `exit 130`，暂不影响结论。

### P2-4 `maintenance_config_get` 的环境变量覆盖完全绕过校验；非法值进入 sysup 算术求值（实测可执行命令）

- 位置：`lib/config.sh:101-109`（优先级：环境变量 > 配置文件 > 默认值）
- 触发条件：任何被环境变量覆盖的键，且调用方没有二次校验。空字符串也算“已设置”。
- 证据：

```bash
# lib/config.sh:103-104
if [[ -n "$env_name" && -v "$env_name" ]]; then
  printf '%s' "${!env_name}"      # 直接返回，不做 maintenance_config_validate
```

实测（cfg 文件里 `BACKUP_KEEP=4 MIRROR_THREADS=8`）：

```text
empty env override  : BACKUP_KEEP=[]        (MAINTENANCE_BACKUP_KEEP="")
invalid env override: MIRROR_THREADS=[abc]  (MIRROR_THREADS=abc)
```

调用方分化：`checkallupdates:70-71` 和 `mirror-update:39/49` 自己补了正则校验；`sysup:32-34` 没有：

```bash
# sysup:34
SYSUP_MIRROR_MAX_AGE_DAYS="$(maintenance_config_get MIRROR_MAX_AGE_DAYS 30 SYSUP_MIRROR_MAX_AGE_DAYS)"
# sysup:226
local THRESHOLD=$((SYSUP_MIRROR_MAX_AGE_DAYS * 24 * 60 * 60))
```

实测（只用 lib 取回值，再照抄 sysup:226 的表达式）：

```text
value fetched by lib = [a[$(touch /tmp/.../pwned)]]
!!! command executed during arithmetic evaluation     <- bash 算术对变量值递归求值，数组下标里的 $( ) 被执行
SYSUP_MIRROR_MAX_AGE_DAYS=abc -> THRESHOLD=0          <- 非法值不报错，静默把阈值变 0（每次都提示镜像源过期）
SYSUP_MIRROR_MAX_AGE_DAYS=   -> THRESHOLD=0
```

- 影响：(1) 环境变量可静默关闭/扭曲配置语义（空值、非数字、超范围）；(2) 在 sysup 这类把值送进 `$(( ))` 的地方，bash 算术的递归求值让**环境变量的内容可以执行任意命令**（前提是能控制该进程的环境，属本地/包装器威胁模型，但确属“恶意值 → 命令执行”这一类）；(3) `SYSUP_*` 覆盖未在 README/config.example 记录。
- 建议：`maintenance_config_get` 增加可选校验（或新增 `maintenance_config_get_int KEY default env min max`），环境变量与配置文件走同一套 `maintenance_config_validate`；调用方禁止把未校验值直接放进 `$(( ))`。
- 确认度：**已确认**（实测，含命令执行）

### P2-5 `ui_panel_stat err` 被计成“缺失”，汇总行把查询失败显示成“缺失”

- 位置：`lib/ui.sh:613-623`（`err` 分支第 619 行）、`lib/ui.sh:636-639`（`ui_tally_summary`）
- 触发条件：任何用 `ui_panel_stat err` 报“查询失败”的检查脚本；汇总列只有 正常/注意/缺失 三列。
- 证据：

```bash
# lib/ui.sh:619
err)  icon="$UI_ICON_ERR";  color="$UI_C_RED";      UI_N_MISS=$(( ${UI_N_MISS:-0} + 1 )) ;;
# lib/ui.sh:637-638
printf "... %s 正常 ... %s 注意 ... %s 缺失\n" "${UI_N_OK:-0}" "${UI_N_WARN:-0}" "${UI_N_MISS:-0}"
```

实测：

```text
[成功] a   [注意] b   [缺失] c   [错误] d
  [成功] 1 正常     [注意] 1 注意     [缺失] 2 缺失      <- 一个是 err，却报“缺失”
N_OK=1 N_WARN=1 N_MISS=2
```

调用点（err 语义都是“查询失败/无法判定”）：`post-update-check:94,109,133,147,150,168,187,195,200`、`storage-health:89,94,99,108,124,125,178`、`pacnew-check:74`、`quicksave:226`、`sysup:363,364`；它们都在 `ui_tally_summary`（post-update-check:205、storage-health:263、pacnew-check:116 等）里汇总。
- 影响：违反 HANDOFF 铁律 6/7（“查询失败不能等同于结果为空/缺失”）。`ui_tally_status` 的 strict 退出码不受影响（err 已计入 MISS，仍返回 1），所以这是**报告正确性**问题：用户会去追“缺少什么文件”，而实际是查询失败。
- 建议：新增 `UI_N_ERR` 与第四列（或在“缺失”列末标注“(含 N 项错误)”），保持 `ui_tally_status` 语义不变。
- 确认度：**已确认**（实测）

### P2-6 `ui_dwidth/ui_pad` 的公开 API 强制每次调用开子 shell，memo 缓存被架空；快照表实测 872 ms

- 位置：`lib/ui.sh:463-466`（`ui_dwidth` 用 `printf` 输出到 stdout）、`lib/ui.sh:542-549`（`ui_pad`）；缓存 `_UI_DWIDTH_CACHE` 在 380 行声明、459 行写入，**只在同一进程内有效**。
- 触发条件：调用方用 `$(ui_dwidth ...)` / `$(ui_pad ...)` 取值——这是唯一的取值方式，仓库里所有调用点都是这样（term-menu:894,901,911-915,1382；ui_panel_open:572；ui_wait_key:690；ui_panel_kv:603）。
- 证据（`t7_perf.sh`，本机实测）：

```text
200 x _ui_dwidth_calc (同进程、命中缓存)   :   7 ms   (0.035 ms/次)
200 x $(ui_dwidth "快照 …中文…")          : 138 ms   (0.69 ms/次，约 20 倍)
200 x $(ui_dwidth "abcdef")               : 151 ms   <- 纯 ASCII 也要付 fork 成本
200 x $(ui_pad …)                         : 147 ms
38 rows x 5 $(ui_pad)                     :  12 ms
38 rows 逐字符 $(ui_dwidth)（30 字 CJK）   : 872 ms   <- 一屏“查看快照”接近 1 秒
```

放大点就是 `term-menu` 的快照表：`term-menu:894-905 compact_text` 在描述超宽时**逐字符** `$(ui_dwidth "$ch")`，`term-menu:909-916 _snap_row` 每行再 5 次 `$(ui_pad)`，`term-menu:949` 每行调用一次 `compact_text`（38 行 × 约 30 字符 ≈ 1140 次子 shell）。
- 影响：正是用户抱怨的“读取/刷新慢”的主要来源——纯 bash 宽度实现本来是为了避免每个调用点 fork awk（注释 378-379），但公开 API 又要求子 shell 取结果，优化在真实调用模式下失效。
- 建议：把 `_ui_dwidth_calc` + `UI_DWIDTH_RESULT` 提升为正式公开 API（或加 `ui_pad_var`/`ui_dwidth_var`），文档示范“先算一次、同进程复用”；截断逻辑改成一次遍历而不是逐字符 `$( )`；`ui_panel_open`/`ui_wait_key` 内的 `$(ui_dwidth)` 同样可直接调用内部函数。
- 确认度：**已确认**（实测计时）

### P2-7 维护锁文件名带 uid：直接以 root 运行与普通用户运行不互斥

- 位置：`lib/ui.sh:217`（`lock_uid="${SUDO_UID:-${PKEXEC_UID:-$(id -u)}}"`）、`lib/ui.sh:230`（`lock_file="$lock_home/.cache/maintenance/maintenance-${lock_uid}.lock"`）
- 触发条件：两条维护链路以不同“有效 uid”进入：普通用户（`id -u` = 1000，锁 `maintenance-1000.lock`）与直接 root 会话（`su -`、root shell、root 运行的 systemd 单元/脚本；`SUDO_UID`/`PKEXEC_UID` 为空 → 0，锁 `maintenance-0.lock`）。`sudo cmd` / `pkexec` 会设置对应变量，因此日常 `sudo quickload` 与用户侧仍共享同一把锁。
- 证据：用 PATH 桩 `id -u` 分别返回 0 / 1000，同一 HOME 实测：

```text
as uid 0    rc=0 lock=maintenance-0.lock
as uid 1000 rc=0 lock=maintenance-0.lock maintenance-1000.lock   <- 两个文件可同时被 flock 持有
```

另外 `t6_lock.sh` 实测：同进程重复 acquire 幂等（rc=0，fd 不变）；受控子进程继承成功；伪造 `MAINTENANCE_LOCK_HELD=1 UI_MAINTENANCE_LOCK_FD=9` 被拒（rc=75）；释放后可再获取。这些行为都正确。
- 影响：README/HANDOFF 承诺“修改系统状态的脚本共享同一把 flock 维护锁”，但在 root 直连场景下不成立：可同时跑两个会写 Snapper/Btrfs/pacman 状态的维护流程（例如用户 quicksave 与 root sysup/clean 并发）。
- 建议：锁路径改为与会话无关的固定位置（用固定的 HOME 解析规则：优先 `SUDO_UID`/`PKEXEC_UID`，否则用 `getent passwd ${EUID}` 的 HOME），或在锁文件里记录维护者并让 root 侧额外检查用户侧锁。
- 确认度：**已确认**（桩实测 + 代码铁证）

### P2-8 `ui_tmp_register/ui_tmp_cleanup`：子 shell 里登记 = 永远不清理

- 位置：`lib/ui.sh:158-188`（`UI_TMP_OWNER_PID` 159、`ui_tmp_register` 161-164、`ui_tmp_cleanup` 182-188 的 BASHPID 守卫）
- 触发条件：在 `( ... )`、`$( ... )`、管道右端、后台 `& ` 里调用 `ui_tmp_register`（登记的是子 shell 的数组副本，父 shell 看不见）；或者在子 shell 里调用 `ui_tmp_cleanup`（守卫直接 `return 0`）。
- 证据（`t5_tmp.sh` 实测）：

```text
== cleanup inside a subshell (BASHPID guard) ==
child: own cleanup skipped (file still there)
parent registry after child: 0
LEAK: temp registered in child cleaned by nobody        <- 两个清理机制互相“礼让”
== register inside command substitution ==
LEAK: temp registered in a subshell cleaned by nobody
```

同时实测正确的部分：注册表对**含空格和含换行**的路径都能原样保存并删除（`${arr[@]+"${arr[@]}"}` 惯用法安全）、空注册表在 `set -u` 下 `ui_tmp_cleanup` 返回 0、`ui_tmp_discard` 会删除任何传入路径（含未登记的）。
- 影响：临时文件（可能含备份清单、错误输出等）静默残留在 `/tmp`。仓库现有调用点（`backup-restore:256,282,368,397`、`log-check:46`、`term-menu:1010`）都在主 shell 里注册，所以目前**没有实际泄漏**；但注释 153-156 只提醒了 `$()` 一种情况，任何“把清理包进管道/子 shell”的后续改动都会无声漏掉。
- 建议：把登记表升级为进程组可见的清单（例如 `${XDG_RUNTIME_DIR}/maintenance-tmp.${MAIN_SHELL_PID}`，用 flock 保护），子 shell 也能登记、父 shell 统一清理；至少让 `ui_tmp_register` 检测 BASHPID 不一致时警告一次。
- 确认度：**已确认**（实测）

### P2-9 配置解析失败的“粘性”标志：第二次 load 返回 0，且第一批已解析的值仍可读

- 位置：`lib/config.sh:62-63`（`MAINTENANCE_CONFIG_LOADED=1` 在读取文件**之前**置位）、`lib/config.sh:96-97`（校验失败前已写入前面的键）
- 触发条件：同一 shell 内调用 `maintenance_config_load` 两次，或调用方预置 `MAINTENANCE_CONFIG_LOADED=1`。
- 证据（`t3_config.sh` 实测）：

```text
== failed load leaves sticky flag / partial values ==
config: "BACKUP_KEEP=4\nUNKNOWN=1\n"
first load rc=1
second load rc=0 (flag=1)        <- 错误被“记住成功”，后续调用者看不到失败
partial value still readable: BACKUP_KEEP=[4]

== caller pre-sets MAINTENANCE_CONFIG_LOADED=1 ==
load rc=0 (config silently skipped); BACKUP_KEEP=[3]   <- 配置被静默忽略
```

- 影响：库语义是“加载失败要能被重试/被感知”，实际是“失败一次后永久装作已加载”，并把半个配置暴露给 `maintenance_config_get`。仓库内所有调用方都是 `maintenance_config_load || exit 2`（backup-restore:10、cache-clean:13、checkallupdates:24、clean:28、mirror-update:28、offsite-backup:10、offsite-backup-schedule:10、sysup:31），所以目前不会误用半配置；但 `tests/run` 会把多个脚本 source 进同一个 shell（例如 tests/run:92），后续复用该函数就会踩。
- 建议：把 `MAINTENANCE_CONFIG_LOADED=1` 移到解析成功之后；失败时回滚本次已写入的键（或先写局部数组、成功后再整体赋值）。
- 确认度：**已确认**（实测）

---

## P3 级

### P3-10 数值校验没有上界，bash 整型回绕可绕过 `MIRROR_THREADS ≤ 32`

- 位置：`lib/config.sh:30-33`
- 触发条件：`MIRROR_THREADS` 写成 > 2^64 的正整数（正则 `^[1-9][0-9]*$` 通过），`(( value <= 32 ))` 在 bash 中以 64 位回绕后可能变成 ≤ 32。
- 证据（实测）：

```text
$ bash -c 'v=18446744073709551648; [[ "$v" =~ ^[1-9][0-9]*$ ]] && (( v <= 32 )) && echo PASS'
PASS                       # 18446744073709551648 - 2^64 = 32
$ printf 'MIRROR_THREADS=18446744073709551648\n' > cfg; maintenance_config_load; echo rc=$?
load rc=0
value=[18446744073709551648]     <- 原样接受，随后传给 reflector --threads
```

- 影响：`mirror-update:48-51` 会带着这个字符串执行 `reflector --threads 18446744073709551648`（reflector 被喂一个荒谬的并发上限）；同族的 `BACKUP_KEEP` 等键没有上界，在 `offsite-backup:341 for ((i = KEEP; ...))` 这类 64 位循环边界里也可能回绕。
- 建议：数值键统一限长（如 `${#value} <= 6`）或先做长度检查再 `10#` 转换；给出“取值范围”错误提示。
- 确认度：**已确认**（实测表达式回绕 + 真实 parser 接受）

### P3-11 `_ui_strip_ansi` 只处理 CSI：OSC 与 ZWJ/变体选择符计宽错误

- 位置：`lib/ui.sh:391-411`（只识别 `ESC [`）、`lib/ui.sh:442-456`（宽度表）
- 触发条件：字符串含 OSC（`\e]0;title\a`、超链接）、ZWJ emoji、VS16。
- 证据（实测）：

```text
OSC title "\e]0;t\aabc" -> 8   （应为 3：整个 OSC 序列应计 0 列）
ZWJ family "👨‍👩‍👧"      -> 8   （终端通常渲染 2 列）
check+VS16 "✔️"          -> 2
```

- 影响：带 emoji/OSC 的说明、日志标题仍会错位；`ui_wrap`（475-538，第 509-514 行同样只处理 CSI）也会把 OSC 当正文参与换行。
- 建议：扩展转义处理到 OSC（`ESC ] ... BEL|ESC \\`）与 `ESC (` 类两字符序列；给 ZWJ(U+200D) 与 VS15/16(U+FE0E/FE0F) 加 0 宽规则。
- 确认度：**已确认**（实测）

### P3-12 `ui_section` 用字节差估算标题宽度，且每次 fork 一个 `wc`

- 位置：`lib/ui.sh:328-346`（估算 333-337，`bytes=$(LC_ALL=C; echo -n "$title" | wc -c)` 在 336）
- 触发条件：标题含非 CJK 的多字节字符。
- 证据（实测，终端宽 78）：

```text
title=中文标题   rule_dwidth=78   ✓
title=ASCII      rule_dwidth=78   ✓
title=✔ 勾       rule_dwidth=77   ✗（✔ 3 字节 1 显示列，被按 2 列估算）
```

- 影响：分节线长度差 1-2 列（轻微错位）；每次调用多一个子 shell + `wc` 进程。
- 建议：直接改用 `_ui_dwidth_calc`/`UI_DWIDTH_RESULT`（同进程、零 fork），删掉 `wc` 估算。
- 确认度：**已确认**（实测）

### P3-13 `ui_status_line` 每次 8 个外部进程；`ip` 缺失时谎报“离线”

- 位置：`lib/ui.sh:774-811`（meminfo 两处 awk 791-792、`df|tail|tr` 802、`ip|awk` 806、`date` 810）
- 触发条件：每打开一次 fzf 菜单（term-menu:664、checkallupdates:746、migration-pack:889 各调用一次）。
- 证据（PATH 桩计数实测）：

```text
ui_status_line external execs: 8  -> awk awk tail tr df ip awk date
```

- 影响：(1) 每次菜单重绘 8 次 fork（非每帧，但可省）；(2) 799 行附近 `load="?"`、`mem_line="?"`、`disk="?"` 都有缺失兜底，唯独 806-807 行 `iface` 为空时写死 `离线`——`ip` 不存在或权限受限时会显示“没有默认路由（离线）”，违反项目“缺失≠空结果”的规则。
- 建议：缓存或合并探测（例如直接读 `/proc/net/route` + `/proc/meminfo`）；网卡探测失败时显示 `?`/`未知`。
- 确认度：**已确认**（计数实测 + 代码铁证）

### P3-14 `ui_cols/_ui_rule_width` 每次调用 fork `tput` 且不缓存

- 位置：`lib/ui.sh:280-302`
- 触发条件：每个 `ui_hr/ui_section/ui_banner/ui_panel_open/ui_panel_close/ui_wait_key` 都经 `$( )` 再调一次 `_ui_rule_width` → 一次 `tput` + 两次 fork。
- 证据（PATH 桩实测一次“panel 屏”）：

```text
_ui_rule_width + ui_hr + ui_panel_open/line/close + ui_banner + ui_section -> 6 次 tput
```

- 影响：高频输出路径上的固定开销；终端尺寸在一次运行中极少变化。
- 建议：把宽度缓存到变量（或按 SIGWINCH 失效），提供 `ui_cols_refresh`。
- 确认度：**已确认**（实测）

### P3-15 sudo 保活：主进程被 SIGKILL 后留下永久保活循环

- 位置：`lib/ui.sh:118-137`（后台循环 131-134）
- 触发条件：调用方没来得及执行 `ui_sudo_keepalive_stop`，例如进程被 SIGKILL（OOM/强杀/“强制退出”）；`sysup:205`、`clean:209` 只挂了 `EXIT` trap。
- 证据（`t10b_keepalive.sh`，`sudo`/`sleep` 全用 PATH 桩，stub sudo 每次调用写日志）：

```text
signal=TERM  wrapper_rc=143  sudo_calls: before=8  after=8  still_alive=no    <- EXIT trap 正常收尾
signal=KILL  wrapper_rc=137  sudo_calls: before=16 after=25 still_alive=yes   <- 保活子 shell 变孤儿，继续每 60s 调 sudo
```

- 影响：一个永不退出的后台子 shell 每 60 秒执行一次 `sudo -n true`；在 tty 时间戳仍有效时会持续续期管理员凭据，同时是进程泄漏。
- 建议：循环里加自终止判据（`kill -0 "$MAIN_PID"`、检查 `PPID` 变化、或让循环读一个主进程持有的管道，父进程退出即 EOF）。
- 确认度：**已确认**（实测）

### P3-16 保活的二次启动只看 PID 非空；停止依赖 `pkill`（procps）

- 位置：`lib/ui.sh:121`（`[[ -z "$UI_SUDO_KEEPALIVE_PID" ]] || return 0`）、`lib/ui.sh:141`（`pkill -TERM -P ... || true`）
- 触发条件：保活进程已退出（例如被自己的清理脚本杀掉）后再调 `ui_sudo_keepalive_start`：函数直接返回 0，调用方以为保活已就绪；系统缺少 `pkill` 时 `ui_sudo_keepalive_stop` 只杀子 shell。
- 影响：保活静默失效 → 长步骤里 sudo 时间戳过期，交互式终端会突然弹密码提示；依赖命令缺失被 `|| true` 吞掉。
- 建议：`start` 里先 `kill -0 "$UI_SUDO_KEEPALIVE_PID"` 验证；`stop` 不要依赖 `pkill` 可用性（缺失时打印一次警告）。
- 确认度：**高度可疑**（`pkill` 缺失与 PID 复用分支未实测，代码铁证）

### P3-17 `UI_FORCE_COLOR=0` 仍然强制上色

- 位置：`lib/ui.sh:33-35`（任何非空值 `return 0`）
- 触发条件：用户/包装器写 `UI_FORCE_COLOR=0` 想关闭颜色。
- 证据（实测）：

```text
$ UI_FORCE_COLOR=0 bash -c '. lib/ui.sh; ui_info hi' | cat -v
^[[38;2;116;199;236m...^[[0m hi        <- 仍然是彩色
（同环境下 NO_COLOR=0 会正确关闭；空串 NO_COLOR 按规范不算“设置”，行为正确）
```

- 影响：轻微；与常见“0=false”直觉冲突。
- 建议：`[[ "$UI_FORCE_COLOR" == "0" ]] && return 1` 或在文档写明“任何非空值都表示开启”。
- 确认度：**已确认**（实测）

### P3-18 `$HOME` 未设置时 `set -u` 直接报 unbound variable

- 位置：`lib/config.sh:60`（`local file="${MAINTENANCE_CONFIG_FILE:-$HOME/.config/maintenance/config}"`）、`lib/config.sh:93-94`（`~/` 展开）
- 触发条件：`env -u HOME script`（精简 systemd 单元/容器/特殊包装器）。
- 证据（实测）：

```text
$ env -u HOME bash -c 'set -euo pipefail; source lib/config.sh; maintenance_config_load; echo rc=$?'
lib/config.sh: 行 60: HOME: 未绑定的变量      （脚本以 1 退出，没有可读的错误提示）
```

- 影响：环境异常时得到 bash 内部报错而不是“缺少 HOME，无法定位配置”。
- 建议：`local home="${HOME:-}"`，为空时给出明确提示（或直接返回无配置）。
- 确认度：**已确认**（实测）

### P3-19 断链的配置符号链接被当作“没有配置”静默忽略

- 位置：`lib/config.sh:64`（`[[ -e "$file" ]] || return 0`）
- 触发条件：`~/.config/maintenance/config` 是断链符号链接（例如指向未挂载的磁盘）。
- 证据（实测）：`load rc=0 (broken symlink treated as no config)`，`BACKUP_KEEP` 落到默认值 3。
- 影响：用户以为配置生效，实际全部回退默认值（BACKUP_TARGET 变空、保留数变 3、超时变默认），且没有任何提示。
- 建议：改用 `[[ -e "$file" || -L "$file" ]]`，符号链接存在但目标不可达时明确报错。
- 确认度：**已确认**（实测）

### P3-20 `BACKUP_ON_CALENDAR`/`BACKUP_TARGET` 校验过弱

- 位置：`lib/config.sh:44-47`（只拒绝空、换行、回车）、`lib/config.sh:52-55`（只要求非空）
- 触发条件：配置里写 `BACKUP_ON_CALENDAR=*:0/5;root`、`BACKUP_TARGET=/mnt/a;reboot`、`BACKUP_TARGET=/mnt/a#b`。
- 证据（实测）：三者都 `rc=0` 被接受并原样返回。
- 影响：`BACKUP_ON_CALENDAR` 会写进 systemd timer 的 `OnCalendar=`（offsite-backup-schedule:324），错误值要等到 `systemctl --user daemon-reload/start` 才暴露（该脚本有回滚）；`BACKUP_TARGET` 会当路径使用/写进 unit（`systemd_quote` 已转义，offsite-backup-schedule:316-317，无注入风险）。换行已被拒绝，因此不构成 unit 文件行注入。
- 建议：`BACKUP_ON_CALENDAR` 用 systemd 日历白名单字符集校验（或调用 `systemd-analyze calendar` 预检）；`BACKUP_TARGET` 校验为绝对路径且拒绝 `;`/`$`/`#` 等。
- 确认度：**已确认**（实测）

### P3-21 `ui_fzf_base` 几乎无人使用，统一契约实际靠调用方自觉

- 位置：`lib/ui.sh:739-760`
- 触发条件：维护者以为“统一 fzf 参数”已被封装。
- 证据：全库 grep，`ui_fzf_base` 只有 `quickload:751` 一个调用点；`term-menu`、`checkallupdates`、`migration-pack`、`btrfs-scrub`、`offsite-backup-schedule` 等各自手写颜色、`--cycle`、header。另外 `--border-label=${label}` 直接吃调用方字符串，label 里出现换行会被 `mapfile` 拆成两个参数。
- 影响：HANDOFF 要求的“所有独立 fzf 选择器都要有 --cycle / 统一提示”无法由库保证；未来新增选择器容易漏。
- 建议：把 fzf 调用收敛到一个真正的包装函数（内部 `fzf "${opts[@]}"` 并统一处理 Esc 退出码 130/10），label 做换行/制表符清洗。
- 确认度：**已确认**（grep 计数 + 代码铁证）

### P3-22 `ui_wrap`：超长 ASCII 词不换行、Tab 按 1 列计

- 位置：`lib/ui.sh:475-538`（`flush_word` 499-503；Tab 落入 515 行普通分支）
- 触发条件：preview 文本含长 URL/长路径，或含 Tab。
- 证据（实测）：

```text
printf 'AAAA…(60 个)' | ui_wrap 20   -> 输出一行 60 列（不硬断）
printf 'a\tb\n' | ui_wrap 80       -> a^Ib    （Tab 原样输出，宽度按 1 计）
```

- 影响：fzf preview 里长词会溢出（term-menu:700 `--preview-window=...,wrap` 会兜底换行，但 `ui_wrap` 自己的宽度计算不准）；Tab 造成实际列数与计算不符。CJK 换行与 ANSI 颜色保持实测正确。
- 建议：对超过 WIDTH 的单词硬断行；把 Tab 展开为空格（或按 8 列计）后再算宽度。
- 确认度：**已确认**（实测）

### P3-23 `config.example` 未说明不支持行内注释

- 位置：`config.example:1-18`（说明只在 1-2 行），行为在 `lib/config.sh:73`（只有整行以 `#` 开头才算注释）
- 触发条件：照着常见 ini 习惯写 `BACKUP_KEEP=3   # 保留三份`。
- 证据（实测）：

```text
config: "BACKUP_KEEP=3   # keep three"
maintenance 配置错误: BACKUP_KEEP 必须是正整数
rc=1                              <- 报“必须是正整数”，看不出真正原因是行内注释
```

- 影响：错误信息误导（用户会去检查数字而不是注释）；README:236 也只说“只接受已知的 KEY=VALUE”。
- 建议：在 `config.example` 顶部注明“注释必须独占一行”，或解析器支持去除未被引号包裹的行尾注释；数值校验失败时把原始值一并打印。
- 确认度：**已确认**（实测）

---

## 已检查、未发现问题的部分（供 Lead 汇总）

- **`set -e` 与 `cond && action` 惯用法**：`ui.sh` 里 `(( pad < 0 )) && pad=0`、`_ui_rule_width` 的 `(( gap >= cols )) && gap=0`、`ui_pad`/`ui_wait_key`/`ui_panel_open` 的同类写法，在 `set -euo pipefail` 下实测不会触发 errexit（`t1_sete.sh` 全流程到达 END、exit 0）。未发现“`local` 吞返回码”“`echo`/`printf` 覆盖返回码”的实际案例。
- **`ui_tmp_discard/ui_tmp_cleanup` 的路径处理**：含空格、含换行的路径都能正确登记与删除；空注册表在 `set -u` 下安全。
- **`ui_maintenance_lock_acquire`**：同进程重复获取幂等；受控子进程能继承（子进程拿不到 `UI_MAINTENANCE_LOCK_OWNED`，无法误释放父锁）；伪造 `MAINTENANCE_LOCK_HELD`+fd 被拒（75）；`flock` 缺失返回 127；锁目录创建失败返回 73；释放后重新获取正常。
- **`lib/config.sh` 解析器**：命令替换值不会被执行（`BACKUP_TARGET=$(touch ...)` 实测无副作用）；引号配对/重复键/未知键/非法数值/CRLF/无结尾换行/前导空格/目录当配置文件 都按预期报错或接受；`~` 展开支持含空格的 HOME 且支持引号包裹。
- **颜色决策**：非 TTY 关闭；pty 下（`env -u NO_COLOR`）实测开启并输出 24 位色；`NO_COLOR=0` 按规范关闭。
- **`ui_panel_*`/`ui_panel_stat`/`ui_working` 的格式串**：都用 `%s` 传正文，动态数据安全（这也是 P2-1 的修法样板）。
- **`config.example` 与 `lib/config.sh:15-25` 的白名单**：13 个键完全一致；`migration-profile.example` 的格式由 `migration-pack` 校验（不在 lib/ 范围内），本次未发现与 lib 相关的边界问题。
- **`ui_wait_key`**：非 TTY 立即返回（设计如此）；pty 下等待按键并恢复光标；`ui_confirm_word` 在 EOF 下正确拒绝。

## 备注 / 环境限制

- 本机 ambient `NO_COLOR=1 TERM=dumb`，非 pty 实测都在“无颜色 + 默认 80 列”分支；pty 用例用 `script -qec` 并显式去掉 `NO_COLOR`。
- `t8_sigint.sh`（SIGINT 打断 `ui_confirm` 的 read）在 FIFO 沙箱里 `wait` 超时，未能拿到结论，已在 P2-3 标注为未确认观察；相关进程已清理。
- 未执行任何真实 sudo、systemctl、snapper、btrfs、pacman 写操作；全部外部命令依赖都用 PATH 桩。
