#!/usr/bin/env bash
# steps/05-aur.sh — Stage 05: AUR / foreign packages.
# 读 manifests/aur.tsv：role=explicit 逐个安装（aur → paru 非 root，其余 → pacman）；
# role=dependency 不主动装，结尾只核对并 warn；单个失败不中断，结尾汇总。
# 幂等：已装过滤；paru 需先按手动 §9.1 备好。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator
machine="${AN_MACHINE:?AN_MACHINE is required (set by install.sh)}"

MANIFEST="${AN_ROOT_DIR}/manifests/aur.tsv"
[[ -f "$MANIFEST" ]] || die "missing manifest: ${MANIFEST}"

explicit_total=0
aur_pending=()
repo_pending=()
deps=()
while IFS=$'\t' read -r pkg channel role _purpose; do
  if [[ -z "$pkg" || "$pkg" == "#"* ]]; then
    continue
  fi
  case "${role:-}" in
    explicit)
      explicit_total=$((explicit_total + 1))
      if ! pacman -Q "$pkg" >/dev/null 2>&1; then
        if [[ "${channel:-}" == "aur" ]]; then
          aur_pending+=("$pkg")
        else
          repo_pending+=("$pkg")
        fi
      fi
      ;;
    dependency)
      deps+=("$pkg")
      ;;
    *)
      warn "unknown role '${role:-}' for ${pkg} in aur.tsv — ignored"
      ;;
  esac
done < "$MANIFEST"

if (( ${#aur_pending[@]} == 0 && ${#repo_pending[@]} == 0 )); then
  ok "Stage 05 aur: nothing to do"
else
  if (( ${#aur_pending[@]} > 0 )) && ! have paru; then
    die "paru is required for AUR packages but was not found — complete the manual §9.1 (archlinuxcn + paru), then re-run."
  fi
  info "selected ${explicit_total} explicit packages; ${#aur_pending[@]} AUR + ${#repo_pending[@]} repo still to install (machine=${machine})"
  confirm "Install ${#aur_pending[@]} AUR + ${#repo_pending[@]} repo packages now?" || die "declined"
  failed=()
  for pkg in "${repo_pending[@]}"; do
    info "installing repo package: ${pkg}"
    if ! as_root pacman -S --needed --noconfirm "$pkg"; then
      warn "install failed: ${pkg} (repo)"
      failed+=("$pkg")
    fi
  done
  # paru 必须以当前用户运行（AUR 构建不允许 root），因此不加 sudo。
  for pkg in "${aur_pending[@]}"; do
    info "installing AUR package: ${pkg}"
    if ! paru -S --needed --noconfirm --skipreview "$pkg"; then
      warn "install failed: ${pkg} (aur)"
      failed+=("$pkg")
    fi
  done
  if (( ${#failed[@]} > 0 )); then
    for pkg in "${failed[@]}"; do
      error "failed package: ${pkg}"
    done
    die "${#failed[@]} package(s) failed to install — fix the cause and re-run (already-installed packages are skipped)"
  fi
  ok "Stage 05 aur: done"
fi

# role=dependency：不主动安装，只在结尾核对；缺的仅提示（可能由显式包带入）。
missing_deps=()
for dep in "${deps[@]}"; do
  if ! pacman -Q "$dep" >/dev/null 2>&1; then
    missing_deps+=("$dep")
  fi
done
if (( ${#missing_deps[@]} > 0 )); then
  for dep in "${missing_deps[@]}"; do
    warn "dependency not installed: ${dep} (expected as a dependency of an explicit package)"
  done
fi
