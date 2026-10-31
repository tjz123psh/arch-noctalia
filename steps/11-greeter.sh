#!/usr/bin/env bash
# steps/11-greeter.sh — Stage 11: greetd + nwg-hello 登录界面。
# 1) 复核资产（/etc/greetd/config.toml、/etc/nwg-hello/*、/var/lib/avatars/pang/.face）——内容由 07 部署；
# 2) 给 /etc/nwg-hello/background.png 加 ACL u:pang:rw（壁纸→登录背景同步 hook 需要写入权限）；
#    该文件的初始快照 = 种子里的默认壁纸（Pictures/wallpapers/斑斓.png，字节完全相同），
#    所以装完第一次开机，登录界面与桌面壁纸就是一致的；之后每次换壁纸由 ~/bin/rice-login-bg
#    （Noctalia 的 wallpaper_changed hook）按原字节跟随改写，本步不再参与。
# 3) 启用 greetd（tty1 由 nwg-hello 接管；不 --now——重启后生效，避免掐断当前安装会话）；
#    并启用 getty@tty2（应急控制台 VT2，与样本一致）。
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
  /etc/nwg-hello/noctalia-greeter.kdl
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

# 1a) 接线：greetd 必须启动安装器管的那份 niri 配置。定制之所以不放 /etc/nwg-hello/niri.kdl，是因为
#     那个文件归 nwg-hello 包、且不在包的备份列表里，升级会整份覆盖（2026-10-30 0.5.0→0.5.1 实测丢过 144Hz 钉死）。
#     /etc/greetd/config.toml 是包的 backup 文件（保留本机版本 + .pacnew），改得住。这里只告警：
#     内容本身由 12 步按 files.tsv 核 md5，被改过会在自检里报出来。
if ! grep -qF 'niri -c /etc/nwg-hello/noctalia-greeter.kdl' /etc/greetd/config.toml 2>/dev/null; then
  warn "greetd does not launch /etc/nwg-hello/noctalia-greeter.kdl - the login session ignores this repo's settings (stage 07 deploys /etc/greetd/config.toml)"
fi

# 1b) 用户头像软链：桌面与登录界面按 ~/.face 取头像（样本机即软链到 /var/lib/avatars/pang/.face，
#     真实文件由 07 部署）。补这一步，新机器才会有一模一样的头像入口。
face_link="${HOME}/.face"
face_target="/var/lib/avatars/pang/.face"
if [[ "$(readlink "$face_link" 2>/dev/null || true)" == "$face_target" ]]; then
  info "avatar symlink already present: ~/.face"
elif [[ -e "$face_link" && ! -L "$face_link" ]]; then
  warn "avatar path exists as a real file - left unchanged: ${face_link}"
else
  ln -sfn "$face_target" "$face_link"
  ok "avatar symlink created: ~/.face -> ${face_target}"
fi

# --- 2) background.png 的 ACL（hook 写入权限） ---
if ! have getfacl || ! have setfacl; then
  die "getfacl/setfacl not found (acl package - expected from the base system)"
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

# --- 3) greetd（tty1） ---
if systemctl is-enabled greetd >/dev/null 2>&1; then
  info "already enabled: greetd"
else
  as_root systemctl enable greetd
  ok "enabled: greetd"
fi
systemctl is-enabled greetd >/dev/null 2>&1 || die "greetd is not enabled"

# --- 4) 应急控制台 VT2 ---
if systemctl is-enabled getty@tty2.service >/dev/null 2>&1; then
  info "already enabled: getty@tty2.service"
else
  as_root systemctl enable getty@tty2.service
  ok "enabled: getty@tty2.service"
fi

ok "Stage 11 greeter: done"
