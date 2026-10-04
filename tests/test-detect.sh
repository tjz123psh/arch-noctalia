#!/usr/bin/env bash
# test-detect.sh — detect 回归：输出必须单行、值域合法。
# 曾经的真实 bug：裸机 systemd-detect-virt 输出 "none" 且 rc=1，
# `|| echo unknown` 又补了一行输出，导致 detect_machine 判成 unknown —— 这里钉死"单行"不变量。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091  # 相对 source；lib 由主检查批量覆盖
source "$ROOT/lib/detect.sh"

v="$(detect_virt)"
lines=$(printf '%s\n' "$v" | wc -l)
[ "$lines" -eq 1 ] || { echo "detect_virt output not single-line: [$v]"; exit 1; }
[ -n "$v" ] || { echo "detect_virt empty"; exit 1; }

m="$(detect_machine)"
lines=$(printf '%s\n' "$m" | wc -l)
[ "$lines" -eq 1 ] || { echo "detect_machine output not single-line: [$m]"; exit 1; }
case "$m" in
  physical|vm|unknown) ;;
  *) echo "detect_machine unexpected value: [$m]"; exit 1 ;;
esac

echo "ok: detect_virt='${v}' detect_machine='${m}' (single-line, valid domain)"
