# Menu/UI layer review — `term-menu`, `lib/ui.sh`, `lib/config.sh`

Reviewer: `review-menu-ui` (task-1). Read-only review of `/home/pang/scripts/maintenance`.
Workspace was **not** modified; all scratch output is under `/tmp/maintenance-review/`.

**Coverage:** all 1518 lines of `term-menu`, all 811 lines of `lib/ui.sh`, all 110 lines of `lib/config.sh`.
`bash -n` and `shellcheck -x` (default + `-S style`) are clean for all three files.
Leaf scripts were not read in full — only greps/call-site checks needed to judge library semantics.
Full `tests/run` was not run (per instructions); the known-failing test 46 was not touched.

**Verdict:** 0 critical, 2 high, 2 medium, 11 low, 6 perf. The menu state/refresh preservation,
loop-around (`--cycle` + `pos()`), ANSI/width stripping and trap cleanup are largely correct — see
"Tricky-but-correct" at the end before filing any finding here.

---

## CRITICAL

None found.

---

## HIGH

### H1. Ctrl+C (and any fzf failure) makes `term-menu` exit 0 — violates the documented 130 contract and hides fzf errors
**Where:** `term-menu:705-707` (`status=$?; [ "$status" -eq 0 ] || return 1`), `term-menu:1488`
(`selected="$(choose_menu …)" || exit_menu`), `term-menu:771-779` (`exit_menu` → `exit 0`), contract in `README.md:324`.

**Evidence (real fzf 0.74.3, PTY):** an fzf wrapper in `PATH` that execs `/usr/bin/fzf` and logs its exit status:

```
$ (sleep 1.5; printf '\003') | PATH=/tmp/maintenance-review/shim3:$PATH \
    script -qec "bash /home/pang/scripts/maintenance/term-menu" /dev/null
term-menu exit=0
fzf exit logged: 130        # <- fzf aborted correctly, term-menu swallowed it
```

Same with a stub `fzf` that just `exit 2` (fzf's generic error code, e.g. no usable tty): `term-menu exit=0`.
The traps at `term-menu:40-42` (`INT` → 130) never fire because in raw mode Ctrl+C is consumed by fzf as its
`abort` action, not delivered as SIGINT.

**Impact:** every nonzero fzf status (130 = Esc/Ctrl+C, 2 = error) is collapsed into "return 1" and the main
menu converts that into a clean `exit 0`. Wrappers/niri keybindings cannot distinguish "user cancelled" from
"completed", and a genuine fzf failure exits silently with success. Sub-menus are unaffected in behaviour
(they treat it as "go back"), but `delete_snapshot:1137,1206,1215` likewise cannot report a real fzf error.

**Fix:** `return "$status"` from `choose_menu` instead of `return 1`; in `show_main_menu` map 130 → `exit 130`
and propagate other nonzero codes (at minimum print them) instead of `exit_menu` → `exit 0`.

---

### H2. `ui_confirm` answers "yes" when stdin is at EOF
**Where:** `lib/ui.sh:656-665` — `read -r answer || true; answer="${answer:-$default}"`.

**Evidence:**
```
$ bash -c '. lib/ui.sh; ui_confirm "危险操作" </dev/null; echo "rc=$?"'
危险操作 [Y/n] rc=0
$ bash -c '. lib/ui.sh; ui_confirm "危险操作" n </dev/null; echo "rc=$?"'
危险操作 [y/N] rc=1
```

**Impact:** for every default-`y` prompt, a closed/EOF stdin (non-interactive launcher, `< /dev/null`,
systemd/cron context) is treated as explicit consent. In-tree default-`y` callers: `mirror-update:271`
(switch to global mirror list) and `mirror-update:337` (accept detected country). The destructive callers
(`clean:185`, `checkallupdates:590,663`, `quicksave:195`) pass `n` and therefore fail safe.

**Fix:** capture the read status and treat EOF as "no": `if ! read -r answer; then return 1; fi`
(keep the empty-Enter default only when the read actually succeeded).

---

## MEDIUM

### M1. Shared maintenance lock can become unopenable for the desktop user (root-first creation), and the failure code 73 is undocumented
**Where:** `lib/ui.sh:222-235` (`mkdir -p "$(dirname "$lock_file")"` with the caller's umask, no `chmod`/`chown`)
and `lib/ui.sh:253-256` (`exec {UI_MAINTENANCE_LOCK_FD}>>"$lock_file"` → `return 73`).

**Evidence (failure mode proven):**
```
$ bash -c '. lib/ui.sh; f=/tmp/.../x.lock; : >"$f"; chmod 400 "$f"; MAINTENANCE_LOCK_FILE="$f" \
    ui_maintenance_lock_acquire test; echo rc=$?'
lib/ui.sh: 行 253: /tmp/.../x.lock: 权限不够
[错误] 无法打开维护锁：/tmp/.../x.lock
rc=73
```
and the same for a 0555 parent directory. On this machine the live lock is user-owned
(`pang pang 644 ~/.cache/maintenance/maintenance-1000.lock`), so it has not triggered yet.

**Suspected trigger (reasoned, not executed):** the lock home is resolved from `SUDO_UID`
(`ui.sh:217,225-230`), i.e. **root writes into the user's `$HOME/.cache`**. Any root-first path —
e.g. `sudo quickload` (`quickload:161` re-execs sudo, `quickload:1186` acquires afterwards) on a fresh
machine or after `rm -rf ~/.cache/maintenance` — creates `maintenance/` as `root:root 0755` and the lock
file as `root:root 0644`. A later plain-user run (`term-menu` snapshot deletion via `term-menu:1060`,
`checkallupdates:596`, `cache-clean:368`, …) then cannot open it and aborts with 73 that the README
(`README.md:316-324`) does not document. Evidence missing: an actual root-first run (cannot be staged
without mutating the live lock).

**Fix:** after creating/opening, best-effort `chmod 0600` + `chown "$lock_uid"` (or `install -d -m 700 -o …`
when euid=0); document 73 as "lock file/permission failure" in the README exit-code list.

---

### M2. `ui_dwidth`/`ui_pad` miscount CJK when the locale is not UTF-8
**Where:** `lib/ui.sh:435-457` — `ch="${s:i:1}"` + `printf -v code '%d' "'$ch"` assumes character-wise
indexing, which only holds in a multibyte locale.

**Evidence:**
```
$ LC_ALL=C bash -c '. lib/ui.sh; for s in "中文" "ab" "中文ab"; do echo "$s -> $(ui_dwidth "$s")"; done'
中文 -> 6        # correct: 4
ab -> 2
中文ab -> 8      # correct: 6
$ LC_ALL=C.UTF-8 bash -c '. lib/ui.sh; … '   # -> 4 / 2 / 6 (correct)
```

**Impact:** in a `C`/`POSIX` locale the function counts UTF-8 bytes as width 1, so every consumer
(`ui_pad`, `ui_panel_open`, `show_snapshots`, `_net_row`, `run_leaf_header`) gets wrong column maths:
misaligned cards and wrong padding for any script that runs with `LC_ALL=C`. Silent — no error.

**Fix:** make `_ui_dwidth_calc` locale-independent, e.g. force `LC_ALL=C.UTF-8` inside the function
(or decode the UTF-8 bytes manually, as `ui_wrap`'s awk already does).

---

### M3. `view-snapshots` builds the whole table with ~8 subshell forks per row
(Also listed under Perf P2 — kept here because it is a user-visible freeze in an interactive path.)

**Where:** `term-menu:890-916` (`compact_text` → `$(ui_dwidth …)` per character; `_snap_row` → four
`$(ui_pad …)` per row), `term-menu:894,901,911-915`.

**Evidence:** stub `snapper` emitting N rows per config, table piped to `/dev/null`:
`N=20 → 289 ms`, `N=100 → 1383 ms`; `strace -f -e trace=clone,execve` on the N=20 run:
`clone calls: 311` (≈7.8 forks/row).

**Impact:** a machine with a few hundred snapshots makes "查看快照" hang for over a second before printing.

**Fix:** use `_ui_dwidth_calc` directly (writes `UI_DWIDTH_RESULT`, no fork) and build cells with
`printf` padding, or add non-forking `ui_dwidth_set`/`ui_pad_set` helpers (see P1).

---

## LOW

### L1. `_ui_rule_width` can return 0, contradicting its own clamp
**Where:** `lib/ui.sh:292-302`. When `ui_cols` returns 0, `w` is first raised to 1 and then lowered back to
`cols` by `(( w > cols )) && w=$cols`.
**Evidence (stub `tput` printing `0`):** `ui_cols=0`, `_ui_rule_width=0`. `ui_hr` self-heals
(`ui.sh:316`), but `ui_banner`/`ui_panel_open`/`ui_panel_close`/`run_leaf_header` use `w` directly.
Real terminals do not report 0 columns, so low.
**Fix:** clamp `ui_cols` to ≥1, or move the `(( w < 1 )) && w=1` clamp after the `w > cols` clamp.

### L2. `ui_panel_stat err` is tallied as "缺失"
**Where:** `lib/ui.sh:619` — `err) … UI_N_MISS=$(( ${UI_N_MISS:-0} + 1 ))`; `ui_tally_summary` (`ui.sh:636-639`)
has no error bucket. Strict-mode behaviour is unchanged (`ui_tally_status` only looks at WARN/MISS), and no
in-tree caller currently passes `err` (grep `_panel_stat "err"` → none). Latent mislabel.
**Fix:** add `UI_N_ERR` and print it in the summary.

### L3. `maintenance_config_load` marks itself loaded before parsing succeeds
**Where:** `lib/config.sh:62-63` vs the parse loop `68-98`.
**Evidence:** config file `BACKUP_KEEP=7` + `MIRROR_THREADS=notanumber`:
first `maintenance_config_load` → rc=1 + error; **second call → rc=0**, and
`maintenance_config_get BACKUP_KEEP 3` returns `7` — a partially applied config is silently live.
All in-tree callers use `maintenance_config_load || exit 2`, so impact is limited to library/test reuse.
**Fix:** set `MAINTENANCE_CONFIG_LOADED=1` only after the whole file parsed, and clear
`MAINTENANCE_CONFIG_VALUES` on failure.

### L4. An empty-but-set environment override beats file and default
**Where:** `lib/config.sh:101-104` (`[[ -n "$env_name" && -v "$env_name" ]]` — only *set*, not *non-empty*).
**Evidence:** `MAINTENANCE_BACKUP_KEEP= bash -c '… maintenance_config_get BACKUP_KEEP 3 MAINTENANCE_BACKUP_KEEP'`
→ `""` (not 3). Consumers validate and exit 2 (`offsite-backup:57`, `offsite-backup-schedule:84`), so it fails
loudly rather than silently. Low.
**Fix:** treat an empty env value as unset (`[[ -n "${!env_name:-}" ]]`).

### L5. Inline comments after a value break the parser with a misleading message
**Where:** `lib/config.sh:80-81` (only surrounding whitespace is trimmed) and `96`.
**Evidence:** `BACKUP_KEEP=7 # keep seven` → `maintenance 配置错误: BACKUP_KEEP 必须是正整数` (rc=1).
`config.example` does not use inline comments, so this is a usability trap, not a live bug.
**Fix:** strip an unquoted ` #…` suffix, or extend the error message to mention trailing comments.

### L6. `ui_status_line` footer is computed once and frozen — "实时状态栏" is misleading
**Where:** `lib/ui.sh:774-811`; used at `term-menu:664` (`footer="$(ui_status_line)"`) and `term-menu:689`
(`--footer="$footer"`). fzf renders the literal string and only substitutes placeholders on selection change;
CPU/RAM/disk/interface/clock therefore freeze at menu-open time (see also P4 for its cost).
**Fix:** if live values are wanted use fzf `--listen` + `transform-footer`; otherwise reword the comment.

### L7. `show_snapshots`: `mktemp` unchecked, tmp path never `ui_tmp_discard`ed
**Where:** `term-menu:1009-1010` (`tmp="$(mktemp)"; ui_tmp_register "$tmp"`) and `1038` (`rm -f "$tmp"`).
If `mktemp` fails, `tmp=""`, `> "$tmp"` fails and `cat "$tmp"` prints nothing — the whole snapshot report is
lost with only redirection errors on screen. On the normal path the path stays registered and the EXIT trap
`rm -rf`s an already-deleted path (harmless). **Fix:** check `mktemp` and call `ui_tmp_discard "$tmp"`.

### L8. `resolve_tool ""` / `have_tool ""` report the script directory as an available tool
**Where:** `term-menu:730-738` (`[[ -x "$SCRIPT_DIR/$name" ]]` is true for directories) and `762-765`.
**Evidence:** `resolve_tool "" -> /home/pang/scripts/maintenance/`, `have_tool "" -> rc=0`. Not reachable from
the static item lists today, but any future empty `act` field would make `run_tool ""` execute a directory (126).
**Fix:** reject empty names and test `-f` instead of `-x`.

### L9. No-fzf fallback menu pads columns by bytes, not display columns
**Where:** `term-menu:714-716` (`printf "  %s  %-12s %-18s %s\n"`). CJK labels are 12 bytes and get no
padding while `退出` (6 bytes) gets 6 spaces → visibly misaligned (`00 退出` row in the fallback listing).
Cosmetic, only when fzf/tput are missing (fallback verified by running `choose_menu` with a reduced `PATH`).
**Fix:** use `ui_pad` for the fallback columns.

### L10. `show_network_status` fixed columns and rule width ignore terminal width
**Where:** `term-menu:1300` (`W_IND/W_DEV/W_TYPE/W_STATE` fixed), `1321` (`rule_w = 16+10+12+3+18 = 59`),
`1327` (`IFS=: read` on `nmcli -t` output). On a <~65-column terminal the rows and the 62-column rule wrap.
The terse parser also splits nmcli's escaped `\:` — *suspected*, no connection with `:` exists on this machine:
`nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status` here shows only names like `GDUFS_Auto`,
`无法连接 1`, `connected (externally)`. Evidence missing: a connection name containing a colon.
**Fix:** derive widths from `ui_cols`, and un-escape `\:`/`\\` before splitting the terse output.

### L11. `--preview` early exit is outside the `BASH_SOURCE` guard
**Where:** `term-menu:634-637` runs before the `[[ "${BASH_SOURCE[0]}" == "$0" ]]` guard at `1507`.
Sourcing `term-menu` from a shell whose `$1` is `--preview` exits the sourcing shell.
Test-harness-only, but the guard should be checked first.

---

## PERF

### P1. The `_UI_DWIDTH_CACHE` memoization is defeated at every real call site
**Where:** cache written at `lib/ui.sh:459`, read at `422-426`; but `ui_dwidth` prints (`463-466`) and every
consumer wraps it in a command substitution: `ui.sh:572`, `ui.sh:690`, `term-menu:894,901,911-915,1292`.
**Evidence (same string, 300 iterations):**
```
with command substitution: 489 ms/300   (1.63 ms per call)
no subshell (cache hits):    17 ms/300  (0.057 ms per call)   # ~29x
```
The sub-shell forked by `$( … )` dies with the cache entry, so the "avoid forking an awk each call" intent
(comment `ui.sh:378-379`) does not hold where it matters.
**Fix:** add non-forking variants (`ui_dwidth_set`, `ui_pad_set`) that write to variables and are called
without `$( … )`, or inline `_ui_dwidth_calc` at hot sites.

### P2. `view-snapshots` fork storm — ~7.8 subshells per row (see M3 for measurements: 289 ms/40 rows, 1383 ms/200 rows, 311 clones).
**Fix:** as M3 — non-forking width helpers + `printf` padding.

### P3. Every fzf preview spawn pays for menu tool detection that the `--preview` path never uses
**Where:** `term-menu:44-58` (NET_TOOL/BT_TOOL probing: `dirname`×2, `readlink`, `systemctl is-active`,
`ls -A`) runs before the `--preview` early exit at `634-637`; fzf re-runs the preview on every cursor move,
so this is the interactive hot path.
**Evidence:** `strace -f -e trace=execve` on one preview child shows
`dirname`×2, `systemctl`, `readlink`, `ls`, `awk`. A/B with an identical-output `/tmp` copy that guards those
two `if`s with `[[ "${1:-}" != "--preview" ]]` (verified `diff` of preview output = empty):
```
original: 400/404/407 ms per 20 calls   (~20 ms per preview)
guarded : 282/280/277 ms per 20 calls   (~14 ms per preview)
```
**Fix:** skip detection when `$1 == --preview` (or run the preview body before it).

### P4. `ui_status_line` costs 8 external processes per menu redraw and is stale anyway
**Where:** `lib/ui.sh:774-811`, called once per `choose_menu` (`term-menu:664`).
**Evidence:** `strace -f -e trace=execve` → `awk`×3, `tr`, `tail`, `ip`, `df`, `date`;
20 calls = 305 ms (~15 ms per redraw). Combine with L6 (values never refresh).
**Fix:** one `awk`/pure-bash pass over `/proc/meminfo` + `/proc/loadavg`, and `printf` for the one-decimal
GiB values; drop `date`/`ip` if the footer is static anyway.

### P5. Rule/banner drawing uses one `printf` per character
**Where:** `lib/ui.sh:319`, `344`, `558/564`, `577`, `586-587`, `697/707`; `term-menu:973, 1324, 1386-1400`.
**Evidence:** `ui_hr 160` ×50 = 209 ms (≈4.2 ms/call; `tput cols` alone 1.2 ms, the 160-iteration builtin loop
≈1.9 ms). The pure-bash alternative `printf -v pad '%160s' ''; line="${pad// /─}"` ×50 = **4 ms** (≈24x faster
than the loop, also faster than `printf | tr` at 87 ms).
**Fix:** build the rule once per width and cache it, e.g. `_ui_rule_cache[$w]`, or use the `printf -v` +
`${var// /─}` idiom.

### P6. `warn_batch_pairs` spawns snapper O(selected × configs) times
**Where:** `term-menu:1083` (one `snapper list` per call), `1085-1102` — for **each** selected snapshot ID it
re-runs `snapper list-configs` and a `snapper -c <other> list` per config, with `grep` per probe.
**Impact:** multi-selecting k snapshots on a box with c configs = 1 + k(1 + c) snapper processes, each typically
tens to hundreds of ms, before the confirmation prompt. Not measured (real snapper is out of scope / stateful).
**Fix:** hoist `list-configs` out of the ID loop and query each config's `number,userdata` once into an
associative array (`batch → configs`) before the loop.

---

## Tricky-but-correct (do not file these)

- `term-menu:706` `set -e` inside `choose_menu` does **not** leak into the menu loop: every call site uses
  `selected="$(choose_menu …)"`, so the option applies only inside the command-substitution subshell.
- `_ui_strip_ansi` (`ui.sh:391-411`) handles empty-parameter CSI correctly: `ui_dwidth $'\e[KABC'` = 3 and
  `\e[mABC` = 3 — the `params == tail` branch means "no final byte at all", not "drop the rest".
- `${arr[@]+"${arr[@]}"}` at `ui.sh:173,179` and `term-menu:992,999` does preserve elements containing spaces
  (verified: `("a b" "c")` → 2 elements; empty array → 0 elements).
- `menu_start_position` + `--bind="load:pos(N)"` is off-by-zero: fzf(1) documents `first` as `pos(1)`, and awk
  `NR` is 1-based; a key that disappeared correctly falls back to position 1 (README.md:311-314).
- fzf single-quotes placeholders (fzf(1): "Each expression expands to a quoted string"), so
  `--preview="bash '$SELF' --preview {3}"` is injection-safe for the fixed internal action names.
- `quicksave:105-107` accumulates repeated `-del`, so `term-menu:1056-1063`'s single batched
  `quicksave -c CONF -del ID… --yes` call is valid (not a silent last-one-wins).
- The `ui_tmp_cleanup` owner-PID guard plus the EXIT trap is effective: the EXIT trap is not run by
  command-substitution/`( )` subshells, and it *does* run for untrapped TERM/HUP (verified: `CLEAN` printed,
  rc=143/129), so "close the window" really does clean `/tmp`.
