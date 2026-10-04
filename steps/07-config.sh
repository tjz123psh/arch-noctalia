#!/usr/bin/env bash
# steps/07-config.sh — Stage 07: deploy dotfiles.
# 计划（后续里程碑实现）：按 manifests/files.tsv（repo_path<TAB>target_path<TAB>mode<TAB>md5）
#   逐行部署 —— payload 文件 → 目标绝对路径（含权限位）；/home 之外的目标走 sudo。
# 现状：里程碑 1 = 骨架。做只读预检（payload 完整性），然后明确停止（不会改动系统）。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator

MANIFEST="${AN_ROOT_DIR}/manifests/files.tsv"
[[ -f "$MANIFEST" ]] || die "missing manifest: ${MANIFEST}"

rows=0
missing=0
while IFS=$'\t' read -r repo_path _target _mode _md5; do
  if [[ -z "$repo_path" || "$repo_path" == "#"* ]]; then
    continue
  fi
  rows=$((rows + 1))
  if [[ ! -f "${AN_ROOT_DIR}/${repo_path}" ]]; then
    missing=$((missing + 1))
    warn "payload missing: ${repo_path}"
  fi
done < "$MANIFEST"

info "Stage 07 config: ${rows} files to deploy; ${missing} missing from payload"
if (( missing > 0 )); then
  die "payload incomplete — the repository copy is broken; re-clone it"
fi
warn "not implemented in milestone 1 (skeleton) — stopping before any changes"
exit 90
