#!/usr/bin/env bash
# steps/06-desktop.sh — Stage 06: niri + Noctalia desktop packages.
# 计划（后续里程碑实现）：安装 packages.tsv 中 module=desktop 的包
#   （niri、noctalia、xdg-desktop-portal 系列、fcitx5 桌面组件等）。
# 现状：里程碑 1 = 骨架。只做只读校验，然后明确停止（不会改动系统）。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator
machine="${AN_MACHINE:?AN_MACHINE is required (set by install.sh)}"

MANIFEST="${AN_ROOT_DIR}/manifests/packages.tsv"
[[ -f "$MANIFEST" ]] || die "missing manifest: ${MANIFEST}"

desktop=0
installed=0
while IFS=$'\t' read -r pkg _repo module _purpose; do
  if [[ -z "$pkg" || "$pkg" == "#"* ]]; then
    continue
  fi
  if [[ "${module:-}" == "desktop" ]]; then
    desktop=$((desktop + 1))
    if pacman -Q "$pkg" >/dev/null 2>&1; then
      installed=$((installed + 1))
    fi
  fi
done < "$MANIFEST"

info "Stage 06 desktop: ${desktop} desktop packages listed (machine=${machine}); ${installed} already installed"
warn "not implemented in milestone 1 (skeleton) — stopping before any changes"
exit 90
