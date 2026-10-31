#!/usr/bin/env bash
# test-quiet-output.sh — --quiet 必须真的静音包管理器输出（审计 F4）：
#   以前 QUIET 只静音 info/ok/summary，`pacman -Syu` / `paru -S` 的下载与构建日志照旧刷屏，
#   与 "one quiet line per stage" 的承诺不符。现在统一走 pkg_run：quiet 吞 stdout、保留 stderr。
# 同时锁住调用点：步骤里不应再出现未包裹的 pacman -S / paru -S。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
# shellcheck disable=SC1091  # 相对 source；lib 在各检查中以独立目标校验
source "$ROOT/lib/common.sh"

fake_pkg() { printf 'stdout-line\n'; printf 'stderr-line\n' >&2; return 0; }

out_q="$(AN_QUIET=1 pkg_run fake_pkg 2>/dev/null)"
err_q="$(AN_QUIET=1 pkg_run fake_pkg 2>&1 >/dev/null)"
[[ -z "$out_q" ]] || { echo "[FAIL] quiet mode did not swallow stdout: [$out_q]"; exit 1; }
[[ "$err_q" == "stderr-line" ]] || { echo "[FAIL] quiet mode must keep stderr: [$err_q]"; exit 1; }

out_v="$(AN_QUIET=0 pkg_run fake_pkg 2>/dev/null)"
err_v="$(AN_QUIET=0 pkg_run fake_pkg 2>&1 >/dev/null)"
[[ "$out_v" == "stdout-line" ]] || { echo "[FAIL] verbose mode lost stdout: [$out_v]"; exit 1; }
[[ "$err_v" == "stderr-line" ]] || { echo "[FAIL] verbose mode lost stderr: [$err_v]"; exit 1; }

if AN_QUIET=1 pkg_run bash -c 'exit 7'; then
  echo "[FAIL] pkg_run swallowed a non-zero exit status"
  exit 1
fi

# 调用点：全部经过 pkg_run（否则 quiet 又是空话）。
if grep -nE '^[[:space:]]*(as_root[[:space:]]+)?pacman[[:space:]]+-(S|Syu|Sy)\b' "$ROOT"/steps/*.sh; then
  echo "[FAIL] unwrapped pacman call found in steps/ (use pkg_run)"
  exit 1
fi
if grep -nE '^[[:space:]]*paru[[:space:]]+-S\b' "$ROOT"/steps/*.sh; then
  echo "[FAIL] unwrapped paru call found in steps/ (use pkg_run)"
  exit 1
fi

echo "ok: pkg_run silences stdout under --quiet, keeps stderr and exit status; all pacman/paru calls wrapped"
