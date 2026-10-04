#!/usr/bin/env bash
# Replicates term-menu show_snapshots row rendering (lines 890-959) to quantify the
# per-row cost of the current command-substitution style vs a fork-free variant.
# Nothing in the repo is modified or executed here beyond sourcing lib/ui.sh.
set -u
R=/home/pang/scripts/maintenance
. "$R/lib/ui.sh"
N=${1:-500}
W_ID=6 W_TIME=18 W_USER=8 W_CLEAN=10 W_IND=3
DESC_SHORT='quicksave-123'
DESC_LONG='自动快照：系统更新前的完整备份（含大量中文描述用于测试截断行为）'

ms() { awk -v a="$1" -v b="$2" -v n="$N" 'BEGIN{printf "%.2f", (b-a)*1000/n}'; }

short_text() { local t="$1" max="$2" out='' i ch w=0
  for ((i = 0; i < ${#t}; i++)); do ch="${t:i:1}"; w=$((w + $(ui_dwidth "$ch"))); [ "$w" -gt $((max - 1)) ] && break; out+="$ch"; done
  printf '%s…' "$out"; }

compact_text() { # as in term-menu:890
  local text="$1" max="$2"
  if [ "$(ui_dwidth "$text")" -le "$max" ]; then printf '%s' "$text"; return; fi
  short_text "$text" "$max"
}

_snap_row() { # as in term-menu:909
  printf "%*s%s %s %s %s %s\n" "$W_IND" "" "$(ui_pad "$1" "$W_ID")" "$(ui_pad "$2" "$W_TIME")" \
    "$(ui_pad "$3" "$W_USER")" "$(ui_pad "$4" "$W_CLEAN")" "$5"
}

row_current() { # exactly the per-row work of print_snapshot_list
  local desc="$1" desc_display entries=''
  local idcell="${UI_C_SKY}#12${UI_RESET}" date_display='2026-08-01 10:00'
  desc_display="$(compact_text "$desc" 48)"
  entries+="$(_snap_row "$idcell" "$date_display" "${UI_C_SUBTLE}root${UI_RESET}" \
    "${UI_C_SUBTLE}time${UI_RESET}" "${UI_C_TEXT}${desc_display}${UI_RESET}")"
  printf '%s' "$entries" >/dev/null
}

row_fixed() { # fork-free: compute width in-process, build string with printf -v
  local desc="$1" desc_display entries=''
  local idcell="#12" date_display='2026-08-01 10:00'
  _ui_dwidth_calc "$desc"
  if ((UI_DWIDTH_RESULT > 48)); then desc_display="${desc:0:44}…"; else desc_display="$desc"; fi
  printf -v entries '%*s%-*s %-*s %-*s %-*s %s\n' \
    "$W_IND" '' "$W_ID" "$idcell" "$W_TIME" "$date_display" "$W_USER" 'root' "$W_CLEAN" 'time' "$desc_display"
  printf '%s' "$entries" >/dev/null
}

bench() { local label="$1" fn="$2" desc="$3" i s e
  s=$EPOCHREALTIME; for ((i=0;i<N;i++)); do "$fn" "$desc"; done; e=$EPOCHREALTIME
  printf '%-42s %s ms/row (n=%d)\n' "$label" "$(ms "$s" "$e")" "$N"; }

bench 'current impl, short desc'      row_current "$DESC_SHORT"
bench 'current impl, LONG desc'       row_current "$DESC_LONG"
bench 'fork-free impl, short desc'    row_fixed   "$DESC_SHORT"
bench 'fork-free impl, LONG desc'     row_fixed   "$DESC_LONG"
