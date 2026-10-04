#!/usr/bin/env bash
set -uo pipefail
cd /home/pang/scripts/maintenance
git show HEAD:lib/ui.sh > /tmp/ui-old.sh
measure() { # $1=ui.sh 路径
  local lib="$1"
  for L in C POSIX en_US.UTF-8; do
    local w
    w=$(LC_ALL=$L bash -c '. "$1"; line="$(ui_panel_open "更新镜像源" "i" 2>/dev/null)"; ui_dwidth "$line"' _ "$lib")
    printf "    LC_ALL=%-12s 顶边框显示宽度=%s\n" "$L" "$w"
  done
}
echo "=== 旧版（git HEAD）==="; measure /tmp/ui-old.sh
echo "=== 新版（已修）==="; measure lib/ui.sh
echo "=== 底边框对照（ui_panel_close，不受标题影响）==="
for L in C en_US.UTF-8; do
  w=$(LC_ALL=$L bash -c '. ./lib/ui.sh; line="$(ui_panel_close 2>/dev/null)"; ui_dwidth "$line"')
  printf "    LC_ALL=%-12s 底边框显示宽度=%s\n" "$L" "$w"
done
