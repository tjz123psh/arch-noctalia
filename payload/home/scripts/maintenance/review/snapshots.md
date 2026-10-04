# Snapshot / destructive-path review — quickload, quicksave, clean, cache-clean, btrfs-scrub

Reviewer: `review-snapshots` (shared task `task-3`) · read-only audit of `/home/pang/scripts/maintenance`
Scope: `quickload` (1425 L), `quicksave` (353 L), `clean` (636 L), `cache-clean` (388 L), `btrfs-scrub` (307 L) — 3,109 lines, all read.

## Method / evidence base

* Static: `bash -n` on all five files (all OK); `shellcheck -x -S warning` on all five (zero findings). Line numbers below were re-verified with `grep -n`.
* Isolated fixtures (all under `/tmp/maintenance-review/`, nothing in the repo touched — `git status --short` clean):
  * `scrub-harness/` — `discover_filesystems()` extracted verbatim (`sed -n '79,97p'`) + stubbed `findmnt`.
  * `native-harness/` — `delete_native_restore_clone` / `prepare_native_snapper_storage` / `native_root_restore` extracted verbatim (`sed -n '892,936p;938,1048p'`) with stub `findmnt/mount/umount/mktemp/btrfs/mv/reboot` and a `/tmp` fake top-level dir.
  * `clean-harness/` — deep-clean batch scan + delete loop extracted verbatim (`sed -n '430,497p'`) with a fake `snapper` that logs deletions.
  * `qload-harness/` — `choose_restore_snapshot` + `snapshot_batch_from_userdata` extracted verbatim (`sed -n '725,736p;819,872p'`), stub `select_menu_choice`.
  * Bash-semantics probes (`exit-trap-test.sh`, `trap-test*.sh`).
* Read-only system probes only: `snapper --csvout list-configs`, `snapper -c {root,home} --csvout --iso list`, `findmnt`, `snapper get-config`, `btrfs version/device stats --help`, `systemd-escape`. **No snapper create/delete/cleanup, no btrfs subvolume/mount/scrub, no clean/cache-clean execution.**
* Real state observed (used only as context): root + home configs, each exactly one snapshot `185` (2026-09-05 23:01:50, `quicksave-sysup`, batch `20260905T150150.566936098-3155465`); `/` = `/dev/nvme0n1p7[/@]`, `/home` = `/dev/nvme0n1p7[/@home]`.

## Severity summary

| severity | # | headline |
|---|---|---|
| critical | 0 | no unconditional live-data-loss path found |
| high | 3 | clean-all rollback retention broken by partial batch; clean-all retention fails open; no signal trap during native root switch |
| medium | 5 | orphaned `@quickload-restore-*`; scrub mountpoint-with-space parsing; picker corrupted by `\|` in description; interrupted quicksave leaves half batch; `quicksave -del all` deletes rollback points |
| low | 10 | see below |
| perf | 4 | N+1 snapper/date/process spawns |
| suspected | 1 | config-subvolume → btrfs-assistant column mapping (missing evidence) |

---

## HIGH

### H1 — `clean all` keeps the newest `maintenance_batch` without checking the batch is complete; it deletes the last *usable* rollback set

* **File:line**: `clean:430-449` (batch scan), `clean:472-475` (retention test), `clean:451-488` (delete loop); interacting with `quicksave:314-339` and `quickload:1227-1232`.
* **Evidence** — fixture with a half batch (root has batch `B2`; home only `B1`), logic extracted verbatim:
  ```
  $ bash /tmp/maintenance-review/clean-harness/run.sh
  INFO: 将保留最近一套回滚快照（批次 B2）。
  ITEM: 保留快照 [root] ID 11 quicksave（最近回滚点）
  ITEM: 已删除快照 [root] ID 9 quicksave
  ITEM: 已删除快照 [home] ID 10 quicksave
  ```
  `keep_batch` is a plain `max` over every config (`clean:436-444`), and retention is a per-row substring test (`clean:472`) — nothing asks whether *every* config has that batch. `quickload:1227-1232` refuses a set restore when any config lacks the batch, so the retained half is unusable while the older complete `B1` set is gone. The half-batch state is reachable: `quicksave` rolls back only on a `create` error (`quicksave:329-339`), not on SIGINT between configs (M4), and the menu delete path explicitly permits deleting one half after a warning (README:77-78).
* **Impact**: `clean all` (an explicitly confirmed deep clean) silently destroys the only complete root+home rollback point and keeps a half that quickload cannot restore — exactly the loss README:80 promises to prevent.
* **Fix**: during the scan, keep the newest batch that is present in *every* config (and preserve incomplete batches only if no complete one exists); abort or warn loudly if no complete batch is found while batches exist.

### H2 — `clean all` fails open: if the batch scan sees no `maintenance_batch`, every non-`before*` snapshot is deleted with no warning

* **File:line**: `clean:431-446` (`SNAP_BATCH_SCAN` written from `sudo snapper … list --columns number,userdata … || true`), `clean:447-449` (only prints when non-empty), `clean:472` (`[[ -n "$keep_batch" && … ]]`).
* **Evidence**: the scan query is wrapped in `|| true` (`clean:434`) and its result is only used to fill `keep_batch`; there is no "batch scan failed / found nothing" branch. The delete loop (`clean:455-486`) uses a *different* query (`number,description,userdata`) and deletes every row that is not `before*` and does not contain `maintenance_batch=$keep_batch`. With `keep_batch=""` the retention condition short-circuits false, so all snapshots of all configs are removed. The fixture confirms the delete path itself (see H1) and with `keep_batch` empty the same loop deleted the `B1`/`B2` rows unconditionally.
* **Impact**: one transient failure/format change of a single query converts the advertised guard (README:80 "保留最近一套 maintenance_batch 快照") into "delete the newest rollback batch too", silently; the user is told only "旧快照已按…清理".
* **Fix**: fail closed — if any config has `maintenance_batch` userdata but none was collected for the keep decision, abort deep clean with an explicit error; never silently treat "no batch found" as "nothing to keep".

### H3 — No SIGINT/SIGTERM/HUP handling around the native root subvolume switch: a signal in the two-rename window can leave the system with no `@`

* **File:line**: `quickload:1020-1030` (`mv active→previous`, then `mv clone→active`), `quickload:1112-1121` (rollback: `mv active→rejected`, then `mv previous→active`), `quickload:298-304` (`cleanup()` only unmounts `MOUNT_DIR`; only `trap cleanup EXIT` exists), `quickload:979`/`1083` (function-scoped `RETURN` trap only).
* **Evidence**: between the two renames there is no trap and no checkpoint. Verified bash semantics with `/tmp/maintenance-review/exit-trap-test.sh`: an `EXIT` trap runs on SIGINT/SIGTERM, but a `RETURN` trap set inside `native_root_restore` does **not** run when the shell dies from a signal — and `cleanup()` (quickload:299-302) only knows `MOUNT_DIR`, not the native `$top` mount. So after `mv "$top/$active_subvol" "$top/$previous"` (quickload:1021) a SIGINT/SIGTERM/SIGHUP (or power loss/OOM) leaves no subvolume named `@`; GRUB/`fstab subvol=@` then cannot boot.
* **Impact**: unbootable system requiring rescue media; the window is short (two adjacent renames) so probability is low, but the blast radius is total and the same gap applies to `--native-root-rollback`. Secondary: a signal anywhere between `mount -o subvolid=5` (quickload:981/1084) and the final `umount` leaks the `/run/quickload-native-root.XXXXXX` mount and directory, because only the `RETURN` trap removes it.
* **Fix**: install `trap '…INT/TERM/HUP handler…' INT TERM HUP` around the native paths that (a) unmounts `$top`, and (b) restores the invariant — if `@` is missing and a `@quickload-pre-*`/`@quickload-restore-*` exists, rename it back before exiting.

---

## MEDIUM

### M1 — Publish-failure path of `--native-root-fallback` leaves an orphaned `@quickload-restore-*` clone (and its nested `.snapshots` subvolume)

* **File:line**: `quickload:1026-1030` (no cleanup), vs `quickload:1023` (first `mv` failure uses a bare `btrfs subvolume delete`), vs `quickload:892-900` (`delete_native_restore_clone`, the helper that handles the nested `.snapshots` subvolume).
* **Evidence** — fixture, functions extracted verbatim, stubbed `mv` failing only on `@quickload-restore-* → @`:
  ```
  $ bash /tmp/maintenance-review/native-harness/run.sh
  INFO: 正在从 root 快照 #101 创建可写恢复子卷…
  native_root_restore rc=1
  --- fixture top after failure ---
  @
  @quickload-restore-20260910T184736-834119      <-- orphan
  --- @ marker = original-root ---
  ```
  The old root *is* restored (`@` intact, no data loss), but the code deletes the clone only in the earlier `prepare_native_snapper_storage`/`show` failure paths (1009, 1013) and in the `mv active→previous` failure path (1023, which itself uses a bare `btrfs subvolume delete` instead of `delete_native_restore_clone`, so it cannot remove a clone that already contains the recreated `.snapshots` subvolume — **suspected**, see S1-style caveat: btrfs refuses/nests that delete; not run here).
* **Impact**: every failed publish leaks a full copy-on-write clone of `/` plus a nested snapshot subvolume; repeated attempts (or an unattended sysup path) accumulate pinned extents that `btrfs filesystem usage` counts as used and that no suite tool reclaims (README:198-199 only tells the user about `@quickload-pre-*`/`@quickload-rejected-*`).
* **Fix**: call `delete_native_restore_clone "$top/$clone"` in the `mv active→previous` and publish-failure branches (and report if it fails), so both rollback paths clean the same way.

### M2 — `btrfs-scrub` mis-parses mountpoints that contain spaces (wrong target and wrong device)

* **File:line**: `btrfs-scrub:87-94` (`while read -r mountpoint source` over `findmnt -rn -t btrfs -o TARGET,SOURCE`, then `device="${source%%\[*}"` and dedupe by `device`).
* **Evidence** — `discover_filesystems()` extracted verbatim, stubbed `findmnt` emitting two fields separated by a space, one mountpoint containing a space:
  ```
  $ bash /tmp/maintenance-review/scrub-harness/run.sh
  [0] target=/  source=/dev/sda2
  [1] target=/run/media/pang/My  source=Disk\ /dev/sdb1
  ```
  Expected `target=/run/media/pang/My Disk`, `source=/dev/sdb1`. Everything downstream uses these values (`status_one` → `btrfs device stats -c "$target"`, `btrfs scrub status -R "$target"`; `unit_instance "$target"`; the non-interactive default `TARGET="${BTRFS_TARGETS[0]}"`).
* **Impact**: for removable/backup disks with spaces in their label, `--status` reports "查询失败"/wrong unit for that filesystem and `--strict` fails; `--start/--enable` without an explicit target can act on a nonexistent path (systemd unit for the truncated path). Dedupe also treats the truncated string as a distinct device.
* **Fix**: use `-P`/JSON output (`findmnt -rn -P -t btrfs -o TARGET,SOURCE`) or `IFS=$'\t'` with a tab-formatted listing so the target keeps embedded spaces.

### M3 — `quickload`'s pipe-delimited snapshot records corrupt the snapshot picker for any description containing `|`

* **File:line**: `quickload:839` (`descs_raw+=("$desc|$sid|$date|$batch")`), `850` (`IFS='|' read -r desc sid date batch`), `855` (`snapshot_choice_map[...]="$desc|$date|$batch"`), `865` (`IFS='|' read -r OPT_DESC TARGET_SNAPSHOT_DATE TARGET_SNAPSHOT_BATCH`); same pattern at `446`/`454` for `-l`.
* **Evidence** — `choose_restore_snapshot` extracted verbatim, stub `select_menu_choice` printing the real menu labels:
  ```
  menu labels shown to user:
      |   2026-09-01 11:00:00 · plain        (snapshot 101)
      |   100 · good                          (snapshot 100, description "good|morning")
  ```
  The row whose description contains `|` is rendered with the *snapshot number* in the date column (`100`) and a truncated description (`good`); the map value becomes `good|100|2026-09-01 10:00:00`, so selecting it yields `OPT_DESC=good TARGET_SNAPSHOT_DATE=100 TARGET_SNAPSHOT_BATCH='2026-09-01 10:00:00'`. Resolution then fails (`get_snap_id_by_batch` finds nothing) — a hard error, not a wrong restore, but the snapshot becomes unselectable and the confirmation page displays wrong metadata. Descriptions are user input (`quicksave -d 'good|morning'`).
* **Impact**: legitimate snapshots can never be chosen via the "先选备份时间点" menu and the displayed ID/date/description are wrong, which undermines the "confirmation page shows exactly which snapshot" guarantee (README:68). A description containing `\037` or a newline would corrupt parsing in the same way.
* **Fix**: don't join records with a printable delimiter — read the snapper CSV directly with `read -r -a` using `SNAP_SEP`, or store `sid` as the associative key and look metadata up by ID.

### M4 — `quicksave` is not transactional on interrupt: SIGINT between configs leaves a half batch that later feeds H1/H2

* **File:line**: `quicksave:314-327` (create loop), `quicksave:329-339` (rollback only on `SAVE_SUCCESS=0`), no `trap … INT/TERM` in the script.
* **Evidence**: the rollback loop runs only when a `snapper create` *returns* non-zero; there is no signal trap, so Ctrl+C / SIGTERM between `root` and `home` leaves the already-created root snapshot with `maintenance_batch=<newest>` and no home half. `clean:436-444` then treats that half as the newest batch to preserve (demonstrated in H1).  Unpaired halves are otherwise handled safely by `quickload:602-614` (it skips incomplete batches).
* **Impact**: the very state that makes H1 destructive becomes persistent; `clean all` afterwards deletes the older complete set.
* **Fix**: add an `INT/TERM` trap during the create loop that performs the existing reverse-order rollback (same code as `quicksave:332-337`).

### M5 — `quicksave -del all` has none of the batch/`before*` guards that `clean all` and the menu path enforce

* **File:line**: `quicksave:255-279` (`is_delete_all` → `snapper -c "$DEL_TARGET" delete "${all_ids[@]}"`), confirmation only at `quicksave:267`.
* **Evidence**: `all_ids` is "every ID except 0" — it includes `before*` (pacman pre-update) nodes and every `maintenance_batch` set, including the newest. `clean all` deliberately preserves both (`clean:466-475`), and README:75-81 documents batch-half protection for the menu path. `quicksave -del all -y` (or `-del all` + typed `delete`) removes them all; the saved rollback point for the last sysup is gone.
* **Impact**: a single documented flag/word combination destroys all Snapper rollback points; symmetric tooling (`clean`, menu delete) refuses to do this without extra ceremony.
* **Fix**: in the `all` branch, exclude `before*` and the newest `maintenance_batch` set, or require an extra confirmation word for "delete all".

---

## LOW

1. **`quicksave -l` can permanently grant `wheel` Snapper access for configs it will not even list** — `quicksave:184-207` runs before the list branch, over all of `TARGETS`, while `quicksave:213-218` narrows listing to `root` when `-c` is absent. A read-only-looking `quicksave -l` therefore prompts `pkexec snapper -c <other> set-config ALLOW_GROUPS=wheel` (persistent root-snapshot access for the whole wheel group). Fix: run the repair only for `LIST_TARGETS`, and never on a pure list without an explicit opt-in.
2. **`cache-clean --list` after a mode flag silently cancels cleaning** — `cache-clean:310-335`: `--list` sets `MODE_LIST=true` but leaves `MODE_SAFE/DEV/CHROME` true, and `cache-clean:356-359` exits before cleaning. Fix: make `--list` reset modes or error on combination.
3. **Dead function + misleading before/after numbers in `cache-clean`** — `target_paths()` (`cache-clean:253-271`) is never called (verified by grep); `target_bytes()` (`cache-clean:95-99`) counts the entire `~/.config/google-chrome` profile although only cache subdirs are removed (`cache-clean:210-231`), so "清理前/清理后" include login state/history. Fix: delete the dead function; measure the real cache subdirectories.
4. **`quickload -x` opens a predictable path in world-writable `/tmp` as root** — `quickload:116` `exec 2>"/tmp/quickload_debug_${EUID}_$$.log"`; after the sudo/pkexec re-exec this truncates/creates a root-owned file at a guessable name (bash follows a pre-created symlink). Fix: `mktemp` (0600) for the debug log.
5. **`clean` exits 1 merely because backup-like subvolumes exist** — `clean:615-621` sets `CLEAN_FAILED=1` for "found but retained"; `clean:631-636` then reports "至少一个步骤失败". Nothing failed; the tool deliberately kept candidates. Fix: report as an advisory without forcing a failure exit (or use a distinct exit code).
6. **Env overrides bypass config validation in `clean`/`cache-clean`** — `clean:29` `CLEAN_JOURNAL_RETENTION` (config validation at `lib/config.sh:40-43` is skipped for the env path) and `cache-clean:14` `CACHE_THUMBNAIL_MAX_AGE_DAYS` are used verbatim in `journalctl --vacuum-time=` / `find -atime +$days` (`cache-clean:177`). A bad value yields a spurious failed step (no unintended deletion observed). Fix: validate the override with the same regex before use.
7. **`btrfs-scrub` dedupes by device, so other mountpoints' timers are never inspected** — `btrfs-scrub:88-93` keeps one mountpoint per device; `status_one` (`btrfs-scrub:140-146`) derives timer/service from that one mountpoint. On `/`+`/home` sharing a device, a disabled `btrfs-scrub@-.timer` is reported "未启用" (and `--strict` fails) even when `btrfs-scrub@home.timer` is enabled, and vice versa. Impact is false alarms only (either timer covers the device). Fix: report all mountpoint instances for the timer state, dedupe only the `btrfs scrub status`/`device stats` queries.
8. **`btrfs-scrub` cancel exit code is inconsistent** — `btrfs-scrub:120,133` return raw `130`, propagated by `mutate_scrub:220` (`select_target || return $?`), while the confirm-cancel path maps to `cancel_status` (`btrfs-scrub:228` → 0 for non-`TERM_MENU_CHILD`). Fix: route all cancels through `cancel_status`.
9. **`btrfs-scrub` fzf selection is not validated; an empty `TARGET` becomes the root unit** — `btrfs-scrub:115-123` accepts whatever fzf returns; `unit_instance ""` (`btrfs-scrub:99-101`) runs `systemd-escape --path ""`, which prints `-` (verified), i.e. `btrfs-scrub@-.timer` = the root filesystem. The path is only reachable if fzf exits 0 with empty output, so this is a hardening issue, not a demonstrated bug. Fix: verify `TARGET` is one of `BTRFS_TARGETS` before use.
10. **`btrfs-scrub --status` cannot read scrub history without privileges** — `/var/lib/btrfs/scrub.status.*` is `-rw------- root root` (verified); without a cached/tty sudo (`btrfs-scrub:67-77`) every filesystem degrades to "scrub 状态查询失败" and `--strict` exits 1 in non-interactive use. The raw "Permission denied" output is printed, but the summary line does not distinguish it from a real query failure, which the code comments (`btrfs-scrub:65-66`) say it wants to avoid. Fix: classify permission-denied explicitly as "需要权限，结果未知".

## PERF

1. **`clean all` bypasses the "single batch delete" pattern**: `clean:478` spawns one `sudo snapper -c "$conf" delete "$snap_id"` per snapshot (M configs, N snapshots → N processes), and `clean:434` re-lists `--columns number,userdata` for every config even though `clean:455` lists the same snapshots with `userdata` already included (2·M + N snapper/sudo spawns where M + 1 calls suffice). README:79's "由 snapper 一次删完" holds for `quicksave`'s `-del` (verified: `quicksave:292` single call, tests/run:1077-1099) but **not** for `clean all`. Fix: collect IDs per config and issue one `snapper -c conf delete id…`; merge the two listings into one pass.
2. **`quickload` invokes `snapper list` up to 3× per config before restoring**: `auto_resolve_default_target` (`quickload:572,593`), `resolve_snapshot_id_for_config`→`get_snap_id_by_desc*/by_batch` (`661/672/682/702`), then `get_snap_row_by_id` (`558`). For root+home that is ~6 snapper processes for one decision (plus `choose_restore_snapshot:833`). Fix: cache one listing per config in an associative array for the lifetime of the run.
3. **`get_snap_id_by_desc_near_date` spawns one `date` per candidate row** — `quickload:703-706` (`date -d "$date" +%s` inside the row loop); a 100-snapshot config = 100 processes for a comparison that awk can do with `mktime`. Fix: compute epochs in awk/one pass.
4. **`btrfs-scrub status_one` spawns 5 processes per filesystem** — `systemctl is-enabled`, `is-active`, `show`, `btrfs device stats`, `btrfs scrub status` (`btrfs-scrub:145-177`). Fix: one `systemctl show -p … unit1 unit2` call per filesystem batch.

## SUSPECTED (unproven — missing evidence stated)

**S1 — `get_btrfs_subvol_name` can map a snapper config's subvolume to `@` and match the *root* restore entry** (`quickload:874-890`, used at `quickload:1303-1315`). If a config's `SUBVOLUME` (e.g. `/home`) is *not itself a mountpoint*, `findmnt -n -o SOURCE /home` returns the containing mount `[…/@]`, so `base_subvol="@";` the btrfs-assistant match then becomes `$2 == "@" && $3 == <that config's snapshot number>`. Root and home snapshot numbers can coincide (the real machine has root #185 and home #185), and only "exactly one match" (`quickload:1310-1314`) stands between that and restoring the wrong subvolume. On *this* machine `/home` is a separate mount (`[/@home]`), so the standard path is correct. Missing evidence: (a) whether a snapper config with a non-mounted `SUBVOLUME` is supported/reachable, and (b) what btrfs-assistant `-l` prints in column 2 for such a config — `btrfs-assistant -l` needs root/GUI and was deliberately not run. Fix if confirmed: derive the match key from the snapper config's `SUBVOLUME` (or match on the config's own subvolume path) instead of from `findmnt` of the path.

## README claim check

* "批量删除只调用一次 `quicksave`，由 `snapper` 一次删完，不再每个 ID 起一个进程" (README:79) — **holds** for `quicksave -del id1 id2 …` (`quicksave:292`, one `snapper -c conf delete …` call; confirmed by tests/run:1077-1099). It does **not** describe `clean all`, which deletes one snapshot per process (PERF-1), nor `quickload`, which restores one `btrfs-assistant -r` per config (`quickload:1319-1328`, inherent to the backend).
* "`clean all` … **保留最近一套 `maintenance_batch` 快照**" (README:80) — **holds only when the newest batch is complete and the batch-scan query succeeds**; see H1 and H2. The batch-ID ordering assumption itself is sound: IDs are `date -u '+%Y%m%dT%H%M%S.%N'-$$` (`quicksave:310`), fixed-width until the PID suffix, and the real machine's userdata renders unquoted exactly as parsed (`snapper -c home … list` → `maintenance_batch=20260905T150150.566936098-3155465`).
* CSV/localisation concern: snapper's `--csvout` headers are fixed identifiers (`config|subvolume`, `number|date|description|userdata`) even under `LANG=zh_CN.UTF-8` — verified with read-only `snapper list-configs` / `snapper -c home list`. No localisation bug in the CSV parsers.

## Coverage & confidence

* Coverage: 5/5 files read line-by-line (3,109 L) and cross-checked with `grep -n`; every finding cites exact lines and, where marked "demonstrated", a reproducible `/tmp` fixture output.
* Confidence: high for H1/H2/M1/M2/M3 (executed, code-extracted evidence); high for M4/M5/H3/P1-P4/README claim check (code-path reading + bash semantics verified with probes); medium for the LOW items (reading only, no fixture); S1 is explicitly suspected with missing evidence named.
* Not verified: real btrfs destructive semantics (nested-subvolume delete behaviour in M1), btrfs-assistant `-l` column values for unusual layouts, and CSV quoting for descriptions containing the separator/newline. **No mutating command was executed**; nothing under `/home/pang/scripts/maintenance` was created or modified.
