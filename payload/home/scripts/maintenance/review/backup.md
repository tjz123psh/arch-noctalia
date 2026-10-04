# Review: backup-restore (525L), offsite-backup (480L), offsite-backup-schedule (448L), migration-pack (1046L)

Reviewer: review-backup (task-4) · READ-ONLY review · 2025-09-10
Workspace: `/home/pang/scripts/maintenance` @ working tree (no files created/modified in the workspace).
Scratch/experiments: `/tmp/maintenance-review/exp/` only. No real backup, restore, schedule install or HOME write was performed.

Method: every line of the four scripts was read (read tool, line-numbered); line references were re-verified with `grep -n`.
Cross-checks with `lib/ui.sh` (lock/tmp traps), `lib/config.sh`, `tests/run`, `README.md`, `migration-profile.example`.
Empirical fixtures under `/tmp` were used for: same-disk detection, `du` vs `tar` exclusion semantics, `set -e`+`pipefail`
command-substitution aborts, GNU tar path-traversal behavior, `systemd-analyze --user verify`, zstd threading, tar member-query cost.
Suite `tests/run` was read (not executed) to see which behaviors are already pinned.

Severity counts: **critical 0 · high 2 · medium 6 · low 13 · perf 5**

---

## CRITICAL

None found. No finding in scope can silently destroy existing backup sets or user data; the destructive operations
(`rm -rf` of staging/published/rotated sets) are all path-constructed inside the destination with `:?`/non-empty guards
(`offsite-backup:343,389,395`, `migration-pack:506,537`, `backup-restore:438`).

---

## HIGH

### H1. Same-disk rejection compares the target against `/`, never against HOME's own disk
**File:line:** `offsite-backup:81-88` (ROOT_DISK/TARGET_DISK computed), `offsite-backup:103-106` (only comparison made)

```bash
81: if ! ROOT_DISK="$(backing_disk /)"; then            # <-- source of data is HOME, but root disk is measured
85: if ! TARGET_DISK="$(backing_disk "$TARGET")"; then
103: if [[ "$ROOT_DISK" == "$TARGET_DISK" ]]; then
104:   ui_err "目标与系统位于同一物理磁盘（%s），拒绝作为异盘备份。" "$ROOT_DISK"
```
HOME is never passed to `backing_disk`. On any machine where `$HOME` lives on a different physical disk than `/`
(separate home SSD/HDD, LUKS home disk, etc.) a target on HOME's own disk is accepted as "异盘".

**Evidence (executed, stubbed `findmnt`/`lsblk`, `--validate-target` only, no writes):**
`/tmp/maintenance-review/exp/samedisk/run.sh`, case A (root=`/dev/rootp1`→rootdisk, HOME=`/dev/homediskp1`→homedisk, target=`/dev/homediskp1`):
```
rc=0
│  系统磁盘            /dev/rootdisk
│  目标磁盘            /dev/homedisk
[成功] 异盘备份目标有效且当前已挂载。
```
Case B (target `/dev/loop9`; the stub `lsblk -s` emits only `loop9 loop`, no `disk` ancestor → `backing_disk` falls
back to printing the device itself at `offsite-backup:75`) is likewise accepted: `目标磁盘 /dev/loop9` → rc=0.
*Suspected for real systems:* no loop device exists on this host, so real `lsblk` output for a mounted loop device could
not be observed; the code path itself is proven, and a loop device never equals the root disk name.
Second consequence of the same gap: an **unmounted** target directory (e.g. `/run/media/$USER/BACKUP` with the disk
removed) resolves to the root filesystem (`findmnt -T` → `/dev/nvme0n1p7[/@]` on this host). When HOME is on another
disk, that no longer equals `ROOT_DISK`, so the script would create `maintenance-backup-$HOST` and archive the whole
HOME **onto the system disk** — the exact outcome `README.md:281-282` and `offsite-backup:35` promise to prevent.
`offsite-backup` never checks `mountpoint`/`findmnt TARGET` itself; only the systemd unit does (`offsite-backup-schedule:268-271,309,315`).

**Impact:** a backup that is believed to be offsite is in fact on the same physical device as the only copy of HOME
(or silently written to the system disk). Total data loss on disk failure; the tool's core safety property is void.

**Fix:** compute `HOME_DISK="$(backing_disk "$HOME")"` (or the SOURCE of `findmnt -no SOURCE -T "$HOME"`) and reject
unless `TARGET_DISK` differs from both `HOME_DISK` and `ROOT_DISK`; additionally require that `findmnt -no TARGET -T "$TARGET"` is not `/`
(i.e. the target really is a mounted foreign filesystem), and treat a `loop` device with no disk ancestor as non-offsite.

---

### H2. Unguarded `du`/`df` command substitutions abort the whole backup silently under `set -euo pipefail`
**File:line:** `offsite-backup:407-417` (estimate) and `offsite-backup:413` (free space); same pattern `backup-restore:332`

```bash
407: HOME_KIB="$(du -sk --exclude='.cache' ... "$HOME_SNAPSHOT_SOURCE" 2>/dev/null | awk '{print $1}')"
413: TARGET_FREE_KIB="$(df -Pk "$TARGET" | awk 'NR == 2 {print $4}')"
414: if [[ ! "$HOME_KIB" =~ ^[0-9]+$ || ! "$TARGET_FREE_KIB" =~ ^[0-9]+$ ]]; then
415:   ui_err "无法计算 HOME 大小或目标剩余空间。"
```
`set -euo pipefail` (line 2) applies to the pipeline inside the assignment: if `du` returns non-zero (it does for any
unreadable/undiscoverable entry) the assignment fails and the shell exits **before** reaching the intended graceful
check at 414-417. `du`'s stderr is discarded (`2>/dev/null`), so nothing is printed at all.

**Evidence (executed, exact statement shape):**
```
$ bash -c 'set -euo pipefail
HOME_KIB="$(du -sk /tmp/.../home 2>/dev/null | awk "{print \$1}")"
echo "REACHED validation with HOME_KIB=$HOME_KIB"'
rc=1     # nothing printed: aborted inside the assignment, guard at 414-417 unreachable
$ du -sk /tmp/.../home 2>/dev/null ; echo rc=$?
4   /tmp/.../home
rc=1
```
(Same for `TARGET_FREE_KIB=...df...` and for `free_kib="$(df -Pk "$stage_parent" | awk ...)"` at `backup-restore:332`.)

**Impact:** any permission anomaly inside HOME (a root-owned or mode-000 directory under HOME, etc.), or the target
becoming unavailable mid-run, makes `offsite-backup` exit 1 right after "正在估算 HOME 备份大小和目标可用空间；请稍候…"
with **no error message**, release the snapshot, delete staging, and leave the user with no diagnosis.
The carefully written Chinese error at 415 is dead code.

**Fix:** guard every such probe, e.g. `HOME_KIB="$(du ... 2>/dev/null | awk ... )" || HOME_KIB=""` (or `local rc` capture)
so the 414 check actually runs, and keep `du`/`df` stderr visible in the failure message.

---

## MEDIUM

### M1. Free-space pre-check underestimates: `du` excludes basenames at any depth, `tar` excludes only top-level
**File:line:** `offsite-backup:407-412` vs `offsite-backup:429-435`

```bash
407: HOME_KIB="$(du -sk --exclude='.cache' --exclude='.local/share/Trash' --exclude='migration' --exclude='migration-backup' ...
429: tar --zstd -cf "$ARCHIVE" --one-file-system --exclude='./.cache' --exclude='./.local/share/Trash' \
433:   --exclude='./migration' --exclude='./migration-backup' -C "$HOME_SNAPSHOT_SOURCE" .
```
GNU `du --exclude='.cache'` (no `/` in the pattern) matches the **basename at any depth**; tar's `'./.cache'` is
anchored to the archive root. The estimate therefore excludes nested `**/.cache`, `**/migration`, etc. that tar does archive.

**Evidence (executed):**
```
du --exclude='.cache' home   -> 0 KiB        # home/proj/.cache/nested excluded from the estimate
tar --zstd -tf t.tar.zst     -> ./.local/ ... ./proj/.cache/nested included
tar --zstd -tvf size         -> 5000 KiB     # actually archived
```
**Impact:** `REQUIRED_KIB=$((HOME_KIB + HOME_KIB/10))` (`:418`) can pass while the archive is much larger than the
10 % margin; the run then dies with ENOSPC mid-archive (recoverable: staging is cleaned, old `latest` preserved, but a
full backup window is wasted). `~/Projects/*/node_modules/.cache`-style trees are common.
**Fix:** derive the estimate from the same member list as the archive (one `tar -tvf | awk '$3 ...'` pass, as
`backup-restore:316` already does) or use `--exclude='*/.cache'`-style patterns in `du` so both agree.

### M2. Retention can delete the set that `latest` currently points to
**File:line:** `offsite-backup:341-347` (prune) called at `:468`, after `latest` publish at `:451-455`

```bash
341: for ((i = KEEP; i < ${#owned_sets[@]}; i++)); do
342:   old_set="$DEST/${owned_sets[i]}"
343:   if ! rm -rf -- "${old_set:?}"; then ...
468: prune_owned_sets || RETENTION_FAILED=1
```
Ordering/selection are by set *name* (`backup_set_is_newer`, `:276-285`), and the set named by `$DEST/latest` is never
protected. If the newest set by name is not the set just published — clock stepped backwards (wrong RTC then NTP), or a
same-second name tie broken by PID (`:283-284`), or later sets copied/restored with future names — and `KEEP` is small,
the loop deletes the freshly published set while `latest` still points at it. The run then exits 0 ("异盘备份完成"),
leaving a dangling `latest` that makes `offsite-backup --check` (`:296`) and `backup-restore --set latest` fail.

**Evidence:** logic proven by reading `:276-285,314-348,451-468`; the clock-skew trigger was not executed.
**Impact:** the newest verified backup is deleted by its own retention pass; silent until the next verification.
**Fix:** exclude the current `readlink "$DEST/latest"` target from the deletion list (and/or prune before publishing
`latest`, or order by `stat -c %Y` instead of the name).

### M3. `migration-pack` deletes the previous package before the new one is durable (no `sync`)
**File:line:** `migration-pack:533-539`

```bash
533: if [[ -e "$backup_dir" || -L "$backup_dir" ]]; then mv -T -- "$backup_dir" "$old_dir"; fi
534: mv -T -- "$staging" "$backup_dir"
537: rm -rf -- "$old_dir"
```
Nothing syncs `$staging` or `$parent` between the rename and the deletion of the old package. Contrast
`offsite-backup:449` which explicitly runs `sync -f "$PUBLISHED"` before publishing `latest`.
**Evidence:** code reading; crash window not reproduced (suspected — power loss / hard reset within the window).
**Impact:** after a crash the published directory can exist with an unwritten/truncated `payload/home-config.tar.zst`
(and a `SHA256SUMS` that no longer verifies) while the previous good package has already been removed → the migration
package, often the only offsite copy of `~/.ssh` and dotfiles, is lost.
**Fix:** `sync -f "$parent"` (syncfs) after the new package is fully written and after the rename, before `rm -rf "$old_dir"`.

### M4. Staging left behind by SIGKILL/power loss is never reclaimed
**File:line:** `offsite-backup:377-382` (`STAGING="$DEST/.$SET_NAME.tmp"`, removed only by the EXIT trap at `:383-398`),
`migration-pack:491,498-510`, `backup-restore:312-313,339,437-441`

All three scripts create a staging directory and rely exclusively on traps (EXIT/INT/TERM/HUP/QUIT) for its removal.
SIGKILL (OOM killer, `kill -9`, power loss) leaves the directory; no code path ever scans for or reclaims
`$DEST/.set-*.tmp`, `$parent/.${base}.new.*`, or `$stage_parent/set-restore.*`. Note `offsite-backup` *does* implement
stale-snapshot reclamation (`remove_stale_home_snapshots`, `:145-164`) but not stale-staging reclamation.
**Evidence:** code reading (absence of any `find ... -name '.set-*'` / `.new.*` cleanup); the trap behavior is
confirmed by the suite's own signal test (`tests/run:1745-1751,1800-1807`) which only covers catchable signals.
**Impact:** a killed long backup leaves a full or partial archive on the backup disk; over time this fills the target and
silently inflates the next run's free-space picture, causing failures the user must clean up by hand.
**Fix:** at startup remove `$DEST/.set-*.tmp` older than a few hours (offsite), `$parent/.${base}.new.*` (migration) and
`$stage_parent/set-restore.*` (backup-restore), reporting what was reclaimed.

### M5. `verify_set` verifies the backup with `migration-pack --check` (live-system comparison) instead of `--verify`
**File:line:** `offsite-backup:273` → `migration-pack:1004-1012` (`--check` ⇒ `run_check "$dir"` with `compare_system=1`; `--verify` ⇒ `0`)

```bash
273:   "$SCRIPT_DIR/migration-pack" --check "$set_dir/migration"
```
For legacy (v1) migration directories `run_check_v1` with `compare_system=1` compares backup package lists against the
**live** system and sets `validation_failed=1` when a live query fails (`migration-pack:669-672,838,850-851`), and walks
`tar-manifest.txt` against `$HOME` (`:858-870`). So verifying a *backup* can fail for unrelated live-system reasons
(pacman db unavailable/locked) and burns pacman queries on every `--check`/backup verification.
**Evidence:** code reading; `backup-restore:464` already uses the correct `--verify`.
**Impact:** false verification failures, misleading "missing package" text during a backup run.
**Fix:** call `migration-pack --verify "$set_dir/migration"` from `verify_set`.

### M6. `offsite-backup-schedule --run` reports success when the service was skipped
**File:line:** `offsite-backup-schedule:405-408`, with the skip guards at `:309` (`ConditionPathIsMountPoint`) and `:315` (`ExecCondition=/usr/bin/mountpoint`)

```bash
407: systemctl --user start "$SERVICE_NAME"
408: ui_ok "备份服务已完成。"
```
A unit-level condition failure prevents activation and a start job completes successfully (`systemctl start` returns 0);
an `ExecCondition` exit 1-254 is explicitly documented as "the unit is *not* marked as failed" (systemd.service(5),
``ExecCondition=``). When the backup disk is not mounted the service is skipped, yet line 408 prints "备份服务已完成。".
The weekly timer behaves the same way: the journal shows a successful activation with no backup created and no retry.
(The skip itself is intended — `README.md:281-282` — the false success report is not.)
**Evidence:** man page `systemd.service.5` quoted above (local file); the systemctl-returns-0-on-condition-skip behavior
was not executed against a live user manager in this review (no units installed, per scope rules).
**Impact:** the documented smoke test (`--run`) cannot distinguish "backup done" from "disk absent"; a user who forgets
to plug in the disk believes the schedule works.
**Fix:** after `start`, check `systemctl --user show -p Result,ExecMainStatus "$SERVICE_NAME"` (or `latest` mtime) and
report a skip explicitly with a non-zero exit for `--run`.

---

## LOW

### L1. v1 key-content checks can never fail validation
**File:line:** `migration-pack:723-732` (`check_archive_entry` always returns 0), used at `:807-812`, verdict at `:874-878`
A v1 package whose archive lacks `pkg-deps.html`, `scripts/`, `md/`, `.config/fish/`, `.config/niri/`,
`.config/opencode/` prints warnings but still ends with "迁移包结构与校验和有效" and rc 0.
**Fix:** track a failure flag in `check_archive_entry` (or `|| validation_failed=1` at the call sites) if the missing
key content is meant to be fatal.

### L2. A symlinked profile is rejected even for an explicit `--profile`
**File:line:** `migration-pack:174` (`-f` follows symlinks) vs `migration-pack:180` (`[[ -f "$profile" && ! -L "$profile" ]]`)
**Evidence (executed):** `migration-pack --plan --profile .../link.conf` (symlink → real.conf) →
`[错误] 迁移配置档不存在或不是普通文件: /tmp/.../link.conf`, rc=1. Symlinking
`~/.config/maintenance/migration-profile.conf` into a dotfiles repo is a common pattern and is silently rejected with a
"does not exist" message.
**Fix:** either accept `-L` files that resolve to regular files, or say explicitly that symlinks are refused and why.

### L3. Profile parser cannot express paths with spaces and does not strip CR
**File:line:** `migration-pack:185-192`
`IFS=$' \t' read -r kind path extra <<< "$line"` makes any path containing a space "格式无效" (verified:
`include My Docs` → rc 1), and CRLF profiles are not normalized (contrast `lib/config.sh:70` which strips `\r`).
**Evidence (executed):** a CRLF profile (`include scripts\r\n`) is accepted, the path is silently treated as
non-existent (`scripts^M` under "不存在，跳过"), the plan exits 0, and `--pack` then fails with
"迁移配置档没有任何存在的可打包路径".
**Fix:** `line="${line%$'\r'}"`, and support quoting or a tab separator for paths containing spaces.

### L4. `backup-restore` reports user cancellation as success (exit 0)
**File:line:** `backup-restore:23-28` (`cancel_to_parent`), used at `:510`
Declining the keyword confirmation exits 0 unless `TERM_MENU_CHILD=1`. An automated caller cannot distinguish
"cancelled, HOME untouched" from "HOME restored"; the printed warning is the only signal.
**Fix:** exit 130 (or a dedicated code) for cancellation in the non-menu case.

### L5. Missing-tool coverage is incomplete
**File:line:** `backup-restore:62` (checks `awk comm df find grep pacman realpath sha256sum sort systemctl tar`), `migration-pack:18` (no dependency check at all), `offsite-backup:64`
Neither list includes `zstd` although both use `tar --zstd`; migration-pack additionally assumes `pacman`,
`sha256sum`, `tar`, `zstd` and (for `--pack`) `find`, `sort`. Failures surface as raw tar/command errors mid-run
(after inventories have been collected).
**Fix:** add `zstd` to `backup-restore`/`offsite-backup` checks and a small `require` list to `migration-pack`.

### L6. Path-containment denylist misses `./`-prefix variants (not exploitable with GNU tar 1.35)
**File:line:** `backup-restore:262-270` and `:294-302`
`normalized="${entry#./}"` strips only one leading `./`; e.g. `.//..` and `.//etc/passwd` do not match
`"$entry" == /*`, `"$normalized" == ".."`, `"../*"` or `"*/../*"`.
**Evidence (executed, `tar (GNU tar) 1.35`):** tar itself refuses interior `..` members
(`tar: 成员名称包含“..” … rc=2`) and strips leading `/` from members on extraction, so the gap is defense-in-depth
only; the same protect-by-denylist style misses newline-embedded member names (line-based reading).
**Fix:** replace the denylist with a containment check (`realpath -m -- "$STAGE/$normalized"` must stay under
`$STAGE`), or state that GNU tar's own protections are the guarantee.

### L7. `mv` without `-T` when publishing a set
**File:line:** `offsite-backup:447` (`mv -- "$STAGING" "$PUBLISHED"`)
If `$PUBLISHED` exists (leftover from a run whose cleanup failed), `mv` nests the staging directory *inside* it instead
of replacing it; the subsequent `verify_set "$PUBLISHED"` fails and cleanup `rm -rf`s the whole directory. Low likelihood
(name = timestamp+PID) but the failure is confusing. **Fix:** `mv -Tf -- "$STAGING" "$PUBLISHED"` after an explicit
existence check.

### L8. Crash ordering: `latest` rename is not durable before old sets are pruned
**File:line:** `offsite-backup:455` (rename), `:468` (prune), `:470` (`sync -f "$DEST"`)
A crash between prune and `sync` can leave the `latest` rename undurable while old sets were already removed; if
`latest`'s old target was among the pruned sets, `latest` dangles. Suspected (crash window not reproduced).
**Fix:** `sync -f "$DEST"` immediately after the rename, before pruning.

### L9. `--check` validates only `latest`; sets without the set marker are never rotated
**File:line:** `offsite-backup:351-356` (`verify_latest` only), `:319-325` (marker required to be prunable), `:322`
Older sets are never re-verified (bit rot undetected), and a set that loses `.offsite-set-owned` (not covered by any
checksum — only `home.tar.zst` is hashed, `:443`) becomes permanently unrotatable, so retention silently stops
deleting it.
**Fix:** report retained sets in `--check` (optionally verify them), and treat a missing marker on a set whose name
matches the tool's own pattern as a warning.

### L10. `After=local-fs.target` in a user unit is a no-op
**File:line:** `offsite-backup-schedule:310`
`local-fs.target` does not exist in the systemd *user* manager, so the ordering dependency is ignored (verified:
`systemd-analyze --user verify` is silent for the generated unit). The only effective protection is the
condition skip, which means a disk that mounts slightly late causes that week's backup to be skipped with no retry
(see M6). **Fix:** drop the misleading ordering or use a user-scope `After=`/`Wants=` that actually exists.

### L11. `backup-restore --apply-home` never checks free space on the apply target
**File:line:** `backup-restore:332-338` (staging filesystem only) and `:505-522` (apply)
The pre-flight `df` is for `$stage_parent`; `rsync` then writes into `$HOME`, which may be a different, smaller
filesystem. A mid-apply ENOSPC leaves a partially merged HOME (rollback copies exist, but the tree is mixed).
**Fix:** `df -Pk "$HOME"` before apply and compare against the staged size.

### L12. Dead code / stale legacy paths
**File:line:** `migration-pack:91-115` (`guard_backup_dir` is never called; `v2_guard_output_dir` replaced it)
`guard_backup_dir` still references `$HOME` directly and would disagree with the v2 guard if re-enabled; the v1 `--pack`
producer no longer exists, so `run_check_v1`/`validate_checksum_manifest` are check-only compatibility code.
**Fix:** delete or wire it up; document that v1 packages can only be verified/restored.

### L13. Privileged retry is broader than the README description
**File:line:** `migration-pack:311-341`, message at `:332`, `sudo` at `:334`
The README (`README.md:111-114`) says sudo is requested "only for that one tar read". In practice the whole `tar`
invocation is re-run as root (all includes, including ones already read successfully as the user), triggered by the
substring `Permission denied` anywhere in tar's stderr. The archive file stays user-owned because it is pre-created
(`:311`, comment at `:308-310`), and `tests/run:754-810` pins the elevation scope, so this is a documentation/scope
precision issue rather than a privilege bug.
**Fix:** narrow the retry to the failing member set or state the actual scope in the docs.

---

## PERF

### P1. Every backup verifies the same archive twice, decompressing it 4× (highest-impact perf item)
**File:line:** `offsite-backup:443` (sha256 write), `:445` (`verify_set "$STAGING"`), `:450` (`verify_set "$PUBLISHED"`);
`verify_set` itself at `:271` (`sha256sum -c` = full decompression) and `:272` (`tar --zstd -tf` = full decompression).
After `tar --zstd -cf` writes the archive (single-threaded I/O + compression), the run performs 4 full decompressions
plus 2 raw reads of the identical bytes, on data that has not changed (same file, same filesystem, atomic rename between
the two calls at `:447`). Measured reference: `tar --zstd -tf` of an 800 MB archive ≈ 0.33 s on this 16-core host;
a 100 GiB HOME archive pays minutes to tens of minutes of redundant verification.
**Fix:** verify once while staging (or hash the stream during creation), `sync`, rename, and drop the second `verify_set`
(or re-check only that `home.tar.zst.sha256` exists and matches the file's size/mtime).

### P2. `backup-restore` walks the whole archive 5× before/while restoring
**File:line:** `backup-restore:250` (`sha256sum -c`), `:252` (`tar -tf >/dev/null`), `:257` (`tar -tf > list`),
`:316`/`:325`/`:328` (`tar -tvf | awk` size estimate), `:341` (`tar -xf`), plus 2 rsync passes over the extracted tree.
`:252` is fully redundant with `:257` (same command, same archive, `>/dev/null`), and the size estimate can be derived
from the listing produced at `:257` (it needs sizes, i.e. `tar -tvf` instead of `-tf`). A single `tar -tvf > list`
serves validation, path-boundary checking and the estimate → 2 archive passes instead of 4 (plus sha256).
**Fix:** read `tar -tvf` once into a temp listing, then loop that listing for safety checks and size estimation.

### P3. `migration-pack --verify/--check` decompresses the payload once per include path
**File:line:** `migration-pack:583` (`tar --zstd -tf "$archive" >/dev/null`), `:589-595` (`tar --zstd -tf "$archive" "$rel"` inside the include-paths loop)
The default profile has 11 includes, so a verification can start up to 12 fresh zstd decompressions of the same archive
(zstd streams are not seekable). **Measured** on an 800 MB archive: one full listing 0.33 s vs 4 per-member queries
1.42 s (≈4.3×); scaling to a real payload with 11 includes is ~11×.
**Fix:** list the archive once into a temp file and compare paths with a sorted/grep containment test.

### P4. `du` performs a full extra walk of HOME before tar
**File:line:** `offsite-backup:407-412`
`du -sk` walks the entire snapshot tree (metadata for every file) only to produce a coarse free-space estimate, and is
then followed by tar's own full walk. On multi-million-file HOMEs this can take minutes for no additional safety
beyond the archive's own size (and it is the source of M1).
**Fix:** derive the estimate from the listing pass (P2-style) or from `tar -tvf` once.

### P5. `--check` re-runs live-system comparison for legacy packages
Covered by M5: `offsite-backup:273` + `migration-pack:669-672,836-856` run pacman queries and a per-manifest-entry
`[[ -e "$HOME/$rel" ]]` loop during what is supposed to be a read-only verification of the backup. Minor, fixed together with M5.

---

## Checked and found sound (coverage statement)

* **GNU tar traversal protection is effective** on this host (`tar 1.35`): interior `..` members are refused with rc=2,
  leading `/` is stripped (measured). `backup-restore:262-270,294-302` and `migration-pack:562-566` are therefore
  defense-in-depth, not the only barrier (see L6 for the residual denylist gaps).
* **`ConditionPathIsMountPoint` vs `mountpoint -q`**: both accept the same paths; `mountpoint -q -- <dir>` is supported
  (measured rc 0 for `/`, rc 32 for a normal dir), `systemd_condition_path` correctly escapes spaces and `%`, and the
  generated service+timer pass `systemd-analyze --user verify` with no output (measured, systemd 261). No mismatch found;
  the real defect is the silent-skip success reporting (M6).
* **zstd threading is not a defect on this host**: `tar --zstd` already parallelises with zstd 1.5.7 (measured
  user/real ≈ 3.2× vs `--single-thread`), so the missing `-T0`/`--use-compress-program` is not flagged.
* **Nested maintenance-lock acquisition works**: `offsite-backup` → `migration-pack --pack` under one lock does not
  self-block; bash's `{fd}` redirections are inherited across exec (verified via `/proc/<pid>/fd`), matching
  `lib/ui.sh:237-247`.
* **v2 checksum coverage is complete**: `migration-pack:420-428` hashes every regular file under staging, and
  `:545-576` requires the full artifact list (including `payload/home-config.tar.zst`) before `sha256sum -c`; SHA256SUMS
  entries are also validated for absolute/`..` paths. Verified by reading and by `tests/run:597-616,2062-2100`.
* **Quoting/subshell scoping**: no unquoted-expansion, pipeline-subshell variable-loss or word-splitting defect found in
  the four scripts (scan for `| while`, `for x in $var`, `=$(...)`-in-unquoted-context and manual review of every
  `find`/`tar`/`rsync`/`mv`/`rm` invocation).
* **Already pinned by tests** (`tests/run`): same-disk rejection only for a target on the **root** disk (`:1672-1680`, my
  H1 case is not covered); retention must not delete unowned `set-*` dirs (`:1786-1795`); publish/latest failure paths and
  signal window (`:1797-1808`, `:1745-1751`); unit staging/rollback/failure paths (`:1869-2060`); v2 pack/verify and
  guard behavior (`:619-753`); scoped sudo retry (`:754-810`); output/checksum guards (`:2062-2127`);
  restore plan/apply guards (`:2644-2736`).
  **H1, H2, M1, M2, M3, M4, M5, M6 are not covered by the suite.**
* **Not executed (per scope rules)**: `offsite-backup` end-to-end, `backup-restore --apply-home`, `offsite-backup-schedule
  --install/--remove`, any write into real HOME or backup targets. Findings that depend on those runtime paths are marked
  as suspected where applicable.
