#!/usr/bin/env bash
# test-no-aur.sh — --no-aur 沙箱闭环（全 stub、零系统副作用）：
#   1) install.sh --run --yes --no-aur：05 被跳过且不写入 steps.done；其余阶段全完成；结尾给出补装命令
#   2) 随后一次普通 --run --yes：只补跑 05（其余 "already done (resume)"），完成后 05 入账、结尾不再提 except AUR
# 沙箱构成：install.sh 副本 + steps/（全替换为 stub）+ 指向真实 lib/manifests/payload 的软链；
# PATH 前置 stub（sudo/pacman/git），一切只发生在 mktemp 目录内。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/repo/steps" "$sandbox/stub-bin"

cp "$ROOT/install.sh" "$sandbox/repo/install.sh"
ln -s "$ROOT/lib" "$sandbox/repo/lib"
ln -s "$ROOT/manifests" "$sandbox/repo/manifests"
ln -s "$ROOT/payload" "$sandbox/repo/payload"

# steps 全替换为只回显的 stub（不再触碰系统）；文件名沿用真实阶段名。
for f in "$ROOT"/steps/*.sh; do
  b="$(basename "$f")"
  printf '#!/usr/bin/env bash\necho "STUB %s"\n' "$b" > "$sandbox/repo/steps/$b"
done

# 前置 PATH stub：install.sh 的前置检查（sudo/pacman/git、sudo -n true）全部通过且无副作用。
for c in sudo pacman git; do
  printf '#!/bin/sh\nexit 0\n' > "$sandbox/stub-bin/$c"
  chmod +x "$sandbox/stub-bin/$c"
done

DONE="$sandbox/repo/.state/steps.done"
run() { PATH="$sandbox/stub-bin:$PATH" bash "$sandbox/repo/install.sh" --run --yes --machine vm "$@" 2>&1; }

# ---- 第一轮：--no-aur ----
if ! out1="$(run --no-aur)"; then
  printf '%s\n' "$out1"
  echo "[FAIL] first run (--no-aur) exited non-zero"
  exit 1
fi
printf '%s\n' "$out1"
printf '%s\n' "$out1" | grep -q 'stage 05 aur: skipped (--no-aur' || { echo "[FAIL] 05 skip line missing"; exit 1; }
printf '%s\n' "$out1" | grep -q '\[skipped: --no-aur\]' || { echo "[FAIL] plan annotation missing"; exit 1; }
if grep -qx '05' "$DONE"; then
  echo "[FAIL] stage 05 was wrongly marked done"
  exit 1
fi
for id in 01 02 03 04 06 07 08 09 10 11 12; do
  grep -qx "$id" "$DONE" || { echo "[FAIL] stage ${id} not marked done"; exit 1; }
done
printf '%s\n' "$out1" | grep -q 'all stages complete except AUR' || { echo "[FAIL] 'except AUR' footer missing"; exit 1; }
printf '%s\n' "$out1" | grep -q 'install.sh --run --yes' || { echo "[FAIL] deferred-finish hint missing"; exit 1; }
if printf '%s\n' "$out1" | grep -q 'STUB 05-aur.sh'; then
  echo "[FAIL] stage 05 ran despite --no-aur"
  exit 1
fi

# ---- 第二轮：普通 --run --yes → 只补 05 ----
if ! out2="$(run)"; then
  printf '%s\n' "$out2"
  echo "[FAIL] second run exited non-zero"
  exit 1
fi
printf '%s\n' "$out2"
printf '%s\n' "$out2" | grep -q 'STUB 05-aur.sh' || { echo "[FAIL] stage 05 did not run on the second pass"; exit 1; }
printf '%s\n' "$out2" | grep -q 'stage 01 sources: already done (resume)' || { echo "[FAIL] resume line for stage 01 missing"; exit 1; }
if printf '%s\n' "$out2" | grep -q 'STUB 01-sources.sh'; then
  echo "[FAIL] stage 01 re-ran on the second pass"
  exit 1
fi
grep -qx '05' "$DONE" || { echo "[FAIL] stage 05 not marked done after the second pass"; exit 1; }
printf '%s\n' "$out2" | grep -q 'all stages complete\.' || { echo "[FAIL] final 'all stages complete.' missing"; exit 1; }
if printf '%s\n' "$out2" | grep -q 'except AUR'; then
  echo "[FAIL] second pass still reports 'except AUR'"
  exit 1
fi
if printf '%s\n' "$out2" | grep -q 'skipped: --no-aur'; then
  echo "[FAIL] second pass still carries the --no-aur annotation"
  exit 1
fi

echo "ok: --no-aur skips+defers stage 05; a later plain run finishes exactly that stage"
