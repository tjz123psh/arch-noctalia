#!/usr/bin/env bash
# test-supergfxd-mode.sh — 07 对 /etc/supergfxd.conf 的 runtime 例外（沙箱，零系统副作用）：
#   该文件由 supergfxd 自己改写（runtime 名单），但 hotplug_type=Asus 是安装器必须保证的值
#   （否则「切集显 → 重启 → 又回混合」）。整份覆盖会把用户选的 mode 一起打回仓库快照 ——
#   那正是同一个坑的另一半。本用例锁住：hotplug_type 被补上、本地 mode 保留、备份可查、
#   第二遍按 runtime 保持不动。
set -Eeuo pipefail
umask 022
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
case "$sandbox" in /tmp/*|/var/tmp/*) ;; *) echo "[FAIL] sandbox is not under /tmp: $sandbox"; exit 1;; esac
cd "$sandbox"

A="$sandbox/a"
repo="$A/repo"
root="$A/root"
home="$root/home/pang"
stub="$A/stub-bin"
mkdir -p "$repo/manifests" "$home" "$stub" "$root/etc"
ln -sfn "$ROOT_DIR/lib" "$repo/lib"
ln -sfn "$ROOT_DIR/payload" "$repo/payload"
cp -a "$ROOT_DIR/steps" "$repo/steps"

src="payload/system/etc/supergfxd.conf"
md5="$(md5sum "$ROOT_DIR/$src" | awk '{print $1}')"
printf '%s\t/etc/supergfxd.conf\t644\t%s\n' "$src" "$md5" > "$repo/manifests/files.tsv"
printf '# schema=1\npayload/system/etc/supergfxd.conf\tsupergfxd 配置（mode 由程序改写）\n' \
  > "$repo/manifests/runtime-regenerated.tsv"
printf '# schema=1\n' > "$repo/manifests/seed.tsv"

for c in pacman paru systemctl usermod locale-gen grub-mkconfig glib-compile-schemas \
         setfacl getfacl fc-cache update-desktop-database gsettings bat zoxide delta fish; do
  printf '#!/bin/sh\nexit 0\n' > "$stub/$c"
  chmod +x "$stub/$c"
done
# sudo 在沙箱里直接执行（沙箱内文件均由当前用户所有，不会碰真机）。
printf '#!/bin/sh\nexec "$@"\n' > "$stub/sudo"
chmod +x "$stub/sudo"

# 预置现场：hotplug_type 被 supergfxd 写成 None，用户把 mode 切到了 iGPU。
cat > "$root/etc/supergfxd.conf" <<'EOF'
{
  "mode": "Integrated",
  "vfio_enable": true,
  "hotplug_type": "None"
}
EOF

run07() {
  env HOME="$home" PATH="$stub:$PATH" AN_RUN=1 AN_MACHINE=physical AN_ROOT_DIR="$repo" \
      AN_TARGET_ROOT="$root" AN_TARGET_ALLOW=/ bash "$repo/steps/07-config.sh"
}

if ! out1="$(run07 2>&1)"; then
  printf '%s\n' "$out1" | tail -20
  echo "[FAIL] first run exited non-zero"
  exit 1
fi
printf '%s\n' "$out1"

grep -q '"hotplug_type": "Asus"' "$root/etc/supergfxd.conf" ||
  { echo "[FAIL] hotplug_type was not restored to Asus"; exit 1; }
grep -q '"mode": "Integrated"' "$root/etc/supergfxd.conf" ||
  { echo "[FAIL] user's mode (Integrated) was reset by the whole-file deploy"; exit 1; }
grep -q 'supergfxd: hotplug_type=Asus restored, local mode kept (Integrated)' <<<"$out1" ||
  { echo "[FAIL] missing 'mode kept' message"; exit 1; }
grep -qF 'files: 1 checked, 1 deployed, 0 unchanged, 0 kept (seed/runtime), 0 failed' <<<"$out1" ||
  { echo "[FAIL] unexpected summary: $(grep 'files:' <<<"$out1" | tail -1)"; exit 1; }

bk="$(find "$sandbox" -path '*overwritten*' -name supergfxd.conf 2>/dev/null | head -1)"
if [[ -z "$bk" ]] || ! grep -q '"hotplug_type": "None"' "$bk"; then
  echo "[FAIL] no backup of the pre-existing supergfxd.conf"
  exit 1
fi
manifest_tsv="$(find "$sandbox" -path '*overwritten*' -name MANIFEST.tsv 2>/dev/null | head -1)"
if [[ -z "$manifest_tsv" ]] || ! grep -qF "$root/etc/supergfxd.conf" "$manifest_tsv"; then
  echo "[FAIL] MANIFEST.tsv has no record for supergfxd.conf"
  exit 1
fi

# 第二遍：hotplug_type 已对 → 按 runtime 保持原样（不重写、不再动 mode）。
if ! out2="$(run07 2>&1)"; then
  printf '%s\n' "$out2" | tail -20
  echo "[FAIL] second run exited non-zero"
  exit 1
fi
grep -qF 'files: 1 checked, 0 deployed, 0 unchanged, 1 kept (seed/runtime), 0 failed' <<<"$out2" ||
  { echo "[FAIL] second run is not runtime-idempotent: $(grep 'files:' <<<"$out2" | tail -1)"; exit 1; }
grep -q '"mode": "Integrated"' "$root/etc/supergfxd.conf" ||
  { echo "[FAIL] mode changed on the second run"; exit 1; }

echo "ok: supergfxd hotplug_type restored, local mode preserved across re-runs, backup recorded"
