#!/usr/bin/env bash
# steps/10-services.sh — Stage 10: enable services.
# 系统级：docker、bluetooth（enable --now）；btrfs（root 是 btrfs 时）：snapper 配置缺则按默认模板创建、
#   snapper-timeline.timer / snapper-cleanup.timer / grub-btrfsd.service / btrfs-scrub@-.timer 启用；
#   另把当前用户加入 docker 组（下次登录生效）。
# 用户级：rice-dnd.timer（单元文件由 07 部署；无用户总线时退化为手工 enable 软链）。
# 注：greetd 的启用归 11；本步骤不碰 tty1。
# 幂等：已启用/已配置/已在组内 → 跳过；重复运行安全。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator

enable_system_unit() { # $1=unit
  local u="$1"
  if ! systemctl cat "$u" >/dev/null 2>&1; then
    warn "unit not found: ${u} (package missing?)"
    return 0
  fi
  if systemctl is-enabled "$u" >/dev/null 2>&1; then
    info "already enabled: ${u}"
  else
    as_root systemctl enable --now "$u"
    ok "enabled: ${u}"
  fi
}

# --- 基础服务 ---
enable_system_unit docker.service
enable_system_unit bluetooth.service

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
    warn "snapper not installed — skipping snapshot configs"
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

ok "Stage 10 services: done"
