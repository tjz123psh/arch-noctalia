#!/usr/bin/env bash
# tests/run-all.sh — 运行全部本地回归测试（驱动真实入口；不依赖 VM）。
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
overall=0
for t in "$HERE"/test-*.sh; do
  name="$(basename "$t")"
  # 机器对账只有「本安装器的目标机」跑才有意义（比对的是 niri/Noctalia 落盘后的真实文件）。
  # 别的机器上它会必然失败，把整套回归拖成永远红——那是噪音，不是信号。
  if [[ "$name" == "test-machine-reconcile.sh" ]] && ! command -v niri >/dev/null 2>&1; then
    printf 'SKIP: %s (this machine has no niri — not an arch-noctalia target)\n\n' "$name"
    continue
  fi
  printf '===== %s =====\n' "$name"
  if bash "$t"; then
    printf 'PASS: %s\n\n' "$name"
  else
    printf 'FAIL: %s\n\n' "$name"
    overall=1
  fi
done
if (( overall == 0 )); then
  echo "ALL TESTS PASSED"
else
  echo "SOME TESTS FAILED"
  exit 1
fi
