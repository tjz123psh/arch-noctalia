#!/usr/bin/env bash
# test-preview.sh — 预览回归（驱动真实入口 install.sh --preview）：
#   rc=0；输出含全部 12 阶段 + machine 行 + "preview OK"；两次输出一致；不产生 .state。
#   --no-aur 预览：05 行标注 [skipped: --no-aur]；默认预览不得带该标注。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out1="$(mktemp)"
out2="$(mktemp)"
out3="$(mktemp)"
out4="$(mktemp)"
sandbox="$(mktemp -d)"
trap 'rm -f "$out1" "$out2" "$out3" "$out4"; rm -rf "$sandbox"' EXIT
# 状态目录现在落在用户 XDG state 下，所以给沙箱 HOME，顺便把「预览不写状态」断言精确到位置上。
export HOME="$sandbox/home"
mkdir -p "$HOME"

if ! bash "$ROOT/install.sh" --preview > "$out1" 2>&1; then
  echo "preview exited non-zero:"
  cat "$out1"
  exit 1
fi
bash "$ROOT/install.sh" --preview > "$out2" 2>&1
if ! diff -u "$out1" "$out2" >/dev/null; then
  echo "preview output is not deterministic:"
  diff -u "$out1" "$out2"
  exit 1
fi

grep -q '^preview OK' "$out1" || { echo "missing 'preview OK' footer"; exit 1; }
grep -qE '^machine: (physical|vm|unknown) ' "$out1" || { echo "missing or odd machine line"; exit 1; }
for s in sources system packages drivers aur desktop config scripts noctalia services greeter verify; do
  grep -qE "^  \[[0-9]{2}\] $s " "$out1" || { echo "missing stage in plan: $s"; exit 1; }
done
if [ -e "$ROOT/.state" ]; then
  echo ".state was created by a preview run"
  exit 1
fi
if [ -e "$HOME/.local/state/arch-noctalia" ]; then
  echo "preview created the state directory under HOME"
  exit 1
fi

# --no-aur 预览：05 行必须带标注；默认预览不得出现标注。
if ! bash "$ROOT/install.sh" --preview --no-aur > "$out3" 2>&1; then
  echo "preview --no-aur exited non-zero:"
  cat "$out3"
  exit 1
fi
grep -qE '^  \[05\] aur .*\[skipped: --no-aur\]$' "$out3" || { echo "no-aur annotation missing in 'preview --no-aur'"; exit 1; }
if grep -q 'skipped: --no-aur' "$out1"; then
  echo "default preview must not carry the --no-aur annotation"
  exit 1
fi

# --redo 预览：注明将清记录重跑；默认预览不得出现。
if ! bash "$ROOT/install.sh" --preview --redo 07 > "$out4" 2>&1; then
  echo "preview --redo exited non-zero:"
  cat "$out4"
  exit 1
fi
grep -q 'note: --redo 07' "$out4" || { echo "redo note missing in 'preview --redo 07'"; exit 1; }
if grep -q 'note: --redo' "$out1"; then
  echo "default preview must not carry the --redo note"
  exit 1
fi

echo "ok: deterministic preview, full stage plan, environment line present, no state written, --no-aur and --redo annotated"
