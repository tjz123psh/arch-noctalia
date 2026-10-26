#!/usr/bin/env bash
# steps/12-verify.sh — Stage 12: post-install self check（只读）。
# 对照 manifests/files.tsv 检查每个目标路径存在、是常规文件、md5 与记录一致
#   （seed 行：个人数据种子，只核对存在性、跳过内容核对——内容可能被用户编辑；
#    系统文件普通用户读不到时回退 root 读——ESP/0077 掩码场景，见 lib/common.sh）；
# 对照 manifests/packages.tsv（同一套机型/模块过滤）检查缺失的包；
# 对照 manifests/bin-links.tsv 检查 ~/bin 软链层（存在且可执行）；
# 服务状态清点：所管服务必须 enabled；当前未运行只提示不算失败（可能待重启/无硬件）；
#   另核对 snapper-timeline.timer 的生效日历=每周（07 部署的 drop-in 覆盖上游 hourly）；
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
load_runtime_targets

info "Stage 12 verify: checking deployed files against files.tsv"
checked=0
okc=0
bad=0
miss=0
seeded=0
runtime=0
while IFS=$'\t' read -r repo_path raw_target mode md5; do
  if [[ -z "$raw_target" || "$raw_target" == "#"* ]]; then
    continue
  fi
  # 与 07 用同一条解析（白名单 + 可选 AN_TARGET_ROOT 沙箱重写），保证沙箱演练两端一致。
  if ! target="$(an_resolve_target "$raw_target")"; then
    bad=$((bad + 1))
    continue
  fi
  ftype="$(t_type "$target")"
  # seed（个人数据种子）：用户可能已编辑——只核对存在性，内容不做核对（缺失仍计入失败）。
  if [[ -n "${AN_SEED[$repo_path]:-}" ]]; then
    if [[ -z "$ftype" ]]; then
      miss=$((miss + 1))
      warn "missing (seed): ${target}"
    else
      seeded=$((seeded + 1))
    fi
    continue
  fi
  # 运行时重写文件（Noctalia 主题产物、登录背景同步 hook 等）：机器用过之后内容必然变，
  # 只核对存在性；否则 --redo 12 / 自检会永远报"安装失败"。
  if [[ -n "${AN_RUNTIME[$repo_path]:-}" ]]; then
    if [[ -z "$ftype" ]]; then
      miss=$((miss + 1))
      warn "missing (runtime-managed): ${target}"
    else
      runtime=$((runtime + 1))
    fi
    continue
  fi
  checked=$((checked + 1))
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
  if [[ "$actual" != "$md5" ]]; then
    bad=$((bad + 1))
    warn "md5 mismatch: ${target}"
    continue
  fi
  # 内容对了还要看权限位（只有支持 Unix 权限位的文件系统才核；vfat/ESP 由挂载选项决定）。
  if fs_has_unix_perms "$(fs_of_target "$target")" && [[ "$(t_perms "$target")" != "$mode" ]]; then
    bad=$((bad + 1))
    warn "mode mismatch (on disk $(t_perms "$target"), manifest ${mode}): ${target}"
    continue
  fi
  okc=$((okc + 1))
done < "$FILES"
summary "$(printf 'files: %d checked, %d ok, %d mismatched, %d missing' "$checked" "$okc" "$bad" "$miss")"
if (( seeded > 0 )); then
  info "seed files (user data): existence checked, content skipped: ${seeded}"
fi
if (( runtime > 0 )); then
  info "runtime-regenerated files (themed by the desktop): existence checked, content skipped: ${runtime}"
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
summary "$(printf 'packages: %d checked, %d missing' "$pk_checked" "$pk_missing")"

# AUR/foreign 包：只核 aur.tsv 里 role=explicit 的那些（dependency 条目由 explicit 传递带入）。
# 05 步没跑过（--no-aur / 只跑了部分阶段）时不核，否则会把「用户主动跳过」误报成安装失败。
info "Stage 12 verify: checking AUR packages against aur.tsv"
AUR="${AN_ROOT_DIR}/manifests/aur.tsv"
aur_checked=0
aur_missing=0
if [[ -f "$AUR" ]] && grep -qx '05' "${AN_STATE_DIR}/steps.done" 2>/dev/null; then
  while IFS=$'\t' read -r pkg _channel role _purpose; do
    if [[ -z "$pkg" || "$pkg" == "#"* || "${role:-}" != "explicit" ]]; then
      continue
    fi
    aur_checked=$((aur_checked + 1))
    if ! pacman -Q "$pkg" >/dev/null 2>&1; then
      aur_missing=$((aur_missing + 1))
      warn "aur package missing: ${pkg}"
    fi
  done < "$AUR"
  summary "$(printf 'aur: %d checked, %d missing' "$aur_checked" "$aur_missing")"
else
  info "aur: stage 05 is not recorded as done - skipped (--no-aur or partial run)"
fi

info "Stage 12 verify: misc (user dirs, login shell)"
misc_bad=0
for d in Desktop Documents Downloads Music Videos Public Projects Templates Pictures/Screenshots; do
  if [[ ! -d "$HOME/$d" ]]; then
    misc_bad=$((misc_bad + 1))
    warn "missing user dir: ~/${d}"
  fi
done
me="$(id -un)"
if [[ "$(getent passwd "$me" | cut -d: -f7)" != "/usr/bin/fish" ]]; then
  misc_bad=$((misc_bad + 1))
  warn "login shell is not fish: $(getent passwd "$me" | cut -d: -f7)"
fi
# 09 步编译的光标传感器：不在 files.tsv 里（是构建产物），magnifier 插件靠它拿光标位置。
if [[ ! -x "$HOME/bin/cursor-track" ]]; then
  misc_bad=$((misc_bad + 1))
  warn "missing or not executable: ~/bin/cursor-track (built by stage 09)"
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
summary "$(printf 'links: %d checked, %d bad' "$links_checked" "$links_bad")"

info "Stage 12 verify: service states (enabled = required; not running now = reported only)"
svc_required=(docker.service bluetooth.service)
# 热点转发自动补（10 步启用、挂在 docker.service 上）：装了 docker 且单元存在，就必须是 enabled。
if systemctl cat docker.service >/dev/null 2>&1 && systemctl cat rice-hotspot-net-sync.service >/dev/null 2>&1; then
  svc_required+=(rice-hotspot-net-sync.service)
fi
# NetworkManager 存在就该是 enabled（archinstall 默认启用；热点/网络页签都靠它）。
if systemctl cat NetworkManager.service >/dev/null 2>&1; then
  svc_required+=(NetworkManager.service)
fi
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
# 生效日历核对：snapper timeline 必须是每周一次（07 部署的 /etc drop-in 覆盖上游 hourly）。
svc_sched_bad=0
if systemctl cat snapper-timeline.timer >/dev/null 2>&1; then
  cal="$(systemctl show -p TimersCalendar --value snapper-timeline.timer 2>/dev/null || true)"
  cal_entries="$(awk -F'OnCalendar=' '{print NF-1}' <<<"$cal")"
  if [[ "$cal_entries" != "1" || "$cal" != *'OnCalendar=Mon *-*-* 00:00:00'* ]]; then
    svc_sched_bad=1
    warn "snapper-timeline.timer is not weekly (expected exactly one weekly OnCalendar): ${cal:-<empty>}"
  fi
fi
summary "$(printf 'services: %d checked, %d not enabled, %d enabled-but-inactive, %d wrong schedule' "${#svc_required[@]}" "$svc_bad" "${#svc_inactive[@]}" "$svc_sched_bad")"
if (( ${#svc_inactive[@]} > 0 )); then
  info "note: enabled but not running right now (may be deferred to reboot / hardware-dependent): ${svc_inactive[*]}"
fi

# supergfxd.conf 是 runtime 名单（只核存在），但 hotplug_type=Asus 是安装器必须保证的值：单独抽查。
if [[ -e /etc/supergfxd.conf ]] && ! grep -q '"hotplug_type": "Asus"' /etc/supergfxd.conf 2>/dev/null; then
  misc_bad=$((misc_bad + 1))
  warn "supergfxd.conf does not carry hotplug_type=Asus - switching to iGPU will bounce back to Hybrid after reboot"
fi

# ACL 抽查：登录背景由 rice-login-bg 以普通用户身份改写，靠 11 步加、07 重跑的 u:<user>:rw。
# 丢了 ACL 不会让任何文件缺失，但换壁纸会静默失败——这种"看不见的坏"正是自检该管的。
if [[ -e /etc/nwg-hello/background.png ]] && have getfacl; then
  if getfacl -p /etc/nwg-hello/background.png 2>/dev/null | grep -q "^user:${me}:rw-"; then
    info "acl: background.png carries u:${me}:rw"
  else
    misc_bad=$((misc_bad + 1))
    warn "acl missing: /etc/nwg-hello/background.png has no u:${me}:rw - rice-login-bg cannot rewrite it"
  fi
fi

if (( bad > 0 || miss > 0 || pk_missing > 0 || aur_missing > 0 || misc_bad > 0 || links_bad > 0 || svc_bad > 0 || svc_sched_bad > 0 )); then
  error "Stage 12 verify: FAIL"
  exit 1
fi
ok "Stage 12 verify: all files, packages, links and service states verified"
