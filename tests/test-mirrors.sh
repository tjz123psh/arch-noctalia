#!/usr/bin/env bash
# test-mirrors.sh — lib/mirrors.sh 的离线回归：
#   解析 [archlinuxcn] 段 → 并行实探（mock curl）→ 降级排序（快→慢→不通沉底）
#   → 就地改写（仅动 Server 行；SigLevel 与其它段原样保留；行数不变）。
# 注：本文件刻意的字面 "…$arch"（pacman 镜像 URL 原样）会触发 SC2016，属预期。
# shellcheck disable=SC2016
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# shellcheck source=lib/mirrors.sh
# shellcheck disable=SC1091  # 相对 source；lib 在各检查中以独立目标校验
source "$ROOT/lib/mirrors.sh"

# ---- mock curl：按 URL 关键词给假吞吐（B/s）；dead 直接失败 ----
mock="$work/bin"
mkdir -p "$mock"
cat > "$mock/curl" <<'CURL'
#!/usr/bin/env bash
url="${*: -1}"
case "$url" in
  *fast*) echo 20000000 ;;
  *mid*)  echo 8000000 ;;
  *slow*) echo 1000000 ;;
  *)      exit 1 ;;
esac
CURL
chmod +x "$mock/curl"
export PATH="$mock:$PATH"

conf="$work/pacman.conf"
cat > "$conf" <<'CONF'
# test pacman.conf
[options]
Color

[archlinuxcn]
SigLevel = Optional TrustAll
Server = https://dead.example/archlinuxcn/$arch
Server = https://slow.example/archlinuxcn/$arch
Server = https://fast.example/archlinuxcn/$arch
Server = https://mid.example/archlinuxcn/$arch

[extra]
Include = /etc/pacman.d/mirrorlist
CONF

# 1) 解析
mapfile -t got < <(cn_servers_in_conf "$conf")
[ "${#got[@]}" -eq 4 ] || { echo "servers parse: want 4, got ${#got[@]}"; exit 1; }
[[ "${got[0]}" == 'https://dead.example/archlinuxcn/$arch' ]] || { echo "first parse wrong: ${got[0]}"; exit 1; }

# 2) 实探 + 排序：fast < mid < slow < dead
mapfile -t ordered < <(printf '%s\n' "${got[@]}" | cn_probe_servers | cn_order_servers)
want=(
  'https://fast.example/archlinuxcn/$arch'
  'https://mid.example/archlinuxcn/$arch'
  'https://slow.example/archlinuxcn/$arch'
  'https://dead.example/archlinuxcn/$arch'
)
for i in 0 1 2 3; do
  [[ "${ordered[$i]}" == "${want[$i]}" ]] || { echo "order[$i]: want ${want[$i]}, got ${ordered[$i]}"; exit 1; }
done

# 3) 就地改写：SigLevel 保留、其它段原样、Server 按新序、行数不变
printf '%s\n' "${ordered[@]}" | cn_rewrite_conf "$conf" > "$work/out.conf"
grep -q 'SigLevel = Optional TrustAll' "$work/out.conf" || { echo "SigLevel lost"; exit 1; }
grep -q '^\[extra\]$' "$work/out.conf" || { echo "[extra] section lost"; exit 1; }
grep -q 'Include = /etc/pacman.d/mirrorlist' "$work/out.conf" || { echo "[extra] Include lost"; exit 1; }
mapfile -t after < <(cn_servers_in_conf "$work/out.conf")
for i in 0 1 2 3; do
  [[ "${after[$i]}" == "${ordered[$i]}" ]] || { echo "rewrite order[$i] wrong: ${after[$i]}"; exit 1; }
done
[[ "${after[3]}" == *dead* ]] || { echo "dead not last after rewrite"; exit 1; }
[ "$(wc -l < "$conf")" -eq "$(wc -l < "$work/out.conf")" ] || { echo "line count changed"; exit 1; }

echo "ok: mirrors parse/probe/order/rewrite all good"
