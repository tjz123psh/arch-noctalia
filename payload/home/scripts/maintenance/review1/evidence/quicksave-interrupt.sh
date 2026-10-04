#!/usr/bin/env bash
# quicksave 中断回滚验证（沙箱；snapper 桩在第二个配置处给父进程发 SIGINT 后立即退出，
# 模拟 Ctrl+C 同时打断子进程与父进程的情形）
set -uo pipefail
SRC=/home/pang/scripts/maintenance
SB=$(mktemp -d /tmp/qs-sbx.XXXXXX)
mkdir -p "$SB/lib" "$SB/bin"
cp "$SRC/quicksave" "$SB/"; cp "$SRC/lib/ui.sh" "$SRC/lib/config.sh" "$SB/lib/"
cat > "$SB/bin/snapper" <<'STUB'
#!/usr/bin/env bash
log() { printf '%s\n' "$*" >> "$QS_LOG"; }
case " $* " in
  *' list-configs '*) printf 'config\037subvolume\nroot\037/\nhome\037/home\n' ;;
  *' create '*)
     if [[ " $* " == *' -c home '* ]]; then
       log "CREATE home (触发中断)"
       kill -INT "$PPID" 2>/dev/null
       exit 130
     fi
     log "CREATE root"; echo 10; exit 0 ;;
  *' delete '*) log "DELETE $*" ;;
  *' get '*) exit 1 ;;
  *' cleanup '*) exit 0 ;;
  *' get-config '*) exit 0 ;;
esac
exit 0
STUB
chmod +x "$SB/bin/snapper"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SB/bin/notify-send"; chmod +x "$SB/bin/notify-send"
: > "$SB/log"
rc=0
QS_LOG="$SB/log" HOME="$SB" PATH="$SB/bin:$PATH" MAINTENANCE_LOCK_FILE="$SB/lock" \
  MAINTENANCE_NO_NOTIFY=1 timeout 20 "$SB/quicksave" >"$SB/out" 2>&1 || rc=$?
echo "exit=$rc (预期 130)"
echo "--- snapper 调用 ---"; cat "$SB/log"
echo "--- 输出（回删相关）---"; grep -a "回删\|中断" "$SB/out" | head -3
ok=1
grep -q "CREATE root" "$SB/log" || { echo "FAIL: 未创建 root 快照"; ok=0; }
grep -q "DELETE .*10" "$SB/log" || { echo "FAIL: 未回滚已创建的 root 快照"; ok=0; }
[[ "$rc" -eq 130 ]] || { echo "FAIL: 退出码不是 130（实际 $rc）"; ok=0; }
[[ "$ok" -eq 1 ]] && echo "RESULT: ALL-PASS" || echo "RESULT: HAS-FAILURE"
rm -rf "$SB"
exit $(( 1 - ok ))
