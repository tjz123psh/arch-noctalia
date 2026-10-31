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
# 插件套件：同一份代码的另一个入口（run_all.py 覆盖 Lua/JS/GTK 与文档契约）。
if command -v python3 >/dev/null 2>&1 && command -v lua >/dev/null 2>&1 \
   && command -v gjs >/dev/null 2>&1 && command -v node >/dev/null 2>&1 \
   && command -v noctalia >/dev/null 2>&1; then
  printf '===== tide-sidebar plugin suite =====\n'
  if python3 -B "$HERE/../payload/home/noctalia-plugins/tide-sidebar/tests/run_all.py"; then
    printf 'PASS: tide-sidebar plugin suite\n\n'
  else
    printf 'FAIL: tide-sidebar plugin suite\n\n'
    overall=1
  fi
else
  printf 'SKIP: tide-sidebar plugin suite (lua/gjs/node/noctalia missing)\n\n'
fi
if (( overall == 0 )); then
  echo "ALL TESTS PASSED"
else
  echo "SOME TESTS FAILED"
  exit 1
fi
