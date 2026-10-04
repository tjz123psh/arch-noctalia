#!/usr/bin/env bash
# tests/run-all.sh — 运行全部本地回归测试（驱动真实入口；不依赖 VM）。
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
overall=0
for t in "$HERE"/test-*.sh; do
  name="$(basename "$t")"
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
