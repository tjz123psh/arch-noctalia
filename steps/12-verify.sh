#!/usr/bin/env bash
# steps/12-verify.sh — Stage 12: post-install self check（只读）。
# 对照 manifests/files.tsv 检查每个目标路径存在、是常规文件、md5 与记录一致；
# 对照 manifests/packages.tsv（同一套机型/模块过滤）检查缺失的包。
# 全部通过 → 0；有缺失/不一致 → 1（并逐条列出）。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator
machine="${AN_MACHINE:?AN_MACHINE is required (set by install.sh)}"

FILES="${AN_ROOT_DIR}/manifests/files.tsv"
PACKAGES="${AN_ROOT_DIR}/manifests/packages.tsv"
[[ -f "$FILES" ]] || die "missing manifest: ${FILES}"
[[ -f "$PACKAGES" ]] || die "missing manifest: ${PACKAGES}"

info "Stage 12 verify: checking deployed files against files.tsv"
checked=0
okc=0
bad=0
miss=0
while IFS=$'\t' read -r _repo_path target _mode md5; do
  if [[ -z "$target" || "$target" == "#"* ]]; then
    continue
  fi
  checked=$((checked + 1))
  if [[ ! -e "$target" ]]; then
    miss=$((miss + 1))
    warn "missing: ${target}"
    continue
  fi
  if [[ ! -f "$target" ]]; then
    bad=$((bad + 1))
    warn "not a regular file: ${target}"
    continue
  fi
  actual="$(md5sum "$target" | awk '{print $1}')"
  if [[ "$actual" == "$md5" ]]; then
    okc=$((okc + 1))
  else
    bad=$((bad + 1))
    warn "md5 mismatch: ${target}"
  fi
done < "$FILES"
printf '[info]  files: %d checked, %d ok, %d mismatched, %d missing\n' "$checked" "$okc" "$bad" "$miss"

info "Stage 12 verify: checking packages against packages.tsv"
pk_checked=0
pk_missing=0
while IFS=$'\t' read -r pkg _repo module _purpose; do
  if [[ -z "$pkg" || "$pkg" == "#"* ]]; then
    continue
  fi
  case "${module:-}" in
    vmware-guest) [[ "$machine" == "vm" ]] || continue ;;
    physical-only) [[ "$machine" == "physical" ]] || continue ;;
  esac
  pk_checked=$((pk_checked + 1))
  if ! pacman -Q "$pkg" >/dev/null 2>&1; then
    pk_missing=$((pk_missing + 1))
    warn "package missing: ${pkg}"
  fi
done < "$PACKAGES"
printf '[info]  packages: %d checked, %d missing\n' "$pk_checked" "$pk_missing"

if (( bad > 0 || miss > 0 || pk_missing > 0 )); then
  error "Stage 12 verify: FAIL"
  exit 1
fi
ok "Stage 12 verify: all files and packages match"
