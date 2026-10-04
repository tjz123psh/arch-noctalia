#!/usr/bin/env bash
# steps/08-scripts.sh — Stage 08: scripts + ~/bin symlink layer.
# 计划（后续里程碑实现）：按 manifests/bin-links.tsv（link_name<TAB>target）
#   在 ~/bin 建立软链层（ln -sfn），并核对脚本可执行位。
# 现状：里程碑 1 = 骨架。做只读校验，然后明确停止（不会改动系统）。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator

MANIFEST="${AN_ROOT_DIR}/manifests/bin-links.tsv"
[[ -f "$MANIFEST" ]] || die "missing manifest: ${MANIFEST}"

links=0
while IFS=$'\t' read -r name _target; do
  if [[ -z "$name" || "$name" == "#"* ]]; then
    continue
  fi
  links=$((links + 1))
done < "$MANIFEST"

info "Stage 08 scripts: ${links} symlinks would be created under ~/bin"
warn "not implemented in milestone 1 (skeleton) — stopping before any changes"
exit 90
