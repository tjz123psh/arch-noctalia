#!/usr/bin/env bash
# steps/09-noctalia.sh — Stage 09: Noctalia settings + plugins + cursor-track.
# 目的：1) 校验插件源目录（~/noctalia-plugins，经 07 部署；magnifier + tide-sidebar）
#          与 tide-sidebar 原生前端运行时（gjs / libgtk4-layer-shell.so）；
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
  "${PLUGINS_DIR}/magnifier/plugin.toml"
  "${PLUGINS_DIR}/magnifier/panel.luau"
  "${PLUGINS_DIR}/magnifier/tools/cursor-track/build.sh"
  "${PLUGINS_DIR}/magnifier/tools/cursor-track/cursor-track.c"
  # tide-sidebar：Lua 服务层 + 原生 GTK4 前端（缺任何一件侧栏都起不来，这里一并预检）
  "${PLUGINS_DIR}/tide-sidebar/plugin.toml"
  "${PLUGINS_DIR}/tide-sidebar/panel.luau"
  "${PLUGINS_DIR}/tide-sidebar/widget.luau"
  "${PLUGINS_DIR}/tide-sidebar/shortcut.luau"
  "${PLUGINS_DIR}/tide-sidebar/service.luau"
  "${PLUGINS_DIR}/tide-sidebar/lib/frontend.luau"
  "${PLUGINS_DIR}/tide-sidebar/lib/notes.luau"
  "${PLUGINS_DIR}/tide-sidebar/lib/calculator.luau"
  "${PLUGINS_DIR}/tide-sidebar/lib/countdown.luau"
  "${PLUGINS_DIR}/tide-sidebar/lib/stopwatch.luau"
  "${PLUGINS_DIR}/tide-sidebar/native/main.js"
  "${PLUGINS_DIR}/tide-sidebar/native/ui.js"
  "${PLUGINS_DIR}/tide-sidebar/native/palette.js"
  "${PLUGINS_DIR}/tide-sidebar/native/transport.mjs"
  "${PLUGINS_DIR}/tide-sidebar/native/style.css"
  "${PLUGINS_DIR}/tide-sidebar/native/views/home.js"
  "${PLUGINS_DIR}/tide-sidebar/native/views/notes.js"
  "${PLUGINS_DIR}/tide-sidebar/native/views/tools.js"
  "${PLUGINS_DIR}/tide-sidebar/native/views/system.js"
  "${PLUGINS_DIR}/tide-sidebar/helpers/system.py"
  "${PLUGINS_DIR}/tide-sidebar/open.sh"
)
missing=0
for f in "${plugin_files[@]}"; do
  if [[ ! -f "$f" ]]; then
    warn "plugin file missing: ${f}"
    missing=$((missing + 1))
  fi
done
(( missing == 0 )) || die "plugins are not deployed under ${PLUGINS_DIR} — stage 07 must run first; re-run ./install.sh --run"
info "plugin sources: present (magnifier + tide-sidebar)"

# --- 1b) tide-sidebar 原生前端运行时依赖 ---
# 侧栏是 gjs 直接吃 Gtk4 + layer-shell 的：gjs 缺失或 libgtk4-layer-shell.so 不可用，
# Super+Shift+W 会静默无反应（只在插件日志里报“原生侧栏无法启动”），所以提前硬拦。
have gjs || die "gjs not found — tide-sidebar native frontend needs it (stage 03 must install gjs)"
[[ -f /usr/lib/libgtk4-layer-shell.so ]] \
  || die "missing /usr/lib/libgtk4-layer-shell.so — gtk4-layer-shell package is required by tide-sidebar"
ok "tide-sidebar: gjs + libgtk4-layer-shell present"

# --- 2) settings.toml 存在性（内容属用户态，不校验） ---
# 这个文件在 manifests/seed.tsv 里：Noctalia 面板会实时改写它（关插件、改顺序、换插件源都是正常操作）。
# 所以这里只要求文件在，不比对内容——否则用户动过设置后 --redo 09 会误判"仓库副本坏了"并中止。
[[ -f "$SETTINGS" ]] || die "missing settings: ${SETTINGS} (stage 07 must deploy it)"
info "settings: present (content is user-managed - not validated)"

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
    die "cursor-track build failed - removed the build/ cache; re-run ./install.sh --run"
  fi
  [[ -x "$BIN" ]] || die "cursor-track build failed (no binary at ${BIN})"
  ok "cursor-track: built and installed"
else
  info "cursor-track: up to date"
fi

ok "Stage 09 noctalia: done"
