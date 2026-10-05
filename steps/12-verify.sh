#!/usr/bin/env bash
# steps/12-verify.sh — Stage 12: post-install self check（只读）。
# 对照 manifests/files.tsv 检查每个目标路径存在、是常规文件、md5 与记录一致
#   （seed 行除外：那是个人数据种子，内容可能被用户编辑，跳过内容核对；
#    系统文件普通用户读不到时回退 root 读——ESP/0077 掩码场景，见 lib/common.sh）；
# 对照 manifests/packages.tsv（同一套机型/模块过滤）检查缺失的包；
# 对照 manifests/bin-links.tsv 检查 ~/bin 软链层（存在且可执行）；
# 服务状态清点：所管服务必须 enabled；当前未运行只提示不算失败（可能待重启/无硬件）；
# 另抽查用户目录与登录 shell（与样本形态一致）。
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

load_seed_targets

info "Stage 12 verify: checking deployed files against files.tsv"
checked=0
okc=0
bad=0
miss=0
seeded=0
while IFS=$'\t' read -r repo_path target _mode md5; do
  if [[ -z "$target" || "$target" == "#"* ]]; then
    continue
  fi
  # seed（个人数据种子）：用户可能已编辑，内容不做核对。
  if [[ -n "${AN_SEED[$repo_path]:-}" ]]; then
    seeded=$((seeded + 1))
    continue
  fi
  checked=$((checked + 1))
  ftype="$(t_type "$target")"
  if [[ -z "$ftype" ]]; then
    miss=$((miss + 1))
    warn "missing: ${target}"
    continue
  fi
  if [[ "$ftype" != "regular file" ]]; then
    bad=$((bad + 1))
    warn "not a regular file: ${target}"
    continue
  fi
  actual="$(t_md5 "$target")"
  if [[ "$actual" == "$md5" ]]; then
    okc=$((okc + 1))
  else
    bad=$((bad + 1))
    warn "md5 mismatch: ${target}"
  fi
done < "$FILES"
printf '[info]  files: %d checked, %d ok, %d mismatched, %d missing\n' "$checked" "$okc" "$bad" "$miss"
if (( seeded > 0 )); then
  info "seed files skipped (user data — initialized only when missing): ${seeded}"
fi

info "Stage 12 verify: checking packages against packages.tsv"
pk_checked=0
pk_missing=0
while IFS=$'\t' read -r pkg _repo module _purpose; do
  if [[ -z "$pkg" || "$pkg" == "#"* ]]; then
    continue
  fi
  case "${module:-}" in
    drivers) [[ "$machine" == "physical" ]] || continue ;;   # 与 04 一致：驱动包仅物理机
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

info "Stage 12 verify: misc (user dirs, login shell)"
misc_bad=0
for d in Desktop Documents Downloads Music Videos Public Projects Templates Pictures/Screenshots; do
  if [[ ! -d "$HOME/$d" ]]; then
    misc_bad=$((misc_bad + 1))
    warn "missing user dir: ~/${d}"
  fi
done
if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "/usr/bin/fish" ]]; then
  misc_bad=$((misc_bad + 1))
  warn "login shell is not fish: $(getent passwd "$USER" | cut -d: -f7)"
fi

info "Stage 12 verify: checking ~/bin links against bin-links.tsv"
LINKS="${AN_ROOT_DIR}/manifests/bin-links.tsv"
links_checked=0
links_bad=0
if [[ -f "$LINKS" ]]; then
  while IFS=$'\t' read -r name _target; do
    if [[ -z "$name" || "$name" == "#"* ]]; then
      continue
    fi
    links_checked=$((links_checked + 1))
    # -x 会跟随软链：既管"链接在、目标在"，也管"目标可执行"。
    if [[ ! -x "$HOME/bin/${name}" ]]; then
      links_bad=$((links_bad + 1))
      warn "bin link missing or not executable: ~/bin/${name}"
    fi
  done < "$LINKS"
fi
printf '[info]  links: %d checked, %d bad\n' "$links_checked" "$links_bad"

info "Stage 12 verify: service states (enabled = required; not running now = reported only)"
svc_required=(docker.service bluetooth.service)
if [[ "$(findmnt -no FSTYPE / 2>/dev/null || true)" == "btrfs" ]]; then
  svc_required+=(snapper-timeline.timer snapper-cleanup.timer 'btrfs-scrub@-.timer')
  if have grub-btrfsd; then
    svc_required+=(grub-btrfsd.service)
  fi
fi
for u in asusd.service supergfxd.service; do
  if systemctl cat "$u" >/dev/null 2>&1; then
    svc_required+=("$u")
  fi
done
svc_bad=0
svc_inactive=()
for u in "${svc_required[@]}"; do
  if ! systemctl cat "$u" >/dev/null 2>&1; then
    svc_bad=$((svc_bad + 1))
    warn "service unit missing: ${u}"
    continue
  fi
  if ! systemctl is-enabled "$u" >/dev/null 2>&1; then
    svc_bad=$((svc_bad + 1))
    warn "service not enabled: ${u}"
    continue
  fi
  if ! systemctl is-active "$u" >/dev/null 2>&1; then
    svc_inactive+=("$u")
  fi
done
printf '[info]  services: %d checked, %d not enabled, %d enabled-but-inactive\n' "${#svc_required[@]}" "$svc_bad" "${#svc_inactive[@]}"
if (( ${#svc_inactive[@]} > 0 )); then
  info "note: enabled but not running right now (may be deferred to reboot / hardware-dependent): ${svc_inactive[*]}"
fi

if (( bad > 0 || miss > 0 || pk_missing > 0 || misc_bad > 0 || links_bad > 0 || svc_bad > 0 )); then
  error "Stage 12 verify: FAIL"
  exit 1
fi
ok "Stage 12 verify: all files, packages, links and service states verified"
