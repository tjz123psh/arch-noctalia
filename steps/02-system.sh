#!/usr/bin/env bash
# steps/02-system.sh — Stage 02: full system upgrade.
# 目的：官方源 + archlinuxcn 一次全量升级（pacman -Syu），
#       保证后续包安装没有"部分升级"窗口。
# 幂等：重跑 = 再次升级。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator

info "Stage 02 system: full system upgrade (pacman -Syu)"
confirm "Run the full system upgrade now?" || die "declined"
as_root pacman -Syu --noconfirm
ok "Stage 02 system: done"
