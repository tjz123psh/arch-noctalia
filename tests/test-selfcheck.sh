#!/usr/bin/env bash
# test-selfcheck.sh — 自检工具回归：tools/selfcheck.sh 在一致仓库上必须 rc=0
# （它覆盖语法 / 映射一致性 / 密钥卫生三节）。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if bash "$ROOT/tools/selfcheck.sh" >/dev/null 2>&1; then
  echo "ok: selfcheck passed"
else
  echo "selfcheck FAILED — run tools/selfcheck.sh to see details"
  exit 1
fi
