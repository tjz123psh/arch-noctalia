#!/usr/bin/env bash
# test-manifests-local.sh — 清单与 payload 的本地一致性（对照 files.tsv）：
#   行数下限；每行 repo 文件存在且 md5 匹配；mode 为八进制；
#   bin-links 目标都在 payload；关键类别（niri/Noctalia/插件/脚本/字体/greeter/壁纸）齐备。
# （VM 侧逐字节复核由 tools/verify-payload.sh 负责，不在本测试内。）
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
bad() { echo "[FAIL] $*"; fail=1; }

FILES="$ROOT/manifests/files.tsv"
PKGS="$ROOT/manifests/packages.tsv"
AUR="$ROOT/manifests/aur.tsv"
LINKS="$ROOT/manifests/bin-links.tsv"

rows=$(grep -cvE '^#|^$' "$FILES")
[ "$rows" -ge 150 ] || bad "files.tsv rows too few: $rows"
prows=$(grep -cvE '^#|^$' "$PKGS")
[ "$prows" -ge 150 ] || bad "packages.tsv rows too few: $prows"
arows=$(grep -cvE '^#|^$' "$AUR")
[ "$arows" -ge 10 ] || bad "aur.tsv rows too few: $arows"

n=0
while IFS=$'\t' read -r repo _target mode md5; do
  if [[ -z "$repo" ]]; then continue; fi
  n=$((n + 1))
  f="$ROOT/$repo"
  if [[ ! -f "$f" ]]; then
    bad "missing payload file: $repo"
    continue
  fi
  m="$(md5sum "$f" | awk '{print $1}')"
  if [[ "$m" != "$md5" ]]; then bad "md5 drift: $repo"; fi
  if [[ ! "$mode" =~ ^[0-7]{3,4}$ ]]; then bad "bad mode '$mode': $repo"; fi
done < <(grep -vE '^#|^$' "$FILES")

while IFS=$'\t' read -r name target; do
  if [[ -z "$name" ]]; then continue; fi
  if [[ ! -f "$ROOT/payload/home/$target" ]]; then bad "bin link target missing: $name -> $target"; fi
done < <(grep -vE '^#|^$' "$LINKS")

grep -q '^payload/home/.config/niri/conf.d/' "$FILES" || bad "no niri conf.d mapping"
grep -q '^payload/home/.local/state/noctalia/settings.toml' "$FILES" || bad "no Noctalia settings mapping"
grep -q '^payload/home/noctalia-plugins/magnifier/' "$FILES" || bad "no magnifier plugin mapping"
grep -q '^payload/home/noctalia-plugins/sidebar/' "$FILES" || bad "no sidebar plugin mapping"
grep -q '^payload/home/scripts/desktop/' "$FILES" || bad "no scripts mapping"
grep -q '^payload/system/usr/share/fonts/maple-mono-nf-cn/' "$FILES" || bad "no maple-mono-nf-cn mapping"
grep -q '^payload/system/usr/share/fonts/google-sans-flex/' "$FILES" || bad "no google-sans-flex mapping"
grep -q '^payload/system/usr/share/fonts/resource-han-rounded/' "$FILES" || bad "no resource-han-rounded mapping"
grep -q '^payload/system/etc/nwg-hello/' "$FILES" || bad "no nwg-hello mapping"
grep -q '^payload/system/etc/greetd/config.toml' "$FILES" || bad "no greetd config mapping"
grep -q '^payload/system/var/lib/avatars/pang/.face' "$FILES" || bad "no avatar mapping"
grep -q '^payload/home/Pictures/wallpapers/' "$FILES" || bad "no wallpaper mapping"

echo "checked: files rows=$rows (iterated $n), packages=$prows, aur=$arows"
if (( fail > 0 )); then
  echo "test-manifests-local: FAIL"
  exit 1
fi
echo "ok: manifests/payload local consistency"
