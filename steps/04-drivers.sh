#!/usr/bin/env bash
# steps/04-drivers.sh — Stage 04: hardware drivers（物理机）。
# 计划（后续里程碑实现）：安装 packages.tsv 中 module=drivers 的驱动/固件包
#   （AMD 核显、NVIDIA、asusctl/supergfxctl 等），仅物理机执行；vm（测试）跳过。
# 现状：里程碑 1 = 骨架。本步骤只做只读校验，然后明确停止（不会改动系统）。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator
machine="${AN_MACHINE:?AN_MACHINE is required (set by install.sh)}"

MANIFEST="${AN_ROOT_DIR}/manifests/packages.tsv"
[[ -f "$MANIFEST" ]] || die "missing manifest: ${MANIFEST}"

drivers=0
while IFS=$'\t' read -r pkg _repo module _purpose; do
  if [[ -z "$pkg" || "$pkg" == "#"* ]]; then
    continue
  fi
  if [[ "${module:-}" == "drivers" ]]; then
    drivers=$((drivers + 1))
  fi
done < "$MANIFEST"

info "Stage 04 drivers: ${drivers} driver packages listed (machine=${machine})"
if [[ "$machine" != "physical" ]]; then
  info "machine is not physical — the drivers stage would be skipped"
  ok "Stage 04 drivers: nothing to do"
  exit 0
fi
warn "not implemented in milestone 1 (skeleton) — stopping before any changes"
exit 90
