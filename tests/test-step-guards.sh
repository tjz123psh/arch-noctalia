#!/usr/bin/env bash
# tests/test-step-guards.sh — steps/*.sh 的入口守卫（离线、零副作用）。
# 每个步骤在未设置 AN_RUN 时必须立刻以 64 退出（require_orchestrator 守卫），
# 保证任何步骤都不能被手滑直跑（这一步发生在读清单/改系统之前）。
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bad=0
count=0
for f in "$ROOT_DIR"/steps/*.sh; do
  count=$((count + 1))
  rc=0
  env -u AN_RUN -u AN_MACHINE bash "$f" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" != "64" ]]; then
    echo "[FAIL] $(basename "$f"): expected exit 64 without AN_RUN, got ${rc}"
    bad=1
  fi
done

if (( count == 0 )); then
  echo "[FAIL] no step scripts found"
  exit 1
fi
if (( bad == 0 )); then
  echo "ok: all ${count} step scripts refuse to run without the orchestrator (rc=64)"
fi
exit "$bad"
