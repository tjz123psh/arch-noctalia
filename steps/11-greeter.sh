#!/usr/bin/env bash
# steps/11-greeter.sh — Stage 11: greetd + nwg-hello login.
# 计划（后续里程碑实现）：
#   1) 配置与资产（/etc/greetd/config.toml、/etc/nwg-hello/*、头像、登录背景）
#      由 07 按 files.tsv 部署；
#   2) 启用 greetd（替换 tty1 getty / 与 nwg-hello 配合）；
#   3) 登录背景同步（壁纸 → /etc/nwg-hello/background.png 的 hook）。
# 现状：里程碑 1 = 骨架。只做只读校验，然后明确停止（不会改动系统）。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator
machine="${AN_MACHINE:?AN_MACHINE is required (set by install.sh)}"
: "$machine"

MANIFEST="${AN_ROOT_DIR}/manifests/files.tsv"
[[ -f "$MANIFEST" ]] || die "missing manifest: ${MANIFEST}"

greeter_rows=0
while IFS=$'\t' read -r repo_path target _mode _md5; do
  if [[ -z "$repo_path" || "$repo_path" == "#"* ]]; then
    continue
  fi
  case "$target" in
    /etc/greetd/*|/etc/nwg-hello/*|/var/lib/avatars/*) greeter_rows=$((greeter_rows + 1)) ;;
  esac
done < "$MANIFEST"

info "Stage 11 greeter: ${greeter_rows} greeter-related files in files.tsv; greetd enable planned"
warn "not implemented in milestone 1 (skeleton) — stopping before any changes"
exit 90
