# Adversarial verification report — task-7 (`verify-findings`)

Verifier: `verify-findings`. Workspace `/home/pang/scripts/maintenance` was **never modified**
(`git status --porcelain` empty before and after). All fixtures live under `/tmp/vf/`, driven by
own stubs (symlink farm `/tmp/vf/farm`, `PATH` shims, `HOME` overrides). No state-changing command
was run; `cache-clean --list`, `offsite-backup --validate-target`, `quickload --list`,
`systemd-analyze`, `findmnt`, `mountpoint -q` are read-only.

Method: each claim was re-derived from the cited lines with its own commands; for every REFUTED or
downgraded item the disproving command is included. Verdicts: CONFIRMED / PARTIALLY CONFIRMED /
REFUTED / UNVERIFIABLE.

Environment: bash 5.2, GNU tar 1.35, zstd 1.5.7, fzf 0.74.3, jq 1.8.x, git 2.5x, uid 1000 `pang`
(groups include `greeter`), 16 CPUs, `/` and `/home` on btrfs (`/dev/nvme0n1p7`).

---

## L0. Lead's RCA of failing project test 46

**Claim:** `tests/run` fails at test 46; `grub_file_state` returns 2 for a non-traversable parent,
but the fixture path `/root/maintenance-unreadable-grub.cfg` is traversable by `pang`
(`/root` has `group:greeter:r-x`, pang ∈ greeter), so the file is diagnosed as missing → warning → exit 0.

**Verdict: CONFIRMED** (mechanism exact; consequence exact).

```
$ id -nG
pang greeter docker input wheel
$ getfacl /root | sed -n '1,8p'
# file: root
user::rwx
group::r-x
group:greeter:r-x
other::---
$ test -x /root; echo "rc=$?"          -> rc=0
$ chmod 000 /tmp/vf/notrav; test -x /tmp/vf/notrav; echo "rc=$?"   -> rc=1
```
`grub_file_state` (post-update-check:29-42, copied verbatim into a /tmp probe):
```
grub_file_state(/root/maintenance-unreadable-grub.cfg) => 1     # "missing"
grub_file_state(/tmp/vf/notrav/x.cfg)                  => 2     # "unreadable"
grub_file_state(/tmp/vf/definitely-absent.cfg)         => 1
```
End-to-end with own stubs (sudo/pacdiff/systemctl/uname), `POST_UPDATE_GRUB_CFG=/root/...`:
```
rc=0
│  [消息] 没有收到本次 grub-mkconfig 结果
│  [注意] /root/maintenance-unreadable-grub.cfg 不存在或为空
```
With a mode-000 parent instead: `rc=1`, `│  [错误] /tmp/vf/notrav/x.cfg 无法读取，GRUB 状态未完成验证`.
Full suite run (`MAINTENANCE_NO_NOTIFY=1 bash tests/run`) confirms `not ok 46 - post-update check must fail when GRUB cannot be read`, stderr only; tests 1-45 pass.

**Correction:** this is a **test-fixture environment assumption**, not a product defect:
`grub_file_state` correctly returns 2 when the parent is genuinely non-traversable. The fix belongs in
`tests/run:2405` (use a mode-000 dir instead of `/root/...`). Severity of the test failure: CI-only.

---

## H1. `term-menu` collapses every nonzero fzf status to "cancel" → exit 0

**Verdict: CONFIRMED** (mechanism and real-fzf reachability).

Code: `term-menu:705-707` `status=$?; [ "$status" -eq 0 ] || return 1`; `term-menu:1488`
`selected="$(choose_menu …)" || exit_menu`; `exit_menu` (771-779) → `exit 0`; README:324 documents 130.

```
$ PATH=/tmp/vf/shim130:$PATH timeout 20 bash term-menu </dev/null ; echo rc=$?
shim130 (fzf exec exit 130): term-menu rc=0
shim2   (fzf exec exit 2)  : term-menu rc=0
```
Real fzf 0.74.3 in a PTY with a wrapper logging fzf's own status; Ctrl+C after 1.5 s:
```
$ (sleep 1.5; printf '\003') | PATH=/tmp/vf/shimreal:$PATH script -qec "bash term-menu" /dev/null
script/term-menu rc=0
fzf wrapper logged status: 130
```
The `trap 'exit 130' INT` (term-menu:41) never fires because fzf consumes the key in raw mode.
Sub-menus call `choose_menu … || return 0`, and `delete_snapshot` (1137/1206/1215) cannot report a
real fzf error either — both as claimed.

**Correction:** none on mechanism. Severity HIGH is defensible for the documented-exit-code
contract, even though no data is harmed.

---

## H2. `ui_confirm` answers "yes" on EOF

**Verdict: CONFIRMED (mechanism); severity HIGH is inflated.**

```
$ bash -c '. lib/ui.sh; ui_confirm "危险操作" </dev/null;   echo rc=$?'
危险操作 [Y/n] rc=0
$ bash -c '. lib/ui.sh; ui_confirm "危险操作" n </dev/null; echo rc=$?'
危险操作 [y/N] rc=1
```
Callers verified: default-y are only `mirror-update:271` and `mirror-update:337`; all destructive
callers pass `n` (`clean:185`, `checkallupdates:590,663`, `quicksave:195`).
`mirror-update:271` on EOF takes `return 1` (abort), and `:337` accepts the *already detected*
country — neither is destructive. `mirror-update` has no non-interactive guard (`grep -n '\-t 0'` → none),
so EOF needs a closed/pipe stdin.

**Correction:** severity should be **LOW/MEDIUM** (library semantics hardening), not HIGH: no in-tree
default-y prompt triggers an unsafe action; the dangerous prompts already fail safe.

---

## M1. Lock path/ownership; root-first creation; undocumented exit 73

**Verdict: PARTIALLY CONFIRMED** — failure mode reproduced; root-first trigger reasoned, not executable here.

Reproduced (all three variants reach `rc=73`, exactly the code path at `lib/ui.sh:253-256`):
```
0555 parent dir, missing lock : 权限不够   → rc=73
0400 existing lock file       : 权限不够   → rc=73
root-owned 0644 file (/tmp/.mount_…, ro fs): 只读文件系统 → rc=73
```
Live lock is user-owned: `-rw-r--r-- pang pang ~/.cache/maintenance/maintenance-1000.lock` (not triggered).

Trigger evidence (not executable: `sudo -n true` → "需要密码"):
```
quickload:161  exec sudo "$SCRIPT_PATH" "$@"
quickload:1186 ui_maintenance_lock_acquire "快照恢复" || exit $?     # after re-exec
$ umask 022; mkdir -p d && : > d/f ; stat -c '%A %U:%G' d d/f
drwxr-xr-x pang:pang   -rw-r--r-- pang:pang
```
`lock_home` resolves `SUDO_UID` via `getent` (lib/ui.sh:217,226-228) → root writes into the user's
`~/.cache`, deterministically leaving `root:root 0755` dir + `root:root 0644` file; the user then
cannot open the file `O_WRONLY` → 73. README:322-324 lists 75/127/130 but **not 73**.

**Correction:** mechanism confirmed; root-first trigger only reasoned (needs root, no passwordless sudo
available). Severity MEDIUM stands.

---

## M2. CJK width miscount under a non-UTF-8 locale

**Verdict: CONFIRMED (mechanism); reachability narrowing noted.**

```
$ LC_ALL=C     bash -c '. lib/ui.sh; for s in 中文 ab 中文ab A中; do printf "%s -> %s\n" "$s" "$(ui_dwidth "$s")"; done'
中文 -> 6   ab -> 2   中文ab -> 8   A中 -> 4
$ LC_ALL=C.UTF-8 bash -c '…'
中文 -> 4   ab -> 2   中文ab -> 6   A中 -> 3
```
Cause is as cited: `ui.sh:435-441` byte indexing + `_ui_is_ascii`'s `local LC_ALL=C`.

**Correction:** no in-tree script sets a C locale before using `ui_dwidth`/`ui_pad`
(`grep -ln '^export LC_ALL=C' * | xargs grep -l 'ui_pad|ui_dwidth'` → none; `mirror-update` exports
`LC_ALL=C` but does no width math). So it requires an externally C/POSIX locale; LOW-MEDIUM in practice,
not medium-high. No error, only misalignment.

---

## P1 (menu-ui). `_UI_DWIDTH_CACHE` is dead at every call site

**Verdict: CONFIRMED.** Same string, one process, 300 iterations:
```
with $(ui_dwidth …): 329 ms      (1.10 ms/call)
direct _ui_dwidth_calc: 14 ms    (0.047 ms/call, cache entries=1)     ~23x
```
All `ui_dwidth` call sites are command substitutions (`ui.sh:572,690`, `term-menu:894,901,1382`);
`ui_pad` internally calls `_ui_dwidth_calc` (no fork) but every `ui_pad` caller also wraps it in `$( )`
(`term-menu:911-915,1292,1305-1307`, `ui.sh:603`). Reviewer's 489/17 ms vs my 329/14 ms — same effect.

---

## D1. `smart_value` `// empty` hides `smart_status.passed=false`

**Verdict: CONFIRMED (dead err branch); severity MEDIUM.**

```
$ jq -n 'false // empty'          -> (no output), rc=0
$ echo '{"smart_status":{"passed":false}}' | jq -r '.smart_status.passed // empty' -> (empty)
```
Own stub smartctl, real jq, stub lsblk (1 disk):
```
passed=false exit_status=0 (no strict): rc=0   │ [注意] 设备没有提供 SMART 总体结论      (no err)
passed=false exit_status=0 (--strict) : rc=1   │ same warning
passed=false exit_status=8            : rc=0   │ [注意] …没有提供 + [错误] smartctl 报告磁盘正在失效
passed=true  exit_status=0            : rc=0   │ [成功] SMART 总体健康检查通过
```
**Correction:** `storage-health:124` *does* surface an err line when smartctl sets bit 8 (the normal
case for a genuinely failing drive), so a real failing disk is not shown as merely 注意; however
`ui_tally_status` ignores `UI_N_ERR`, so **non-strict exit is 0 in every case**. The specific
`false)` branch is dead code. Keep MEDIUM (wrong classification, no false "healthy" in strict mode).

---

## D2. `terminal-tools` `rc=$?` after `if !` reads the negation

**Verdict: CONFIRMED.**

```
$ git config --global --unset-all nonexistent.key; echo rc=$?   -> 5
```
Temp HOME, valid state file, `core.pager` absent from git config, all other managed keys present:
```
$ MAINTENANCE_NO_NOTIFY=1 bash terminal-tools --disable ; echo rc=$?
[错误] 无法清除 Git 配置项 core.pager（退出码 0）。
[错误] Fish 集成已移除，但 Git 配置恢复失败；状态文件仍保留在: …/terminal-tools-git-before.tsv
rc=1        state file still there? yes
```
The intended "key absent (5) → tolerate" path is unreachable; `rc` is always 0 from the `!` compound.

---

## D3. Missing-command exit-code contract (README:323 promises 127)

**Verdict: CONFIRMED exactly.** Own symlink farm (`/tmp/vf/farm`) with one tool hidden per run:

| script | hidden | rc | message |
|---|---|---|---|
| gpu-check | lspci | **0** | `[缺失] 缺少 lspci，建议安装 pciutils` |
| storage-health | lsblk,btrfs | **0** | `[缺失] 缺少 lsblk（util-linux）` |
| hw-doctor | lscpu | 1 | `[缺失] 缺少 lscpu` |
| boot-check | findmnt | 1 | (findmnt branch) |
| pacnew-check | pacdiff | 1 | `[缺失] 缺少 pacdiff；请安装 pacman-contrib` |
| recommend-check | pacman | 1 | `[缺失] 缺少 pacman；这不是可识别的 Arch 环境` |
| log-check | systemctl,journalctl | 1 | `[缺失] 缺少 systemctl 或 journalctl` |
| check-battery | upower | **127** | `[错误] 未找到 upower…` |

Only `check-battery` honours the documented 127; `gpu-check`/`storage-health` exit 0 despite doing
nothing (both warnings land in the miss bucket, and `ui_tally_status` only fails in `--strict`).

---

## D4. gpu-check module filter misses Intel i915/xe

**Verdict: CONFIRMED.** Stub lspci (Intel Iris Xe, `Kernel driver in use: i915`) + stub lsmod (`i915`, `xe`):
```
gpu-check        rc=0  │ [成功] PCI 已识别 1 块显卡并读取驱动绑定 │ [注意] 未发现 amdgpu / nvidia / nouveau 模块
gpu-check --strict rc=1 │ same
```
On an Intel-only machine this is a false warning plus strict-mode failure; the awks at `gpu-check:197`
match only `amdgpu|nvidia|nouveau`.

---

## D5. storage-health reports "no btrfs mounts" as a query failure

**Verdict: CONFIRMED.**
```
$ findmnt -rn -t minix -o TARGET,SOURCE; echo rc=$?     (guaranteed no match)
rc=1        (stdout empty: out_bytes=0)
$ findmnt -rn -t btrfs -o TARGET,SOURCE                 (this host has btrfs)
/ /dev/nvme0n1p7[/@]                                    rc=0
```
`storage-health:199` treats rc=1 as failure → `[注意] Btrfs 挂载查询失败`; the
`BTRFS_COUNT -eq 0` → `[信息] 当前没有已挂载的 Btrfs 文件系统` branch (255-259) requires
`findmnt` rc=0 with empty output, which cannot happen. Reproduced with my stub (`VF_FINDMNT=none`):
warning printed, info branch absent.

---

## Perf P1 (batch 3). Snapshot-view rendering cost / fork attribution

**Verdict: CONFIRMED (scaling and cause); exact ratio corrected.**

Own stub snapper, 2 configs (root, home), short descriptions:
```
rows/config=10  -> 201 ms
rows/config=200 -> 3043 ms   (7.6 ms/row over 400 rows)
rows/config=500 -> 7120 ms
strace -f -e clone,clone3 on N=20 : 311 clone calls = 7.8 clones/row   (reviewer: 311, 7.8) ✔
```
Non-forking equivalent (repo untouched, `_ui_dwidth_calc` + `printf -v` in /tmp):
```
2×200 rows: 83 ms = 0.21 ms/row   (~37x faster)
```
**Correction:** I measured **~37x / 0.21 ms per row**, not the claimed ~65x / 0.09 ms (their harness
likely excluded row assembly). Cause attribution (6 `$(ui_pad)` + `$(ui_dwidth)` per row) confirmed by
the exact clone count. Long CJK descriptions are far worse (200 rows/config → 9.5 s) due to the
per-character `$(ui_dwidth "$ch")`.

## Perf P2. Three serial snapper calls, no parallelism

**Verdict: CONFIRMED.** `show_snapshots` issues exactly 3 snapper execve (`grep -c execve … snapper` = 3);
0.3 s stub latency: `0 s → 114 ms`, `0.3 s → 1016 ms` (≈3×300 + overhead). One `list-configs` + one
`list` per config, all sequential (term-menu:926,990).

## Perf P3. quickload `--list` / `--list-all`

**Verdict: CONFIRMED (structure/scale); fixture arithmetic differs.**
```
--list     0.3 s/list : 350 ms   snapper list calls=1   (total snapper calls=2)
--list-all 0.3 s/list : 669 ms   snapper list calls=2   (total=3)
--list     zero-lat, 200 rows: 663 ms
--list-all zero-lat, 200 rows: 1297 ms
```
My `list-configs` stub does not sleep; making it sleep reproduces the reviewer's 673/1015 ms
(2 vs 3 total calls at 0.3 s). Row rendering uses 3 `$(ui_pad …)` (quickload:456) → ~3 forks/row,
consistent with 0.66-1.3 s at 200 rows/config.

## Perf P4. checkallupdates refresh bookkeeping

**Verdict: CONFIRMED (numbers close); one sub-count corrected.**
```
--refresh        (zero-latency stubs): 72-75 ms;  strace execve = 56  (reviewer 71 ms / 59)
--refresh-stale  (all fresh)         : 71-72 ms;  strace execve = 38  (reviewer 75 ms / 37)
top commands: mktemp ×10, find ×6, mv ×8, touch ×4
```
**Correction:** I observed **0 `date` execve** (bash `EPOCHSECONDS` is used); the 6 date forks in the
reviewer's count came from their harness, the rest of the count matches.

## Perf P5. storage-health one `jq` per field

**Verdict: PARTIALLY CONFIRMED.** 3 stub disks, 5 KB JSON:
```
jq execve = 38  (≈12.7 per disk)   — reviewer: 12/disk, 126 total execve (all procs) ✔
3-disk run: 355 ms                 — reviewer: 474 ms
same 5 KB JSON: 12 parses 43 ms vs 1 parse 4 ms  (~11x) — reviewer 56 vs 3.4 ms (~16x)
```
Mechanism exact; magnitudes within ~30 %.

## Batch-3 deliberate non-findings (confirmed, do not file)

* `--refresh` really parallelises: stubs sleeping 1 s each → **1072 ms**, all three `ok`, data published.
* `--refresh-stale` with all stamps fresh → **0 query calls** (counter file absent).
* `cache-clean --list`: **2320 ms** with real `du` vs **145 ms** with an instant `du` stub → dominated by
  real traversal (94 %), not process overhead.

---

## B1. offsite-backup same-disk check ignores HOME's disk

**Verdict: PARTIALLY CONFIRMED** (first half confirmed, second half REFUTED).

Stubs: `/` → `/dev/sdA1` (disk sda); target under `*homeDisk*` → `/dev/sdB2` (disk sdb).
```
$ offsite-backup --target /tmp/vf/tgt/homeDisk/backup --validate-target
│  系统磁盘 /dev/sda
│  目标磁盘 /dev/sdb
[成功] 异盘备份目标有效且当前已挂载。          rc=0
```
`backing_disk` is only ever called for `/` and `$TARGET` (grep: lines 79, 83) — HOME's backing device
is never compared.
**REFUTED sub-claim** ("an unmounted target resolving onto the root filesystem is also accepted"):
```
$ offsite-backup --target /tmp/vf/tgt/rootfs/backup --validate-target
[错误] 目标与系统位于同一物理磁盘（/dev/sda），拒绝作为异盘备份。  rc=1
$ offsite-backup --target /tmp/vf/tgt/tmpfs/backup --validate-target
[错误] 目标文件系统 tmpfs 不具备持久备份语义，已拒绝。            rc=1
```
A target resolving onto the root filesystem is rejected by `offsite-backup:99-102`; a `/run/media`
target is rejected by the tmpfs check (or fails `[[ -d ]]`). Severity of the real half: MEDIUM/HIGH
depending on whether HOME lives on another disk than `/`.

## B2. `du`/`df` inside `$( )` + `set -euo pipefail` kills the script before the guard

**Verdict: CONFIRMED for offsite-backup; PARTIALLY for backup-restore:332. Severity MEDIUM (fails safe).**

Excerpt built from the exact cited lines (405-418), own mode-000 subdir:
```
$ du -sk /tmp/vf/dufix ; echo rc=$?      -> 196  /tmp/vf/dufix ; rc=1 (权限不够)
$ bash /tmp/vf/b2-excerpt.sh /tmp/vf/dufix /tmp/vf ; echo rc=$?
rc=1        (no "无法计算 HOME 大小…" message; du stderr discarded by 2>/dev/null)
control (dir readable): REACHED GUARD: HOME_KIB=196 FREE_KIB=5627364 ; rc=0
```
So the guard at 414-417 is effectively dead for this failure class: `pipefail` propagates `du`'s rc 1
into the assignment → errexit → silent exit. `backup-restore:332` has the identical pattern but is
preceded by `mkdir -p "$stage_parent"` (line 313), so its `df` can only fail in exotic states.
**Correction:** the reviewer's HIGH overstates it — the script aborts *before* creating anything
(fails safe) and only lacks an error message.

## B3. `du --exclude='.cache'` (any depth) vs tar `--exclude='./.cache'` (root-anchored)

**Verdict: CONFIRMED exactly.**
```
fixture: /tmp/vf/b3/sub/.cache/big.bin = 5000 KiB
du --exclude='.cache' …          -> 0 KiB        (nested cache silently excluded)
du without exclude               -> 5000 KiB
tar --zstd -cf out.tar.zst --exclude='./.cache' -C /tmp/vf/b3 .
tar -tf | grep -c 'sub/.cache'   -> 2            (nested .cache included in the archive)
tar -tf | grep -c '^\./\.cache/' -> 0            (top-level excluded)
```
Free-space precheck undercounts by all nested caches → ENOSPC risk. MEDIUM stands.

## B4. Retention prune never protects the set `latest` points to

**Verdict: PARTIALLY CONFIRMED** (mechanism confirmed; trigger unusual, severity corrected to LOW/MEDIUM).

`sed -n '/^prune_owned_sets()/,/^}/p'` contains **0** references to `latest`; the comparison
(`offsite-backup:276-284`) orders by name timestamp then PID. Own harness from the extracted
functions (`KEEP=2`, 4 owned sets, newest published set backdated):
```
prune rc=0
latest -> set-20251231-235959-999          <- still the target
surviving sets: set-20260102-000000-200 set-20260103-000000-300
```
i.e. the just-published set was `rm -rf`'d, `latest` dangles, and the script would still print
`异盘备份完成` and exit 0. **Correction:** requires clock skew backwards (or ≥KEEP same-second sets
with smaller PIDs — impossible for real multi-minute backups). MEDIUM is optimistic; LOW/MEDIUM.

## B5. migration-pack publish lacks an fsync/sync barrier

**Verdict: PARTIALLY CONFIRMED** (code fact confirmed; catastrophic outcome unproven).

`grep -n 'sync\|fsync' migration-pack` → **no matches**; sequence at 533-539 is
`mv -T backup_dir old_dir; mv -T staging backup_dir; rm -rf old_dir`, while `offsite-backup:449`
does `sync -f "$PUBLISHED"` before `verify_set`. `cleanup_pack` (EXIT trap) restores `old_dir` only if
`backup_dir` is absent *during process lifetime*, not after power loss.
**Correction:** "both lost" additionally requires metadata reordering across the two renames plus a
power cut; not reproducible here. Severity LOW; not a normal-run data-loss path.

## Batch-4 cleared items (confirmed)

* **GNU tar 1.35** — absolute member: extraction strips the leading `/` (warning) rc=0;
  `..` member: `tar: ../evil.txt：成员名称包含“..”` → **rc=2, file not created** (python-built tar).
* **Generated systemd unit** — reproduced the exact `[Unit]`+`[Service]` shape incl.
  `ConditionPathIsMountPoint=/tmp/vf/My\x20Disk/backup` and `ExecCondition=/usr/bin/mountpoint -q -- …`:
  `systemd-analyze --user verify` rc=0 for both `/` and the space path;
  `systemd-analyze condition` says succeeded for `/` (matches `mountpoint -q -- /` rc=0) and failed for
  the space path (matches rc=32).
* **`tar --zstd` multithreads** — tar passes no `-T`, but zstd 1.5.7 itself spawns worker threads:
  `strace -f -e clone` shows 6 clones inside the zstd process (10 with explicit `-T0`).

---

## S1. `clean all` keeps an incomplete newest batch and destroys the last complete set

**Verdict: CONFIRMED.** Harness = `clean:417-528` extracted verbatim + stub `snapper` + `sudo(){ "$@"; }`
(sudo stub delegates), fixture root: B2=#11, B1=#9; home: B1=#10.
```
INFO 将保留最近一套回滚快照（批次 B2）。
ITEM 保留快照 [root] ID 11 running（最近回滚点）
ITEM 已删除快照 [root] ID 9 pre-update
ITEM 已删除快照 [home] ID 10 running
OK 快照清理完成
deletes: DELETE root 9; DELETE home 10;      rc=0
```
Both halves of the last complete batch B1 are gone; only half of B2 remains, and the run reports
success — contradicting README:80. Precondition (partial newest batch) is reachable: `quicksave` has
**no INT/TERM/HUP trap** (grep: none) and rolls back only on a create *failure* (quicksave:329-336),
so Ctrl+C between configs leaves exactly this state; so does deleting one half via the menu.
Severity HIGH stands (silent loss of the only complete rollback point).

## S2. `clean all` batch-scan failure is fail-open

**Verdict: CONFIRMED exactly.** Same harness with the `--columns number,userdata` query failing
(exit 1, `|| true` swallows it) while the detail list succeeds:
```
INFO 清理快照
ITEM 已删除快照 [root] ID 11 running
ITEM 已删除快照 [root] ID 9 pre-update
ITEM 已删除快照 [home] ID 10 running
OK 快照清理完成
deletes: DELETE root 11; DELETE root 9; DELETE home 10;    rc=0, no warning
```
`keep_batch=""` disables the README:80 guard entirely; every non-`before*` snapshot in every config is
deleted with a success message. Severity HIGH stands.

## S3. quickload native restore/rollback: no signal trap around the renames; leaked mount

**Verdict: PARTIALLY CONFIRMED** (code-path; destructive test not possible).

`grep -n '^trap ' quickload` → only **`trap cleanup EXIT`** (line 304); `native_root_restore` installs
only `trap native_cleanup RETURN` (979, removed at 1042). Critical window: line 1021
(`mv $top/@ $top/$previous`) → line 1026 (`mv $top/$clone $top/@`); a fatal signal there leaves no `@`
(the second mv's *failure* path at 1027 restores the name, but signals do not).
Measured bash semantics (important correction to a common assumption):
```
$ bash -c 'trap "echo EXIT-TRAP-RAN" EXIT; kill -TERM $$; sleep 5'   -> EXIT-TRAP-RAN, rc=143
$ … kill -INT … -> EXIT-TRAP-RAN rc=130 ;  $ … kill -HUP … -> EXIT-TRAP-RAN rc=129
```
So the EXIT trap **does** run on untrapped INT/TERM/HUP — but `cleanup` (quickload:298-302) only
unmounts `MOUNT_DIR`, never `$top` (`/run/quickload-native-root.XXXXXX`); the RETURN trap does not fire
on signal-driven exit, so the `mount -o subvolid=5` mount leaks after any signal in that whole
function. **Correction/limits:** the unbootable window is sub-millisecond (two renames); exact leak
persistence requires a real btrfs mount (not executable here without root); severity MEDIUM rather
than HIGH, given the tiny window but catastrophic outcome.

## S4. Orphan `@quickload-restore-*` clone after publish failure

**Verdict: PARTIALLY CONFIRMED** (code asymmetry proven; btrfs removability reasoned).

`prepare_native_snapper_storage` (line 1012) creates `$clone/.snapshots` as a nested subvolume before
the renames. On first-mv failure the branch at 1023 uses **bare** `btrfs subvolume delete "$top/$clone"`
with `>/dev/null 2>&1 || true`, whereas `delete_native_restore_clone` (892-900) deletes
`$clone/.snapshots` first and exists precisely for that. A plain (non-recursive) btrfs subvolume delete
refuses a subvolume containing nested subvolumes, so the error is swallowed and the orphan remains
(besides, `native_cleanup`'s `rmdir "$top"` then also fails). The second-mv failure path (1026-1030)
restores `/@` but performs **no** clone cleanup at all. **Limit:** the exact btrfs error could not be
executed (needs btrfs + root); severity MEDIUM (cleanup leak, no data loss) confirmed.

## S5. btrfs-scrub splits mountpoints on spaces

**Verdict: CONFIRMED.** `btrfs-scrub:87` `while read -r mountpoint source`:
```
input:  /run/media/pang/My Disk /dev/sdb1
parsed: mountpoint=[/run/media/pang/My] source=[Disk /dev/sdb1]
with IFS=$'\t': mountpoint=[/run/media/pang/My Disk] source=[/dev/sdb1]
```
Affects `--status/--start/--enable` and device dedupe as claimed.

## S / snapshots extras

* **quickload `|` delimiter corruption — CONFIRMED.** `quickload:839` builds `"$desc|$conf|$sid|$date"`
  and `:456` re-splits on `|`. Stub with description `my|custom desc`:
  `- my   [配置: custom desc-1 | ID: root | 时间: 1|2026-09-01 10:00:00]` vs correct control row.
* **quicksave has no INT trap — CONFIRMED** (`grep -n 'trap ' quicksave` → none; rollback only on
  create failure, quicksave:329-336).
* **README:79 single-call contrast — CONFIRMED.** `quicksave:292` `snapper -c "$DEL_TARGET" delete
  "${OPT_DELETE[@]}"` (one call) and `term-menu:1063` `run_tool quicksave -c "$conf" "${del_args[@]}" --yes`;
  `clean:478` loops `sudo snapper -c "$conf" delete "$snap_id"` per ID. The README sentence is about the
  menu delete, so it holds there and not for `clean all`.

---

## A0 (adjudication). post-update-check severity / sysup reachability

**Verdict: lead's counter-evidence CONFIRMED; the reviewer's CRITICAL is REFUTED.**

Missing `/root/...grub.cfg` × status (my stubs):
```
success rc=1  [错误] …不存在、为空或无法验证
failed  rc=1  [错误] …不存在、为空或无法验证
skipped rc=0  [注意] …不存在或为空
unknown rc=0  [注意] …不存在或为空
```
sysup only passes `--grub-status "$grub_status"` with `grub_status` ∈ {skipped (initial, sysup:322),
success (:384), failed (:387)} and, on rc≠0, warns and sets `post_update_failed=1` (sysup:422-425),
then `return 1` (sysup:428-431).
**Therefore "sysup reports step 7 OK while GRUB is actually broken" is NOT reachable:**
* success/failed + missing cfg → post-update-check rc 1 → sysup warns + fails;
* skipped is only reached when `grub-mkconfig` is absent, and that branch already sets
  `post_update_failed=1` (sysup:392-395), so sysup still fails.
Correct severity: **LOW/MEDIUM** for the standalone default (`unknown`) misleading "注意" result —
which is exactly the test-46 disagreement (L0), not a critical sysup path.

## A1. fzf kills the reload child untrappably; leaked files; lock

**Verdict: PARTIALLY CONFIRMED** — live leak and untrappable kill confirmed; lock-held timing and
"orphaned query trees" not reproduced.

Live cache (read-only inspection):
```
~/.cache/checkallupdates (2026-09-09 23:32): repo.wtRXoN, aur.9UD52T (206 B),
  flatpak.Kgp8Xe, status.{e3xIgT,IrxAvs,sCXqV3,V7kBwM}, error.{l5XpoF,QEYFvl,XzivVw}  = 10 temp files
  last-refresh 21:54 (aur/flatpak 21:49); updates-aur.txt 206 B (same size as the uncommitted aur temp)
```
README:32-33 claims the opposite ("会收掉后台查询进程并清理临时文件"). Real fzf 0.74.3 PTY probe with
own traps logging:
```
$ (sleep 2; printf '\003') | script -qec "printf 'a\nb\n' | fzf --bind 'load:reload(bash reload.sh)'"
reload.log: start <pid>; grandchild <pid>     (NO TRAP-INT/TERM/HUP/EXIT lines)
same-group grandchild: dead     setsid-detached grandchild: ALIVE
```
So fzf kills the reload child (and its process group) with SIGKILL — untrappable, matching the leaked
files. **Corrections:** (a) `flock -w 2` now acquires immediately (rc=0, no holder 9 h later), so the
2.001 s lock contention was a transient at 23:32 and is not reproducible; (b) because fzf kills the
whole group, the checkallupdates query subshells (same group, not `setsid`) are killed too — the
"orphaned query trees" detail is likely wrong, while the temp-file leak is certain. Severity HIGH stands
for the untrappable-kill design flaw (leaks + a stale lock for up to the next refresh).

## A2. Failed cache publish still reports rc=0 / pacman:ok

**Verdict: CONFIRMED** (mechanism slightly corrected). Own `mv` shim failing only for
`updates-repo.txt`, zero-latency sources, temp HOME:
```
rc=0
source-status.tsv:  pacman ok   /  aur skipped  /  flatpak ok
last-refresh-pacman + last-refresh both touched (same second)
updates-repo.txt: NO    stdout: only the aur "未检查" row
stderr: mv: 模拟发布失败: …/updates-repo.txt
```
**Correction:** the `mv` failure is not ignored by `set -e` — it aborts the query subshell *after*
`printf 'pacman\tok'` was already written (checkallupdates:266-270); the parent's
`wait` rc is then discarded by `_cau_settle_status` (which reads the stale `ok` line) and the stamp is
touched. Observable result is exactly as claimed.

## A3. Missing data files + fresh stamps → `--refresh-stale` queries nothing, touches stamp, prints None

**Verdict: CONFIRMED exactly.**
```
setup: cache dir with only last-refresh-{pacman,aur,flatpak} touched + source-status.tsv (all ok);
       no updates-*.txt, no last-refresh
$ checkallupdates --refresh-stale   -> rc=0
stdout: none - [None]    当前没有待更新项目
checkupdates calls: 0
after: data files: 0, CACHE_STAMP: yes (re-touched), status still all ok
```
This is the downstream state produced by A2; the degraded cache is presented as "nothing to update".
Severity HIGH stands (misleading result, stamp extended for another hour).

## A4. `flock -w … || true` refreshes anyway on timeout

**Verdict: CONFIRMED.** External holder `( exec 9>>refresh.lock; flock 9; sleep 5 ) &`, run with
`CHECKALLUPDATES_LOCK_WAIT=1`:
```
rc=0 elapsed=1072 ms (lock held externally for 5 s)
queries executed anyway: 1
CACHE_STAMP updated: yes; updates-repo.txt exists: yes
```
No mutual exclusion after the wait; the 300 s default wait happens inside fzf's blocking reload-sync.

## A5. `timeout 1` without `-k` honours a TERM-ignoring child

**Verdict: CONFIRMED exactly.**
```
$ timeout 1 bash -c 'trap "" TERM; sleep 5'        -> rc=124 elapsed=5005 ms
$ timeout -k 1 1 bash -c 'trap "" TERM; sleep 5'    -> rc=137 elapsed=2003 ms
```
`run_query` (`checkallupdates:238-244`) uses plain `timeout "$QUERY_TIMEOUT"`.

## Updates extras

* **Nested lock sysup → mirror-update via inherited fd — CONFIRMED.** Parent acquires
  `MAINTENANCE_LOCK_FILE=/tmp/vf/nested.lock` (rc=0); child process running a fresh `bash -c` that
  sources `lib/ui.sh` inherits `UI_MAINTENANCE_LOCK_FD`/`MAINTENANCE_LOCK_HELD=1`, its fd reads
  `-> /tmp/vf/nested.lock`, acquire → rc=0. An independent process with the env vars stripped →
  `[注意] 另一项系统维护正在运行…` rc=**75**.

---

## Summary table

| # | Claim (short) | Verdict | Severity after verification |
|---|---|---|---|
| L0 | test 46 fails because `/root` is traversable via `greeter` ACL | CONFIRMED | test-fixture bug (CI only) |
| H1 | any nonzero fzf status → `term-menu` exit 0, not 130 | CONFIRMED | HIGH (contract violation, no data harm) |
| H2 | `ui_confirm` EOF = default answer | CONFIRMED mechanism | **LOW/MEDIUM** (no in-tree default-y destructive caller) |
| M1 | root-first lock creation → user EACCES → exit 73 undocumented | PARTIALLY CONFIRMED | MEDIUM (trigger not executable here) |
| M2 | CJK width wrong under non-UTF-8 locale | CONFIRMED | **LOW/MEDIUM** (needs external C locale; no in-tree path) |
| P1 | `_UI_DWIDTH_CACHE` dead at every `$( )` caller | CONFIRMED | perf LOW (23× on width calls) |
| D1 | `jq // empty` makes `passed=false` unreachable | CONFIRMED | MEDIUM (bit 8 still prints err; non-strict rc 0 always) |
| D2 | terminal-tools `rc=$?` after `if !` breaks rc=5 tolerance | CONFIRMED | MEDIUM |
| D3 | missing-command contract: gpu-check/storage-health exit 0, only check-battery 127 | CONFIRMED | MEDIUM |
| D4 | gpu-check module filter ignores i915/xe | CONFIRMED | MEDIUM (false warn + strict fail on Intel) |
| D5 | storage-health treats "no btrfs" as query failure | CONFIRMED | LOW/MEDIUM |
| P1b | snapshot view ~7.4 forks/row, 7.3 ms/row | CONFIRMED (311 clones exactly) | perf HIGH in interactive path |
| P2 | 3 serial snapper calls | CONFIRMED | perf MEDIUM |
| P3 | quickload list 2-3 snapper calls + 3 forks/row | CONFIRMED | perf MEDIUM |
| P4 | refresh bookkeeping ~56-59 execve / ~72 ms | CONFIRMED (0 date forks, not 6) | perf LOW |
| P5 | 12 jq/disk | PARTIALLY CONFIRMED (38 jq/3 disks; ~11×) | perf MEDIUM |
| NF1 | `--refresh` parallelises (3×1 s → ~1.07 s) | CONFIRMED | non-finding |
| NF2 | `--refresh-stale` 0 queries when fresh | CONFIRMED | non-finding |
| NF3 | cache-clean `--list` = real `du` traversal | CONFIRMED (2320→145 ms with du stub) | non-finding |
| B1 | same-disk check ignores HOME disk | PARTIALLY CONFIRMED (HOME half CONFIRMED; root-fs half **REFUTED**) | MEDIUM/HIGH |
| B2 | `du`/`df` pipefail dies before the guard | CONFIRMED (backup-restore:332 PARTIAL) | **MEDIUM** (silent fail-safe abort) |
| B3 | `du --exclude='.cache'` undercounts nested caches | CONFIRMED (0 vs 5000 KiB) | MEDIUM |
| B4 | prune can delete the set `latest` points to | PARTIALLY CONFIRMED (simulated; needs clock skew) | **LOW/MEDIUM** |
| B5 | migration-pack publish lacks sync barrier | PARTIALLY CONFIRMED (barrier absent; both-lost unproven) | **LOW** |
| S1 | `clean all` keeps incomplete newest batch, kills last complete set | CONFIRMED | HIGH |
| S2 | batch-scan failure → delete everything, no warning | CONFIRMED | HIGH |
| S3 | no signal trap around restore renames; leaked mount | PARTIALLY CONFIRMED (EXIT trap *does* run; it just ignores `$top`) | MEDIUM (sub-ms window) |
| S4 | orphan restore clone; bare `btrfs subvolume delete` | PARTIALLY CONFIRMED (code asymmetry; btrfs behavior not executable) | MEDIUM |
| S5 | btrfs-scrub splits mountpoints on spaces | CONFIRMED | MEDIUM |
| A0 | post-update-check CRITICAL / "sysup step 7 OK" | reviewer REFUTED (lead counter-evidence CONFIRMED) | LOW/MEDIUM (standalone default only) |
| A1 | fzf untrappable reload kill leaks temps/lock | PARTIALLY CONFIRMED (leak certain; lock timing + orphan trees not) | HIGH for the design flaw |
| A2 | failed publish still rc=0/pacman:ok | CONFIRMED | HIGH |
| A3 | missing data + fresh stamps → "nothing to update" | CONFIRMED | HIGH |
| A4 | `flock -w \|\| true` refreshes anyway | CONFIRMED | MEDIUM |
| A5 | `timeout 1` = 5 s against TERM-ignoring child | CONFIRMED | MEDIUM |
| C1 | tar 1.35 rejects `..`, strips absolute paths | CONFIRMED (cleared) | non-finding |
| C2 | generated units pass `systemd-analyze --user verify`; condition == `mountpoint -q` | CONFIRMED (cleared) | non-finding |
| C3 | `tar --zstd` multithreads | CONFIRMED (zstd's own default) | non-finding |
| C4 | nested sysup→mirror-update lock via inherited fd | CONFIRMED (cleared) | non-finding |
| C5 | quickload `\|` delimiter corrupts the picker | CONFIRMED | MEDIUM |
| C6 | quicksave has no INT trap; README:79 one-call holds for `-del` but not `clean all` | CONFIRMED | MEDIUM / doc nuance |

**Highest-value corrections for the lead:** H2, M2, B2, B4, B5 and S3 severities are inflated;
B1's "root-filesystem target accepted" half is refuted; A0's CRITICAL/sysup path is refuted;
P1b/P5 perf magnitudes are within ~30-40 % but not exact; A1's lock-contention and orphan-tree details
are unreproducible while the leak itself is certain.
