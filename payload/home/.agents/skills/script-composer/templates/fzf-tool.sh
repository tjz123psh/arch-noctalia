#!/usr/bin/env bash
# 描述：fzf 交互脚本模板
# Description: fzf interactive script template

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: script-name [options]

Options:
  -p, --print   只打印候选项，不进入 fzf
  -h, --help    显示帮助并退出
EOF
}

PRINT_ONLY=false

# --- 参数解析 ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--print)
      PRINT_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '错误: 未知参数: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$PRINT_ONLY" == false ]] && ! command -v fzf >/dev/null 2>&1; then
  printf '错误: 缺少依赖: fzf\n' >&2
  exit 127
fi

BOLD=$'\033[1m'
CYAN=$'\033[36m'
NC=$'\033[0m'

if [[ ! -t 1 || "$PRINT_ONLY" == true ]]; then
  BOLD=""; CYAN=""; NC=""
fi

build_items() {
  printf '%s\n' \
    "item-1"$'\t'"说明 1" \
    "item-2"$'\t'"说明 2"
}

items="$(build_items)"
if [[ -z "$items" ]]; then
  printf '错误: 没有可选择项目\n' >&2
  exit 1
fi

if [[ "$PRINT_ONLY" == true ]]; then
  printf '%s\n' "$items"
  exit 0
fi

set +e
selection="$(
  printf '%s\n' "$items" |
    fzf \
      --ansi \
      --height=95% \
      --layout=reverse \
      --border=rounded \
      --preview-window='down,55%,border-top,wrap' \
      --prompt='选择: '
)"
fzf_status=$?
set -e

case "$fzf_status" in
  0) ;;
  1|130) exit 0 ;;
  *)
    printf '错误: fzf 失败，退出码 %s\n' "$fzf_status" >&2
    exit "$fzf_status"
    ;;
esac

printf '%s选中:%s %s\n' "$BOLD$CYAN" "$NC" "$selection"
