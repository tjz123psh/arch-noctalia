#!/usr/bin/env bash
# cursor-track — 全屏透明覆盖层，把指针位置写进文件（给 pang/magnifier 插件当光标传感器）
#   构建：./build.sh            → build/cursor-track
#   安装：./build.sh install    → ~/bin/cursor-track
# 依赖：gcc、wayland（含 wayland-scanner）、wayland-protocols、pkg-config
set -e
cd "$(dirname "$0")"
OUT=build
mkdir -p "$OUT"
if [ ! -f "$OUT/wlr-layer-shell-unstable-v1.xml" ]; then
  curl -sL -o "$OUT/wlr-layer-shell-unstable-v1.xml" \
    https://raw.githubusercontent.com/swaywm/wlroots/master/protocol/wlr-layer-shell-unstable-v1.xml
fi
wayland-scanner client-header "$OUT/wlr-layer-shell-unstable-v1.xml" "$OUT/wlr-layer-shell-unstable-v1.h"
wayland-scanner private-code  "$OUT/wlr-layer-shell-unstable-v1.xml" "$OUT/wlr-layer-shell-unstable-v1.c"
wayland-scanner client-header /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml "$OUT/xdg-shell.h"
wayland-scanner private-code  /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml "$OUT/xdg-shell.c"
gcc -O2 -Wall -I"$OUT" -o "$OUT/cursor-track" cursor-track.c \
    "$OUT/wlr-layer-shell-unstable-v1.c" "$OUT/xdg-shell.c" $(pkg-config --cflags --libs wayland-client)
echo "构建完成: $(pwd)/$OUT/cursor-track"
if [ "${1:-}" = "install" ]; then
  install -m755 "$OUT/cursor-track" "$HOME/bin/cursor-track"
  echo "已安装: ~/bin/cursor-track"
fi
