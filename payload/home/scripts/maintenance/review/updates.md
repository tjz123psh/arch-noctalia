# Review: update / refresh chain

Scope (read-only review): `checkallupdates` (846 L), `mirror-update` (429 L), `sysup` (537 L),
`post-update-check` (209 L), plus the `lib/ui.sh` / `lib/config.sh` helpers they call.
Reviewer: `review-updates` (task-2). Machine: Arch, bash 5, fzf 0.74.3, EUID 1000.

Method: full line-by-line read of all four files; `bash -n` + `shellcheck -x` (clean);
static line-number verification with `grep -n`; isolated reproductions driven by PATH stubs under
`/tmp/maintenance-review/u/` (never touched `/home/pang/scripts/maintenance`); real `fzf` driven
through a Python PTY to observe how reload children are killed. No state-changing command ran
(`checkupdates` was the only network/real tool invoked; it writes only to `/tmp/checkup-db-1000`).

| # | Severity | One-line | Location |
|---|----------|----------|----------|
| C-1 | critical | Unreadable GRUB is reported healthy: `post-update-check` exits 0, and `sysup` step 7 therefore passes | post-update-check:39-42,194-202 |
| H-1 | high | Esc / Ctrl+C / second Ctrl+R kills the reload child without traps: 10 temp files leak, query children orphaned, `refresh.lock` stays held | checkallupdates:409-427, 838-845 |
| H-2 | high | A refresh can be reported `ok` + fresh even though the cache file was never committed → UI answers "no updates" | checkallupdates:266-270, 296-298, 325-329, 344-354 |
| H-3 | high | Missing cache files + fresh per-source stamps → `--refresh-stale` queries nothing and the list renders "no updates" | checkallupdates:103-123, 370-403, 539-551 |
| M-1 | medium | `flock` timeout is ignored (`|| true`) → two refreshes run concurrently, cache can interleave | checkallupdates:409-413 |
| M-2 | medium | Clock skew / future mtime pins the cache "fresh" and the label prints "刚刚更新" | checkallupdates:108-111, 126-143 |
| M-3 | medium | `QUERY_TIMEOUT` is not a hard bound: no `timeout -k`, and shell functions bypass the timeout | checkallupdates:239-247 |
| M-4 | medium | Lock wait (default 300 s) is spent inside fzf's blocking reload → list freezes with old data | checkallupdates:412 + 791 |
| M-5 | medium | `post-update-check` silently degrades to unprivileged reads when there is no TTY | post-update-check:15-27 |
| M-6 | medium | `sysup` always exits 1 on machines without `grub-mkconfig` (systemd-boot/UKI) | sysup:382-394 |
| M-7 | medium | `sysup` news fetch: `pipefail` turns "curl timed out after complete data" into "fetch failed" | sysup:496-497 |
| M-8 | medium | `mirror-update`: a failed `reflector --list-countries` looks like "invalid country" and silently falls back to global mode | mirror-update:207-223, 266-272 |
| L-1 | low | `_cau_query_aur` accepts rc==1 with no output as `ok` (suspected false-healthy) | checkallupdates:295 |
| L-2 | low | `--refresh` is documented as machine-readable but always emits ANSI escapes | checkallupdates:77-81, 532-549 |
| L-3 | low | `sysup` mirror-age text hardcodes ">30天" while the threshold is configurable | sysup:147, 226 |
| L-4 | low | `cache_age_text` only reads the global stamp → label says "尚未成功刷新" while 2 of 3 sources are fresh | checkallupdates:126-143, 495-499 |
| L-5 | low | `mirror-update -c` with no argument exits 1, not the usage-error 2 used elsewhere | mirror-update:308-311 |
| L-6 | low | `mirror-update`: `sudo cp` failure inside `_run_reflector` is silent (returns 1 with no message) | mirror-update:248-259 |
| L-7 | low | Dead duplicate flatpak branch + undocumented `CHECKALLUPDATES_FLATPAK_CACHED` | checkallupdates:321-325 |
| L-8 | low | `post-update-check` mixes `find` stderr into the module-dir value | post-update-check:146-148 |
| P-1 | perf | Dominant cost is `checkupdates` (full `pacman -Sy` into a temp DB): measured 9.5 s / 11 MB per refresh, repeated after every upgrade | checkallupdates:266; /usr/bin/checkupdates:150 |
| P-2 | perf | Per-refresh bookkeeping is cheap; parallel-source design is correct (positive) | checkallupdates:428-456 |

---

## CRITICAL

### C-1 — "GRUB cannot be read" is reported as healthy, and `sysup` accepts it

**Location:** `post-update-check:29-43` (`grub_file_state`), `post-update-check:194-202`, `post-update-check:206-209`;
consumed by `sysup:411-425`.

```bash
# post-update-check:38-42
  [[ -s "$path" ]] && return 0
  if [[ "$EUID" -ne 0 && ! -x "$(dirname "$path")" ]]; then
    return 2
  fi
  return 1
```

`return 2` ("cannot read") is only produced when the *parent directory* is not executable. Anything
else that fails the `-s` test — a file that exists but is unreadable, or a path the process cannot
verify (the test's `/root/maintenance-unreadable-grub.cfg`) — falls through to `return 1`
("missing or empty"), i.e. the tool cannot tell "I was denied" from "it is not there". Then:

```bash
# post-update-check:197-202
elif [[ "$GRUB_STATUS" == "skipped" || "$GRUB_STATUS" == "unknown" ]]; then
  ui_panel_stat warn "$GRUB_CFG 不存在或为空"      # warning only, QUERY_FAILED stays 0
else
  ui_panel_stat err "$GRUB_CFG 不存在、为空或无法验证"
  QUERY_FAILED=1
fi
```

With no `--grub-status` (the default when a human runs the tool, and the case the test exercises),
`GRUB_STATUS=unknown` → warning only → `QUERY_FAILED=0` → `exit 0`.

**Evidence** (exact reproduction of the scenario in `tests/run:2403-2410`, run from `/tmp` with PATH stubs;
`/root` on this machine is `drwxr-x---+`, so `[[ -x /root ]]` is true):

```console
$ printf 'x=[%s]\n' "$([[ -x /root ]] && echo yes || echo no)"
x=[yes]
$ PATH=/tmp/maintenance-review/u/postbin:$PATH POST_UPDATE_MODULES_DIR=.../postmodules \
    POST_UPDATE_GRUB_CFG=/root/maintenance-unreadable-grub.cfg POST_SUDO_UNAVAILABLE=1 \
    /home/pang/scripts/maintenance/post-update-check ; echo "rc=$?"
  │  [注意] /root/maintenance-unreadable-grub.cfg 不存在或为空
rc=0
```

**Impact:** this is exactly the suite failure at test 46 ("post-update check must fail when GRUB cannot
be read"). Blast radius into my scope: `sysup:422` calls `post-update-check` *without* `--strict` and
treats a zero exit as "step 7 OK"; a `grub-mkconfig` run whose result was never verified is reported as
a fully successful update (`sysup:431 _success "${MSG[DONE]}"`). The whole point of the check —
"did the bootloader config regenerate correctly after a kernel/GRUB update" — is silently dropped.
Also note `prepare_read_access` can leave `SUDO_READ` empty (see M-5), in which case even a *readable*
GRUB file is verified by an unprivileged process.

**Fix:** in `grub_file_state`, distinguish "not readable" from "missing" for real: `[[ -e $path ]] && ! [[ -r $path ]] && return 2`
(or attempt `"${SUDO_READ[@]}" test -r`), and make the `skipped|unknown` branch set `QUERY_FAILED=1`
when the file exists but could not be validated. (Full RCA is owned by the Lead; this is the
file-scope evidence needed to judge blast radius.)

---

## HIGH

### H-1 — Esc / Ctrl+C during a refresh kills the reload child without running any trap → leaked temp files, orphaned queries, held lock

**Location:** `checkallupdates:838-845` (traps), `checkallupdates:194-219` (cleanup),
`checkallupdates:409-427` (lock + 10 `mktemp` files), `checkallupdates:430-456` (background queries).

`checkallupdates` relies on EXIT/INT/TERM/HUP traps for all cleanup. The fzf reload child
(`--refresh-stale` from the `load` event, `--refresh` from Ctrl+R, lines 790-791) is *killed by fzf*,
and fzf does not give it a catchable signal.

**Evidence 1 — fzf kills reload children with an untrappable signal** (real `fzf` 0.74.3 in a PTY,
probe script with TERM/INT/HUP/EXIT traps that log, then `sleep 20`):

```console
$ python3 ptydrive2.py
Ctrl+C (SIGINT) while reload running -> start pid=931353 ppid=931343      # no trap line at all
Esc while reload running            -> start pid=931898 ppid=931880      # no trap line at all
   survivors: none
```

Only the first line of the probe ran; neither `got TERM`, `got INT`, `got HUP` nor `got EXIT` was
written, i.e. no `_cau_cleanup` would run.

**Evidence 2 — what survives a killed refresh** (`kill -9` of the refresh parent, same effect):

```console
$ kill -9 784328   # the checkallupdates --refresh process
$ ps -eo pid,ppid,etime,cmd | grep -E 'checkallupdates --refresh|timeout|stub'
784354 1843  bash .../checkallupdates --refresh        # 3 orphaned per-source subshells
784358 784354 timeout 600 checkupdates
784359 784356 timeout 600 flatpak remote-ls --updates ...
784361 784355 timeout 600 paru -Qua
...   (plus the real query processes and their `sleep`)
$ ls -la ~/.cache/checkallupdates/      # all 10 mktemp files still there, nothing reclaimed
repo.kQq1oC  aur.fJbfeW  flatpak.xn0aNC  status.*(4)  error.*(3)
$ time flock -w 2 ~/.cache/checkallupdates/refresh.lock -c 'echo LOCK-ACQUIRED'
flock rc=1
real  0m2.001s      # the orphaned subshells still hold the refresh lock
```

**Evidence 3 — live-machine corroboration (unmodified production cache):**

```console
$ ls -la --time-style=long-iso ~/.cache/checkallupdates/
-rw------- 206 2026-09-09 23:32 aur.9UD52T        # completed AUR result, never committed
-rw-------   0 2026-09-09 23:32 repo.wtRXoN
-rw-------   0 2026-09-09 23:32 status.*  (x4)   # 4 status files
-rw-------   0 2026-09-09 23:32 error.*   (x3)
-rw-------   0 2026-09-09 23:32 flatpak.Kgp8Xe
-rw-r--r--   0 2026-09-09 21:49/21:54 last-refresh*   # last *successful* run 21:54
-rw------- 206 2026-09-09 21:49 updates-aur.txt       # old data still in place
```

A refresh was started at 23:32 the previous night and interrupted; all **10** `mktemp` files are
still there ~19 h later, and a finished 206-byte AUR result (`aur.9UD52T`) was never committed.
This is the H-1 leak observed in the wild, not just in the lab.

**Impact:**
1. Up to 3 real network queries (`pacman -Sy` inside checkupdates, `paru -Qua`, `flatpak remote-ls`)
   keep running for up to `UPDATE_QUERY_TIMEOUT` after the UI is gone, and then commit their results
   into the shared cache (older data overwriting a newer refresh).
2. `refresh.lock` stays held by the orphans. The next refresh that runs (`--refresh` from sysup, the
   `load`-event `--refresh-stale`, or Ctrl+R) blocks in `flock -w "$REFRESH_LOCK_WAIT"` for up to
   300 s *inside fzf's blocking reload*, so the list freezes on old data (see M-4); after the wait it
   proceeds anyway (M-1).
3. Temp files are only reclaimed 60 minutes later and only if another refresh runs
   (`_cau_reclaim_orphans`, line 222-229); the orphan *processes* are never reclaimed.
4. This directly contradicts `README.md:32-33` ("刷新期间被 Esc、Ctrl+C 或关窗中断时，会收掉后台查询
   进程并清理临时文件"). Trigger is trivial: Esc, Ctrl+C, Esc-on-error, or two quick Ctrl+R
   (fzf's `reload-sync` supersedes and kills the previous command).

**Fix:** do not rely on traps for the reload child. Either run the refresh in a process the UI can
reap (e.g. `--refresh` writes a pidfile and the parent/main process kills it, or use `setsid` + a
supervisor), or make orphan detection cheap: on startup, list live PIDs from `$CACHE_DIR/refresh.pid`
and kill stale trees; and treat "lock busy" as "do not query, show cached data" instead of waiting.

### H-2 — Success status is committed before the cache file: a failed `mv` certifies an empty/stale cache as `ok` and fresh

**Location:** `checkallupdates:266-270`, `checkallupdates:296-298`, `checkallupdates:325-329`,
consumed by `_cau_settle_status` (`checkallupdates:344-354`) and the stamp logic (`checkallupdates:459-499`).

```bash
# checkallupdates:266-270
run_query "$QUERY_TIMEOUT" checkupdates > "$out" 2> "$err" || rc=$?
if (( rc == 0 || rc == 2 )); then
    printf 'pacman\tok\t\n' > "$status"   # status written first
    mv -- "$out" "$CACHE_REPO"            # commit can fail; exit status discarded
    return 0
fi
```

The same pattern exists for AUR and Flatpak. `_cau_settle_status` only looks at the *status file*
(`[[ "$state" != "error" ]]`); the subshell's exit code (`rc_pacman`) is used **only** to format the
message on an empty status file (`checkallupdates:347-351`). So if `mv` fails (ENOSPC, EROFS, a
partially reclaimed cache file, a killed/parenthesised filesystem), the parent still touches
`last-refresh-pacman` (line 461) and `CACHE_STAMP` (line 496) — "query succeeded, cache fresh" —
while `updates-repo.txt` is missing or old.

**Evidence** (sourced with `CACHE_*` in `/tmp`, `checkupdates` stubbed to return one update,
`mv` made to fail only for the repo cache file):

```console
$ bash scen/t3.sh
STUB-MV FAILED for /tmp/maintenance-review/u/scen3/updates-repo.txt
refresh rc=0
CACHE_REPO exists: NO
status file    : pacman:ok: aur:skipped:... flatpak:skipped:...
pacman stamp   : PRESENT
global stamp   : PRESENT
```

`refresh_update_cache` reported success, the source is recorded `ok`, the freshness stamps were
touched, and there is no repo list at all.

**Impact:** the failure is invisible: the next UI load computes "cache fresh", `--refresh-stale`
re-queries nothing, and the list shows only AUR/Flatpak rows (or "no updates", see H-3) while a
pending Pacman upgrade set is silently dropped. "Healthy when the query failed" — the exact class
the test-suite is trying to protect against (`tests/run:105-115`).

**Fix:** commit the data *first*, then write the status, and propagate the commit result:
`mv -- "$out" "$CACHE_REPO" || { printf '%s\terror\t...\n' ...; return 1; }` — or have the
subshell return non-zero on commit failure and let `_cau_settle_status` take the return code into
account.

### H-3 — Missing cache files + fresh per-source stamps ⇒ the UI answers "当前没有待更新项目"

**Location:** `checkallupdates:103-123` (staleness tests), `checkallupdates:370-403` (`stale` scope),
`checkallupdates:491-499` (global stamp), `checkallupdates:539-551` (empty→"none").

`cache_is_fresh()` (line 113) requires the three data files to *exist*, but the `stale` scope decides
per source only from the timestamp files:

```bash
# checkallupdates:392-396
stale)
    _cau_source_is_fresh pacman || do_pacman=1
    _cau_source_is_fresh aur || do_aur=1
    _cau_source_is_fresh flatpak || do_flatpak=1
    ;;
```

and `_cau_source_is_fresh` (line 103-111) never checks the data file. So when the data files vanish
but the stamps are younger than `CACHE_MAX_AGE`, the load-event refresh queries nothing,
`refresh_failed` stays 0, `CACHE_STAMP` is (re)created at line 496, and
`print_cached_updates_or_empty` finds no rows and no status lines → prints the green
"[None] 当前没有待更新项目".

**Evidence** (sourced, `CACHE_*` in `/tmp`, stamps fresh, data files removed, all sources "unavailable"):

```console
$ bash scen/t1.sh
cache_is_fresh=no
--- UI output with REFRESH_PENDING=0:
none	-	[1;32m[None]    当前没有待更新项目[0m
```

**Impact:** a definitive "everything is up to date" while the pacman/AUR/flatpak data does not exist.
Self-sealing for up to an hour: the no-op `--refresh-stale` also re-creates `CACHE_STAMP`, so the
cycle repeats (pending → no-op refresh → "none") until the per-source stamps age out. Any cause of
missing data files hits it: manual `rm ~/.cache/checkallupdates/*.txt`, a HOME restore, a partial
backup restore, or H-2 (a missing file with an `ok` status).

**Fix:** make `_cau_source_is_fresh <src>` also require the matching data file
(`-f "$CACHE_REPO"` etc.), and let `print_cached_updates_or_empty` distinguish "no data files at all"
(print the pending/error row) from "files exist and are empty" (a real "no updates").

---

## MEDIUM

### M-1 — `flock` timeout is swallowed: the refresh lock provides no mutual exclusion precisely when it is needed

**Location:** `checkallupdates:409-413`

```bash
if check_cmd flock; then
    exec {refresh_fd}>"$CACHE_DIR/refresh.lock"
    flock -w "$REFRESH_LOCK_WAIT" "$refresh_fd" || true
fi
```

A timed-out `flock` returns 1 and the refresh proceeds anyway. So when it matters (a hung/orphaned
refresh still holding the lock, see H-1), the second refresh both waits the full `UPDATE_LOCK_WAIT`
*and* then runs concurrently: two `checkupdates` (`pacman -Sy`) runs, two writers `mv`-ing into the
same cache files, `CACHE_STATUS` assembled from mixed generations, and `flock -u` (line 502) on an
fd that was never locked.

**Evidence:** `flock -w 2 <lock> -c true` → `rc=1` after `real 0m2.001s` (run while an orphan held it),
and lines 409-413 show the result is discarded. Concurrency is otherwise possible from two terminal
windows and from `sysup:406` running `checkallupdates --refresh` while a list is open.

**Fix:** if the lock cannot be taken, return a distinct status and print cached data (with a "刷新被
另一个进程占用" status row) instead of refreshing; never refresh unlocked.

### M-2 — Clock skew / future stamp: cache pinned as fresh and labelled "刚刚更新"

**Location:** `checkallupdates:108-111`, `checkallupdates:130-133`

```bash
(( current_time - file_time < CACHE_MAX_AGE ))     # negative age => "fresh"
...
age=$(( now - mtime )); (( age < 0 )) && age=0      # "刚刚更新"
```

**Evidence** (cache data written 3 days ago, stamps set 2 h in the future):

```console
$ bash scen/t2.sh
now=2026-09-10 18:50:24  stamp=2026-09-10 20:50:24 +0800
cache_is_fresh=YES   (data files are 3 days old!)
label: 待更新列表 · 刚刚更新
```

**Impact:** after a backwards clock/RTC/timezone change, or after restoring a HOME/cache copy with
preserved timestamps, the list can show 3-day-old data as "刚刚更新" and never refresh for the whole
skew + 1 h. `cache_age_text` deliberately hides the negative age, so the UI cannot reveal it.

**Fix:** treat future stamps as stale (`(( age >= 0 && age < CACHE_MAX_AGE ))`) and, in
`cache_age_text`, show an explicit "时间异常" when `age < 0` instead of clamping.

### M-3 — `QUERY_TIMEOUT` is not a hard bound

**Location:** `checkallupdates:239-247`

```bash
run_query() {
    local seconds="$1"; shift
    if declare -F "$1" >/dev/null 2>&1 || ! check_cmd timeout; then
        "$@"; return $?
    fi
    timeout "$seconds" "$@"
}
```

Two gaps: (a) no `-k/--kill-after`, and GNU `timeout` without `-k` waits for the child to exit after
signalling it — a command that traps/ignores/delays TERM makes the "90 s" bound unbounded; (b) if the
name resolves to a shell function, no timeout at all is applied (reachable via exported
`BASH_FUNC_checkupdates%%`, and this is also the branch the test-suite stubs rely on).

**Evidence:**

```console
$ time timeout 1 bash -c 'trap "" TERM; sleep 5; echo survived'; echo rc=$?
survived
rc=124
real 0m5.005s          # a "1 second" timeout took 5 s; with an ignoring child it never returns
```

**Impact:** a stalled mirror/blackholed TCP connection can hang the refresh past `QUERY_TIMEOUT`;
`refresh_update_cache` then blocks in `wait` (lines 448-455) forever, and H-1's lock-hold becomes
permanent until the user kills the process. README:30 claims "不会无限挂起".

**Fix:** `timeout -k 5 "$seconds" "$@"` (plus `--foreground` if TTY behaviour matters) and, for the
function branch, document it or wrap in a hard deadline.

### M-4 — The lock wait happens inside fzf's blocking reload

**Location:** `checkallupdates:412` together with `checkallupdates:791`
(`ctrl-r:...+reload-sync(...)`) and the `load`-event `reload-sync` at line 154.

`REFRESH_LOCK_WAIT` defaults to 300 s and is spent inside `flock -w`, which runs inside a
`reload-sync` child: fzf does not update the list until the child exits, and the old list is what the
user keeps seeing. With an orphaned refresh holding the lock (H-1), Ctrl+R or even opening a stale
list freezes on stale data for up to 5 minutes with only the label "正在刷新" as feedback.

**Fix:** use `flock -n` for the UI-triggered refresh, or wait at most a few seconds, return a
"refresh busy" status row immediately, and let the *next* load retry.

### M-5 — `post-update-check` silently degrades to unprivileged reads without a TTY

**Location:** `post-update-check:15-27`

```bash
if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then SUDO_READ=(sudo -n); return 0; fi
[[ -t 0 && -t 1 ]] || return 0        # <- returns *success* with SUDO_READ empty
```

When there is no cached sudo credential *and* stdin/stdout are not a TTY (the normal case for
automation, `$(...)`, cron, CI, and for the test harness at `tests/run:2404-2406`),
`prepare_read_access` returns 0 with `SUDO_READ=()`: every privileged read then silently runs
unprivileged and can only ever produce "查询失败"/"无法读取" (or, combined with C-1, a false pass).

**Evidence:** in the C-1 reproduction, `sudo -n true` fails and the whole run proceeds with
`SUDO_READ` empty; the GRUB panel still reported a *warning* and exited 0.

**Fix:** distinguish "checked as root" from "checked unprivileged": record a `PRIVILEGED=0` flag and
set `QUERY_FAILED=1` (or at least emit an explicit `miss` row) when a check could not be performed
with the access it requires.

### M-6 — `sysup` always exits 1 on machines without `grub-mkconfig`

**Location:** `sysup:382-394`

```bash
else
  _warn "未找到 grub-mkconfig，跳过 GRUB 更新。"
  post_update_failed=1        # unconditional
fi
```

On a systemd-boot / UKI machine `grub-mkconfig` is legitimately absent, so every single `sysup` run
ends with `post_update_failed=1` → `sysup:427-430` warns "主系统软件包已升级，但至少一个后续步骤失败"
and returns 1 (and `checkallupdates:564-569` then reports "完整系统更新未成功完成"). The bootloader
step is skipped, not failed.

**Fix:** treat "tool not installed" as skipped (no failure flag), like the Flatpak branch
(`sysup:371-379`); only a real `grub-mkconfig` failure should set the flag. Verify the bootloader in
`post-update-check` instead.

### M-7 — News fetch: `pipefail` turns a partial curl failure into "获取新闻失败"

**Location:** `sysup:496-497` (`set -o pipefail` at `sysup:7`)

```bash
if curl -sS -L --connect-timeout 10 --max-time 25 -A "Mozilla/5.0" "$NEWS_URL" |
  python -c "$PYTHON_SCRIPT" "$COUNT_LIMIT" "${MSG[NEWS_HEADER]}"; then
```

If the feed was fully received/parsed but curl exits non-zero (e.g. `--max-time` hits during the
final read, `rc=28`), `pipefail` makes the pipeline fail even though the news was displayed, and the
user is pushed into the "是否忽略新闻强制更新？" prompt. Not destructive, but it misreports the state
and weakens the read-the-news safety step.

**Fix:** judge on python's status and treat curl's failure as informational when the parser produced
items, or use `curl --fail-with-body ... | python` and check `PIPESTATUS[1]`.

### M-8 — `mirror-update`: an unavailable `--list-countries` is treated as an invalid country

**Location:** `mirror-update:207-223` and `mirror-update:266-272`

```bash
VALID_COUNTRIES=$(reflector --list-countries 2>/dev/null || true)   # network failure => empty
...awk... END { exit !found }                                       # empty => "not found"
...
ui_err "%s %s" "$MSG_INVALID_CTRY" "$target"
if ui_confirm "$MSG_SWITCH_GLOBAL" "y"; then return 1; fi           # default y => global mode
```

With `-c Japan` on a machine where the mirror-status page cannot be fetched (the common offline case),
the user sees "无效的国家名称/代码: Japan" and the run silently switches to global mode
(`main:394-403`), discarding the explicit user choice.

**Fix:** distinguish "the list could not be fetched" from "not in the list": if
`reflector --list-countries` produced nothing, skip validation and let reflector itself decide.

---

## LOW

### L-1 — `_cau_query_aur` accepts `rc==1` with empty output as success (suspected)

**Location:** `checkallupdates:295`

```bash
if (( rc == 0 )) || { (( rc == 1 )) && [[ ! -s "$out" && ! -s "$err" ]]; }; then
```

`paru -Qua` legitimately exits 1 when there are no AUR updates, so this is intended; but a silent AUR
failure (helper exits 1 printing nothing) is then recorded `ok` and stamped fresh for an hour.
**Missing evidence:** I did not exercise a real `paru` failure mode (network queries were kept
minimal). Suggested fix: also require a successful helper "healthy" sanity marker, or record
`rc==1 && empty` as `skipped` with a note.

### L-2 — `--refresh` output is not actually free of escape codes

**Location:** `checkallupdates:77-81` (hardcoded `C_*` escapes), used by `print_cached_updates_or_empty`
(lines 539-551) and `print_cached_source_statuses` (532-534). README:35 advertises `--refresh` as the
machine-readable entry. Observed in every stub run: `none<TAB>-<TAB>ESC[1;32m[None] ...ESC[0m`.
Fix: emit a `--porcelain`/`--no-color` mode (or honour `NO_COLOR`) for the reload/automation output.

### L-3 — Hardcoded ">30天" while the threshold is configurable

`sysup:147 MSG[MIR_OLD]="镜像源已 %s 天未更新 (>30天)..."` vs `sysup:34/226` which read
`MIRROR_MAX_AGE_DAYS` (default 30). With `MIRROR_MAX_AGE_DAYS=60` the prompt lies.
Fix: interpolate the configured value.

### L-4 — The border label only knows the global stamp

`cache_age_text` (`checkallupdates:126-143`) reads `CACHE_STAMP`, which is only touched when *all*
sources are healthy (`checkallupdates:495-499`). One failing source makes the label read
"尚未成功刷新" while pacman/AUR data may be seconds old — the per-source data added in
`_cau_source_is_fresh` is not surfaced. Fix: render the oldest per-source age, or add
"(Pacman/AUR 已更新 · Flatpak 失败)" to the label.

### L-5 — Inconsistent usage exit code in `mirror-update`

`mirror-update:308-311`: a missing `-c` value calls `error` (=`ui_die`, exit 1) while an unknown
option exits 2. Automation cannot distinguish argument errors from runtime failures.
Fix: `printf ... >&2; exit 2`.

### L-6 — Silent failure when the mirrorlist cannot be written

`mirror-update:248-259`: if `reflector` succeeds and the file has `Server = https://` lines but
`sudo cp` fails, `_run_reflector` returns 1 with no message; the caller's retry/global logic then
blames the region. Fix: print the `sudo cp` error before returning 1.

### L-7 — Dead duplicate branch + undocumented env var

`checkallupdates:321-325` — the only difference between the branches is `--cached`, so the `if` is a
one-line duplication; `CHECKALLUPDATES_FLATPAK_CACHED` is not in README/config.example.
Fix: build the args array conditionally and document (or drop) the variable.

### L-8 — `find` stderr mixed into a value

`post-update-check:146-148`: `MODULE_DIRS="$(find ... -printf '%f\n' 2>&1 | sort -V)"` — find's
diagnostics become part of the "已安装模块" value printed to the user. The `|| { ... }` only fires on
a non-zero pipeline status. Fix: `2>/dev/null` (or capture stderr separately).

---

## PERF

### P-1 — `checkupdates` dominates every refresh, and it re-downloads the whole sync DB each time

`checkallupdates:266` runs `checkupdates`, which is `/usr/bin/checkupdates:150`:
`fakeroot -- pacman -Sy --dbpath "$CHECKUPDATES_DB" --logfile /dev/null` — a *full* sync-database
download into a throwaway DB on every invocation, no reuse, no `-n/--nosync`, no `-c/--change`.

**Measured on this machine:**

```console
$ time timeout 150 checkupdates > cu.out 2> cu.err
real 0m9.523s     # 10 pending updates
$ du -sh /tmp/checkup-db-1000
11M
```

Refresh calls that pay this cost: every `--refresh` (Ctrl+R, `sysup:406`, the first stale UI open),
and `update_all_pacman`/`update_selected` for the pacman source. A full upgrade cycle pays it twice
more than necessary: `sysup:348` runs `pacman -Sy --needed archlinux-keyring` (real DB sync), then
`sysup:406` immediately runs `checkallupdates --refresh` → `checkupdates` downloads all DBs again.
`flatpak remote-ls --updates` (line 324, online by default) is the second-largest cost and also
re-fetches remote metadata; `CHECKALLUPDATES_FLATPAK_CACHED` exists but is off by default and
undocumented.

**Suggested fixes (1-2):** (a) keep the existing `CHECKUPDATES_DB` and call `checkupdates -n` when the
temp DB is younger than ~10 min (the post-upgrade refresh in particular); (b) pass
`-c/--change` or reuse the DB that `pacman -Sy`/`paru -Su` just synced rather than triggering a third
full download; (c) expose `CHECKALLUPDATES_FLATPAK_CACHED` in config.example and use it when the UI
only needs a fast re-render.

### P-2 — Per-refresh overhead is negligible and the parallel design is correct (no action)

`checkallupdates:428-456` runs the three sources concurrently and waits in `wait` (total ≈ slowest
source, measured 9.5 s dominated by checkupdates). `_cau_reclaim_orphans` costs 6 `find` calls on a
≤14-file directory; 10 `mktemp` + 4 `mv` per refresh. `print_tagged_cache` (`169-183`) uses a single
`awk` for the whole list instead of per-line `read`; `cache_age_text` is one `stat`; `ui_status_line`
(1 `df` + 1 `ip`) runs once per UI loop. None of these are worth changing. The only real latency
multiplier is the lock wait (M-1/M-4) and the extra full DB syncs (P-1).

---

## Coverage / confidence

**Read line-by-line:** all 2021 lines of the four in-scope scripts (plus `lib/ui.sh` lock/keepalive/
tally/panel code and `lib/config.sh`). `bash -n` and `shellcheck -x -f gcc` are clean on all four.

**Executed (read-only / stubbed):** `checkupdates` (real, 9.5 s); `reflector --list-countries` (real);
`bash -n`, `shellcheck`; PATH-stub refresh runs in `/tmp` (orphan/lock/SIGKILL experiment, false
"no-updates" harness, failed-`mv` harness, clock-skew harness); real `fzf` 0.74.3 driven through a
Python PTY (Esc/Ctrl+C kill semantics); nested maintenance-lock test (`sysup`-style outer lock →
`mirror-update`), which **passed** (the inherited-fd reentrancy in `ui.sh:237-247` works, so the
`sysup:256` → `mirror-update` call is not blocked — no finding).

**Not verified (would need more intrusive tests):** end-to-end `sysup` run (requires real state
changes — forbidden); `systemd-inhibit` behaviour without a D-Bus session; real `paru -Qua` failure
modes (L-1 stays "suspected"); absolute timings for `flatpak remote-ls`/`paru -Qua`; text of the
`fzf` reload-failure message on a non-zero `--refresh` exit. The test-46 RCA is the Lead's; the
file-scope mechanism + reproduction is in C-1.
