#!/usr/bin/env bash
# test-08-link-backup.sh — 08 步 ~/bin 链接层的数据安全（沙箱，零系统副作用）：
#   1) 既有**真实文件**被软链替换前，内容进 overwritten/<时间戳>/ 并写 MANIFEST.tsv；
#   2) 既有**软链**（含指向不存在路径的）被替换前，把它原本指向哪记进 <名字>.symlink；
#   3) 第二遍幂等（unchanged）。
# 背景：2026-10-31 审计指出 08 以前只备份真实文件、且从不写 MANIFEST，旧软链被 ln -sfn
# 静默替换后无从追溯。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
case "$sandbox" in /tmp/*|/var/tmp/*) ;; *) echo "[FAIL] sandbox is not under /tmp: $sandbox"; exit 1;; esac

repo="$sandbox/repo"
home="$sandbox/home"
mkdir -p "$repo/manifests" "$repo/steps" "$home/scripts/desktop" "$home/bin"
ln -sfn "$ROOT/lib" "$repo/lib"
cp "$ROOT/steps/08-scripts.sh" "$repo/steps/"

printf '#!/bin/sh\necho one\n' > "$home/scripts/desktop/fake-one"
printf '#!/bin/sh\necho two\n' > "$home/scripts/desktop/fake-two"
chmod +x "$home/scripts/desktop/fake-one" "$home/scripts/desktop/fake-two"
printf 'fake-one\tscripts/desktop/fake-one\nfake-two\tscripts/desktop/fake-two\n' > "$repo/manifests/bin-links.tsv"

# 预置：fake-one 位置是个指向别处的软链；fake-two 位置是用户自己写的真实脚本。
ln -s /old/place/fake-one "$home/bin/fake-one"
printf '#!/bin/sh\necho USER SCRIPT\n' > "$home/bin/fake-two"
chmod 755 "$home/bin/fake-two"

run08() {
  env HOME="$home" AN_RUN=1 AN_ROOT_DIR="$repo" bash "$repo/steps/08-scripts.sh"
}

if ! out1="$(run08 2>&1)"; then
  printf '%s\n' "$out1"
  echo "[FAIL] first run exited non-zero"
  exit 1
fi
printf '%s\n' "$out1"

[[ -L "$home/bin/fake-one" && "$(readlink "$home/bin/fake-one")" == "$home/scripts/desktop/fake-one" ]] ||
  { echo "[FAIL] fake-one was not relinked to the payload target"; exit 1; }
[[ -L "$home/bin/fake-two" && "$(readlink "$home/bin/fake-two")" == "$home/scripts/desktop/fake-two" ]] ||
  { echo "[FAIL] fake-two was not relinked to the payload target"; exit 1; }

state="$home/.local/state/arch-noctalia/overwritten"
link_rec="$(find "$state" -name 'fake-one.symlink' 2>/dev/null | head -1)"
if [[ -z "$link_rec" || "$(cat "$link_rec")" != "/old/place/fake-one" ]]; then
  echo "[FAIL] replaced symlink left no record of where it pointed"
  exit 1
fi
file_bk="$(find "$state" -name 'fake-two' 2>/dev/null | head -1)"
if [[ -z "$file_bk" ]] || ! grep -q 'USER SCRIPT' "$file_bk"; then
  echo "[FAIL] replaced real file was not backed up"
  exit 1
fi
manifest_tsv="$(find "$state" -name MANIFEST.tsv 2>/dev/null | head -1)"
if [[ -z "$manifest_tsv" ]]; then
  echo "[FAIL] 08 did not write MANIFEST.tsv"
  exit 1
fi
grep -qF "$home/bin/fake-one" "$manifest_tsv" || { echo "[FAIL] MANIFEST.tsv misses fake-one"; exit 1; }
grep -qF "$home/bin/fake-two" "$manifest_tsv" || { echo "[FAIL] MANIFEST.tsv misses fake-two"; exit 1; }

# 幂等
if ! out2="$(run08 2>&1)"; then
  printf '%s\n' "$out2"
  echo "[FAIL] second run exited non-zero"
  exit 1
fi
grep -qF 'links: 2 checked, 0 linked, 2 unchanged, 0 replaced, 0 failed' <<<"$out2" ||
  { echo "[FAIL] second run is not idempotent: $(grep 'links:' <<<"$out2" | tail -1)"; exit 1; }

echo "ok: 08 records replaced symlinks and real files (MANIFEST.tsv), re-run idempotent"
