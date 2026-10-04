#!/usr/bin/env bash
# test-bootstrap.sh — bootstrap 冒烟：本地路径源 → git clone → 交接 install.sh --preview。
# 说明：clone 取的是 git HEAD（未提交的工作树改动不在克隆内）——干净工作树上最有意义。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$(mktemp -d)"
trap 'rm -rf "$dest"' EXIT

if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
  echo "[warn] working tree is dirty — the clone tests committed HEAD only"
fi

set +e
out="$(bash "$ROOT/bootstrap.sh" --src "$ROOT" --dest "$dest/repo" -- --preview 2>&1)"
rc=$?
set -e
printf '%s\n' "$out"
[ "$rc" -eq 0 ] || { echo "bootstrap rc=${rc}"; exit 1; }
printf '%s\n' "$out" | grep -q 'preview OK' || { echo "handover did not reach 'preview OK'"; exit 1; }
[ -d "$dest/repo/.git" ] || { echo "clone did not produce a git repo"; exit 1; }

echo "ok: bootstrap cloned the local source and the clone ran preview OK"
