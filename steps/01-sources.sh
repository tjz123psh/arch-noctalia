#!/usr/bin/env bash
# steps/01-sources.sh — Stage 01: sources
# 目的：把"源"相关的一切准备好（2026-10-05 起 §9.1 的配置部分由本步代做）：
#   1a) 官方仓库镜像表（/etc/pacman.d/mirrorlist）：一律写入标准列表（tuna 打头；先备份、幂等）
#   1) archlinuxcn 仓库：一律写入安装器标准块（缺失追加／已有整段覆盖，先备份；用户 2026-10-05 确认可覆盖）
#   1b) 镜像"降级链"：并行实探，快的排前、不通的沉底（pacman 逐文件取用，前不行后顶上）
#   2) [multilib] 已启用（lib32 包需要；§9.5 的兜底）
#   3) 刷新数据库（pacman -Sy）+ 确保 archlinuxcn-keyring 已装
#   4) paru（AUR 辅助）：缺失则从 archlinuxcn 自动安装
#   5) 镜像健康检查（只读；失败仅提示，不阻塞）
# 幂等：重复运行安全。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"
# shellcheck source=lib/mirrors.sh
source "${AN_ROOT_DIR}/lib/mirrors.sh"

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

# 1a) 官方仓库镜像表：一律写成安装器标准列表（tuna 打头）——base 自带顺序可能阿里云打头
#     （实测 aliyun 持续只有 ~2.3MB/s，会拖垮 stage 02/03）。先备份、内容一致则跳过（幂等）。
MIRRORLIST="/etc/pacman.d/mirrorlist"
confirm "Write the installer's official mirror list to ${MIRRORLIST}?" || die "official mirrorlist is required (stages 02-03 use it)."
tmp_ml="$(mktemp)"
cat > "$tmp_ml" <<'EOF'
# arch-noctalia 写入：官方仓库镜像（tuna 打头）
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/$arch
Server = https://mirrors.huaweicloud.com/archlinux/$repo/os/$arch
Server = https://mirrors.ustc.edu.cn/archlinux/$repo/os/$arch
Server = https://mirrors.aliyun.com/archlinux/$repo/os/$arch
Server = https://mirrors.cloud.tencent.com/archlinux/$repo/os/$arch
EOF
if cmp -s "$tmp_ml" "$MIRRORLIST"; then
  ok "official mirrorlist: already the installer's list"
  rm -f "$tmp_ml"
else
  if [[ -e "$MIRRORLIST" && ! -e "${MIRRORLIST}.pre-arch-noctalia" ]]; then
    as_root cp -a "$MIRRORLIST" "${MIRRORLIST}.pre-arch-noctalia"
  fi
  as_root tee "$MIRRORLIST" >/dev/null < "$tmp_ml"
  rm -f "$tmp_ml"
  grep -q '^Server' "$MIRRORLIST" || die "failed to write ${MIRRORLIST} — please check it manually."
  ok "official mirrorlist: installer's list written (backup: ${MIRRORLIST}.pre-arch-noctalia)"
fi

# 1) archlinuxcn：一律写成安装器标准块——缺失则追加、已有则整段覆盖
#    （2026-10-05 用户确认"覆盖即可"：重装时不会再手配源）。覆盖前自动备份；随后 1b 按实测重排。
if grep -qE '^[[:space:]]*\[archlinuxcn\]' "$PACMAN_CONF"; then
  info "archlinuxcn repo present — overwriting it with the installer's mirror list"
else
  info "archlinuxcn repo missing in ${PACMAN_CONF} — adding the installer's mirror list"
fi
confirm "Write the installer's [archlinuxcn] block to ${PACMAN_CONF}?" || die "archlinuxcn repo is required (stages 03-05 use it)."
tmp_conf="$(mktemp)"
cn_replace_section "$PACMAN_CONF" > "$tmp_conf" <<'EOF'
[archlinuxcn]
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/$arch
Server = https://mirrors.lzu.edu.cn/archlinuxcn/$arch
Server = https://mirrors.huaweicloud.com/archlinuxcn/$arch
Server = https://mirrors.ustc.edu.cn/archlinuxcn/$arch
Server = https://mirrors.aliyun.com/archlinuxcn/$arch
Server = https://mirrors.cloud.tencent.com/archlinuxcn/$arch
Server = https://mirrors.zju.edu.cn/archlinuxcn/$arch
EOF
if cmp -s "$tmp_conf" "$PACMAN_CONF"; then
  ok "archlinuxcn repo: already the installer's block"
  rm -f "$tmp_conf"
else
  [[ -e "${PACMAN_CONF}.pre-arch-noctalia" ]] || as_root cp -a "$PACMAN_CONF" "${PACMAN_CONF}.pre-arch-noctalia"
  as_root tee "$PACMAN_CONF" >/dev/null < "$tmp_conf"
  rm -f "$tmp_conf"
  grep -qE '^[[:space:]]*\[archlinuxcn\]' "$PACMAN_CONF" || die "failed to write [archlinuxcn] — please edit ${PACMAN_CONF} manually."
  ok "archlinuxcn repo: installer's block written (backup: ${PACMAN_CONF}.pre-arch-noctalia)"
fi

# 1b) 镜像"降级链"：并行实探 [archlinuxcn] 各镜像，快的排前、不通的沉底；顺序变了才改写。
#     pacman 逐文件按 Server 顺序取用，天然"前不行后顶上"；本步保证慢/死镜像不打头阵。
mapfile -t cn_servers < <(cn_servers_in_conf "$PACMAN_CONF")
if (( ${#cn_servers[@]} >= 2 )); then
  info "probing ${#cn_servers[@]} archlinuxcn mirrors (parallel)…"
  mapfile -t cn_fast < <(printf '%s\n' "${cn_servers[@]}" | cn_probe_servers | cn_order_servers)
  tmp_conf="$(mktemp)"
  printf '%s\n' "${cn_fast[@]}" | cn_rewrite_conf "$PACMAN_CONF" > "$tmp_conf"
  if (( ${#cn_fast[@]} < 2 )); then
    warn "mirror probe returned no usable result — leaving order as-is"
  elif cmp -s "$tmp_conf" "$PACMAN_CONF"; then
    ok "mirror order: already fastest-first"
  else
    [[ -e "${PACMAN_CONF}.pre-arch-noctalia" ]] || as_root cp -a "$PACMAN_CONF" "${PACMAN_CONF}.pre-arch-noctalia"
    as_root tee "$PACMAN_CONF" >/dev/null < "$tmp_conf"
    ok "mirror order updated: first=$(cn_host "${cn_fast[0]}"), last=$(cn_host "${cn_fast[-1]}")"
  fi
  rm -f "$tmp_conf"
else
  warn "archlinuxcn mirror list has <2 entries — skipping reorder"
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
