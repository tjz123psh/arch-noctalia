#!/usr/bin/env bash
# tests/test-services-enable.sh — 10-services 的「启用语义」沙箱回归（不碰真系统）。
# 背景：10/11 的脚本体此前从未被任何测试执行（test-step-guards 只跑到守卫那一行），
# 所以「到底 enable 了哪些 unit」「有没有误碰 tty1/greetd」无人看守。
# 做法：PATH 前置一个会记账的 systemctl stub（cat/is-enabled/enable/is-active/show 全可控），
#       sudo/usermod/snapper/locale-gen 等为 no-op；HOME 与 AN_TARGET_ROOT 都在 mktemp 沙箱内。
# 断言：docker.service 与 bluetooth.service 必须 enable --now；不得出现 greetd（那是 11 的职责）；
#       步骤必须 rc=0 且摘要行完整。
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
bad() { echo "[FAIL] $*"; fail=1; }

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
case "$sandbox" in /tmp/*|/var/tmp/*) ;; *) echo "[FAIL] sandbox is not under /tmp: $sandbox"; exit 1;; esac
# 步骤在沙箱目录里执行（相对路径目标也不会落到仓库 cwd）。
cd "$sandbox"

repo="$sandbox/repo"; root="$sandbox/root"; home="$root/home/pang"; stub="$sandbox/stub-bin"
log="$sandbox/systemctl.log"
mkdir -p "$repo/manifests" "$home" "$stub"
ln -sfn "$ROOT_DIR/lib" "$repo/lib"
ln -sfn "$ROOT_DIR/payload" "$repo/payload"
cp -a "$ROOT_DIR/steps" "$repo/steps"
for m in "$ROOT_DIR"/manifests/*.tsv; do cp -- "$m" "$repo/manifests/"; done

# 会记账的 systemctl：单元都存在、都未启用；enable 记录下来并成功；is-active 视为在跑。
cat > "$stub/systemctl" <<STUB
#!/bin/sh
echo "systemctl \$*" >> "$log"
case "\$1" in
  cat|show|daemon-reload|--user) exit 0 ;;
  is-enabled) exit 1 ;;
  is-active) exit 0 ;;
  enable) exit 0 ;;
esac
exit 0
STUB
chmod +x "$stub/systemctl"
# 其余 no-op：系统写操作全部无效。
for c in pacman paru yay snapper usermod locale-gen grub-mkconfig glib-compile-schemas \
         setfacl getfacl mkinitcpio fc-cache gsettings btrfs; do
  printf '#!/bin/sh\nexit 0\n' > "$stub/$c"; chmod +x "$stub/$c"
done
printf '#!/bin/sh\necho ext4\n' > "$stub/findmnt"; chmod +x "$stub/findmnt"
# sandbox-sudo：只放行沙箱内路径（与 test-step-guards.sh 同款护栏）。
sed -e "s|@ROOT@|$root|" -e "s|@REPO@|$repo|" > "$stub/sudo" <<'STUB'
#!/bin/sh
root="@ROOT@"; repo="@REPO@"
case "$1" in
  install|cp|mv|tee|cat|rm|mkdir|ln|touch|chmod|chown|md5sum|stat)
    for a in "$@"; do
      case "$a" in */*) case "$a" in "$root"/*|"$repo"/*) ;; *) echo "sandbox-sudo: refuse $a" >&2; exit 1;; esac;; esac
    done ;;
esac
exec "$@"
STUB
chmod +x "$stub/sudo"

rc=0
out="$(env HOME="$home" PATH="$stub:$PATH" AN_RUN=1 AN_MACHINE=physical AN_ROOT_DIR="$repo" \
        AN_TARGET_ROOT="$root" AN_TARGET_ALLOW=/ bash "$repo/steps/10-services.sh" 2>&1)" || rc=$?
printf '%s\n' "$out" | tail -3

(( rc == 0 )) || bad "10-services exited non-zero in the sandbox (rc=$rc)"
grep -q 'enable --now docker.service' "$log" || bad "docker.service was not enabled (--now)"
grep -q 'enable --now bluetooth.service' "$log" || bad "bluetooth.service was not enabled (--now)"
if grep -q 'greetd' "$log"; then bad "10-services must not touch greetd (that is stage 11's job)"; fi
grep -q 'services: ' <<<"$out" || bad "summary line missing"

if (( fail > 0 )); then
  echo "test-services-enable: FAIL"
  exit 1
fi
echo "ok: 10-services enables docker/bluetooth (--now) in the sandbox and leaves greetd to stage 11"
