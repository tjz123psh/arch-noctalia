#!/usr/bin/env bash
# checkallupdates 刷新完整性沙箱验证（不触碰真实缓存）
set -uo pipefail
SB=/tmp/cau-sandbox
SRC=/home/pang/scripts/maintenance
rm -rf "$SB"; mkdir -p "$SB/src/lib" "$SB/bin" "$SB/home/.cache/checkallupdates"
cp "$SRC/checkallupdates" "$SB/src/checkallupdates"
cp "$SRC/lib/ui.sh" "$SRC/lib/config.sh" "$SB/src/lib/"
chmod +x "$SB/src/checkallupdates"
CACHE="$SB/home/.cache/checkallupdates"
printf "linux 6.10.1-1 -> 6.10.2-1\n" > "$CACHE/updates-repo.txt"
printf "aurpkg 1 -> 2\n" > "$CACHE/updates-aur.txt"
printf "" > "$CACHE/updates-flatpak.txt"
printf "pacman\tok\t\naur\tok\t\nflatpak\tok\t\n" > "$CACHE/source-status.tsv"
touch "$CACHE/last-refresh" "$CACHE/last-refresh-pacman" "$CACHE/last-refresh-aur" "$CACHE/last-refresh-flatpak"
BASE_SHA="$(sha256sum "$CACHE/updates-repo.txt" | cut -d" " -f1)"

cat > "$SB/bin/checkupdates" <<'STUB'
#!/usr/bin/env bash
printf "network down\n" >&2; exit 1
STUB
cat > "$SB/bin/fakeroot" <<'STUB'
#!/usr/bin/env bash
exec "$@"
STUB
cat > "$SB/bin/paru" <<'STUB'
#!/usr/bin/env bash
printf "aur api error\n" >&2; exit 1
STUB
cat > "$SB/bin/flatpak" <<'STUB'
#!/usr/bin/env bash
printf "flatpak remote error\n" >&2; exit 1
STUB
chmod +x "$SB/bin"/*
run() { HOME="$SB/home" XDG_CACHE_HOME="$SB/home/.cache" PATH="$SB/bin:$PATH" \
  CHECKALLUPDATES_QUERY_TIMEOUT=5 CHECKALLUPDATES_LOCK_WAIT="${LOCK_WAIT:-5}" MAINTENANCE_NO_NOTIFY=1 \
  timeout 30 "$SB/src/checkallupdates" "$@" 2>&1; }
fail=0
chk() { if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; else echo "  FAIL: $1 (期望 $3，实际 $2)"; fail=1; fi; }

echo "=== A) 三来源全失败：不得覆盖上次成功列表，必须非 0 退出 ==="
out="$(run --refresh)"; rc=$?
after="$(sha256sum "$CACHE/updates-repo.txt" | cut -d" " -f1)"
chk "退出码非 0" "$([[ $rc -ne 0 ]] && echo yes || echo no)" "yes"
chk "旧列表未被空文件覆盖" "$([[ "$after" == "$BASE_SHA" ]] && echo yes || echo no)" "yes"
chk "仍显示缓存里的待更新项" "$([[ "$out" == *linux* ]] && echo yes || echo no)" "yes"
chk "显示查询失败" "$([[ "$out" == *查询失败* ]] && echo yes || echo no)" "yes"
chk "失败不刷新总时间戳" "$([[ -f "$CACHE/last-refresh" ]] && echo yes || echo no)" "no"
echo "--- 输出 ---"; printf "%s\n" "$out" | head -6

echo "=== B) 缓存目录不可写：必须非 0 退出且不动缓存 ==="
chmod 500 "$CACHE"
out="$(run --refresh)"; rc=$?
chmod 700 "$CACHE"
after="$(sha256sum "$CACHE/updates-repo.txt" | cut -d" " -f1)"
chk "退出码非 0" "$([[ $rc -ne 0 ]] && echo yes || echo no)" "yes"
chk "提示无法创建临时文件" "$([[ "$out" == *无法在*创建刷新临时文件* ]] && echo yes || echo no)" "yes"
chk "已有缓存保持原样" "$([[ "$after" == "$BASE_SHA" ]] && echo yes || echo no)" "yes"

echo "=== C) 已有刷新持锁：等待超时后取消，不得并发刷新 ==="
( flock -x 9; sleep 8 ) 9>"$CACHE/refresh.lock" &
locker=$!; sleep 0.3
LOCK_WAIT=1 out="$(run --refresh)"; rc=$?
kill "$locker" 2>/dev/null || true; wait "$locker" 2>/dev/null || true
chk "退出码非 0" "$([[ $rc -ne 0 ]] && echo yes || echo no)" "yes"
chk "提示另一刷新仍在进行" "$([[ "$out" == *另一个刷新仍在进行* ]] && echo yes || echo no)" "yes"
echo "--- 输出 ---"; printf "%s\n" "$out" | head -3
echo "RESULT: $([[ $fail -eq 0 ]] && echo ALL-PASS || echo HAS-FAILURE)"
exit $fail