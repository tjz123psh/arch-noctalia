#!/usr/bin/env bash
# steps/09-noctalia.sh — Stage 09: Noctalia settings + plugins + cursor-track.
# 计划（后续里程碑实现）：
#   1) 校验插件源目录（payload/plugins → ~/noctalia-plugins，实体文件经 07/08 部署）；
#   2) 构建 cursor-track（gcc + wayland-scanner + wayland-protocols + wlr-layer-shell xml）；
#   3) 校验 Noctalia 设置（settings.toml 的插件源/启用列表，经 07 部署）生效。
# 现状：里程碑 1 = 骨架。只做只读校验，然后明确停止（不会改动系统）。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator
machine="${AN_MACHINE:?AN_MACHINE is required (set by install.sh)}"
: "$machine"

PLUGINS_DIR="${AN_ROOT_DIR}/payload/home/noctalia-plugins"
[[ -d "$PLUGINS_DIR" ]] || die "payload/home/noctalia-plugins missing — regenerate the payload first"
plugin_files="$(find "$PLUGINS_DIR" -type f | wc -l | tr -d ' ')"
info "Stage 09 noctalia: ${plugin_files} plugin files in payload; cursor-track build planned"

BUILD_SH="${PLUGINS_DIR}/magnifier/tools/cursor-track/build.sh"
if [[ -f "$BUILD_SH" ]]; then
  ok "cursor-track build script: present"
else
  warn "cursor-track build script not found at expected path (will be finalized with the payload)"
fi

warn "not implemented in milestone 1 (skeleton) — stopping before any changes"
exit 90
