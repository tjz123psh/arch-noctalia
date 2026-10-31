#!/usr/bin/env bash
# test-12-verify-sandbox.sh — 12-verify 的 runtime 分支此前没有回归测试。这里在沙箱里直跑
# steps/12-verify.sh，锁四件事：
#   1) 正常的 runtime 文件 + supergfxd(hotplug_type=Asus) → 全绿，且 runtime 计数为 2；
#   2) runtime 目标被换成目录 → FAIL（"存在"不等于"对"）；
#   3) /etc/supergfxd.conf 的 hotplug_type 被改掉 → FAIL（这是安装器保证值，不是机器派生）；
#   4) runtime 目标缺失 → FAIL（原有的 missing 口径不变）。
# 所有写入都在 mktemp 沙箱内（AN_TARGET_ROOT / HOME / AN_STATE_DIR），不碰真实系统。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"; root="$tmp/root"; home="$root/home/pang"; stub="$tmp/stub"; state="$tmp/state"
mkdir -p "$repo/lib" "$repo/manifests" "$stub" "$state" \
  "$home/Desktop" "$home/Documents" "$home/Downloads" "$home/Music" "$home/Videos" \
  "$home/Public" "$home/Projects" "$home/Templates" "$home/Pictures/Screenshots" "$home/bin" \
  "$root/etc"
cp "$ROOT/lib/common.sh" "$repo/lib/common.sh"

normal="$home/an-test-normal.conf"
runtime="$home/an-test-runtime.conf"
sgfx="$root/etc/supergfxd.conf"

# --- stubs：12 只做只读查询，这里全部给固定回答 ---
cat > "$stub/pacman" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$stub/systemctl" <<'SH'
#!/usr/bin/env bash
# docker/bluetooth 是 12 的必备服务；其余单元（snapper/asusd/supergfxd）一律视为不存在。
case "$1" in
  cat) case "$2" in docker.service|bluetooth.service) exit 0 ;; *) exit 1 ;; esac ;;
  is-enabled|is-active) exit 0 ;;
  show) echo "OnCalendar=Mon *-*-* 00:00:00" ;;
  *) exit 0 ;;
esac
SH
cat > "$stub/findmnt" <<'SH'
#!/usr/bin/env bash
echo ext4
SH
cat > "$stub/getent" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "passwd" ]]; then echo "$2:x:1000:1000::/home/$2:/usr/bin/fish"; exit 0; fi
exec /usr/bin/getent "$@"
SH
cat > "$stub/getfacl" <<'SH'
#!/usr/bin/env bash
echo "user:$(id -un):rw-"
SH
chmod +x "$stub"/*
: > "$home/bin/cursor-track"; chmod +x "$home/bin/cursor-track"

# --- 最小清单 ---
normal_md5="$(printf 'NORMAL\n' | md5sum | awk '{print $1}')"
printf '# schema=1\npayload/test/normal.conf\t/home/pang/an-test-normal.conf\t644\t%s\n' "$normal_md5" > "$repo/manifests/files.tsv"
printf 'payload/test/runtime.conf\t/home/pang/an-test-runtime.conf\t644\tdeadbeef\n' >> "$repo/manifests/files.tsv"
printf 'payload/system/etc/supergfxd.conf\t/etc/supergfxd.conf\t644\tdeadbeef\n' >> "$repo/manifests/files.tsv"
printf '# schema=1\npayload/test/runtime.conf\ttest runtime file\npayload/system/etc/supergfxd.conf\ttest supergfxd\n' > "$repo/manifests/runtime-regenerated.tsv"
printf '# schema=1\n' > "$repo/manifests/packages.tsv"

reset_fixture() {
  rm -rf "$runtime" "$sgfx"
  printf 'NORMAL\n' > "$normal"
  printf 'RUNTIME\n' > "$runtime"
  printf '{"mode": "Hybrid", "hotplug_type": "Asus"}\n' > "$sgfx"
  chmod 644 "$normal" "$runtime" "$sgfx"
}

run12() {
  env -i PATH="$stub:/usr/bin:/bin" HOME="$home" TERM=dumb AN_RUN=1 AN_MACHINE=physical \
    AN_ROOT_DIR="$repo" AN_TARGET_ROOT="$root" AN_TARGET_ALLOW="/home/ /etc/" \
    AN_STATE_DIR="$state" bash "$ROOT/steps/12-verify.sh"
}

fails=0
bad() { echo "[FAIL] $*"; fails=$((fails + 1)); }
reset_fixture

# 1) 全绿
if ! out="$(run12 2>&1)"; then bad "healthy sandbox run exited non-zero (unexpected FAIL)"; fi
grep -q 'files: 1 checked, 1 ok, 0 mismatched, 0 missing' <<<"$out" \
  || bad "file counters wrong: $(grep '^files:' <<<"$out" | tail -1)"
grep -q 'runtime-regenerated files (themed by the desktop): existence checked, content skipped: 2' <<<"$out" \
  || bad "runtime counter does not report both runtime rows"
grep -q 'all files, packages, links and service states verified' <<<"$out" \
  || bad "healthy run did not finish with the success summary"

# 2) runtime 目标是目录：存在也不算通过
reset_fixture; rm -f "$runtime"; mkdir "$runtime"
if out="$(run12 2>&1)"; then bad "runtime target as a directory was accepted"; fi
grep -q 'not a regular file (runtime-managed): .*an-test-runtime.conf' <<<"$out" \
  || bad "missing the not-a-regular-file warning for a runtime target"

# 3) supergfxd 的 hotplug_type 漂移：12 必须报出来（沙箱目标，不读真实 /etc）
reset_fixture
printf '{"mode": "Hybrid", "hotplug_type": "None"}\n' > "$sgfx"
if out="$(run12 2>&1)"; then bad "supergfxd hotplug_type drift was not reported"; fi
grep -q 'supergfxd.conf does not carry hotplug_type=Asus' <<<"$out" \
  || bad "missing the supergfxd hotplug_type warning"

# 4) runtime 缺失：原有的 missing 口径不变
reset_fixture; rm -f "$runtime"
if out="$(run12 2>&1)"; then bad "missing runtime target was accepted"; fi
grep -q 'missing (runtime-managed): .*an-test-runtime.conf' <<<"$out" \
  || bad "missing the missing-runtime warning"

reset_fixture
if (( fails > 0 )); then
  echo "test-12-verify-sandbox: FAIL (${fails} problem(s))"
  exit 1
fi
echo "ok: 12-verify accepts healthy runtime files and flags type/drift/missing (sandbox only)"
