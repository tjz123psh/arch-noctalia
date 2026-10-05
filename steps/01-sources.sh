#!/usr/bin/env bash
# steps/01-sources.sh — Stage 01: sources
# 目的：把"源"相关的一切准备好（2026-10-05 起 §9.1 的配置部分由本步代做）：
#   1) archlinuxcn 仓库：缺失则自动补齐（先备份 pacman.conf；写法照物理机）
#   2) [multilib] 已启用（lib32 包需要；§9.5 的兜底）
#   3) 刷新数据库（pacman -Sy）+ 确保 archlinuxcn-keyring 已装
#   4) paru（AUR 辅助）：缺失则从 archlinuxcn 自动安装
#   5) 镜像健康检查（只读；失败仅提示，不阻塞）
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

# 1) archlinuxcn：缺失则自动补齐（2026-10-05 用户要求：不再手填镜像地址；写法照物理机 pacman.conf）。
if grep -qE '^[[:space:]]*\[archlinuxcn\]' "$PACMAN_CONF"; then
  ok "archlinuxcn repo: present"
else
  info "archlinuxcn repo missing in ${PACMAN_CONF} — adding it (backup first)"
  confirm "Add the [archlinuxcn] repo section to ${PACMAN_CONF}?" || die "archlinuxcn repo is required (stages 03-05 use it)."
  as_root cp -a "$PACMAN_CONF" "${PACMAN_CONF}.pre-arch-noctalia"
  # 顺序 = 2026-10-05 宿主同链路实测（持续速度）：tuna/lzu/huawei ≈20MB/s，ustc ≈10，
  # aliyun 持续仅 ≈2MB/s（大文件会触发 pacman "operation too slow"），tencent 抖动，zju 常超时（留作最后兜底）。
  as_root tee -a "$PACMAN_CONF" >/dev/null <<'EOF'

[archlinuxcn]
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/$arch
Server = https://mirrors.lzu.edu.cn/archlinuxcn/$arch
Server = https://mirrors.huaweicloud.com/archlinuxcn/$arch
Server = https://mirrors.ustc.edu.cn/archlinuxcn/$arch
Server = https://mirrors.aliyun.com/archlinuxcn/$arch
Server = https://mirrors.cloud.tencent.com/archlinuxcn/$arch
Server = https://mirrors.zju.edu.cn/archlinuxcn/$arch
EOF
  grep -qE '^[[:space:]]*\[archlinuxcn\]' "$PACMAN_CONF" || die "failed to add [archlinuxcn] — please edit ${PACMAN_CONF} manually."
  ok "archlinuxcn repo: added (backup: ${PACMAN_CONF}.pre-arch-noctalia)"
fi

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

# 4b) paru（AUR 辅助，来自 archlinuxcn；§9.1 原为手动步骤，2026-10-05 起由本步兜底）
if have paru; then
  ok "paru: present"
else
  info "installing paru (AUR helper from archlinuxcn)"
  as_root pacman -S --needed --noconfirm paru
  ok "paru: installed"
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
