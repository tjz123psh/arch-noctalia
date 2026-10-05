#!/usr/bin/env bash
# test-probe-locale.sh — t_type 的输出必须稳定（回归锁，2026-10-05 VM 实测两个坑）：
#   1) zh_CN locale 下 `stat -c %F` 输出"普通文件"——直接与 "regular file" 比较会让
#      07 幂等失效（全量重部署）、12 全量误报 "not a regular file"；修法 = 强制 LC_ALL=C；
#   2) coreutils 把空文件报为 "regular empty file"——需归一为 "regular file"。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
f="$(mktemp)"                       # 空文件（触发 "regular empty file" 分支）
f2="$(mktemp)"; printf 'x\n' > "$f2" # 非空文件
d="$(mktemp -d)"
trap 'rm -f "$f" "$f2"; rmdir "$d"' EXIT

check() { # $1=locale 值
  local loc="$1" out
  out="$(LANG="$loc" LC_ALL="$loc" bash -c '
    source "'"$ROOT"'/lib/common.sh"
    printf "e=%s f=%s d=%s" "$(t_type "'"$f"'")" "$(t_type "'"$f2"'")" "$(t_type "'"$d"'")"
  ')"
  if [[ "$out" != "e=regular file f=regular file d=directory" ]]; then
    echo "[FAIL] locale=${loc}: ${out}"
    exit 1
  fi
}

check C
if locale -a 2>/dev/null | grep -qi '^zh_CN'; then
  check zh_CN.UTF-8
else
  echo "[skip] zh_CN locale not available — only C checked"
fi
echo "ok: t_type is locale-invariant and normalizes empty files (C + zh_CN)"
