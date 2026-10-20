#!/usr/bin/env bash
set -euo pipefail
entry='pang/tide-sidebar:backend'
case "${1:-}" in
  '') exec noctalia msg plugin "$entry" all toggle ;;
  notes|tools|hotspot|windows) exec noctalia msg plugin "$entry" all show "$1" ;;
  calculator|timer) exec noctalia msg plugin "$entry" all show tools ;;
  home) exec noctalia msg plugin "$entry" all show notes ;;
  hide) exec noctalia msg plugin "$entry" all hide ;;
  *) printf '用法: bash tide-sidebar/open.sh [notes|tools|hotspot|windows|hide]\n' >&2; exit 2 ;;
esac
