#!/usr/bin/env bash
# test-preview.sh — 预览回归（驱动真实入口 install.sh --preview）：
#   rc=0；输出含全部 12 阶段 + machine 行 + "preview OK"；两次输出一致；不产生 .state。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out1="$(mktemp)"
out2="$(mktemp)"
trap 'rm -f "$out1" "$out2"' EXIT

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

echo "ok: deterministic preview, full stage plan, environment line present, no state written"
