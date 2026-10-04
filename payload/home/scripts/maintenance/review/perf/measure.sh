#!/usr/bin/env bash
# Read-only measurement battery for /home/pang/scripts/maintenance performance review.
# All artifacts live under /tmp/maintenance-review/perf/. Nothing in the repo is touched.
set -u
P=/tmp/maintenance-review/perf
R=/home/pang/scripts/maintenance
L=$P/logs
BIN=$P/bin
STUB=$P/stub
mkdir -p "$L" "$P/home"
export HOME=$P/home
BASE_PATH=$BIN:$STUB:/usr/local/sbin:/usr/local/bin:/usr/bin:/bin
now_ms() { date +%s%N; }
run_ms() { # run_ms <n> <cmd...>  -> prints "median min max"
  local n=$1; shift
  local i s e times=()
  for ((i = 0; i < n; i++)); do
    s=$(now_ms); "$@" >/dev/null 2>&1; e=$(now_ms)
    times+=("$(( (e - s) / 1000000 ))")
  done
  printf '%s' "$(printf '%s\n' "${times[@]}" | sort -n | awk '{a[NR]=$1} END{ printf "median=%d min=%d max=%d n=%d", a[int((NR+1)/2)], a[1], a[NR], NR }')"
}
hdr() { printf '\n########## %s ##########\n' "$1"; }

export PATH=$BASE_PATH
export FZF_SHIM_LOG=$L/fzf.log FZF_SHIM_COUNT=$L/fzf.count
unset FZF_SHIM_PICK FZF_SHIM_RC

hdr "0. environment"
printf 'date=%s kernel=%s\n' "$(date -Is)" "$(uname -r)"
printf 'bash=%s jq=%s fzf=%s strace=%s\n' "$(bash --version | head -1)" "$(jq --version)" "$(fzf --version)" "$(strace -V | head -1)"
printf 'repo HEAD=%s\n' "$(git -C "$R" rev-parse --short HEAD 2>/dev/null || echo n/a)"
printf 'repo dirty files=%s\n' "$(git -C "$R" status --porcelain 2>/dev/null | wc -l)"

hdr "1. term-menu cold start, fake fzf cancels immediately (FZF_SHIM_RC=130)"
export FZF_SHIM_RC=130
printf 'term-menu cancel-to-exit: %s\n' "$(run_ms 5 "$R/term-menu")"
FZF_SHIM_RC=130 "$R/term-menu" </dev/null >/dev/null 2>&1
strace -f -e trace=execve -o "$L/tm-execve.txt" "$R/term-menu" </dev/null >/dev/null 2>&1
printf 'successful execve per cancel-to-exit: %s\n' "$(grep 'execve(' "$L/tm-execve.txt" | grep -vc ENOENT)"
grep 'execve(' "$L/tm-execve.txt" | grep -v ENOENT | sed -E 's/.*execve\("([^"]+)".*/\1/' | sort | uniq -c | sort -rn | sed 's/^/    /'
printf 'ui_status_line (bash -c, sources lib/ui.sh): %s\n' "$(run_ms 10 bash -c ". $R/lib/ui.sh; ui_status_line")"
printf 'term-menu --preview __update_menu: %s\n' "$(run_ms 10 "$R/term-menu" --preview __update_menu)"
printf 'term-menu --preview clean: %s\n' "$(run_ms 10 "$R/term-menu" --preview clean)"

hdr "2. term-menu view-snapshots drive, stub snapper (2 configs)"
export SNAPPER_LOG=$L/snapper.log STUB_SNAP_COUNT=10
drive_snaps() {
  rm -f "$FZF_SHIM_LOG" "$FZF_SHIM_COUNT" "$SNAPPER_LOG"
  local s e; s=$(now_ms); FZF_SHIM_PICK="1:__snapshot_menu;2:view-snapshots" "$R/term-menu" </dev/null >/dev/null 2>&1; e=$(now_ms)
  printf '%d ms (snapper calls=%s)' "$(( (e - s) / 1000000 ))" "$(grep -c CALL "$SNAPPER_LOG" 2>/dev/null || echo 0)"
}
for d in 0 0.1 0.3 0.6; do
  export STUB_DELAY_SNAPPER=$d
  printf 'per-snapper-latency %ss -> %s\n' "$d" "$(drive_snaps)"
done
export STUB_DELAY_SNAPPER=0
for c in 10 200 500; do
  export STUB_SNAP_COUNT=$c
  printf 'snapshots/config %s -> %s\n' "$c" "$(drive_snaps)"
done
export STUB_SNAP_COUNT=200
rm -f "$FZF_SHIM_LOG" "$FZF_SHIM_COUNT" "$SNAPPER_LOG"
FZF_SHIM_PICK="1:__snapshot_menu;2:view-snapshots" strace -f -c -o "$L/tm-snap200-c.txt" "$R/term-menu" </dev/null >/dev/null 2>/dev/null
printf 'strace summary 200 snaps/config (clone/execve/wait4):\n'
grep -E 'clone|execve|wait4|% time' "$L/tm-snap200-c.txt" | sed 's/^/    /'
printf 'system time in that run: %s\n' "$(grep -E '^[0-9.]+ +[0-9.]+' "$L/tm-snap200-c.txt" | tail -1)"

hdr "3. lib/ui.sh helper costs"
printf 'bash -c exit: %s\n' "$(run_ms 20 bash -c exit)"
printf 'bash -c ". lib/ui.sh": %s\n' "$(run_ms 20 bash -c ". $R/lib/ui.sh")"
printf 'bash -c ". lib/ui.sh; ui_status_line": %s\n' "$(run_ms 20 bash -c ". $R/lib/ui.sh; ui_status_line")"
printf 'ui_pad x1 standalone process: %s\n' "$(run_ms 20 bash -c ". $R/lib/ui.sh; ui_pad abc 8")"

hdr "4. checkallupdates --refresh with stubs"
export STUB_LOG=$L/stub.log
refresh_ms() {
  rm -f "$STUB_LOG"
  local s e; s=$(now_ms); "$R/checkallupdates" --refresh >/dev/null 2>&1; e=$(now_ms)
  printf '%d ms (source stub calls=%s)' "$(( (e - s) / 1000000 ))" "$(grep -c START "$STUB_LOG" 2>/dev/null || echo 0)"
}
rm -rf "$P/home/.cache/checkallupdates"
export STUB_DELAY_CHECKUPDATES=1 STUB_DELAY_PARU=1 STUB_DELAY_FLATPAK=1
printf 'all sources 1.0s  (parallel=>1000 sequential=>3000): %s\n' "$(refresh_ms)"
grep -E 'START|END' "$STUB_LOG" | sed 's/^/    /'
export STUB_DELAY_CHECKUPDATES=3 STUB_DELAY_PARU=1 STUB_DELAY_FLATPAK=1
printf 'pacman 3s aur 1s flatpak 1s (parallel=>3000 sequential=>5000): %s\n' "$(refresh_ms)"
export STUB_DELAY_CHECKUPDATES=0 STUB_DELAY_PARU=0 STUB_DELAY_FLATPAK=0
printf 'all sources 0s (pure bookkeeping): %s\n' "$(refresh_ms)"
strace -f -e trace=execve -o "$L/cau-execve.txt" "$R/checkallupdates" --refresh >/dev/null 2>&1
printf 'successful execve per --refresh (warm, 0s stubs): %s\n' "$(grep 'execve(' "$L/cau-execve.txt" | grep -vc ENOENT)"
grep 'execve(' "$L/cau-execve.txt" | grep -v ENOENT | sed -E 's/.*execve\("([^"]+)".*/\1/' | sort | uniq -c | sort -rn | sed 's/^/    /'
export STUB_DELAY_CHECKUPDATES=1 STUB_DELAY_PARU=1 STUB_DELAY_FLATPAK=1
printf -- '--refresh-stale, everything fresh: %s\n' "$(refresh_stale() { rm -f "$STUB_LOG"; local s e; s=$(now_ms); "$R/checkallupdates" --refresh-stale >/dev/null 2>&1; e=$(now_ms); printf '%d ms (source stub calls=%s)' "$(( (e - s) / 1000000 ))" "$(grep -c START "$STUB_LOG" 2>/dev/null || echo 0)"; }; refresh_stale)"
touch -d '2 hours ago' "$P/home/.cache/checkallupdates/last-refresh-aur"
printf -- '--refresh-stale, only AUR stale: %s\n' "$(refresh_stale)"
printf -- '--load-actions (fzf load event, fired per render): %s\n' "$(run_ms 5 "$R/checkallupdates" --load-actions)"

hdr "5. checkallupdates interactive open (fake fzf, CHECKALLUPDATES_ALLOW_NONINTERACTIVE_UI=1)"
export CHECKALLUPDATES_ALLOW_NONINTERACTIVE_UI=1 FZF_SHIM_RC=130
rm -f "$FZF_SHIM_LOG" "$FZF_SHIM_COUNT"
printf 'cold cache open: %s (fzf calls=%s)\n' "$(run_ms 5 "$R/checkallupdates")" "$(grep -c CALL "$FZF_SHIM_LOG" 2>/dev/null || echo 0)"
rm -rf "$P/home/.cache/checkallupdates"
strace -f -e trace=execve -o "$L/cau-ui-execve.txt" "$R/checkallupdates" >/dev/null 2>&1
printf 'successful execve, cold interactive open: %s\n' "$(grep 'execve(' "$L/cau-ui-execve.txt" | grep -vc ENOENT)"
grep 'execve(' "$L/cau-ui-execve.txt" | grep -v ENOENT | sed -E 's/.*execve\("([^"]+)".*/\1/' | sort | uniq -c | sort -rn | sed 's/^/    /'
"$R/checkallupdates" --refresh >/dev/null 2>&1
printf 'warm cache open: %s\n' "$(run_ms 5 "$R/checkallupdates")"

hdr "6. quickload list paths (stub snapper)"
export SNAPPER_LOG=$L/snapper-ql.log STUB_DELAY_SNAPPER=0.3 STUB_SNAP_COUNT=10
rm -f "$SNAPPER_LOG"; s=$(now_ms); "$R/quickload" --list >/dev/null 2>&1; e=$(now_ms)
printf -- '--list (2 serial snapper calls @0.3s): %d ms, snapper_calls=%s\n' "$(( (e - s) / 1000000 ))" "$(grep -c CALL "$SNAPPER_LOG" 2>/dev/null || echo 0)"
rm -f "$SNAPPER_LOG"; s=$(now_ms); "$R/quickload" --list-all >/dev/null 2>&1; e=$(now_ms)
printf -- '--list-all (3 serial snapper calls @0.3s): %d ms, snapper_calls=%s\n' "$(( (e - s) / 1000000 ))" "$(grep -c CALL "$SNAPPER_LOG" 2>/dev/null || echo 0)"
export STUB_DELAY_SNAPPER=0
printf -- '--list-all zero-latency snapper, 300 snaps/config: %s\n' "$(run_ms 3 env STUB_SNAP_COUNT=200 "$R/quickload" --list-all)"

hdr "7. storage-health"
unset PATH; export PATH=$BASE_PATH
printf 'REAL (this machine, read-only): %s\n' "$(run_ms 3 "$R/storage-health")"
export SMART_LOG=$L/smart.log STUB_DELAY_SMARTCTL=0 STUB_DELAY_BTRFS=0
rm -f "$SMART_LOG"
strace -f -e trace=execve -o "$L/sh-execve.txt" "$R/storage-health" >/dev/null 2>&1
printf 'STUBBED 3 disks + 3 btrfs mounts: %s\n' "$(run_ms 3 env STUB_DELAY_SMARTCTL=0 "$R/storage-health")"
printf 'successful execve (stubbed): %s\n' "$(grep 'execve(' "$L/sh-execve.txt" | grep -vc ENOENT)"
grep 'execve(' "$L/sh-execve.txt" | grep -v ENOENT | sed -E 's/.*execve\("([^"]+)".*/\1/' | sort | uniq -c | sort -rn | sed 's/^/    /'

hdr "8. micro-benchmarks (in-process loop, EPOCHREALTIME)"
bash "$P/bench2.sh" 2>/dev/null
