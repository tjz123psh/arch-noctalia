#!/usr/bin/env bash
# steps/11-greeter.sh — Stage 11: greetd + nwg-hello 登录界面。
# 1) 复核资产（/etc/greetd/config.toml、/etc/nwg-hello/*、/var/lib/avatars/pang/.face）——内容由 07 部署；
# 2) 给 /etc/nwg-hello/background.png 加 ACL u:pang:rw（壁纸→登录背景同步 hook 需要写入权限）；
# 3) 启用 greetd（tty1 由 nwg-hello 接管；不 --now——重启后生效，避免掐断当前安装会话）。
# 幂等：已启用 / ACL 已存在 → 跳过；重复运行安全。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator

BG="/etc/nwg-hello/background.png"

# --- 1) 资产 ---
assets=(
  /etc/greetd/config.toml
  /etc/nwg-hello/niri.kdl
  /etc/nwg-hello/nwg-hello.css
  /etc/nwg-hello/nwg-hello.json
  "$BG"
  /var/lib/avatars/pang/.face
)
missing=0
for f in "${assets[@]}"; do
  if [[ ! -f "$f" ]]; then
    warn "greeter asset missing: ${f}"
    missing=$((missing + 1))
  fi
done
(( missing == 0 )) || die "greeter assets incomplete — stage 07 should have deployed them; re-run ./install.sh --run"
info "greeter assets: present"

# --- 2) background.png 的 ACL（hook 写入权限） ---
if ! have getfacl || ! have setfacl; then
  die "getfacl/setfacl not found (acl package — expected from the base system)"
fi
facl="$(getfacl -p "$BG" 2>/dev/null || true)"
if grep -q '^user:pang:rw-' <<<"$facl"; then
  info "ACL already present: u:pang:rw on background.png"
else
  as_root setfacl -m u:pang:rw "$BG"
  ok "ACL added: u:pang:rw on background.png"
fi
facl="$(getfacl -p "$BG" 2>/dev/null || true)"
grep -q '^user:pang:rw-' <<<"$facl" || die "failed to verify the ACL on ${BG}"
info "ACL verified: u:pang:rw on background.png"

# --- 3) greetd ---
if systemctl is-enabled greetd >/dev/null 2>&1; then
  info "already enabled: greetd"
else
  as_root systemctl enable greetd
  ok "enabled: greetd"
fi
systemctl is-enabled greetd >/dev/null 2>&1 || die "greetd is not enabled"

ok "Stage 11 greeter: done"
