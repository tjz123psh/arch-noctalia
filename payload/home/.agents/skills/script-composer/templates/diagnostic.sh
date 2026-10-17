#!/usr/bin/env bash
# 描述：系统诊断脚本模板
# Description: System diagnostic script template

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: script-name [options]

Options:
  -h, --help    显示帮助并退出

说明:
  只读诊断脚本，不修改系统配置。
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    printf '错误: 未知参数: %s\n' "$1" >&2
    usage >&2
    exit 2
    ;;
esac

BOLD=$'\033[1m'
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
CYAN=$'\033[36m'
NC=$'\033[0m'

if [[ ! -t 1 ]]; then
  BOLD=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; NC=""
fi

ok() { printf '%sOK%s    %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%sWARN%s  %s\n' "$YELLOW" "$NC" "$*"; }
miss() { printf '%sMISS%s  %s\n' "$RED" "$NC" "$*"; }
info() { printf '%sINFO%s  %s\n' "$CYAN" "$NC" "$*"; }

section() {
  printf '\n%s== %s ==%s\n' "$BOLD" "$1" "$NC"
}

check_cmd() {
  local cmd="$1"
  local why="$2"

  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd - $why"
  else
    miss "$cmd - $why"
  fi
}

check_service() {
  local unit="$1"
  local label="${2:-$unit}"
  local scope="${3:-system}"
  local state

  if [[ "$scope" == "user" ]]; then
    state="$(systemctl --user is-active "$unit" 2>/dev/null || true)"
  else
    state="$(systemctl is-active "$unit" 2>/dev/null || true)"
  fi

  case "$state" in
    active) ok "$label active" ;;
    inactive|failed) warn "$label $state" ;;
    *) info "$label ${state:-not-found}" ;;
  esac
}

main() {
  section "基础工具"
  check_cmd systemctl "服务状态检查"
  check_cmd journalctl "日志查看"

  section "服务状态"
  check_service NetworkManager.service "NetworkManager"
}

main
