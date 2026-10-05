#!/usr/bin/env bash
# steps/10-services.sh — Stage 10: enable services.
# 系统级：docker、bluetooth（enable --now）；btrfs（root 是 btrfs 时）：snapper 配置缺则按默认模板创建、
#   snapper-timeline.timer / snapper-cleanup.timer / grub-btrfsd.service / btrfs-scrub@-.timer 启用；
#   物理机驱动配套 asusd / supergfxd 若存在则启用；另把当前用户加入 docker 组（下次登录生效）。
# 用户级：rice-dnd.timer（单元文件由 07 部署；无用户总线时退化为手工 enable 软链）。
# 幂等与重跑修复：已启用的单元额外核对"当前是否在跑"——没在跑的会补一次启动尝试，
#   并区分"内核升级后待重启延期"、"systemd 条件不满足（如无硬件）"与"真故障"（只报告，不误判为成功）。
# 缺失（应由 03/06 的包提供）的单元/包在结尾汇总为失败；grub-btrfsd / asusd / supergfxd 为显式可选。
# 注：greetd 的启用归 11；本步骤不碰 tty1。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator

missing_units=()
inactive_units=()

# 单元是否为"条件跳过"（如无硬件时 ConditionPathIsDirectory 不满足）。
unit_condition_skipped() { # $1=unit
  [[ "$(systemctl show -p ConditionResult --value "$1" 2>/dev/null || true)" == "no" ]]
}

# 内核升级未重启的延期判定：运行中内核的模块已不在磁盘上（如 docker 需要 nf_tables）。
kernel_defer() {
  [[ ! -d "/usr/lib/modules/$(uname -r)" ]]
}

enable_system_unit() { # $1=unit
  local u="$1"
  if ! systemctl cat "$u" >/dev/null 2>&1; then
    warn "unit not found: ${u} (package missing?)"
    missing_units+=("$u")
    return 0
  fi
  if systemctl is-enabled "$u" >/dev/null 2>&1; then
    if systemctl is-active "$u" >/dev/null 2>&1; then
      info "already enabled and active: ${u}"
      return 0
    fi
    # 已启用但当前没在跑：补一次启动尝试（重跑修复场景），并区分三种结果。
    as_root systemctl start "$u" >/dev/null 2>&1 || true
    if systemctl is-active "$u" >/dev/null 2>&1; then
      ok "was enabled but not running — started now: ${u}"
    elif kernel_defer; then
      warn "${u}: enabled; start deferred — the running kernel's modules were replaced by the upgrade; it will start after reboot"
    elif unit_condition_skipped "$u"; then
      warn "${u}: enabled; condition not met (no matching hardware?) — systemd skips it"
    else
      warn "${u}: enabled but still not running (see: systemctl status ${u})"
      inactive_units+=("$u")
    fi
    return 0
  fi
  if as_root systemctl enable --now "$u"; then
    ok "enabled: ${u}"
  elif kernel_defer; then
    # 刚升级过内核但尚未重启：单元保持 enabled，启动自动延期到重启之后。
    warn "${u}: start deferred — the running kernel's modules were replaced by the upgrade; it will start after reboot"
    systemctl is-enabled "$u" >/dev/null 2>&1 || missing_units+=("$u")
  elif unit_condition_skipped "$u"; then
    # 条件不满足（如无蓝牙控制器）：enable 已生效，启动被 systemd 跳过——硬件就绪后会自动启动。
    warn "${u}: enabled; condition not met (no matching hardware?) — systemd skips it"
  else
    die "failed to start ${u} (see: systemctl status ${u})"
  fi
}

# --- 基础服务 ---
enable_system_unit docker.service
enable_system_unit bluetooth.service

# --- 物理机驱动配套（由 04 的包提供；本机不存在则跳过） ---
for u in asusd.service supergfxd.service; do
  if systemctl cat "$u" >/dev/null 2>&1; then
    enable_system_unit "$u"
  fi
done

# --- btrfs：snapper 配置 + 快照/巡检单元 ---
if [[ "$(findmnt -no FSTYPE / 2>/dev/null || true)" == "btrfs" ]]; then
  home_ok=0
  if [[ "$(findmnt -no TARGET /home 2>/dev/null || true)" == "/home" && "$(findmnt -no FSTYPE /home 2>/dev/null || true)" == "btrfs" ]]; then
    home_ok=1
  fi
  if have snapper; then
    for pair in "root:/" "home:/home"; do
      c="${pair%%:*}"
      m="${pair##*:}"
      if [[ -f "/etc/snapper/configs/${c}" ]]; then
        info "snapper config '${c}': present"
      elif [[ "$c" == "home" && "$home_ok" != "1" ]]; then
        warn "snapper: /home is not a separate btrfs mount — skipping the 'home' config"
      else
        confirm "Create the missing snapper config '${c}' (defaults)?" || die "declined"
        as_root snapper -c "$c" create-config "$m"
        ok "snapper config '${c}': created"
      fi
    done
  else
    warn "snapper not installed — snapshot configs cannot be created"
    missing_units+=("snapper")
  fi
  enable_system_unit snapper-timeline.timer
  enable_system_unit snapper-cleanup.timer
  if have grub-btrfsd; then
    enable_system_unit grub-btrfsd.service
  else
    warn "grub-btrfsd not found — skipping snapshot boot menu daemon"
  fi
  enable_system_unit 'btrfs-scrub@-.timer'
else
  warn "root filesystem is not btrfs — skipping snapper / grub-btrfsd / btrfs-scrub setup"
fi

# --- docker 组 ---
if getent group docker >/dev/null 2>&1; then
  me="$(id -un)"
  my_groups="$(id -nG "$me")"
  if [[ " ${my_groups} " == *" docker "* ]]; then
    info "docker: user ${me} already in the docker group"
  else
    as_root usermod -aG docker "$me"
    ok "docker: user ${me} added to the docker group (takes effect at next login)"
  fi
else
  warn "docker group not found (docker not installed?)"
  missing_units+=("docker(group)")
fi

# --- 用户级：rice-dnd.timer ---
TIMER_FILE="${HOME}/.config/systemd/user/rice-dnd.timer"
if [[ ! -f "$TIMER_FILE" ]]; then
  warn "rice-dnd.timer is not deployed (stage 07/08 must run first)"
elif systemctl --user enable --now rice-dnd.timer >/dev/null 2>&1; then
  ok "user unit enabled: rice-dnd.timer"
else
  WANTS_DIR="${HOME}/.config/systemd/user/timers.target.wants"
  mkdir -p "$WANTS_DIR"
  ln -sfn "$TIMER_FILE" "${WANTS_DIR}/rice-dnd.timer"
  warn "user session bus not reachable — created the enable symlink directly (the timer starts at login)"
fi

if (( ${#missing_units[@]} > 0 )); then
  die "required units/packages missing: ${missing_units[*]} — stages 03/06 should provide them"
fi
if (( ${#inactive_units[@]} > 0 )); then
  warn "services enabled but not running: ${inactive_units[*]}"
  warn "fix the cause, then re-run: ./install.sh --run --redo 10 (or reboot and verify)"
fi
ok "Stage 10 services: done"
