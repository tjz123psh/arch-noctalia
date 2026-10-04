# 数据/破坏性路径审查 findings（task-3 · data-safety）

审查范围（只读）：quicksave、quickload、clean、cache-clean、btrfs-scrub、backup-restore、
offsite-backup、offsite-backup-schedule、migration-pack。
方法：逐行读代码 + 在 /tmp 沙箱用命令桩（snapper/findmnt/lsblk/tar）跑只读或等价路径；
不修改工作区任何文件，也不执行真实删除/恢复/备份/scrub/升级。

环境事实（实测）：Arch / btrfs（/ = /dev/nvme0n1p7[/@]，/home = [/@home]）、snapper 0.13.1、
当前只有 root+home 各一个快照（ID 185，同一 maintenance_batch）、无外部备份盘。

发现统计：P1 × 1、P2 × 8、P3 × 10（共 19 条）；其中"已确认（实测或代码铁证）"16 条、"高度可疑"3 条
（DS-10 / DS-16 / DS-17）。按主文件归属：clean 3、quicksave 3、migration-pack 3、backup-restore 2、
offsite-backup 2、offsite-backup-schedule 2、quickload 2、btrfs-scrub 1、cache-clean 1（DS-03/DS-05/DS-14 同时涉及多个文件）。
文末附"已核对但判定不是缺陷"的清单与复现材料位置。

---

## P1

### DS-01 clean 深度清理的"最近一套批次"护栏可能选中不完整/单配置批次，把真正的成套回滚点删掉
- 文件：`clean:427-449`（keep_batch 选取）、`clean:472-475`（保留判断）、`clean:478`（删除）
- 触发：`clean all`（含 term-menu「深度清理」）时，全局最新批次不是"每个 Snapper 配置都有一套"的完整批次。例如：
  1) 之后单独跑过 `quicksave -c home`（生成 home 单配置批次，时间戳更新）；
  2) 某次 quicksave 在 root 建好后失败、回删又不完整（`quicksave:329-339`）留下单配置快照。
- 证据（代码）：

```bash
  clean:430-444
  keep_batch=""
  SNAP_BATCH_SCAN="$(mktemp)"
  while IFS="$SNAP_SEP" read -r conf _subvolume; do
    sudo snapper --csvout --separator "$SNAP_SEP" -c "$conf" list --columns number,userdata 2>/dev/null || true
  done <<< "$snap_config_rows" > "$SNAP_BATCH_SCAN"
  keep_batch="$(awk -F "$SNAP_SEP" '
    { if (match($2, /maintenance_batch=[^,]+/)) { b = substr($2, RSTART + 18, RLENGTH - 18); if (b > best) best = b } }
    END { if (best != "") print best }' "$SNAP_BATCH_SCAN")"
```

  选的是**所有配置里字典序最大**的批次，从不检查该批次是否成套（root 与 home 是否都有）。
  实测（同一段 awk，喂合成行；US = 0x1F 分隔符）：

```
  $ printf '%s\n' "185<US>maintenance_batch=20260905T150150.566936098-3155465" \
                   "186<US>maintenance_batch=20260906T090000.000000000-999" | awk -F "$(printf '\x1f')" '<same as above>'
  keep_batch=20260906T090000.000000000-999      # 只有 home 有这批；root 的成套批次 20260905 会被删
```

  `clean:472` 只按子串保留：`[[ "$snap_userdata" == *"maintenance_batch=$keep_batch"* ]]`
- 影响：README:80-81 承诺"保留最近一套 maintenance_batch 快照，也就是最近一次更新前的回滚点"，
  在以上场景会退化为只保留半套；剩余批次不完整后，`quickload` 的"全部还原"再也选不到完整批次
  （`quickload:602-614` 要求每个配置都有该 batch）。
- 建议：复用 `quickload:565-622` 的"完整批次"判定：先在最新批次里找每个配置都在的那一套再保留；
  找不到完整批次时中止深度清理而不是猜。输出里写明保留的是哪个批次、覆盖哪些配置。
- 确认度：**已确认**（代码逻辑铁证 + 合成数据实测；未对真实快照执行删除）

---

## P2

### DS-02 backup-restore --apply-home 会把 $HOME 自身的权限/时间戳改成 staging 目录的
- 文件：`backup-restore:339`（STAGE="$(mktemp -d ...)" → 0700）、`backup-restore:505-524`（应用段）、`backup-restore:518-519`
- 触发：`backup-restore --source ~/migration --apply-home`（独立 v2 迁移包；v2 的 payload 归档无 `./` 根条目，
  staging 保持 mktemp 的 0700）。
- 证据（用与脚本完全相同的一条命令在 /tmp 复现；脚本自己的 dry-run 预览也已暴露这一行）：

```
  $ mktemp -d → 700 ；tar 解 v2 payload（成员 d1/…，无 ./）→ STAGE 仍 700
  $ HOME before: 755
  $ rsync -a --no-owner --no-group -- "$STAGE/" "$HOME/"      # = backup-restore:518
  $ HOME after : 700
  $ rsync -a ... --dry-run --itemize-changes → ".d...p..... ./"     # 权限会被改写
  真实预览（backup-restore 生成的 plan/home-changes.txt 第一行）：".d..tp..... ./"
```

  offsite `set-*` 路径（归档由 `-C <snapshot> .` 生成，含 `./` 成员）会把 STAGE 模式覆盖成备份里 HOME 的模式，
  因此同样可能把当前 HOME 改成备份里的权限（可能放松也可能收紧）。
- 影响：apply 会改动 $HOME 自身的 mode 与 mtime（未在 README/帮助里声明）；0700 收紧后依赖他人遍历 HOME 的服务会受影响。
- 建议：apply 前记录 `stat -c '%a %y' "$HOME"`，rsync 后 `chmod` / `touch -d` 还原；或对根条目单独处理。
- 确认度：**已确认**（等价命令实测 + 真实预览计划证据）

### DS-03 同一归档被反复全量解压（N+1），是"读取/校验慢"的主因
- 文件：
  - `migration-pack:583`（整包列一次）+ `migration-pack:589-595`（**每个 include 再整包列一次**）
  - `migration-pack:723-732` + `migration-pack:738-752`（v1：manifest 每一行一次 `tar -tzf`）+ `migration-pack:799-815`（固定 6 次关键项检查）
  - `backup-restore:464`（migration-pack --verify）、`backup-restore:466`（路径清单）、`backup-restore:316-317`（体积估算）、`backup-restore:341`（解包）
- 触发：`migration-pack --check/--verify <完整包>`、`backup-restore --source <完整 v2 包>`（恢复前必须先看的预览）、`offsite-backup` 的 `verify_set`。
- 证据（沙箱用 `tar` 桩记录调用；payload 101 MB / 5 个 include）：

```
  migration-pack --check <pack>     → tar --zstd -tf 调用 6 次 = 1(整包) + 5(每 include 一次)
  migration-pack --verify <v1pack>  → tar -tzf 调用 9 次 = 1 + 2(manifest 行) + 6(固定检查)
  backup-restore --source <pack>    → 同一归档被完整读取 9 次
     (verify 6 次 + 路径清单 1 + 体积估算 1 + 解包 1)
  实测单次整包列出：101 MB = 53 ms（约 0.52 ms/MB）
```

  量化到本机 25 GB HOME：单次列出约 13 s；默认 profile 有 10 个 include，则
  `migration-pack --check` 约 11 次约 **2.5 分钟**，`backup-restore` 预览约 14 次约 **3 分钟**
  （HANDOFF 记录的"约 115 秒验包"与此量级一致）。`backup-restore` 还会额外做一次 `sha256sum -c` 全量读。
- 影响：用户感知就是"读取/刷新慢"，而且每次校验都在重复做同样的事；时间与 SSD 寿命双重浪费。
- 建议：整包只列一次，落成集合后用 `grep -Fx` / `comm` 与 `payload/include-paths.txt`（v2 已生成 archive-paths.txt）比对；
  v1 同理只列一次清单再比对；估算与解包合并（`tar --totals` 或解包后 `du`）。
- 确认度：**已确认**（stub 计数 + 实测耗时）

### DS-04 clean 深度清理逐条 `sudo snapper delete`（N+1 进程），且不检查 snapper 实际是否删除
- 文件：`clean:451-497`（尤其 `clean:478-485`）
- 触发：`clean all`，快照数量多时（每配置 6 个 ID 就 6 次 `sudo` + `snapper` 进程）。
- 证据：

```bash
  clean:478   if sudo snapper -c "$conf" delete "$snap_id" >/dev/null 2>&1; then
  clean:481       _item "已删除快照" "...ID $(ui_pad "$snap_id" 4) ..."
```

  对照：`quicksave:271` / `quicksave:292` 走批量 `snapper -c <conf> delete id1 id2 ...`；
  上游 `client/snapper/cmd-delete.cc`（openSUSE/snapper master）确认 `while (get_opts.has_args())` 支持多参数与区间
  （本机 man 页只写 `number | number1-number2`，是文档滞后；本机二进制含 "Command 'delete' needs at least one argument."）。
  另一个更要紧的点：snapper 对"当前系统/已挂载/下次挂载"的快照是**静默跳过**——
  `filter_undeletables()` 只往 stderr 打印并 `nums.erase()`，整体仍返回 0；这里 `2>&1` 把提示丢掉，
  于是会打印"已删除快照"，实际什么都没删，最终还能报"所有指定的 Btrfs 快照已彻底清理"。
- 影响：性能（N 次 fork+sudo）；以及删除结果误报（用户以为快照已清空，`snapper list` 里还在）。
- 建议：按配置一次性 `snapper delete "${ids[@]}"`（已验证支持）；保留 stderr 并区分"跳过"与"失败"，
  用删除前后的 `snapper list` 计数校验结果。
- 确认度：**已确认**（上游源码 + 本机二进制字符串 + 代码；未执行真实删除）

### DS-05 非交互高风险操作缺少确认时返回 0 而不是 README 契约的 2
- 文件：`quicksave:267` / `quicksave:287`（`-del`，默认 root）、`clean:182` / `clean:185`、`cache-clean:161`（调用点 `cache-clean:363`）
- 触发：stdin 不是 TTY（cron/管道/`</dev/null`）且没有 `--yes/-y`：
  `quicksave -del 185`、`clean`、`cache-clean --safe`。
- 证据（实测，全部 exit 0；ui.sh:671-678 的 `read -r answer || true` 在 EOF 时得到空串 → 视为"已取消"）：

```
  $ ./quicksave -del 185 </dev/null   → exit=0  "已取消删除"（snapper 桩日志中无任何 delete 调用）
  $ ./clean </dev/null                → exit=0  "用户已取消清理。"
  $ ./cache-clean --safe </dev/null   → exit=0  "已取消"
  正确做法（同项目已有）：btrfs-scrub:211-216 / offsite-backup-schedule:108-113 / backup-restore:507-511
    [[ -t 0 ]] || { ui_err "非交互操作必须指定 --yes"; return 2; }   → 实测 btrfs-scrub --start 非 TTY exit=2
  附：quicksave -del abc → exit=1（README 说参数错误应为 2）
```

- 影响：自动化把"什么都没做"当成成功（最危险的是 `quicksave -del`：以为快照删了/以为清理跑了）。
- 建议：统一在确认前加非 TTY 检查并返回 2；或让 `ui_confirm_word` 在 stdin 非 TTY 时返回 2 由调用方区分。
- 确认度：**已确认**（实测）

### DS-06 btrfs-scrub 用空白拆分 findmnt -r 输出，挂载点含空格/反斜杠时目标错乱
- 文件：`btrfs-scrub:80-97`（解析在 `btrfs-scrub:87`）

```bash
  btrfs-scrub:83  if ! mounts="$(findmnt -rn -t btrfs -o TARGET,SOURCE 2>&1)"; then
  btrfs-scrub:87  while read -r mountpoint source; do
  btrfs-scrub:88      [[ -n "$mountpoint" && -n "$source" ]] || continue
  btrfs-scrub:89      device="${source%%\[*}"
  btrfs-scrub:92      BTRFS_TARGETS+=("$mountpoint"); BTRFS_SOURCES+=("$device")
```

- 触发：`btrfs-scrub --status` / `--start <TARGET>` / `--enable`，只要某个 btrfs 挂载点含空格
  （典型：`/run/media/$USER/My Passport`）或反斜杠。
- 证据/推理链：`-r/--raw` 会把"不安全字符"十六进制转义（空格 → `\x20`），
  于是 `BTRFS_TARGETS` 里拿到的是 `/run/media/pang/My\x20Passport` 这种**不存在的路径**；
  即便某版不转义，`read -r mountpoint source` 也会按空白切分，把 `.../My` 当挂载点、把 `Passport /dev/sdX1` 当 source。
  后续 `systemd-escape --path` 生成的实例名、`btrfs device stats -c`、`btrfs scrub status -R` 全部落在错路径上。
- 影响：这类盘无法用本工具 scrub；`--status` 显示错误的 target/查询失败（`--start` 会因 `findmnt --target` 校验不通过而拒绝，属安全方向）。
- 建议：改用 `findmnt -rn -t btrfs -o TARGET,SOURCE --json`（jq 或 awk 按引号取字段），
  或只取 TARGET 一列再逐行 `findmnt -n -o SOURCE --target "$mp"`；不要依赖 `read` 拆分。
- 确认度：**已确认**（代码 + util-linux 原始输出约定；本机没有带空格的 btrfs 挂载点，未做端到端）

### DS-07 offsite-backup-schedule --run 在目标未挂载/条件跳过时仍报"备份服务已完成"
- 文件：`offsite-backup-schedule:404-409`，配合生成的 unit（`offsite-backup-schedule:305-318`：ConditionPathIsMountPoint + ExecCondition mountpoint）
- 触发：`offsite-backup-schedule --run`（或菜单"立即运行"）目标盘未挂载。
- 证据：systemd.unit(5)（本机 man）：条件不满足时 "the starting of the unit will be (mostly silently) skipped…
  Failing conditions … will not result in the unit being moved into the 'failed' state … other units are still
  pulled in and ordered as if this unit was successfully activated" → `systemctl --user start` 返回 0；
  而 `offsite-backup-schedule:407-408` 无条件 `ui_ok "备份服务已完成。"`。
- 影响：用户/自动化以为备份完成，实际什么都没做（"未挂载时跳过"的设计被误报成成功）。
- 建议：start 后用 `systemctl --user show -p Result -p ActiveState -p ExecMainStatus --value` 判定，
  或紧接着执行 `offsite-backup --target ... --check` 来证明集合确实存在。
- 确认度：**已确认**（代码 + systemd 文档；未安装真实 timer 实测）

### DS-08 offsite-backup-schedule 生成 unit 时未转义 `$`，systemd 会做变量展开
- 文件：`offsite-backup-schedule:90-96`（systemd_quote）、`offsite-backup-schedule:315-317`（ExecCondition/ExecStart 使用它）

```bash
  offsite-backup-schedule:90  systemd_quote() {
  :92    value="${value//\\/\\\\}"     # 转义反斜杠（源码原样）
  :93    value="${value//\"/\\\"}"     # 转义双引号
  :94    value="${value//%/%%}"        # 转义 %
  :95    printf '"%s"' "$value"
  :316  printf 'ExecStart=%s --target %s --keep %s\n' "$(systemd_quote "$BACKUP_CMD")" "$(systemd_quote "$TARGET")" "$KEEP"
```

- 触发：`BACKUP_TARGET`（或 `BACKUP_CMD` 路径）里含 `$`，例如 `/run/media/pang/My$Backup`。
- 证据：systemd.service(5)（本机 man）："Unless for commands with the special executable prefix ':', to pass a
  literal dollar sign, use "$$". **Variables whose value is not known at expansion time are treated as empty strings.**"
  → `$Backup` 被展开为空串，`--target` 参数错位/为空（`ConditionPathIsMountPoint` 不做命令展开，只有 ExecStart/ExecCondition 受影响）。
- 影响：定时备份在错误目标上跑（大概率直接失败退出 2），而 unit 文件看起来完全正常 → 长期"定时器在跑但从未备份"。
- 建议：systemd_quote 里补 `value="${value//\$/$$}"`（放在反斜杠转义之后）；`ExecCondition` 同样处理。
- 确认度：**已确认**（文档 + 代码；未在带 `$` 的路径上装机实测）

### DS-09 offsite-backup --check 在"已初始化但还没有集合"时静默 exit 1（预期告警是不可达死代码）
- 文件：`offsite-backup:287-312`（latest_set）、`offsite-backup:351-356`（verify_latest）、`offsite-backup:370-373`（check 分支）

```bash
  :311  [[ -n "$latest" ]] && printf '%s\n' "$latest"     # 没有集合 → 函数返回 1
  :352  set_dir="$(latest_set)" || return 1               # 直接返回，下面这句永远到不了
  :354  [[ -n "$set_dir" ]] || { ui_warn "目标中还没有完整备份集合"; return 1; }
```

- 触发：`offsite-backup --target <第一次使用、只有 .offsite-backup-owned 的盘> --check`。
- 证据（沙箱：findmnt/lsblk 桩让目标识别为异盘）：exit=1，stdout 只有横幅与目标面板，**没有任何错误/警告文本**；
  补上完整 `set-*` + `latest` 后同一命令 exit=0 且打印校验成功。
- 影响：定时任务/排障只看到 exit 1，不知道为什么。
- 建议：`latest_set` 改成显式"找到/没找到"两种正常返回，由调用方报错。
- 确认度：**已确认**（实测）

---

## P3

### DS-10 quicksave 创建时若 --print-number 输出无法解析，刚建好的那个快照不会被回滚
- 文件：`quicksave:314-339`

```bash
  :316  if snap_id="$(snapper -c "$conf" create --print-number ... )" \
  :320      && [[ "$snap_id" =~ ^[1-9][0-9]*$ ]]; then
  :321      CREATED_CONFS+=("$conf"); CREATED_IDS+=("$snap_id")
  :323  else
  :324      SAVE_SUCCESS=0; break
  :332  for ((i = ${#CREATED_IDS[@]} - 1; i >= 0; i--)); do snapper -c "${CREATED_CONFS[$i]}" delete "${CREATED_IDS[$i]}" ...
```

- 触发：snapper 创建成功但 stdout 不是纯数字（插件/包装脚本额外输出、被日志污染等）。
  上游 `cmd-create.cc` 单快照 `-p` 只打印数字，所以触发面窄。
- 影响：留下一个属于本批次但未成套的快照；与 DS-01 叠加时可能顶掉真正的成套回滚点。
- 建议：解析失败时按 `maintenance_batch=$SNAP_BATCH_ID` 反查并删除该批次新出现的快照，或要求人工确认。
- 确认度：**高度可疑**（需 snapper 异常输出才能触发）

### DS-11 migration-pack 两次 rename 之间被 SIGKILL 会留下隐藏的旧包目录
- 文件：`migration-pack:533-539`、`migration-pack:495-509`（cleanup_pack）

```bash
  :492  old_dir="$parent/.${base}.old.$$"
  :533  if [[ -e "$backup_dir" || -L "$backup_dir" ]]; then mv -T -- "$backup_dir" "$old_dir"; fi
  :534  mv -T -- "$staging" "$backup_dir"
```

- 触发：SIGKILL/断电正好落在两次 rename 之间（`~/migration` 短暂不存在）。
- 影响：旧包以 `~/.migration.old.<pid>` 保留（未丢失，可人工找回），但没人知道这个路径；SIGKILL 下 EXIT trap 不执行。
- 建议：启动时回收 `"$parent/.${base}.old.*"`，或在错误文案里给出该路径。
- 确认度：**已确认**（代码）

### DS-12 migration-pack v1 校验中"关键内容缺失"只 warn，不影响退出码
- 文件：`migration-pack:723-732`、`migration-pack:799-815`
- 触发：v1 包缺 `pkg-deps.html` / `scripts` / `md` / `.config/fish` / `.config/niri` / `.config/opencode` 中任意项。
- 证据（沙箱最小 v1 fixture，2 条 manifest）：

```
  $ migration-pack --verify <v1pack>   → exit=0
    [注意] 压缩包未包含 .config/opencode/
    [成功] 迁移包结构与校验和有效
```

- 影响：与 README:117-119 描述的"校验内容完整性"强度不符，恢复时才发现缺东西。
- 建议：把关键项缺失计入失败集合（或 README 明确"仅提示"）。
- 确认度：**已确认**（实测）

### DS-13 offsite-backup 的空间估算与实际归档排除规则不一致
- 文件：`offsite-backup:406-423`（`du -sk --exclude='.cache' --exclude='migration' ...`）vs `offsite-backup:428-435`（`tar --exclude='./.cache' ...`）
- 触发：HOME 里存在嵌套 `<子目录>/.cache`。
- 证据：`du --exclude` 按 basename 匹配（任意层的 `.cache` 都被排除），tar 只排除顶层 `./.cache` →
  tar 实际体积大于估算；余量只有 10%（`offsite-backup:418` 的 REQUIRED_KIB 计算）。
- 影响：估算偏小时可能在归档中途写满目标盘（staging 会被清理，旧集合不受影响）。
- 建议：估算与归档用同一套排除规则；或先采样实际归档大小。
- 确认度：**已确认**（代码）

### DS-14 死代码 / 重复事实来源（维护风险）
- `cache-clean:253-271` 的 `target_paths()` 无任何调用（`grep -n target_paths cache-clean` 只有定义），
  而 `cache-clean:82-104` 的 `target_bytes()`、`cache-clean:275-305` 的 `show_targets()`、
  `cache-clean:182-249` 的 `clean_*()` 各自维护一份路径清单（三处需同步）。
- `migration-pack:91-115` 的 `guard_backup_dir()` 是 v1 遗留、无调用（v2 用 `v2_guard_output_dir`）。
- `offsite-backup:354` 的告警不可达（见 DS-09）。
- 建议：删除或让唯一清单函数成为事实来源，避免以后增删缓存路径时三处不一致。
- 确认度：**已确认**（grep）

### DS-15 quickload -l 把 snapper 原始 stderr 直接塞进卡片
- 文件：`quickload:378-394`（get_snapper_list_output 未收 stderr）、调用点 `quickload:427`
- 证据（stub snapper 让 list 失败）：输出先出现 `IO error: permission denied`，然后才是
  `错误: 配置 [root] 的快照列表查询失败。`；退出码 1（这点正确，符合 HANDOFF 的"查询失败 ≠ 空列表"）。
- 影响：UX 瑕疵。
- 建议：stderr 收进变量，需要时经 `ui_panel_raw` 展示。
- 确认度：**已确认**（实测）

### DS-16 quickload 恢复倒计时文案可能让人以为 Ctrl+C 撤销了恢复
- 文件：`quickload:1336-1353`（提示语在 `quickload:1342`："Ctrl+C 可取消并留在当前系统检查"），恢复已下发见 `quickload:1318-1331`。
- 影响：Ctrl+C 只取消自动重启；btrfs-assistant 的恢复任务已下发，原生后端更是已经完成子卷 swap，
  下次重启（或任何原因重启）仍会进入恢复后的系统；用户可能据此判断"恢复没生效"。
- 建议：文案改为"仅取消自动重启；恢复已生效/已下发，重启后仍会应用"。
- 确认度：**高度可疑**（依赖 btrfs-assistant `-r` 的语义；本机未做真实恢复验证）

### DS-17 backup-restore 的路径校验只看条目名，不看符号链接目标（加固项）
- 文件：`backup-restore:243-276`、`backup-restore:278-308`（只检查 `/` 开头与 `..` 段）、`backup-restore:518`（rsync 未加 `--safe-links`）
- 影响：仅在被篡改/恶意归档时才有意义（本工具自产包不太可能），可能借"符号链接 + 后续成员"把文件写到 HOME 之外。
- 建议：校验阶段解析 `tar -tvf` 的箭头目标，拒绝指向 HOME 外的链接；rsync 加 `--safe-links`。
- 确认度：**高度可疑**（未构造恶意归档实测）

### DS-18 clean 深度清理分支里 findmnt 失败会无提示退出
- 文件：`clean:538`：`BTRFS_ROOT_DEV=$(findmnt -n -o SOURCE / | cut -d'[' -f1)`
  （没有 `|| true`，`set -euo pipefail` 下 findmnt 失败即整脚本退出；同文件 `clean:404-411` 的同类查询是显式处理的）。
- 影响：极端情况下无解释中断（不产生破坏，但不符合"查询失败要报告"的约定）。
- 建议：加 `|| { _warn ...; CLEAN_FAILED=1; }`。
- 确认度：**已确认**（代码）

### DS-19 quicksave -del 的 CLI 路径没有"批次只剩一半"的护栏
- 文件：`quicksave:236-301`（无 batch 检查；README:77-79 描述的护栏只在菜单里）
- 触发：`quicksave -del <id> --yes` 删掉某个成套批次中的一半（例如 root 侧）。
- 影响：另一配置中的同批次快照变成孤例；`quickload` 的"全部还原"再找不到完整批次（`quickload:602-614`）。
  删除本身是用户显式确认过的，因此不构成数据丢失，但 `--yes` 脚本化时容易批量破坏成套性。
- 建议：删除前查询其余配置是否有同 batch 快照，有则提示"删掉这一半后成套恢复会失效"（与菜单一致），
  `--yes` 场景下也至少打印警告。
- 确认度：**已确认**（代码）

---

## 已核对、判定不是缺陷（避免重复劳动）

1. `snapper delete` **支持多 ID/区间**：上游 `client/snapper/cmd-delete.cc` 用 `while (get_opts.has_args())` 逐个解析；
   本机 0.13.1 二进制含 "Command 'delete' needs at least one argument."（而不是 "needs one argument"）。
   → `quicksave:271` 的批量删除与 `quicksave:292` 的多 ID 删除是正确用法，man 页写法滞后。
2. `snapper create --print-number` 单快照**只输出数字**（上游 `cmd-create.cc` 里 cout 的就是 getNum()），
   `quicksave:316-320` 的正则校验成立。
3. `btrfs-scrub` 的 unit 实例名用 `systemd-escape --path <挂载点>` 与 btrfs-progs 模板一致
   （`/usr/lib/systemd/system/btrfs-scrub@.service` 用 `%f`；本机 `systemd-escape --path /` 得到 `-`，
   与实测 `btrfs-scrub@-.timer 已启用` 吻合）。
4. `ui_confirm` / `ui_confirm_word` 在 EOF 时视为取消（ui.sh:656-678），本范围内**没有**默认 y 的确认调用
   （`quicksave:195` 与 `clean:185` 都显式传 `n`）→ 不存在"非交互静默确认破坏性操作"。
5. bash 在未捕获的 SIGINT/SIGTERM 下**会**执行 EXIT trap（实测 exit 130/143 且 trap 运行）→
   `clean` 的扫描文件/临时挂载/sudo 保活、`quickload` 的临时挂载清理在 Ctrl+C 时不会漏掉。
6. `offsite-backup` 的护栏实测有效：同盘目标被拒（"目标与系统位于同一物理磁盘"）、目标在 HOME 内被拒、
   `mkdir`/写标记失败被转成受控错误、`latest` 用相对名 + `return 0`、`prune` 只删带 marker 的 `set-*`，
   校验通过前不更新 `latest`（`verify_set` 失败会删掉未提交集合，`offsite-backup:394-396`）。
7. `migration-pack` 输出目录边界实测有效：`--pack <源HOME>`、`--pack /`、
   `--pack <被 include 的目录>` 全部被拒（`v2_guard_output_dir` 用 `realpath -m`）。
8. `backup-restore` 的 HOME 合并**没有** `--delete`（合并语义与 README 一致），覆盖前旧版本进 rollback 目录；
   `--set` / `latest` 的名称与越界都有正则 + `dirname` 校验（`backup-restore:183-241`）。
9. `quickload` 默认目标解析在真实数据上正确：`quickload -c root -d quicksave-sysup </dev/null` 解析出
   `#185 2026-09-05 23:01:50 quicksave-sysup` 并在确认处安全取消（exit 0）；
   snapper 查询失败时 `quickload -l` 返回 1 而不是"空列表"（stub 实测）。
10. `clean` 深度清理用 `snap_id == 0` 跳过当前系统节点、保留 `before*`，临时文件经 `mktemp`（0600）
    并在两代 EXIT trap 链里都清理；`clear_aur_cache_dir`（clean:133-143）有 `realpath` + 符号链接/越界双重校验。
11. `offsite-backup` 在主机名命令缺失（本机无 `hostname`）时正确回退到 `/proc/sys/kernel/hostname`。
12. 性能小项（非缺陷，可顺手优化）：`cache-clean --list` 对 13 个路径串行 `du -sb` + 每行一个 `awk`，
    本机 warm cache 实测 638 ms；合并成一次 `du -sb` 多路径调用可少 12 次 fork。

---

## 复现材料（全部只写 /tmp，可重复执行）

- 沙箱：`/tmp/maintenance-review/sandbox/`（`bin/`：snapper / findmnt / lsblk / tar 桩；`fakehome/`：带 5 个 include 的假 HOME；
  `profile.conf`；`pack/`：真实生成的 v2 迁移包；`v1pack/`：手工 v1 夹具）
- 观测输出：`/tmp/maintenance-review/out/`（tar/snapper 调用日志、各命令 stdout/stderr）
- 异盘备份目标夹具：`/var/tmp/maintenance-review/offsite-target/`（含 marker + 完整 set/latest）
- 关键实测命令见各条"证据"小节；所有命令均未触碰工作区文件，也未执行真实删除/恢复/备份/scrub/timer 写操作。
