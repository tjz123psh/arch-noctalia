#!/usr/bin/env bash
# 干净沙箱验证 clean 的深度快照清理逻辑（不改系统状态）
set -uo pipefail
SB=/tmp/clean-sandbox
SRC=/home/pang/scripts/maintenance
MODE="${1:-ok}"
rm -rf "$SB/src" "$SB/bin" "$SB/home" "$SB/log" "$SB/out"
mkdir -p "$SB/src/lib" "$SB/bin" "$SB/home"
cp "$SRC/clean" "$SB/src/clean"
cp "$SRC/lib/ui.sh" "$SRC/lib/config.sh" "$SB/src/lib/"
chmod +x "$SB/src/clean"

cat > "$SB/bin/snapper" <<'STUB'
#!/usr/bin/env bash
log() { printf "%s\n" "$*" >> "$CLEAN_TEST_LOG"; }
case " $* " in
  *' list-configs '*) printf 'config\037subvolume\nroot\037/\nhome\037/home\n' ;;
  *' list --columns number,userdata '*)
    case "${SNAP_MODE:-ok}" in
      fail) exit 1 ;;
      partial) case " $* " in *' -c root '*) printf 'number\037userdata\n9\037maintenance_batch=20260101T000000.0-1\n11\037maintenance_batch=20260901T000000.0-2\n' ;; *) printf 'number\037userdata\n9\037maintenance_batch=20260101T000000.0-1\n' ;; esac ;;
      allpartial) case " $* " in *' -c root '*) printf 'number\037userdata\n11\037maintenance_batch=20260901T000000.0-2\n' ;; *) printf 'number\037userdata\n12\037maintenance_batch=20260902T000000.0-3\n' ;; esac ;;
      *) printf 'number\037userdata\n9\037maintenance_batch=20260101T000000.0-1\n11\037maintenance_batch=20260901T000000.0-2\n' ;;
    esac ;;
  *' list --columns number,description,userdata '*)
    case "${SNAP_MODE:-ok}" in
      fail) exit 1 ;;
      partial) case " $* " in *' -c root '*) printf 'number\037description\037userdata\n0\037current\037\n9\037quicksave\037maintenance_batch=20260101T000000.0-1\n11\037quicksave-sysup\037maintenance_batch=20260901T000000.0-2\n' ;; *) printf 'number\037description\037userdata\n0\037current\037\n9\037quicksave\037maintenance_batch=20260101T000000.0-1\n' ;; esac ;;
      allpartial) case " $* " in *' -c root '*) printf 'number\037description\037userdata\n0\037current\037\n11\037quicksave-sysup\037maintenance_batch=20260901T000000.0-2\n' ;; *) printf 'number\037description\037userdata\n0\037current\037\n12\037quicksave-sysup\037maintenance_batch=20260902T000000.0-3\n' ;; esac ;;
      *) printf 'number\037description\037userdata\n0\037current\037\n9\037quicksave\037maintenance_batch=20260101T000000.0-1\n11\037quicksave-sysup\037maintenance_batch=20260901T000000.0-2\n' ;;
    esac ;;
  *' delete '*) log "DELETE $*" ;;
  *' cleanup '*) exit 0 ;;
esac
STUB
cat > "$SB/bin/sudo" <<'STUB'
#!/usr/bin/env bash
[[ "${1:-}" == "-v" ]] && exit 0
[[ "${1:-}" == "-n" ]] && shift
case "${1:-}" in mount|umount) exit 0 ;; esac
exec "$@"
STUB
cat > "$SB/bin/pacman" <<'STUB'
#!/usr/bin/env bash
case " $* " in
  *' -Qtdq '*) exit 1 ;;
  *' -Sc '*|*' -Scc '*) exit 1 ;;
  *) exit 0 ;;
esac
STUB
cp "$SB/bin/pacman" "$SB/bin/paru"; cp "$SB/bin/pacman" "$SB/bin/yay"
cat > "$SB/bin/findmnt" <<'STUB'
#!/usr/bin/env bash
if [[ " $* " == *" -rn -t btrfs -o SOURCE "* ]]; then printf "/dev/test[/@]\n/dev/test[/@home]\n"; else printf "btrfs\n"; fi
STUB
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$SB/bin/flatpak"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$SB/bin/btrfs"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$SB/bin/journalctl"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$SB/bin/systemctl"
chmod +x "$SB/bin"/*
export CLEAN_TEST_LOG="$SB/log" SNAP_MODE="$MODE"
status=0
HOME="$SB/home" PATH="$SB/bin:$PATH" MAINTENANCE_LOCK_FILE="$SB/lock" MAINTENANCE_NO_NOTIFY=1 \
  timeout 30 "$SB/src/clean" all --yes > "$SB/out" 2>&1 || status=$?
echo "MODE=$MODE exit=$status"
echo "--- 关键输出 ---"
grep -E "保留|回滚|删除|跳过|失败" "$SB/out" | head -12
echo "--- snapper delete 调用 ---"
cat "$SB/log" 2>/dev/null || echo "(无)"
echo "--- 断言 ---"
fail=0
assert_has() { if grep -qF -- "$2" "$1"; then echo "  PASS: $3"; else echo "  FAIL: $3"; fail=1; fi; }
assert_not() { if grep -qF -- "$2" "$1"; then echo "  FAIL(不应出现): $3"; fail=1; else echo "  PASS: $3"; fi; }
case "$MODE" in
  ok)
    assert_has "$SB/out" "将保留最近一套回滚快照（批次 20260901T000000.0-2）" "成套批次取最新（B2）"
    assert_has "$SB/log" "delete 9" "删除旧批次 B1 的 ID 9"
    assert_not "$SB/log" "delete 11" "不删最近回滚点 ID 11" ;;
  partial)
    assert_has "$SB/out" "将保留最近一套回滚快照（批次 20260101T000000.0-1）" "半套 B2 不算数，改保留成套的 B1"
    assert_has "$SB/log" "delete 11" "半套批次 ID 11 被删除"
    assert_not "$SB/log" "delete 9" "成套回滚点 ID 9 保留" ;;
  allpartial)
    assert_has "$SB/out" "没有找到每个配置都具备的成套回滚批次" "无成套批次时告警"
    assert_not "$SB/log" "DELETE" "无成套批次时不删除任何维护批次快照" ;;
  fail)
    assert_has "$SB/out" "回滚批次扫描失败" "扫描失败明确告警"
    assert_not "$SB/log" "DELETE" "扫描失败时一个快照都不删（修复前会全删）" ;;
esac
echo "RESULT: $([[ $fail -eq 0 ]] && echo ALL-PASS || echo HAS-FAILURE)"
exit $fail