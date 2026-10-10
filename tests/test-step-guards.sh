#!/usr/bin/env bash
# tests/test-step-guards.sh — steps/*.sh 的入口守卫（离线、零副作用）。
# 每个步骤在未设置 AN_RUN 时必须立刻以 64 退出（require_orchestrator 守卫），
# 保证任何步骤都不能被手滑直跑（这一步发生在读清单/改系统之前）。
#
# 安全设计（2026-10 事故后加固）：本测试会**真的执行每个 step 脚本**（这是验证守卫是否有效的
# 唯一方式），所以必须假定某个 step 的守卫已经失效。为此准备了四层隔离：
#   1) 沙箱仓库：AN_ROOT_DIR 指向 mktemp 目录，steps/manifests 是副本，lib/payload 是软链
#      （payload 144MB 不复制）；步骤写的 .state、备份、清单都落在沙箱里。
#   2) 目标重写：AN_TARGET_ROOT=<沙箱 root> —— 07/12 会把清单里的绝对目标整体重写到沙箱下
#      （见 lib/common.sh 的 an_resolve_target）；步骤真跑起来写的也是沙箱路径。
#      HOME 放在 <沙箱 root>/home/pang，使 07 的「$HOME 内用当前用户 / 其余走 root」判定与真实布局一致。
#   3) sandbox-sudo：PATH 前置的 sudo 只放行「参数里的路径都在沙箱/仓库副本内」的命令（绝对或相对都查），
#      其余命令交给同目录 no-op stub（pacman/systemctl/snapper/locale-gen/... 全部无效）。
#   4) 步骤在沙箱目录里执行（cd "$sandbox"）：清单里万一有相对路径目标，落点也在沙箱内。
#      每个步骤还有 timeout 兜底（防止交互式 read 挂住）。
# 另有自检：清单目标必须都是绝对路径且不含 ..（否则重写后可能逃出沙箱）→ 直接判失败。
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
case "$sandbox" in /tmp/*|/var/tmp/*) ;; *) echo "[FAIL] sandbox is not under /tmp: $sandbox"; exit 1;; esac
cd "$sandbox"
repo="$sandbox/repo"
root="$sandbox/root"
home="$root/home/pang"
stub_bin="$sandbox/stub-bin"
mkdir -p "$repo/manifests" "$home" "$stub_bin"
ln -s "$ROOT_DIR/lib" "$repo/lib"
ln -s "$ROOT_DIR/payload" "$repo/payload"
cp -a "$ROOT_DIR/steps" "$repo/steps"
for m in "$ROOT_DIR"/manifests/*.tsv; do cp -- "$m" "$repo/manifests/"; done

# no-op stub：系统写操作全部无效（即使某个步骤真的跑起来，也碰不到真系统）。
for c in pacman paru yay systemctl snapper usermod locale-gen grub-mkconfig \
         glib-compile-schemas setfacl getfacl mkinitcpio fc-cache update-desktop-database \
         gsettings curl wget ping; do
  printf '#!/bin/sh\nexit 0\n' > "$stub_bin/$c"
  chmod +x "$stub_bin/$c"
done

# sandbox-sudo：只有参数里的路径都落在沙箱或仓库副本内才真的执行；否则拒绝（含相对路径）。
sed -e "s|@ROOT@|$root|" -e "s|@REPO@|$repo|" > "$stub_bin/sudo" <<'STUB'
#!/bin/sh
root="@ROOT@"; repo="@REPO@"
case "$1" in
  install|cp|mv|tee|cat|rm|mkdir|ln|touch|chmod|chown|md5sum|stat)
    for a in "$@"; do
      # 含 "/" 的参数（绝对或相对）都必须落在沙箱/仓库副本内 → 相对路径不再能穿透。
      case "$a" in */*) case "$a" in "$root"/*|"$repo"/*) ;; *) echo "sandbox-sudo: refuse $a" >&2; exit 1;; esac;; esac
    done ;;
esac
exec "$@"
STUB
chmod +x "$stub_bin/sudo"

# 自检：沙箱清单里的目标必须是绝对路径且不含 ..，否则重写后可能写穿到沙箱外。
unsafe="$(awk -F'\t' '!/^[[:space:]]*#/ && NF >= 2 { if ($2 !~ /^\// || $2 ~ /\.\.\//) print $2 }' "$repo/manifests/files.tsv")"
if [[ -n "$unsafe" ]]; then
  echo "[FAIL] manifest targets are not safe to rewrite inside the sandbox:"
  printf '%s\n' "$unsafe" | head -5
  exit 1
fi

bad=0
count=0
for f in "$ROOT_DIR"/steps/*.sh; do
  count=$((count + 1))
  rc=0
  # AN_TARGET_ALLOW=/ 是刻意的：本测试验证的是守卫，不是白名单（白名单另有测试）。
  env -u AN_RUN -u AN_MACHINE \
      HOME="$home" PATH="$stub_bin:$PATH" \
      AN_ROOT_DIR="$repo" AN_TARGET_ROOT="$root" AN_TARGET_ALLOW=/ \
      timeout 20 bash "$repo/steps/$(basename "$f")" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" != "64" ]]; then
    echo "[FAIL] $(basename "$f"): expected exit 64 without AN_RUN, got ${rc}"
    bad=1
  fi
done

if (( count == 0 )); then
  echo "[FAIL] no step scripts found"
  exit 1
fi
if (( bad == 0 )); then
  echo "ok: all ${count} step scripts refuse to run without the orchestrator (rc=64, sandboxed)"
fi
exit "$bad"
