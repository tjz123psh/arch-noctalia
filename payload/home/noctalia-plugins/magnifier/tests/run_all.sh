#!/usr/bin/env bash
# Offline only: Lua IO is mocked, and the C test never connects to Wayland.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
TMP="$(mktemp -d /tmp/magnifier-lease-tests.XXXXXXXXXX)"
case "$TMP" in /tmp/magnifier-lease-tests.*) ;; *) exit 1 ;; esac
cleanup() {
  local status=$?
  trap - EXIT
  if [[ -d "$TMP" && ! -L "$TMP" ]]; then
    rm -f -- "$TMP/lease-test"
    rmdir -- "$TMP"
  fi
  exit "$status"
}
trap cleanup EXIT
lua "$ROOT/magnifier/tests/magnifier_spec.lua" "$ROOT/magnifier/panel.luau"
gcc -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/magnifier/tests/tracker_lease_spec.c" -o "$TMP/lease-test"
"$TMP/lease-test"
noctalia plugins lint "$ROOT/magnifier"
