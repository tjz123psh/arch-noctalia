# Diagnostics review — hw-doctor, storage-health, gpu-check, check-battery, boot-check, pacnew-check, log-check, recommend-check, terminal-tools

Reviewer: review-diagnostics (task-5). Read-only audit of `/home/pang/scripts/maintenance`.
Scope fully read: hw-doctor 439L, storage-health 264L, gpu-check 278L, check-battery 121L,
boot-check 294L, pacnew-check 121L, log-check 187L, recommend-check 320L, terminal-tools 369L,
plus `lib/ui.sh` (shared exit/tally semantics) and README exit-code contract.

Method: read every line; `bash -n` + `shellcheck -x -S info` (0 findings); ran each script with
harmless flags only (`--status`/`--strict`/`--help`); failure paths reproduced with stub commands
placed in `/tmp/maintenance-review/bin*` or by isolating `PATH` to a `/usr/bin` symlink farm minus
one tool; `terminal-tools` exercised against a throwaway `HOME`/`XDG_*`/`GIT_CONFIG_GLOBAL` under
`/tmp`. Raw runs: `/tmp/maintenance-review/runs/*.out`. **No workspace file was created or modified.**

Environment: Arch, `LANG=zh_CN.UTF-8`, root fs btrfs (`/`, `/home`), `/boot` vfat mode 700,
jq/smartctl/upower/lspci/lsmod/findmnt/btrfs(v7.1)/systemd-escape/pacdiff all present, non-TTY
(so `sudo -n` fails and the `-t 0` prompts are skipped), EUID 1000.

---

## CRITICAL

No finding reached critical. No path was found that reports a *real failing disk / corrupted
filesystem* as healthy without at least one warning line. The three highest-risk items are H1–H3.

---

## HIGH

### H1. `jq` `// empty` swallows boolean `false` — the "SMART overall health FAILED" branch is dead code

- **file:line** `storage-health:44-46` (`smart_value`), `:70` (`health=`), `:87-91` (`case "$health"`)
- **Code**
  ```bash
  smart_value() { local json="$1" filter="$2"; jq -r "$filter // empty" <<< "$json" 2>/dev/null || true; }
  health="$(smart_value "$json" '.smart_status.passed')"
  case "$health" in
    true)  ui_panel_stat ok "SMART 总体健康检查通过" ;;
    false) ui_panel_stat err "SMART 总体健康检查失败" ;;   # never runs
    *)     ui_panel_stat warn "设备没有提供 SMART 总体结论" ;;
  esac
  ```
- **Evidence** jq's `//` yields the RHS for both `null` **and `false`**:
  ```
  $ jq -n 'false // empty'          # prints nothing, rc=0
  $ echo '{"smart_status":{"passed":false}}' | jq -r '.smart_status.passed // empty'   # 0 bytes
  $ echo '{"smart_status":{"passed":false}}' | jq -c '.smart_status'                   # {"passed":false}
  ```
  End-to-end with a stub `smartctl` returning `"smart_status":{"passed":false}` and
  `"smartctl":{"exit_status":0}`: `storage-health --strict` printed
  `│  [注意] 设备没有提供 SMART 总体结论` (rc=1), never the intended `[错误] SMART 总体健康检查失败`.
- **Impact** A device whose overall-health verdict is FAILED is reported as "device did not provide
  a verdict" (warn). Mitigation: on real ATA/NVMe disks smartctl normally also sets exit bit 3,
  which line 124 surfaces as `[错误] smartctl 报告磁盘正在失效`; the fixture above shows the
  mis-report is real whenever bit 3 is absent (bridges/wrappers/JSON produced by other tools).
  The `false)` branch is unreachable as written.
- **Fix** Use `jq -r 'if .smart_status.passed == null then empty else (.smart_status.passed|tostring) end'`
  or drop `// empty` for booleans (`jq -r '.smart_status.passed'` prints `false` correctly).

### H2. `terminal-tools --disable` Git rollback always fails when any managed key is absent ("退出码 0")

- **file:line** `terminal-tools:241-247`
- **Code**
  ```bash
  if ! git config --global --unset-all "$key" >/dev/null 2>&1; then
    # 退出码 5 代表该键原本不存在；其它错误才算失败。
    rc=$?                     # <-- $? is the status of the negated condition = 0
    if [[ "$rc" -ne 5 ]]; then
      ui_err "无法清除 Git 配置项 %s（退出码 %s）。" "$key" "$rc"
      return 1
    fi
  fi
  ```
- **Evidence** bash gives `$? = 0` inside the `then` branch of `if ! cmd` (verified:
  `if ! false; then echo $?; fi` → `0`), while `git config --global --unset-all` really returns 5
  for a missing key (verified with a nonexistent key: `rc=5`, `~/.gitconfig` mtime/size unchanged).
  Reproduced end-to-end in a temp HOME:
  ```
  terminal-tools --enable                       # ok, state file written
  git config --global --unset delta.side-by-side
  terminal-tools --disable                       # rc=1
  stderr: [错误] 无法清除 Git 配置项 delta.side-by-side（退出码 0）。
          [错误] Fish 集成已移除，但 Git 配置恢复失败；状态文件仍保留在: …/terminal-tools-git-before.tsv
  ```
  Fish block removed, state file kept, `core.pager` etc. left at the delta values.
- **Impact** The documented "完整撤销 / 准确恢复旧值" rollback breaks as soon as one managed key was
  removed externally (dotfiles sync, another tool, a partially failed `--enable`). The error text
  reports a nonsensical exit code 0. The repo test `test_terminal_tools_lifecycle` does not cover
  this state (it only exercises a normal enable→disable round trip).
- **Fix** Capture the code before negating: `if git config --global --unset-all "$key" >/dev/null 2>&1; then :; else rc=$?; [[ $rc -eq 5 ]] || { …; return 1; }; fi`
  (or `git config --global --unset-all "$key" >/dev/null 2>&1; rc=$?` then test `rc`).

### H3. Missing required commands violate the README exit-code contract; two scripts exit 0

- **file:line** `gpu-check:187-189`, `storage-health:138-142`, `hw-doctor:276-278`,
  `pacnew-check:60-64`, `recommend-check:145-150`, `log-check:163-168`, `boot-check:141-144`,
  contract at `README.md:323` (`127：缺少执行该功能所需的命令`); `check-battery:43-46` is the only
  script that gets it right.
- **Code (examples)**
  ```bash
  gpu-check:188        ui_panel_stat miss "缺少 lspci，建议安装 pciutils"     # no failure flag, then ui_tally_status "$strict"
  storage-health:138-142  miss "缺少 lsblk（util-linux）" / "缺少 jq…"        # no failure flag
  hw-doctor:276-278    miss "缺少 lscpu"; HW_QUERY_FAILED=1                   # -> return 1
  pacnew-check:60-63   ui_panel_stat miss "缺少 pacdiff…"; panel_end; exit 1
  ```
- **Evidence** isolated-PATH farm runs (script with the named tool removed from `PATH`):
  ```
  gpu-check   (no lspci)     -> rc=0     # "缺失 缺少 lspci" visible, exit says success
  gpu-check --strict         -> rc=1
  storage-health (no lsblk/jq) -> rc=0   # 5 miss items, exit says success
  storage-health --strict    -> rc=1
  hw-doctor   (no lscpu)     -> rc=1
  boot-check  (no findmnt)   -> rc=1
  pacnew-check (no pacdiff)  -> rc=1
  recommend-check (no pacman)-> rc=1
  log-check   (no systemctl) -> rc=1
  check-battery (no upower)  -> rc=127   # correct per README
  ```
- **Impact** Automation and `term-menu` (`term-menu:1469` special-cases 127 as "command missing")
  cannot distinguish "tool not installed" from "system unhealthy"; `gpu-check`/`storage-health`
  return 0 when their primary input commands are absent, i.e. a silent success.
- **Fix** Return 127 (or set a dedicated flag → 127) when a required query command is absent in all
  diagnostic scripts, matching `check-battery:45` and `README.md:323`.

---

## MEDIUM

### M1. `check-battery` never checks the exit status of its own `upower` calls

- **file:line** `check-battery:48`, `:55` (and `:50-53`, `:86-91`)
- **Code**
  ```bash
  BAT_PATH="$(upower -e | awk '/battery/ {print; exit}')"   # pipeline rc ignored; pipefail set
  INFO="$(upower -i "$BAT_PATH")"                            # set -e aborts on failure
  ```
- **Evidence**
  1. stub `upower` failing on `-e`: `PATH=$stub:$PATH check-battery` → `rc=1`, stdout empty,
     stderr only `upower: daemon not running`. The intended `未检测到电池设备（虚拟机 / 台式机属正常）`
     message is never printed (`set -euo pipefail` kills the script at line 48).
  2. stub `upower -e` ok, `-i` failing: `rc=3` (upower's raw code, outside the documented 0/1/2/127
     set), zero UI output — the script dies at line 55.
  3. stub `upower -e` ok, `-i` succeeding with **empty** output: `rc=0` and a full report of
     `设备型号 未知 / 当前状态 未知 / 当前电量 未知 / 电池健康度 未知` — success exit on unparseable data.
- **Impact** A broken/absent upower daemon is indistinguishable from "desktop, no battery", the user
  gets no diagnostic, and empty output is reported as a successful run.
- **Fix** Check each `upower` call explicitly (`rc` + non-empty output) and `ui_err` + `exit 1` on
  failure before falling back to the "no battery" path.

### M2. `gpu-check` does not know Intel (`i915`/`xe`) or legacy `radeon` modules → false warning on Intel systems

- **file:line** `gpu-check:199-204`
- **Code** `awk '$1 ~ /^(amdgpu|nvidia|nouveau)$/ …'` then `warn "未发现 amdgpu / nvidia / nouveau 模块"`
- **Evidence** stub `lspci` (Intel Iris Xe, driver `i915`) + stub `lsmod` (`i915`, `drm`):
  ```
  $ PATH=$stub:$PATH gpu-check --strict
  rc=1
  │  [注意] 未发现 amdgpu / nvidia / nouveau 模块
  ```
- **Impact** Every Intel-GPU machine (and Intel+NVIDIA hybrid under `i915`) gets a spurious "no GPU
  kernel module" warning and a strict-mode failure; the check quietly only understands AMD/NVIDIA.
- **Fix** Add `i915|xe|radeon|amdgpu|nvidia|nouveau` (and print the actually loaded DRM modules)
  before deciding "none found".

### M3. `recommend-check` treats "no GPU present" as "GPU query failed" (rc=1) on headless hosts

- **file:line** `recommend-check:167-172`, `:196-199`; same pattern for CPU vendor at `:159-164`, `:192-195`
- **Code**
  ```bash
  gpu="$(first_gpu_line 2>&1)" || gpu_rc=$?
  if [[ "$gpu_rc" -ne 0 ]]; then gpu=""
  elif [[ -z "$gpu" ]]; then gpu_rc=1        # lspci succeeded, simply no VGA/3D/Display line
  fi
  ```
- **Evidence** stub `lspci` printing only an ISA bridge (headless server/VM):
  ```
  $ PATH=$stub:$PATH recommend-check
  rc=1
  │  GPU                 unknown
  │  [注意] GPU 查询失败（退出码 1）
  ```
  (lscpu without a `Vendor ID:` line, e.g. ARM, takes the same branch at `:163`.)
- **Impact** A machine that simply has no discrete/integrated PCI display device is reported as a
  failed query and the whole script exits 1 — automated runs flag a healthy host.
- **Fix** Distinguish "lspci succeeded but no GPU" (info/"none detected") from a real command
  failure; only set `RECOMMEND_QUERY_FAILED` when the command itself failed.

### M4. `storage-health` misreads "no Btrfs mounts" (`findmnt` rc=1) as a query failure

- **file:line** `storage-health:199-204`, unreachable branch `:255-258`
- **Code** `if ! BTRFS_MOUNTS="$(findmnt -rn -t btrfs -o TARGET,SOURCE 2>&1)"; then … warn "Btrfs 挂载查询失败"`
- **Evidence** `findmnt` returns 1 with empty output when a filter matches nothing
  (`findmnt -rn -t ext4 -o TARGET,SOURCE` → rc=1, no output; same for `xfs`), and with a stub
  `findmnt` that always exits 1 (simulating a non-btrfs machine):
  ```
  $ PATH=$stub:$PATH storage-health --strict
  rc=1
  │  [注意] Btrfs 挂载查询失败
  ```
  The intended `info "当前没有已挂载的 Btrfs 文件系统"` (line 257) can never be reached.
- **Fix** Treat rc=1 with empty output as "no Btrfs filesystem"; only report a query failure when
  `findmnt` failed with output/other rc.

### M5. `storage-health` reports legitimate `is-enabled` states (`masked`, `static`, …) as query failures

- **file:line** `storage-health:243-251`
- **Code** only `enabled` / `disabled` are accepted; everything else → `warn "每月 scrub timer 状态查询失败（退出码 $timer_rc）"`
- **Evidence** stub `systemctl` printing `masked` and exiting 1:
  ```
  │  [注意] 每月 scrub timer 状态查询失败（退出码 1）
  ```
  `systemctl is-enabled` legitimately returns e.g. `alias` (rc 0), `not-found` (rc 4),
  `masked`/`static`/`enabled-runtime`/`indirect`/`generated` (rc 1).
- **Impact** Masking the scrub timer (the normal way to disable it) is reported as a broken query
  rather than "masked/not enabled". `boot-check:81-84` already has the complete state list to copy.
- **Fix** Accept the full `is-enabled` state vocabulary; only warn "查询失败" when the output is not
  one of the known states (as `boot-check:check_unit` does).

### M6. `df` space panel includes pseudo/immutable filesystems and can produce false "err"

- **file:line** `storage-health:175-181`
- **Code** `df -P -x tmpfs -x devtmpfs` → percent ≥95 → `err`; ≥85 → `warn`
- **Evidence** current run already lists `efivarfs` as a "persistent filesystem":
  `│  [成功] /sys/firmware/efi/efivars 已使用 52%`. `-x` only excludes tmpfs/devtmpfs, so
  `efivarfs`, `overlay` (docker/snap), `squashfs` (snap/ISO), `fuse.*` are included.
  **Suspected** for squashfs/overlay: such a mount is 100 % full by construction → `[错误] … 已使用
  100%` and a strict rc=1 on a healthy machine; no squashfs/overlay mount exists on this host to
  demonstrate it (efivarfs inclusion is observed).
- **Fix** Restrict to real block-backed filesystems (`df -P -x tmpfs -x devtmpfs -x efivarfs -x overlay -x squashfs`),
  or explicitly skip read-only/pseudo mounts.

---

## LOW

### L1. `err` findings are accumulated into the "缺失" (missing) counter
- **file:line** `lib/ui.sh:619` (`err) … UI_N_MISS=$((…+1))`), summary at `:636-638`.
- **Evidence** `storage-health --strict` with a stub reporting `percentage_used: 95` and
  `media_errors: 2`: `│  [错误] NVMe 寿命已使用 95%` … `[成功] 8 正常  [注意] 2 注意  [缺失] 1 缺失`.
  Exit semantics are unaffected (`ui_tally_status:642-648` tests WARN+ MISS), but the summary
  mislabels hard errors as missing items for every script in scope.
- **Fix** Give `err` its own counter/label (or print `UI_N_MISS` as "缺失/错误").

### L2. `hw-doctor` prints a second, misleading warning when `lscpu` is absent
- **file:line** `hw-doctor:276-278` then `:284-289`.
- **Evidence** isolated PATH run: `│  [缺失] 缺少 lscpu` **and** `│  [注意] 无法判断 CPU 厂商`.
- **Impact** Double signal and the real cause ("cannot detect vendor") is attributed to a vendor
  ambiguity; microcode package check is skipped without saying so.
- **Fix** Gate the vendor block on `lscpu_rc == 0` / non-empty output.

### L3. `pacnew-check` temp files are not registered for cleanup
- **file:line** `pacnew-check:67-71`, `:93-97`, `:111`; contrast `log-check:9-11`, `:45-49` which
  uses `ui_tmp_register`/`ui_tmp_discard` and INT/TERM traps.
- **Impact** Ctrl+C between `mktemp` and `rm` leaks `/tmp/tmp.XXXXXXXX` files; `set -e` aborts also
  skip the `rm`.
- **Fix** Add `trap 'ui_tmp_cleanup' EXIT` + `ui_tmp_register`/`ui_tmp_discard` as in `log-check`.

### L4. `terminal-tools --disable` creates an empty `config.fish` when none exists
- **file:line** `terminal-tools:84-90`, `:100-101`, `:129-130` (`old_mode` defaults to 644,
  `: > "$tmp"` then `mv -f "$tmp" "$FISH_CONFIG"`).
- **Evidence** temp HOME, no `config.fish` before: `terminal-tools --disable` → rc=0 and
  `-rw-r--r-- … 0 config.fish` created.
- **Fix** Skip the rewrite (and report "nothing to remove") when `$FISH_CONFIG` does not exist.
- Note (suspected): `mv -f` replaces a *symlinked* `config.fish` with a regular file; on this
  machine the file is a regular file, so dotfiles-managed symlink setups were not exercised.

### L5. `log-check` duplicates `systemctl --failed` and has no report handling
- **file:line** `log-check:74-76` (system+user) and `:141` (third call, `2>/dev/null … || true`).
- **Impact** Extra subprocess per run; a failure at `:141` is silently swallowed (no hint emitted).
- Also `log-check:170-172`: every run writes `~/log-check-YYYYmmdd-HHMMSS.md` (documented in
  `term-menu:391`) with no rotation/cleanup — the files accumulate in `$HOME` forever.
- Also `log-check:172`: an unwritable `LOG_CHECK_REPORT` aborts with raw bash text and no UI error:
  `LOG_CHECK_REPORT=/tmp log-check` → `rc=1`, stderr `… 行 172: /tmp: 是一个目录`, panel never closes.
- **Fix** Reuse the first `--failed` output for the hint; wrap the report redirect and emit
  `ui_err` on failure; mention/rotate the report files.

### L6. Strict/warning semantics of `log-check` (assigned focus) — verified, one gap
- `log-check` has no `--strict` (usage error 2, consistent with its `--help`) and returns 1 only
  when a query failed (`:182`), or 1/exit-1 on missing deps (`:163-168`).
- **Gap**: a report full of failed units/errors still exits 0, unlike siblings. Evidence: with
  stub `systemctl`/`journalctl` failing, rc=1 (correct); on the live machine failed units are
  absent so the "items found → rc 0" path could not be exercised. Marked **suspected** for the
  "failed units are not signalled" claim (`log-check:182` only tests `REPORT_QUERY_FAILED`).

### L7. `boot-check` checks `btrfs-scrub@-.timer` and snapper units unconditionally
- **file:line** `boot-check:278-281` (after `:257-261` already determined `/` is not Btrfs on some
  machines). On a non-btrfs host the `-.timer` instance is `not-found` → `miss` → strict rc=1.
- **Fix** Only check the scrub/snapper units when `/` is Btrfs / when snapper is installed.

### L8. `storage-health` prints `0.0 GiB` when `lsblk` reports a null size
- **file:line** `storage-health:153` (`(.size // 0) | tostring`) → `:162-166` (`".1f GiB"`).
- **Impact** The intended `大小未知` fallback only triggers for non-numeric size; a missing/0 size
  is displayed as "0.0 GiB".
- **Fix** Emit an empty/`null` marker and keep the `大小未知` branch for it.

### L9. `storage-health` ignores the scrub `Status:` field; error regex omits `corrected_errors`
- **file:line** `storage-health:233-238`, regex `:235`.
- **Impact (suspected)** With rc=0 the code prints `ok 上次 scrub 未报告关键错误` for any output that
  has no error counters — including an `aborted`/in-progress scrub — because `Status:` is never
  inspected. `corrected_errors:` is the one raw counter not covered by the regex (btrfs-progs v7.1
  emits `corrected_errors: %lld`; verified via `strings /usr/bin/btrfs`); it is normally accompanied
  by `csum_errors`/`read_errors`, so this is defence-in-depth only. **Missing evidence**: no aborted
  scrub could be produced on this live machine (would require a write operation).

### L10. `check-battery` leading-zero health values hit bash octal arithmetic
- **file:line** `check-battery:102-107`. `HEALTH_NUM` comes from `awk '{print a[1]}'`; a value such
  as `08` passes `^[0-9]+$` and then `(( HEALTH_NUM >= 80 ))` errors ("value too great for base"),
  printing to stderr and falling through to the red branch. upower normally formats without a
  leading zero, so this is **suspected/edge**; the fix is `(( 10#$HEALTH_NUM >= 80 ))`.

### L11. `cmd | awk '{…; exit}'` under `pipefail` can turn a huge producer output into a false query failure
- **file:line** `recommend-check:45` (`lspci | awk … exit`), `check-battery:48` (`upower -e | awk … exit`).
- **Impact (suspected)** When the producer writes more than the pipe buffer after awk exits, it dies
  of SIGPIPE (rc 141) and `pipefail` propagates 141 → "GPU 查询失败（退出码 141）"/ script abort.
  Not observed here: `lspci` output is ~4 KB and `upower -e` 5 lines, both below the 64 KiB buffer.
  **Missing evidence**: no wide-PCI machine available to exceed the buffer.

### L12. `hw-doctor` `run_cmd` prints nothing when a command succeeds with empty output
- **file:line** `hw-doctor:48-49`. `run_cmd snapper list-configs` on a host with no configs is
  silent; the panel just lacks a line. Cosmetic.

### L13. `recommend-check` duplicates the Bluetooth probe and mislabels virtualisation failures
- **file:line** `recommend-check:204` and `:241` both call `has_bluetooth_controller` (each runs
  `find` + `grep`); `:247-248` treats `virt="unknown"` (query failed) as "当前是虚拟机".
- **Fix** Call the probe once; only print the VM sentence when `virt_rc == 0`.

---

## PERF (read latency / process spawning)

### P1. `hw-doctor` — many single-value subprocesses
- `:242-244` three separate `uname` calls; `:248-249` two `timedatectl show` calls;
  `:386-398` one `findmnt` per mountpoint (up to 4); `:342-350` + `:415-422` 11 `systemctl
  is-active` calls (one per unit); `:24-26` `pkg_installed` spawns a `grep` with a ~300 KB herestring
  for every package check (~10×). Could be: one `uname -srmn`, one
  `timedatectl show -p Timezone -p NTPSynchronized`, one `findmnt -rn -o …`, one
  `systemctl is-active u1 u2 …`, and one assoc-array load of `pacman -Qq` (as `recommend-check:26-41`
  already does).

### P2. `boot-check` loads the whole package database to test six names
- `:163` `pacman -Qq` (≈12 k lines on this host) then `check_pkg` greps it six times;
  `:75-76` spawns `systemctl is-active` **and** `is-enabled` per unit (8 calls for 4 units —
  `systemctl show -p ActiveState,UnitFileState` does it in one call per unit).

### P3. `storage-health` — per-device/per-mount serial external calls
- `:60` one `smartctl -a -j` per disk (unavoidable, but sequential across multiple disks);
  `:213` `btrfs device stats` + `:229` `btrfs scrub status` + `:243` `systemctl is-enabled` per
  Btrfs mount. Acceptable for 1–2 mounts; would be a visible delay on many disks/mounts.

### P4. `log-check` / `pacnew-check` / `recommend-check` duplicate scans
- `log-check:76` + `:141` (same `systemctl --failed` twice, plus the user variant);
  `pacnew-check:68` `pacdiff --output` then `:95` four full `find` walks of `/etc`, `/boot`,
  `/usr/lib/sysusers.d`, `/usr/lib/tmpfiles.d`; `recommend-check:204/241` double Bluetooth probe.

### P5. Unbounded `~` report accumulation from `log-check`
- `log-check:170`: one new `~/log-check-<timestamp>.md` per invocation, never pruned by `clean`
  or any other script (grep found no references outside `term-menu:391`).

---

## Coverage / confidence

- **Read in full**: all nine scope scripts + `lib/ui.sh` (exit/tally contract) + README exit-code
  section + the scope-relevant parts of `tests/run` and `term-menu`'s leaf-status handling.
- **Strict semantics explicitly verified for my files**: `ui_tally_status` (`lib/ui.sh:642-648`)
  cannot lose warnings here — every `ui_panel_stat`/`warn` call in these nine scripts runs in the
  main shell (no subshell/pipeline wrappers), and the query-failure gates
  (`hw-doctor:435`, `boot-check:290`, `pacnew-check:117`, `recommend-check:316`) precede
  `ui_tally_status`, so `--strict` results are sound. `pacnew-check`/`boot-check`/`log-check`
  strict behaviour was exercised with stubs and matches intent except H3 (missing-command codes)
  and L6. **No lost-warning bug found.**
- **Static checks**: `bash -n` clean for all nine; `shellcheck -x -S info` produced **zero**
  findings for all nine (no unquoted-expansion or `[ ]`-vs-`[[ ]]` hits).
- **Live-machine limitations**: no failing disk, no non-btrfs root, no Intel GPU, no aborted scrub,
  no 100 %-full filesystem, non-TTY session (so the interactive `sudo -v` prompt paths of
  `boot-check`/`pacnew-check`/`storage-health` were checked by code reading and by the repo's
  `test_privileged_read_prompts`, not by running them). Items marked *suspected* above list their
  missing evidence.
