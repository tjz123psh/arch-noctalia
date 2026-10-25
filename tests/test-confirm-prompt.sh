#!/usr/bin/env bash
# tests/test-confirm-prompt.sh — 确认提示必须可见、回答能被读到（2026-10-25 真机回归）。
#   事故：confirm() 用 `read -p ... </dev/tty 2>/dev/null`，read 的提示写在 stderr 且被 2>/dev/null 吞掉，
#   交互安装看起来像「卡死」——用户根本不知道在等一个 y/N。
#   这里用 pty（script）复现真终端：提示必须出现，答 n 不继续、答 y 继续。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v script >/dev/null 2>&1 || { echo "[skip] script(1) not available"; exit 0; }

run_case() { # $1=answer
  printf '%s\n' "$1" | script -qec "bash -c 'source \"$ROOT/lib/common.sh\"; confirm \"PROMPT_VISIBLE\" && echo ANSWERED_YES'" /dev/null 2>&1 || true
}

out="$(run_case n)"
grep -q 'PROMPT_VISIBLE \[y/N\]' <<<"$out" || { echo "[FAIL] confirmation prompt is invisible: ${out}"; exit 1; }
if grep -q ANSWERED_YES <<<"$out"; then echo "[FAIL] answering n must not proceed"; exit 1; fi

out="$(run_case y)"
grep -q ANSWERED_YES <<<"$out" || { echo "[FAIL] answering y must proceed: ${out}"; exit 1; }

echo "ok: confirmation prompt is visible and reads the answer"
