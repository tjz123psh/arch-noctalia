#!/usr/bin/env bash
# steps/10-services.sh — Stage 10: enable services.
# 计划（后续里程碑实现）：启用并检查：
#   系统级：docker、bluetooth、btrfs-scrub@-.timer、（snapper/snap-pac 为配置+钩子）
#   用户级：rice-dnd.service / rice-dnd.timer（经 07/08 部署的单元文件）
#   注：greetd 的启用归 11-greeter。
# 现状：里程碑 1 = 骨架。仅打印计划，然后明确停止（不会改动系统）。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator
machine="${AN_MACHINE:?AN_MACHINE is required (set by install.sh)}"
: "$machine"

info "Stage 10 services: planned service enablement"
printf '  system: docker, bluetooth, btrfs-scrub@-.timer\n'
printf '  user:   rice-dnd.service, rice-dnd.timer\n'
warn "not implemented in milestone 1 (skeleton) — stopping before any changes"
exit 90
