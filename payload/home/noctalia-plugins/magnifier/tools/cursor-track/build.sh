#!/usr/bin/env bash
# cursor-track — 全屏透明覆盖层，把指针位置写进文件（给 pang/magnifier 插件当光标传感器）
#   构建：./build.sh            → build/cursor-track
#   安装：./build.sh install    → ~/bin/cursor-track
# 依赖：gcc、wayland（含 wayland-scanner）、wayland-protocols、pkg-config
set -e
cd "$(dirname "$0")"
OUT=build
PROTOCOL=protocols/wlr-layer-shell-unstable-v1.xml
# 协议随仓库提供，build/ 仅放可再生的构建产物；不在构建时联网下载。
if [ ! -r "$PROTOCOL" ]; then
  printf '缺少协议源码：%s；请恢复完整的 protocols/ 目录。\n' "$PROTOCOL" >&2
  exit 1
fi
mkdir -p "$OUT"
wayland-scanner client-header "$PROTOCOL" "$OUT/wlr-layer-shell-unstable-v1.h"
wayland-scanner private-code  "$PROTOCOL" "$OUT/wlr-layer-shell-unstable-v1.c"
wayland-scanner client-header /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml "$OUT/xdg-shell.h"
wayland-scanner private-code  /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml "$OUT/xdg-shell.c"
gcc -O2 -Wall -I"$OUT" -o "$OUT/cursor-track" cursor-track.c \
    "$OUT/wlr-layer-shell-unstable-v1.c" "$OUT/xdg-shell.c" $(pkg-config --cflags --libs wayland-client)
echo "构建完成: $(pwd)/$OUT/cursor-track"
if [ "${1:-}" = "install" ]; then
  install -m755 "$OUT/cursor-track" "$HOME/bin/cursor-track"
  echo "已安装: ~/bin/cursor-track"
fi
