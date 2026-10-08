#!/usr/bin/env bash
# 运行 sidebar 插件的全部离线检查：不启动桌面程序、不播放媒体、不写入用户数据。
# 用法：bash sidebar/tests/run_all.sh
set -euo pipefail
cd -- "$(dirname -- "$0")/../.."

echo "== 语法检查 =="
lua -e 'assert(loadfile("sidebar/panel.luau"))'
echo "panel.luau 语法正常"

echo
echo "== 离线回归 =="
lua sidebar/tests/sidebar_spec.lua
lua sidebar/tests/regressions_spec.lua
lua sidebar/tests/async_spec.lua
python3 sidebar/tests/shell_spec.py

echo
echo "== 性能基准（仅打印，不与基线比较）=="
lua sidebar/tests/benchmark.lua

echo
if command -v noctalia >/dev/null 2>&1; then
  echo "== 宿主静态检查 =="
  noctalia plugins lint sidebar
else
  echo "跳过宿主静态检查：未找到 noctalia 命令"
fi
