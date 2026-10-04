#!/usr/bin/env bash
# steps/05-aur.sh — Stage 05: AUR / foreign packages.
# 计划（后续里程碑实现）：逐个 paru -S --needed --noconfirm（manifests/aur.tsv），
#   任一失败则汇总报错，便于人工跟进。
# 现状：里程碑 1 = 骨架。只做只读校验，然后明确停止（不会改动系统）。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator
machine="${AN_MACHINE:?AN_MACHINE is required (set by install.sh)}"

MANIFEST="${AN_ROOT_DIR}/manifests/aur.tsv"
[[ -f "$MANIFEST" ]] || die "missing manifest: ${MANIFEST}"

total=0
pending=0
while IFS=$'\t' read -r pkg _repo _purpose; do
  if [[ -z "$pkg" || "$pkg" == "#"* ]]; then
    continue
  fi
  total=$((total + 1))
  if ! pacman -Q "$pkg" >/dev/null 2>&1; then
    pending=$((pending + 1))
  fi
done < "$MANIFEST"

info "Stage 05 aur: ${total} foreign packages listed (machine=${machine}); ${pending} not installed yet"
warn "not implemented in milestone 1 (skeleton) — stopping before any changes"
exit 90
