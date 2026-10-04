#!/usr/bin/env bash
# steps/03-packages.sh — Stage 03: official/archlinuxcn packages.
# 读 manifests/packages.tsv（列：package<TAB>repo<TAB>module<TAB>purpose）：
#   本步骤安装"系统/应用"类；drivers 归 04、desktop 归 06、外来/AUR 归 05。
# 幂等：--needed + 已装过滤。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator
machine="${AN_MACHINE:?AN_MACHINE is required (set by install.sh)}"

MANIFEST="${AN_ROOT_DIR}/manifests/packages.tsv"
[[ -f "$MANIFEST" ]] || die "missing manifest: ${MANIFEST}"

selected=0
to_install=()
while IFS=$'\t' read -r pkg _repo module _purpose; do
  if [[ -z "$pkg" || "$pkg" == "#"* ]]; then
    continue
  fi
  case "${module:-}" in
    drivers|desktop|aur) continue ;;
    vmware-guest) [[ "$machine" == "vm" ]] || continue ;;
    physical-only) [[ "$machine" == "physical" ]] || continue ;;
  esac
  selected=$((selected + 1))
  if ! pacman -Q "$pkg" >/dev/null 2>&1; then
    to_install+=("$pkg")
  fi
done < "$MANIFEST"

info "selected ${selected} packages for machine=${machine}; ${#to_install[@]} still to install"
if (( ${#to_install[@]} == 0 )); then
  ok "Stage 03 packages: nothing to do"
  exit 0
fi
confirm "Install ${#to_install[@]} packages now?" || die "declined"
as_root pacman -S --needed --noconfirm "${to_install[@]}"
ok "Stage 03 packages: done"
