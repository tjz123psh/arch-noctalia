#!/usr/bin/env bash
# steps/04-drivers.sh — Stage 04: hardware drivers.
# 只处理 packages.tsv 中 module=drivers 的行（AMD 核显、NVIDIA、asusctl/supergfxctl 等）。
# 仅物理机执行；machine != physical 时说明后跳过（VM 是验证场地，不装目标机驱动）。
# 幂等：--needed + 已装过滤；重复运行安全。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator
machine="${AN_MACHINE:?AN_MACHINE is required (set by install.sh)}"

MANIFEST="${AN_ROOT_DIR}/manifests/packages.tsv"
[[ -f "$MANIFEST" ]] || die "missing manifest: ${MANIFEST}"

if [[ "$machine" != "physical" ]]; then
  info "machine is not physical (machine=${machine}) — drivers are physical-only; skipping"
  ok "Stage 04 drivers: nothing to do"
  exit 0
fi

selected=0
to_install=()
while IFS=$'\t' read -r pkg _repo module _purpose; do
  if [[ -z "$pkg" || "$pkg" == "#"* ]]; then
    continue
  fi
  [[ "${module:-}" == "drivers" ]] || continue
  selected=$((selected + 1))
  if ! pacman -Q "$pkg" >/dev/null 2>&1; then
    to_install+=("$pkg")
  fi
done < "$MANIFEST"

info "selected ${selected} driver packages for machine=${machine}; ${#to_install[@]} still to install"
if (( ${#to_install[@]} == 0 )); then
  ok "Stage 04 drivers: nothing to do"
  exit 0
fi
confirm "Install ${#to_install[@]} driver packages now?" || die "declined"
# --ask=4：冲突包自动替换（与 03 一致）
as_root pacman -S --needed --noconfirm --ask=4 "${to_install[@]}"
ok "Stage 04 drivers: done"
