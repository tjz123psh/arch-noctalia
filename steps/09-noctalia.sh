#!/usr/bin/env bash
# steps/09-noctalia.sh — Stage 09: Noctalia settings + plugins + cursor-track.
# 目的：1) 校验插件源目录（~/noctalia-plugins，经 07 部署）；
#       2) 构建/更新 cursor-track 光标传感器（gcc + wayland-scanner，产物 ~/bin/cursor-track）；
#       3) 校验 settings.toml 里的插件源与启用列表（经 07 部署）。
# 幂等：二进制比源码新时跳过构建；重复运行安全。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator

have noctalia || die "noctalia CLI not found — stage 06 (desktop packages) must run first"

PLUGINS_DIR="${HOME}/noctalia-plugins"
SETTINGS="${HOME}/.local/state/noctalia/settings.toml"
BIN="${HOME}/bin/cursor-track"
SRC_DIR="${PLUGINS_DIR}/magnifier/tools/cursor-track"

# --- 1) 插件源目录 ---
plugin_files=(
  "${PLUGINS_DIR}/sidebar/plugin.toml"
  "${PLUGINS_DIR}/sidebar/panel.luau"
  "${PLUGINS_DIR}/magnifier/plugin.toml"
  "${PLUGINS_DIR}/magnifier/panel.luau"
  "${PLUGINS_DIR}/magnifier/tools/cursor-track/build.sh"
  "${PLUGINS_DIR}/magnifier/tools/cursor-track/cursor-track.c"
)
missing=0
for f in "${plugin_files[@]}"; do
  if [[ ! -f "$f" ]]; then
    warn "plugin file missing: ${f}"
    missing=$((missing + 1))
  fi
done
(( missing == 0 )) || die "plugins are not deployed under ${PLUGINS_DIR} — stage 07 must run first; re-run ./install.sh --run"
info "plugin sources: present (sidebar + magnifier)"

# --- 2) settings.toml 校验（插件源 + 启用列表） ---
[[ -f "$SETTINGS" ]] || die "missing settings: ${SETTINGS} (stage 07 must deploy it)"
settings_bad=0
grep -q '"pang/sidebar"' "$SETTINGS" || { warn "settings: pang/sidebar not in the enabled list"; settings_bad=$((settings_bad + 1)); }
grep -q '"pang/magnifier"' "$SETTINGS" || { warn "settings: pang/magnifier not in the enabled list"; settings_bad=$((settings_bad + 1)); }
grep -q 'location = "/home/pang/noctalia-plugins"' "$SETTINGS" || { warn "settings: local plugin source 'pang-dev' missing"; settings_bad=$((settings_bad + 1)); }
(( settings_bad == 0 )) || die "settings.toml does not match the payload — repository copy broken?"
info "settings: plugin source + enabled list look right"

# --- 3) cursor-track（构建产物不入仓，09 负责重建） ---
mkdir -p "${HOME}/bin"
need_build=0
if [[ ! -x "$BIN" ]]; then
  need_build=1
  info "cursor-track: not built yet"
else
  newer="$(find "$SRC_DIR" -maxdepth 1 -type f \( -name '*.c' -o -name 'build.sh' \) -newer "$BIN" -print -quit 2>/dev/null || true)"
  if [[ -n "$newer" ]]; then
    need_build=1
    info "cursor-track: source is newer than the binary"
  fi
fi

if (( need_build == 1 )); then
  have gcc || die "gcc not found — base-devel (stage 03) must be installed"
  have wayland-scanner || die "wayland-scanner not found (wayland package)"
  have pkg-config || die "pkg-config not found (pkgconf package)"
  [[ -f /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml ]] || die "wayland-protocols (xdg-shell.xml) not found"
  info "building cursor-track (gcc + wayland-scanner)"
  if ! ( cd "$SRC_DIR" && bash build.sh install ); then
    rm -rf "${SRC_DIR}/build"
    die "cursor-track build failed — removed the build/ cache; re-run ./install.sh --run"
  fi
  [[ -x "$BIN" ]] || die "cursor-track build failed (no binary at ${BIN})"
  ok "cursor-track: built and installed"
else
  info "cursor-track: up to date"
fi

ok "Stage 09 noctalia: done"
