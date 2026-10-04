#!/usr/bin/env bash
. /home/pang/scripts/maintenance/lib/ui.sh
b() { local label="$1" n="$2" body="$3"; local s e
  s=$EPOCHREALTIME
  for ((i=0;i<n;i++)); do eval "$body"; done
  e=$EPOCHREALTIME
  printf '%-46s %8.3f ms/iter (n=%d)\n' "$label" "$(awk -v a="$s" -v b="$e" -v n="$n" 'BEGIN{printf "%.3f",(b-a)*1000/n}')" "$n"
}
b 'plain function ui_pad abc 8 (no subshell)' 3000 'ui_pad abc 8 >/dev/null'
b 'subshell $(ui_pad abc 8)'                  3000 'x=$(ui_pad abc 8)'
b 'subshell $(ui_dwidth abc)'                 3000 'x=$(ui_dwidth abc)'
b '_snap_row-equiv: 1+5 subshells'            1000 'r=$(printf "%*s%s %s %s %s %s" 3 "" "$(ui_pad 1 6)" "$(ui_pad d 18)" "$(ui_pad u 8)" "$(ui_pad c 10)" "$(ui_pad x 20)")'
