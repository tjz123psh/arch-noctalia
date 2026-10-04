# 更新链路审查：checkallupdates / mirror-update / sysup / post-update-check / recommend-check

- 审查者：update-chain（共享任务 task-2）
- 审查日期：2026-09-10
- 范围（只读）：`checkallupdates`、`mirror-update`、`sysup`、`post-update-check`、`recommend-check`（辅以 `lib/ui.sh`、`lib/config.sh` 中与锁/计时相关的部分）
- 约束遵守：未访问 `review/`；未修改工作区任何文件；所有实测均在 `/tmp/mr-sandbox`、`/tmp/mr-sysup` 中用命令桩完成；真实系统只读命令（`--help`、`bash -n`、只读查询、`post-update-check`/`recommend-check` 的只读运行）未写系统状态。

## 0. 方法与证据基线

- 沙箱脚本副本：`/tmp/mr-sandbox/src/`（5 个脚本）+ `lib/`；`/tmp/mr-sysup/sysup` 使用同目录桩 `quicksave/mirror-update/checkallupdates/post-update-check`。
- 命令桩：`checkupdates/paru/flatpak/sudo/pacman/grub-mkconfig/curl/systemd-inhibit/reflector`，支持按来源设置睡眠、失败、忽略 INT。
- 测试脚本（可复跑）：`/tmp/mr-sandbox/tests-checkallupdates.sh`、`t7.sh`、`t8.sh`、`t12.sh`、`t16.sh`、`t17.sh`、`t18.sh`、`t21.sh`、`t22.sh`、`t23.sh`、`t24.sh`、`t25.sh`、`mu.sh`、`/tmp/mr-sysup-test.sh`。
- 环境：Bash 5.3.15、reflector/fakeroot/fzf 已装、根文件系统 = btrfs、真实 `/etc/pacman.d/mirrorlist` 有 6 行 `Server = ` 且 `# When: 2026-09-04`。
- `bash -n` 对 5 个脚本全部通过。

---

## 1. 发现总览（按级别）

| 编号 | 级别 | 位置 | 一句话 |
|---|---|---|---|
| F-01 | P1 | checkallupdates:409-427, 487-507 | 缓存目录不可写（ENOSPC/权限）时整轮刷新彻底失败，却 `exit 0` 并把旧缓存当刷新结果显示；sysup 会认为刷新成功 |
| F-02 | P1 | checkallupdates:266-279, 459-499 | 来源状态先写 `ok` 再 `mv` 数据，`mv` 失败被忽略 → 报 ok、打新鲜时间戳、显示"当前没有待更新项目" |
| F-03 | P2 | checkallupdates:222-229 | 孤儿回收只按 mtime>60min 删除，无存活判断，会删掉正在运行的并发刷新的临时文件 |
| F-04 | P2 | checkallupdates:272-273, 300-301, 331-332 | 某个来源查询失败时用空文件覆盖它的上一次成功列表（最后一次已知好数据被销毁） |
| F-05 | P1（含数据丢失） | mirror-update:363-372, 112-121 | 当前 mirrorlist 无 `Server = ` 行时备份指向历史旧备份；刷新失败后 trap 会把旧备份覆盖到当前文件，用户现有配置丢失 |
| F-06 | P1 | sysup:183 | `clear` 在 TERM 未设置/dumb 时失败，`set -e` 让 sysup 在第一条输出前静默退出 1；文档化的非交互 `--yes` 路径不可用 |
| F-07 | P2 | checkallupdates:515-521, 539-551 | 首次（缓存目录为空）打开列表显示"状态异常 缺少来源状态缓存"；为首次使用写的"正在查询"pending 行是死代码 |
| F-08 | P2 | checkallupdates:409-413 | `flock -w UPDATE_LOCK_WAIT ... || true`：等待超时后无视锁继续刷新 → 重复并发网络查询 + 跨代缓存混合 |
| F-09 | P2 | checkallupdates:447-485 | 中断时已完成的来源只落盘数据、不打 `last-refresh-<source>` 时间戳，下次打开会重查它们 |
| F-10 | P2 | post-update-check:15-27, 83-100 | 非 TTY 且无 sudo 凭据时静默以普通用户跑 pacdiff，"看不到"可能与"未发现"无法区分 |
| F-11 | P3 | checkallupdates:38-55, 509-551 | `--refresh/--refresh-stale` 机器契约未文档化：`status/none/pending` 行复用第 2 字段；失败时 stderr 会混入裸报错 |
| F-12 | P3 | checkallupdates:216-218, 743, 790-791 | fzf 的 reload 子进程继承 `CHECKALLUPDATES_PENDING_FLAG` 并在退出时删掉不属于它的标记 |
| F-13 | P3 | mirror-update:48-50 | `MIRROR_THREADS` 环境变量越界/非法时静默回落到 5（配置文件路径却是报错退出），行为不一致 |
| F-14 | P3 | mirror-update:232, 258 | `_run_reflector` 的 mktemp 临时文件未注册 trap，INT/TERM 时泄漏到 /tmp |
| F-15 | P3 | mirror-update:308-310 | `-c` 缺参数 `exit 1`，未知参数 `exit 2`，与 README"参数错误=2"不一致 |
| F-16 | P3 | sysup:335-338 | quicksave（快照）失败直接 `set -e` 终止，无用户可见说明、无失败累计 |
| F-17 | P3 | sysup:232, 326-327, 496-497 | `check_mirror_age` 里 `. /etc/os-release` 覆盖当前 shell 变量；README 顺序与实现（先锁后 sudo）不一致；`curl | python` 依赖 `python` 存在 |
| F-18 | P3 | ui.sh:619；recommend-check:55-57, 204, 241, 320 | `err` 计入"缺失"统计；`has_bluetooth_controller` 重复调用；`main "$@"` 无 `BASH_SOURCE` 保护 |
| F-19 | P3 | ui.sh:774-811；checkallupdates:407 | 性能可再压：每次开列表 `ui_status_line` 约 8 次 fork；每次刷新 6 次 `find` 回收 |

已确认为**符合设计**（见第 3 节）：来源并行查询、单来源超时与孤儿回收、Ctrl+C/HUP 清理与已完成来源落盘、`--refresh-stale` 只补查失败来源、非 TTY 拒绝、fzf load/Ctrl+R 绑定、维护锁继承与嵌套、mirror-update 备份轮换与失败回滚、sysup 7 步顺序与失败累计。

---

## 2. 详细发现

### F-01（P1，已确认）`checkallupdates --refresh` 整轮刷新失败仍返回 0，并把旧缓存当"刷新结果"

**位置**：`checkallupdates:415-427`（mktemp 失败未检查）、`487-499`（失败判定只来自合并状态文件）、`712-720`（`refresh_update_cache ... || refresh_status=$?`）。

**触发**：缓存目录存在但不可写（磁盘满 ENOSPC、权限被改、目录被换成只读挂载）：

```bash
HOME=/tmp/mr-sandbox/home PATH=/tmp/mr-sandbox/bin:$PATH \
  /tmp/mr-sandbox/src/checkallupdates --refresh
```

**证据（实测 T18）**：`chmod 500` 缓存目录后，10 个 `mktemp` 全部失败（stderr 10 行 `mktemp: ... 权限不够`），**0 次查询**（桩日志 0 行），但：

```
exit=0   (0 here means: total refresh failure reported as success)
stdout: pacman  linux  [Pacman]  linux 6.10.1-1 -> 6.10.2-1
        ...（全部来自上一轮缓存）
```

代码链：

```bash
415  tmp_repo=$(mktemp "$CACHE_DIR/repo.XXXXXX")      # 失败不被检查
...
487  cat -- "$st_pacman" "$st_aur" "$st_flatpak" > "$tmp_status"
488  mv -- "$tmp_status" "$CACHE_STATUS"
491  while IFS=$'\t' read -r _ state _; do
492      [[ "$state" == "error" ]] && refresh_failed=1
493  done < "$CACHE_STATUS"                            # 文件不存在 → 循环体不执行
495  if (( refresh_failed == 0 )); then touch "$CACHE_STAMP"   # 失败也不影响
```

同时 `refresh_update_cache` 在主流程里是 `refresh_update_cache || refresh_status=$?`（`||` 列表会让整个函数体内的 errexit 失效），所以内部的 `mv`/`touch`/`cat` 失败都不会中止脚本。

**影响**：
1. 机器可读入口骗人：自动化得到 `exit 0`，但没有任何来源被刷新；
2. `sysup:406` 的 `elif ! "$refresh_cmd" --refresh >/dev/null 2>&1` 判定为成功 → "更新缓存刷新失败不再静默"的保证在这条路径上失效；
3. UI 上旧列表被当成新数据展示（边框时间标签也不会更新）。

该触发条件在系统升级时并不罕见（`/var/cache` 满、`$HOME` 只读、ENOSPC）。

**建议修法（只描述）**：`mktemp` 全部加 `|| { ui_err ...; return 1; }`；`refresh_update_cache` 内维护独立 `failed` 标志（mktemp/写状态/mv/cat/touch 任一步失败即置位），不要只依赖读取 `CACHE_STATUS`；`print_cached_updates_or_empty` 在本轮刷新失败时不要只打印旧列表，至少在机器输出里加一行 `status all error ...`；`--refresh` 明确返回非零。

---

### F-02（P1，已确认）来源状态先写 ok 再写数据 → `mv` 失败会报"全部成功 + 没有待更新项目"

**位置**：`checkallupdates:266-279`（pacman；AUR/Flatpak 同构于 294-308、322-339）、`344-354`（`_cau_settle_status`）、`459-485`（时间戳）、`539-551`（显示层）。

**触发**：查询完成但临时文件在 `mv` 前消失（并发同伴的孤儿回收、外部 `rm -rf ~/.cache/checkallupdates`、其他缓存清理器）。

**证据（实测 T16）**：进程 A 三个来源都在 `sleep 8`；把 A 的 `repo.*/aur.*/flatpak.*` 的 mtime 改成 2 小时前，再启动进程 B（`_cau_reclaim_orphans` 在取锁之前运行，会删掉 A 的临时文件）。A 的收尾：

```
mv: 对 '.../repo.aLNoXf' 调用 stat 失败: 没有那个文件或目录
（aur / flatpak 同）
none [TAB] - [TAB] [None]    当前没有待更新项目        ← 三个来源结果全部丢失
```

而 A：`exit=0`、`source-status.tsv` = `pacman ok / aur ok / flatpak ok`、`last-refresh-*` 时间戳被 touch。原因：

```bash
267  if (( rc == 0 || rc == 2 )); then
268      printf 'pacman\tok\t\n' > "$status"   # 先判"成功"
269      mv -- "$out" "$CACHE_REPO"            # 后写数据；失败被 || 列表吞掉
270      return 0
```

**影响**：把"查询结果丢失"显示成"当前没有待更新项目"，并且在 1 小时缓存有效期内不会再查（时间戳已更新），直接违反项目铁律"查询失败不能等同于结果为空"。

**建议修法**：把 `mv` 放在写状态之前并检查返回值；任一步失败必须写 `error` 状态且 `return 1`；`print_cached_updates_or_empty` 在有来源处于 error 或数据文件缺失时不得输出 `none` 行（`none` 只应在三个来源本轮都成功且确实为空时出现）。

---

### F-03（P2，已确认）孤儿临时文件回收没有存活判断，会破坏正在运行的并发刷新

**位置**：`checkallupdates:222-229`；调用点 `407`（在取锁之前）。

```bash
223  for pattern in repo aur flatpak status error; do
225      find "$CACHE_DIR" -maxdepth 1 -type f -name "$pattern.??????" -mmin +60 -delete
```

**触发**：一次刷新持续超过 60 分钟（例如把 `UPDATE_QUERY_TIMEOUT` 配成 3600 以上；配置校验只要求正整数、无上限），随后另一次刷新启动。

**证据**：T16/T15 —— 用 `touch -d "2 hours ago"` 模拟运行中的长刷新，第二个进程启动后第一个进程的临时文件被删除，第一个进程随即出现 `mv` 失败并落到 F-02 的结果（`exit 0` + "没有待更新项目"）。

**影响**：并发刷新互相破坏；单独运行时影响很小（60 分钟以上才是现实孤儿），但与 F-02 组合成错误显示。

**建议修法**：临时文件带 PID 命名（`repo.<pid>.XXXXXX`）并先检查 `/proc/<pid>` 是否存活；或先取 `refresh.lock` 再做回收；给 `UPDATE_QUERY_TIMEOUT` 加上限校验。

---

### F-04（P2，已确认）查询失败会用空文件覆盖上一次成功列表

**位置**：`checkallupdates:272-273`、`300-301`、`331-332`（`: > "$out"; mv -- "$out" "$CACHE_REPO"`）。

**证据（实测 T25）**：先正常刷新（`updates-flatpak.txt` 20 字节 1 行），再让 flatpak 桩失败一次：

```
healthy cache sizes: 20 updates-flatpak.txt 50 updates-repo.txt
after failure sizes:  0 updates-flatpak.txt 50 updates-repo.txt
flatpak rows now: 0   ← 最后一次已知好数据被销毁
```

**影响**：离线或远端超时一次，就会丢失该来源上次的待更新清单；用户重新联网前再打开列表只剩错误行。状态行仍显示"查询失败"，所以没有违反"失败≠空"的显示铁律，但数据保留策略与 README"某个来源失败不会连累其它来源"的目标相悖。

**建议修法**：失败时保留旧数据文件，只用状态文件表达失败（`cache_is_fresh` 已按来源计时，不需要靠清空数据来表达"这次没查到"）。

---

### F-05（P1，含数据丢失，已确认）mirror-update 失败回滚会把"历史旧备份"覆盖到当前 mirrorlist

**位置**：`mirror-update:352-372`（备份来源选择）、`112-121`（trap 回滚）。

```bash
352  if grep -q '^Server = ' "$MIRRORLIST" 2>/dev/null; then
...      # 正常：本次备份 = 当前文件
363  else
364    BACKUP_PATH="$(find "$BACKUP_DIR" ... -printf '%T@ %p\n' | sort -nr | cut -d' ' -f2- | sed -n '1p')"
368    if [[ ! -s "$BACKUP_PATH" ]]; then error "...没有可用的历史备份"; fi
371    warn "当前 mirrorlist 无效，保留历史备份不覆盖：$BACKUP_PATH"
```

**触发**：`/etc/pacman.d/mirrorlist` 不含 `^Server = ` 行（例如使用 `Include = /etc/pacman.d/mirrorlist.d/*.conf` 的配置、全部被注释、内容为空但历史备份存在），且 reflector 三次尝试都失败。

**证据（实测 M5）**：

```
before:  # user current, only Include line
         Include = /etc/pacman.d/mirrorlist.d/*.conf
exit=1
   [注意] 当前 mirrorlist 无效，保留历史备份不覆盖：.../mirrorlist-20200101-000000-1.bak
   [注意] 脚本被中断或运行失败，正在安全恢复...
   [成功] 已从备份恢复原始镜像源。
after:   Server = https://ancient.example.com/x      ← 2020 年的备份覆盖了用户当前配置
```

**影响**：用户当前 mirrorlist（合法但被脚本判为"无效"）被一份无关的旧备份覆盖，当前内容没有被备份、无法恢复；pacman 会用陈旧镜像。属于数据丢失路径（文件可再生，但用户自己的编辑丢失）。

**建议修法**：当前文件不匹配 `^Server = ` 时不要把它当作"可回滚到历史备份"的对象：失败时保持原文件不变（或先把当前文件也复制成一份备份再回滚）；回滚目标只允许"本轮创建的备份"。

---

### F-06（P1，已确认）`sysup --yes` 在 TERM 未设置/dumb 时静默失败

**位置**：`sysup:183`（`clear`），脚本第 7 行 `set -euo pipefail`。

**触发**：cron / systemd unit / `env -u TERM` / `TERM=dumb` 下运行：

```bash
env -u TERM HOME=/tmp/mr-sysup/home PATH=/tmp/mr-sandbox/bin:/usr/bin \
  /tmp/mr-sysup/sysup --yes </dev/null
```

**证据（实测 S0）**：`exit=1`、stdout **0 字节**、stderr `TERM environment variable not set.`；桩日志 0 行（快照/升级/GRUB 都没有发生）。对照 `env TERM=xterm-256color sysup --yes`（S1）完整跑完 7 步并 `exit 0`。

**影响**：文档明确支持的非交互入口（`-y, --yes 非交互环境下明确确认执行更新`）在无 TERM 环境完全不可用，且失败时没有任何自有输出，看起来像"什么都没做"。同类 `clear` 调用在 checkallupdates 的 `run_full_update/update_all_pacman/update_selected` 也存在，但那些都在交互 UI 内触发。

**建议修法**：`clear 2>/dev/null || true`（或在 TERM 缺失/dumb 时跳过），并在非 TTY 且非 `--yes` 时给出明确提示。

---

### F-07（P2，已确认）首次打开列表显示"状态异常"，设计中的 pending 行不可达

**位置**：`checkallupdates:515-521`、`539-551`、`749-754`。

```bash
518  [[ -f "$CACHE_STATUS" ]] || {
519      printf 'status\tcache\t...缺少来源状态缓存，请按 Ctrl+R 重试...'
520      return 0
543  if [[ -n "$output" ]]; then printf '%s\n' "$output"
545  elif (( REFRESH_PENDING == 1 )); then printf 'pending\t-\t...正在查询...'   # 永远走不到
```

**触发**：缓存目录为空（首次使用，或被人清空）时打开列表：

```bash
rm -rf ~/.cache/checkallupdates && checkallupdates      # 真实交互路径
```

**证据（实测 U2，PTY）**：fzf 首个列表只有 1 行；对 PTY 输出计数：`状态异常` 出现 1 次、`正在查询 Pacman` 出现 **0** 次。后台刷新本身正常（load 事件在约 2s 后触发，三个来源桩被调用并落盘），所以"不阻塞"没问题，问题在提示文案与状态语义。

**影响**：新用户/清缓存后第一眼看到"状态异常…请按 Ctrl+R 重试"，实际后台已经在刷新；README 第 25-26 行描述的"正在刷新"边框状态与 pending 文案在首次场景不可达。

**建议修法**：把 pending 判断提前（`REFRESH_PENDING==1` 且三份数据文件都不存在时显示 pending），或让"缺少来源状态缓存"只在 `CACHE_STATUS` 缺失但数据文件存在时输出。

---

### F-08（P2，已确认）`UPDATE_LOCK_WAIT` 超时后无视锁继续刷新

**位置**：`checkallupdates:409-413`

```bash
409  if check_cmd flock; then
410      exec {refresh_fd}>"$CACHE_DIR/refresh.lock"
412      flock -w "$REFRESH_LOCK_WAIT" "$refresh_fd" || true     # 超时 → 忽略，继续刷新
413  fi
```

**证据（实测 T12，`CHECKALLUPDATES_LOCK_WAIT=2`，同伴需要 6s）**：

```
second: exit=0 wait-then-run elapsed=8093ms
stub calls total=6 (3 = serialized, 6 = duplicate concurrent work)
  +0.00s checkupdates | aur | flatpak     ← 进程 A
  +2.72s checkupdates | aur | flatpak     ← 进程 B 在 A 还在跑时重复查询
```

T13（等待 30s > 同伴 4s）显示正常串行等待后仍然重跑全部来源（`--refresh` 全量语义，符合预期）。真实场景：待更新列表 UI 的 load 已触发一次后台刷新时按 Ctrl+R（`reload-sync --refresh`），fzf 会卡住最长 300 秒且没有进度提示；超时后还会与同伴并发写同一批缓存文件（`mv` 原子，但三个来源可能来自不同代）。

**建议修法**：超时后不要"继续执行"，而是明确返回"另一刷新正在进行"；至少在接受超时后重新检查一次"数据是否已经足够新"，避免重复全量查询；fzf 侧给 reload 增加可视提示。

---

### F-09（P2，已确认）中断时已完成的来源数据落盘但没有新鲜度时间戳

**位置**：`checkallupdates:447-455`（wait）、`459-485`（touch 时间戳）、`103-123`（`_cau_source_is_fresh`/`cache_is_fresh`）。

**证据（实测 T7b，PTY Ctrl+C，pacman/aur 1s、flatpak 37s）**：

```
exit=130
cache dir: refresh.lock updates-aur.txt updates-repo.txt
updates-repo.txt: linux 6.10.1-1 -> 6.10.2-1 ...     ← 数据确实保住了
（没有 last-refresh-pacman / last-refresh-aur）
```

因为时间戳 `touch` 在全部 `wait` 之后才执行。下一次打开列表 `cache_is_fresh` 为假 → 又会查询这两个刚查过的来源。README"已经查完的来源仍然会正常落盘，不会白跑"只兑现了一半。

**建议修法**：每个来源的 `wait` 完成后立即结算它的状态和时间戳（现在按 pacman→aur→flatpak 串行 wait，可改成 `wait -n` 逐个收割）。

---

### F-10（P2，分析 + 实测，覆盖范围需进一步验证）post-update-check 无 sudo 时静默降级

**位置**：`post-update-check:15-27`（`prepare_read_access`）、`83-100`（pacdiff）。

```bash
17  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then SUDO_READ=(sudo -n); return 0; fi
21  [[ -t 0 && -t 1 ]] || return 0        # 非 TTY：直接放弃提权，且不提示
85  elif PACDIFF_OUTPUT="$( <SUDO_READ 前缀> pacdiff --output 2>&1)"; then
86      if [[ -z "$PACDIFF_OUTPUT" ]]; then ui_panel_stat ok "未发现需要处理的 .pacnew / .pacsave"
```

（第 85 行的实际前缀是 SUDO_READ 数组展开；无 sudo 时数组为空，即直接 `pacdiff --output`。）

**证据（实测）**：本机 `sudo -n true` 失败、`/etc` 下 `.pacnew/.pacsave` 计数为 0、`pacdiff --output` 以普通用户运行 `exit 0` 且输出 0 行 → 面板显示"未发现需要处理的 .pacnew / .pacsave"。当前事实正确，但脚本无法区分"真的没有"和"没有权限看不到"（`pacdiff` 也不以非零表达权限不足）。另一支 `grub_file_state` 在无 sudo 且 `/boot/grub` 不可读时走 `return 2` → 显示"无法读取"，是安全的。

**影响**：在 systemd 定时任务/非交互脚本里调用时，配置残留检查可能被静默跳过并报"正常"。

**建议修法**：`prepare_read_access` 在"非 TTY 且无 sudo -n"时输出一条"以普通用户检查，结果可能不完整"的注意项（可计入 `--strict`）；或用抽查 `/etc` 下自身不可读目录的方式判定降级。

---

### F-11（P3）`--refresh/--refresh-stale` 机器可读契约未文档化、字段含义不稳定

**位置**：`checkallupdates:38-55`（用法）、`509-551`（输出）。

- 正常行：`<source><TAB><package><TAB><ANSI 显示文本>`；
- 状态行：`status<TAB><source><TAB><文本>`（第 2 字段变成"来源"）；
- 空结果：`none<TAB>-<TAB>...`；等待：`pending<TAB>-<TAB>...`。
- 失败时 stderr 可能出现裸 `mktemp/mv/touch` 报错（T17/T18 实测），stdout 契约本身不被污染。

**影响**：调用方只能靠第 1 字段区分类型（fzf 与 term-menu 就是这么做的），但没有文档说明；`--refresh` 与 `--refresh-stale` 的退出码语义（0/1/2）也没有写进 `--help`。建议在 `--help` 和 README 中固化字段表与退出码。

---

### F-12（P3，已确认）reload 子进程会删除它继承来的 pending 标记

**位置**：`checkallupdates:216-218`（`_cau_cleanup` 删 `CHECKALLUPDATES_PENDING_FLAG`）、`743`（export）、`790-791`（fzf reload）。

**证据（实测 T14）**：`CHECKALLUPDATES_PENDING_FLAG=/tmp/...flag checkallupdates --refresh`（模拟 fzf 的 reload 子进程）→ 退出后该文件被删除。当前 UI 流程里标记在 transform 阶段就已由父进程 `rm`，所以实际观测不到破坏；但这是"子进程删掉不属于自己的路径"的设计缺陷，多窗口/未来改 bind 时容易踩。

**建议修法**：只在本进程创建了该标记时删除（例如标记名固定为 `refresh-pending.<pid>` 并在清理时校验名称中的 pid 等于自己的 pid），或改成不导出的局部标记。

---

### F-13（P3，已确认）`MIRROR_THREADS` 环境变量越界静默回落到默认值

**位置**：`mirror-update:48-50`（正则+范围判断失败则 `MIRROR_THREADS=5`）、`lib/config.sh:30-33`（配置文件路径会报错并 `exit 2`）。

**证据（实测 M2）**：`MIRROR_THREADS=64 mirror-update -c China` → 实际参数 `--threads 5`；配置文件写 `MIRROR_THREADS=64` 则直接报错退出。同一配置项两条路径行为不一致，且用户显式设置的 64 被静默忽略（按 README 应"上限 32"）。

**建议修法**：环境变量路径同样报错退出（或夹到 32 并提示），不要静默回到 5。

---

### F-14（P3，已确认）`_run_reflector` 的临时文件在 INT/TERM 时泄漏

**位置**：`mirror-update:232`（`tmp="$(mktemp)"`）、`258`（`rm -f "$tmp"`），脚本没有 `ui_tmp_register`/清理钩子。

**证据（实测 M6）**：SIGTERM 时退出码正确（143、mirrorlist 已回滚），但 /tmp 留下一个 `/tmp/tmp.XXXXXXXXXX`（每次中断一个）。成功路径与"reflector 失败"路径都会 `rm`，只有信号路径泄漏。

**建议修法**：改用 `ui_tmp_register` + `trap 'ui_tmp_cleanup; ...' EXIT INT TERM`（库已提供）。

---

### F-15（P3，已确认）`mirror-update -c` 缺参数退出码 1

**位置**：`mirror-update:308-310`（`else error "--country 缺少参数"` → `ui_die` → exit 1）。

**证据（实测 T19）**：`mirror-update -c </dev/null` → `exit 1`；`mirror-update --bogus` → `exit 2`；`sysup --count 0` → 2。README 第 321 行规定"参数错误 = 2"。建议统一为 2。

---

### F-16（P3，已确认）quicksave 失败直接终止 sysup，无说明与失败累计

**位置**：`sysup:335-338`：

```bash
335  if [[ -n "$quicksave_cmd" ]] && [[ "$(findmnt -no FSTYPE /)" == "btrfs" ]]; then
337      "$quicksave_cmd" -d quicksave-sysup
```

**证据（实测 S5）**：`STUB_FAIL_QUICKSAVE=1 sysup --yes` → 只走到 `quicksave` 就退出 1（桩日志 5 行），镜像检查、密钥环、升级、GRUB、更新后检查全部跳过。行为上"没有回滚点就别升级"是安全的，但与 HANDOFF 铁律 7"允许继续、必须累计失败状态"不一致，且用户只看到 quicksave 自己的报错。建议显式判断并输出"未取得快照，已中止升级"。

---

### F-17（P3）sysup 细节

- `sysup:232`：`check_mirror_age` 内 `. /etc/os-release` 会把 `ID/NAME/PRETTY_NAME` 等注入当前 shell（本脚本只用到 `ID/ID_LIKE`，当前无实际冲突，属可维护性隐患；建议用子 shell 读取）。
- `sysup:326-327`：实际顺序是"先取维护锁 → 再 `request_sudo`（sudo -v）"；README 第 48 行写的是"才请求管理员权限 → 取得维护锁后依次执行"。实测 S1 桩日志顺序为 `curl` → `sudo -v` → `quicksave`（锁在 sudo 之前取得），文档与实现不一致。
- `sysup:496-497`：`curl ... | python -c "$PYTHON_SCRIPT"`。本机 `python` 存在（`/usr/bin/python`），但若只装了 `python3`，管道失败会落到"获取新闻失败"分支，提示与真实原因不符；建议先 `command -v python` 探测并给出明确缺失提示。

---

### F-18（P3）统计与健壮性小问题

- `lib/ui.sh:619`：`ui_panel_stat err` 也累加 `UI_N_MISS`，于是 post-update-check 的 `--strict` 摘要把"错误"显示成"缺失"（实测输出：`4 正常 1 注意 1 缺失`，其中缺失来自 GRUB 无法读取的 err 行）。建议区分统计。
- `recommend-check:204` 与 `241` 两次调用 `has_bluetooth_controller`（每次 `find | grep`），可缓存一次。
- `recommend-check:320` `main "$@"` 没有 `[[ BASH_SOURCE[0] == $0 ]]` 保护，被 source 时会直接执行（其它脚本均有保护）。
- `recommend-check:41` `pkg_installed` 依赖 `INSTALLED_PKGS`，`pacman -Qq` 全量装入关联数组（本机 24 项检查 264ms，可接受）。

---

### F-19（P3/性能专项）读取/刷新慢的量化结论

- **并行确实生效**（用户核心诉求）：三个来源各 `sleep 3`，`checkallupdates --refresh` 总耗时 **3062ms**（串行应为约 9000ms），三个桩在同一毫秒级启动（实测 T1）。
- 单来源超时生效：`CHECKALLUPDATES_QUERY_TIMEOUT=2` + pacman 桩 `sleep 37` → 2060ms 返回、`exit 1`、提示"查询超时…镜像源可能过慢"，且**没有孤儿进程**（T4）。
- 每次"打开列表"的固定开销约等于 `ui_status_line`（`ui.sh:774-811`）：2 次 `awk`、`df|tail|tr`、`ip route|awk`、`date`，约 8 次 fork，加上 4 次 `stat` 与一次渲染；绝对量小，但它在每轮 `while true` 都会重算（`fzf --footer` 是静态字符串，可只在分钟变化时重算）。
- 每次刷新固定 6 次 `find`（`_cau_reclaim_orphans`）+ 10 次 `mktemp`；正常路径可忽略，但 `-mmin +60` 扫描应与 F-03 的正确性修复一起处理。
- `print_tagged_cache` 用单个 `awk` 处理整个文件（注释里明确避免了逐行 `read`+here-string 的临时文件开销），这一处是有意的优化，未发现问题。
- post-update-check 实测 205ms；recommend-check 实测 264ms（含 `pacman -Qq`、`lscpu/lspci`），无性能问题。

---

## 3. 回归确认：设计意图中被验证为正确的部分

| 声明 | 验证方式 | 结果 |
|---|---|---|
| 三来源真并行 | T1（各 sleep 3） | 3062ms，同时启动 ✅ |
| 单来源超时（默认 90s 可配） | T4（2s + sleep 37） | 2060ms，指明来源与可能原因 ✅ |
| 失败来源不连累其它来源、下次只补查失败来源 | T2→T3 | `--refresh-stale` 只调用 flatpak 桩 1 次 ✅ |
| Ctrl+C 收进程+清临时文件+已完成来源保数据 | T7/T7b（PTY Ctrl+C；桩忽略 INT 以排除进程组信号干扰） | exit 130、无临时残留、无孤儿、repo/aur 数据保留 ✅ |
| SIGHUP（关窗）清理 | T6 | exit 129、临时文件清零、无孤儿 ✅ |
| 非交互终端拒绝 UI | T10 | `exit 2` + 指向 `--refresh` ✅ |
| `--load-actions` 契约与一次性标记 | T11 | 输出 `change-list-label(…正在刷新)+reload-sync('…' --refresh-stale)`，标记被消费 ✅ |
| 打开列表不阻塞（过期缓存 / 空缓存） | T8、U2（PTY，真实 fzf） | 旧列表先出现，load 事件在后台触发 `--refresh-stale`；Ctrl+R 触发全量 `--refresh`；`TERM_MENU_CHILD=1` 下 Esc → 130 ✅ |
| 维护锁继承（sysup→quicksave 模式） | L1 | 子进程通过继承 FD 取锁成功 ✅ |
| 第二进程互斥 | L3 | 返回 75 + "另一项系统维护正在运行" ✅ |
| 伪造锁环境变量不被信任 | L2 | 伪造 FD 无效时回落到真实取锁（实测取到新 fd，未直接放行） ✅ |
| sysup 持锁时调用 checkallupdates | S6（真实 checkallupdates） | 锁状态探针显示 `LOCK-HELD-BY-SYSUP`，刷新正常完成、无死锁 ✅ |
| sysup 7 步顺序 | S1 桩日志 | 快照→(镜像新鲜跳过)→密钥环 `pacman -Sy`→`paru -Su`→`flatpak update -y`→`grub-mkconfig`→`checkallupdates --refresh`→`post-update-check --grub-status success` ✅ |
| 部分失败继续并累计 | S2/S3/S4 | Flatpak 失败/刷新失败/GRUB 失败都继续执行后续步骤，最终 `exit 1`；`--grub-status failed` 正确传递 ✅ |
| mirror-update 备份与轮换 | M1/M4 | 备份含 PID 严格命名 + `latest` 符号链接；`MIRROR_BACKUP_KEEP=2` 三次运行后刚好保留 2 份 ✅ |
| mirror-update 失败回滚 | M3 | 三次尝试全失败 → 恢复原 mirrorlist → `exit 1` ✅ |
| mirror-update SIGTERM | M6 | `exit 143`、mirrorlist 回滚 ✅ |
| post-update-check 契约 | 实测 | `--strict` → 1（有注意/缺失）；`--grub-status nope` → 2；查询失败 `exit 1` ✅ |
| recommend-check 契约 | 实测 | `--strict` → 0（本机 24 项全齐）；坏参数 → 2 ✅ |

---

## 4. 建议修复优先级（只描述，不改文件）

1. F-01/F-02/F-03（checkallupdates 的失败与并发语义）——同一段代码，一起改：mktemp/写状态/`mv` 全链路检查返回值、失败必须非零且不得显示为 `none`、孤儿回收加存活/持锁判断。
2. F-05（mirror-update 回滚来源）——避免把历史备份覆盖到用户当前文件。
3. F-06（`clear` 在 `set -e` 下）——非交互路径的硬失败，一行修复。
4. F-04（失败保留旧列表）、F-07（首次提示）、F-08（锁超时语义）、F-10（无 sudo 降级提示）。
5. 其余 P3：F-09、F-11～F-19。

