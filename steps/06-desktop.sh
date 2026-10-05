#!/usr/bin/env bash
# steps/06-desktop.sh — Stage 06: niri + Noctalia desktop packages.
# 只处理 packages.tsv 中 module=desktop 的行（niri、noctalia、portal、fcitx5、greetd 等）。
# 幂等：--needed + 已装过滤；重复运行安全。
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
  [[ "${module:-}" == "desktop" ]] || continue
  selected=$((selected + 1))
  if ! pacman -Q "$pkg" >/dev/null 2>&1; then
    to_install+=("$pkg")
  fi
done < "$MANIFEST"

info "selected ${selected} desktop packages for machine=${machine}; ${#to_install[@]} still to install"
if (( ${#to_install[@]} == 0 )); then
  ok "Stage 06 desktop: nothing to do"
  exit 0
fi
confirm "Install ${#to_install[@]} desktop packages now?" || die "declined"
as_root pacman -S --needed --noconfirm "${to_install[@]}"
ok "Stage 06 desktop: done"
