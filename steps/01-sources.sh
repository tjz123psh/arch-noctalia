#!/usr/bin/env bash
# steps/01-sources.sh — Stage 01: sources
# 目的：确认手动 §9.1 已生效，并补齐安装器真正需要的东西：
#   1) archlinuxcn 仓库已配置（缺失 → 停止并给出指引；安装器不代做 §9.1）
#   2) [multilib] 已启用（lib32 包需要；§9.5 的兜底）
#   3) 刷新数据库（pacman -Sy）+ 确保 archlinuxcn-keyring 已装
#   4) 镜像健康检查（只读；失败仅提示，不阻塞）
# 幂等：重复运行安全。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator
machine="${AN_MACHINE:?AN_MACHINE is required (set by install.sh)}"
: "$machine"

PACMAN_CONF="/etc/pacman.conf"

info "Stage 01 sources: checking pacman sources..."

# 0) 基础工具：curl（后续引导/健康检查都要用）
if ! have curl; then
  info "installing required tool: curl"
  as_root pacman -S --needed --noconfirm curl
fi
ok "tool: curl present"

# 1) archlinuxcn 必须已由手动 §9.1 配好 —— 缺了就停。
if ! grep -qE '^[[:space:]]*\[archlinuxcn\]' "$PACMAN_CONF"; then
  die "archlinuxcn repo is missing in ${PACMAN_CONF}. Complete the manual step §9.1 first (add the archlinuxcn section, install paru/git), then re-run."
fi
ok "archlinuxcn repo: present"

# 2) [multilib]（lib32 包的依赖）
if grep -qE '^[[:space:]]*\[multilib\]' "$PACMAN_CONF"; then
  ok "[multilib]: present"
else
  confirm "Enable [multilib] in ${PACMAN_CONF}?" || die "multilib is required for lib32 packages (stages 03/06)."
  as_root sed -i -e 's/^#\[multilib\][[:space:]]*$/[multilib]/' \
                   -e 's/^#Include = \/etc\/pacman\.d\/mirrorlist[[:space:]]*$/Include = \/etc\/pacman.d\/mirrorlist/' \
                   "$PACMAN_CONF"
  grep -qE '^[[:space:]]*\[multilib\]' "$PACMAN_CONF" || die "failed to enable [multilib] — please edit ${PACMAN_CONF} manually."
  ok "[multilib] enabled"
fi

# 3) 刷新数据库（stage 02 会立刻做全量 -Syu，避免部分升级窗口）
info "refreshing package databases (pacman -Sy)"
as_root pacman -Sy --noconfirm

# 4) keyring（archlinuxcn 包的签名环）
if pacman -Q archlinuxcn-keyring >/dev/null 2>&1; then
  ok "archlinuxcn-keyring: installed"
else
  info "installing archlinuxcn-keyring"
  as_root pacman -S --needed --noconfirm archlinuxcn-keyring
  ok "archlinuxcn-keyring: installed"
fi

# 5) 镜像健康检查（只读）
check_url() { curl -fsS --connect-timeout 4 --max-time 8 -o /dev/null "$1" 2>/dev/null; }
first_official="$(awk '/^Server[[:space:]]*=/ {print $3; exit}' /etc/pacman.d/mirrorlist 2>/dev/null || true)"
if [[ -n "$first_official" ]]; then
  probe="${first_official/\$repo/core}"
  probe="${probe/\$arch/x86_64}"
  if check_url "${probe}/core.db"; then
    ok "official mirror reachable: ${first_official}"
  else
    warn "official mirror probe failed: ${first_official} (pacman may still work; check the mirrorlist)"
  fi
fi
cn_url="$(awk '/^\[archlinuxcn\]/{s=1} s && /^Server[[:space:]]*=/ {print $3; exit}' "$PACMAN_CONF" 2>/dev/null || true)"
if [[ -n "$cn_url" ]]; then
  cn_probe="${cn_url/\$arch/x86_64}"
  if check_url "${cn_probe}/archlinuxcn.db"; then
    ok "archlinuxcn mirror reachable: ${cn_url}"
  else
    warn "archlinuxcn mirror probe failed: ${cn_url}"
  fi
fi

ok "Stage 01 sources: done"
