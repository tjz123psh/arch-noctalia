#!/usr/bin/env bash
# lib/ui.sh 修复后的功能自测（只读，全部在 /tmp）
set -uo pipefail
cd /home/pang/scripts/maintenance
fail=0
chk() { if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; else echo "  FAIL: $1 (期望 [$3] 实际 [$2])"; fail=1; fi; }

echo "=== 1) 消息含裸 % 不再截断/中止 ==="
out="$(set -euo pipefail; . ./lib/ui.sh; ui_info "进度 100% 完成"; ui_ok "已处理 %s 项" 3; echo REACHED_END)"
chk "脚本继续执行" "$([[ "$out" == *REACHED_END* ]] && echo yes || echo no)" "yes"
chk "百分号原样输出" "$([[ "$out" == *"进度 100% 完成"* ]] && echo yes || echo no)" "yes"
chk "合法格式仍生效" "$([[ "$out" == *"已处理 3 项"* ]] && echo yes || echo no)" "yes"

echo "=== 2) 宽度计算与 locale 无关 ==="
u="$(. ./lib/ui.sh; ui_dwidth "中文abc")"
c="$(LC_ALL=C; . ./lib/ui.sh; ui_dwidth "中文abc")"
p="$(LC_ALL=POSIX bash -c '. ./lib/ui.sh; ui_dwidth "中文abc"')"
chk "UTF-8 = 7" "$u" "7"
chk "LC_ALL=C = 7（修复前 9）" "$c" "7"
chk "POSIX = 7" "$p" "7"

echo "=== 3) C locale 与 UTF-8 的卡片顶边框宽度 ==="
for L in C en_US.UTF-8; do
  dashes=$(LC_ALL=$L bash -c '. ./lib/ui.sh; ui_panel_open "更新镜像源" "i" 2>/dev/null | tr -cd "─" | wc -m')
  echo "  LC_ALL=$L 顶边框破折号=$dashes"
done

echo "=== 4) ui_confirm：EOF 不再自动同意 ==="
rc=0; ( . ./lib/ui.sh; ui_confirm "危险操作" y </dev/null ) >/dev/null 2>&1 || rc=$?
chk "EOF + 默认 y -> 拒绝(1)" "$rc" "1"
rc=0; ( . ./lib/ui.sh; printf "y\n" | ui_confirm "继续" n ) >/dev/null 2>&1 || rc=$?
chk "输入 y -> 同意(0)" "$rc" "0"
rc=0; ( . ./lib/ui.sh; printf "n\n" | ui_confirm "继续" y ) >/dev/null 2>&1 || rc=$?
chk "输入 n -> 拒绝(1)" "$rc" "1"
rc=0; ( . ./lib/ui.sh; printf "\n" | ui_confirm "回车取默认" y ) >/dev/null 2>&1 || rc=$?
chk "回车 + 默认 y -> 同意(0)" "$rc" "0"

echo "=== 5) err 与 miss 分开统计 ==="
res="$(. ./lib/ui.sh; ui_tally_reset; ui_panel_stat err "无法检查磁盘" >/dev/null; ui_panel_stat miss "缺少 smartctl" >/dev/null; printf "OK=%s MISS=%s ERR=%s" "$UI_N_OK" "$UI_N_MISS" "$UI_N_ERR")"
chk "err 不再计入 miss" "$res" "OK=0 MISS=1 ERR=1"
rc=0; ( . ./lib/ui.sh; ui_tally_reset; ui_panel_stat err "查询失败" >/dev/null; ui_tally_status 1 ) >/dev/null 2>&1 || rc=$?
chk "strict 模式下查询失败 -> 1" "$rc" "1"
rc=0; ( . ./lib/ui.sh; ui_tally_reset; ui_panel_stat err "查询失败" >/dev/null; ui_tally_status 0 ) >/dev/null 2>&1 || rc=$?
chk "非 strict 仍为 0" "$rc" "0"

echo "=== 6) tput 只调用一次（进程内缓存）==="
stub=$(mktemp -d)
printf '#!/usr/bin/env bash\nprintf "call\\n" >> "$TPL_LOG"\nprintf "120\\n"\n' > "$stub/tput"
chmod +x "$stub/tput"
TPL_LOG="$stub/log"; : > "$TPL_LOG"
PATH="$stub:$PATH" TPL_LOG="$TPL_LOG" bash -c '. ./lib/ui.sh; for i in 1 2 3 4 5; do ui_panel_open "卡片 $i" >/dev/null; done' >/dev/null 2>&1
chk "5 次卡片渲染只 fork 1 次 tput" "$(wc -l < "$TPL_LOG")" "1"
rm -rf "$stub"

echo "=== 7) 锁：显式路径可加锁 ==="
lockdir="$(mktemp -d)"
out="$(MAINTENANCE_LOCK_FILE="$lockdir/l.lock" bash -c '. ./lib/ui.sh; ui_maintenance_lock_acquire 测试; echo "first_rc=$?"; ui_maintenance_lock_release')"
chk "显式覆盖路径加锁成功" "$([[ "$out" == *first_rc=0* ]] && echo yes || echo no)" "yes"
rm -rf "$lockdir"

echo "RESULT: $([[ $fail -eq 0 ]] && echo ALL-PASS || echo HAS-FAILURE)"
exit $fail
