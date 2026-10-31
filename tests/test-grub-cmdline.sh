#!/usr/bin/env bash
# test-grub-cmdline.sh — /etc/default/grub 的「受管内容 vs 机器派生」只允许 rootfstype 一处不同：
#   07 在非 btrfs 根上会 sed 掉 rootfstype=<fs>（不摘则生成的菜单起不来）；若 12 照常比 md5，非 btrfs
#   机器装完自检立刻红，而 --redo 12 只读、修不了（写回 btrfs 又会让菜单起不来）。这里锁三件事：
#   1) 归一后 payload（btrfs）与 07 派生后的内容相等；
#   2) 归一不看 rootfstype 的取值（ext4/xfs 换上去同样算派生态）；
#   3) 其它任何差异（例如 zswap.enabled）归一后仍然不等 —— 不把真问题放过。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
# shellcheck disable=SC1091  # 相对 source；lib 在各检查中以独立目标校验
source "$ROOT/lib/common.sh"

src="$ROOT/payload/system/etc/default/grub"
tmpd="$(mktemp -d)"
trap 'rm -rf "$tmpd"' EXIT

fail() {
  echo "[FAIL] $*"
  exit 1
}

# 前提：payload 里确实写着 rootfstype（否则下面的相等断言是空的）
grep -q 'rootfstype=btrfs' "$src" || fail "payload GRUB config no longer carries rootfstype=btrfs — this test is vacuous, revisit it"

# 1) 与 07 的真实动作对齐：steps/07-config.sh 用 sed -i 's/ *rootfstype=btrfs//'
sed 's/ *rootfstype=btrfs//' "$src" > "$tmpd/derived"
if [[ "$(grub_defaults_canonical "$src")" != "$(grub_defaults_canonical "$tmpd/derived")" ]]; then
  fail "canonical(payload) != canonical(07-derivative) — 12 would report md5 mismatch on a non-btrfs root"
fi

# 2) 取值无关：换一个文件系统名，归一后仍应相等
sed 's/rootfstype=btrfs/rootfstype=ext4/' "$src" > "$tmpd/ext4"
if [[ "$(grub_defaults_canonical "$src")" != "$(grub_defaults_canonical "$tmpd/ext4")" ]]; then
  fail "canonical form still depends on the rootfstype value — ext4/xfs machines would false-alarm"
fi

# 3) 反向：非 rootfstype 的改动必须仍然被看出来
sed 's/zswap.enabled=0/zswap.enabled=1/' "$src" > "$tmpd/other"
if [[ "$(grub_defaults_canonical "$src")" == "$(grub_defaults_canonical "$tmpd/other")" ]]; then
  fail "canonical form hides a non-rootfstype change (zswap.enabled) — 12 would stop catching real drift"
fi
grep -q 'zswap.enabled=0' <(grub_defaults_canonical "$src") || fail "canonical form dropped unrelated kernel parameters"

# 4) 归一后不应残留空白串：GRUB_CMDLINE_LINUX 变成干净的单空格分隔
if grep -Eq '" .*"|  ' <(grub_defaults_canonical "$src" | grep '^GRUB_CMDLINE_LINUX='); then
  fail "canonical form leaves stray whitespace: $(grub_defaults_canonical "$src" | grep '^GRUB_CMDLINE_LINUX=')"
fi

echo "ok: rootfstype derivation is normalized for verify, other differences still detected"
