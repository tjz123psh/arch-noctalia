#!/usr/bin/env bash
set -euo pipefail
ROOT=/tmp/lead-regress
TMP_DIR=$(mktemp -d)
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; exit 1; }

test_migration_failure_status() {
  source "$ROOT/migration-pack"
  local dir="$TMP_DIR/migration"
  mkdir -p "$dir"
  printf 'bash\n' > "$dir/pkglist-explicit.txt"
  : > "$dir/pkglist-foreign.txt"
  : > "$dir/system-enabled-units.txt"
  : > "$dir/user-enabled-units.txt"
  : > "$dir/tar-manifest.txt"
  printf 'broken archive\n' > "$dir/pang-arch-configs.tar.gz"
  printf '00  missing\n' > "$dir/SHA256SUMS"
  echo "  [repro] before run_check"
  if run_check "$dir" >/dev/null; then
    fail 'corrupt migration package must return nonzero'
  fi
  echo "  [repro] before pass"
  pass 'corrupt migration package returns nonzero'
}

run_selected() { local name="$1"; "$name"; }
echo "--- 直接调用 ---"
test_migration_failure_status
echo "--- 经包装函数调用 ---"
run_selected test_migration_failure_status
echo DONE
rm -rf "$TMP_DIR"
