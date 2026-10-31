#!/usr/bin/env bash
# test-greeter-wiring.sh — 登录界面会话配置的归属与接线（回归锁，2026-10-30 事故）：
#   /etc/nwg-hello/niri.kdl 归 nwg-hello 包所有，且**不在包的备份列表**（pacman 本地库 %BACKUP% 只有
#   hyprland.conf / sway-config）→ 0.5.0→0.5.1 升级整份覆盖，安装器钉的 144Hz 与背景色当场丢失。
#   现在定制放自有路径 /etc/nwg-hello/noctalia-greeter.kdl，由 greetd 的 /etc/greetd/config.toml
#   （包的 backup 文件，改得住）指过去。这里锁住整条接线，防止有人图省事改回包文件。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILES="$ROOT/manifests/files.tsv"
KDL_REPO="payload/system/etc/nwg-hello/noctalia-greeter.kdl"
KDL_TARGET="/etc/nwg-hello/noctalia-greeter.kdl"

fail() {
  echo "[FAIL] $*"
  exit 1
}

# 1) 自有路径在清单里，且 md5 与仓库文件一致
row="$(awk -F'\t' -v p="$KDL_REPO" '$1==p {print $2"\t"$3"\t"$4}' "$FILES")"
[[ -n "$row" ]] || fail "files.tsv has no row for ${KDL_REPO}"
IFS=$'\t' read -r target mode md5 <<<"$row"
[[ "$target" == "$KDL_TARGET" ]] || fail "unexpected target for ${KDL_REPO}: ${target}"
[[ "$mode" == "644" ]] || fail "unexpected mode for ${KDL_REPO}: ${mode}"
[[ -f "$ROOT/$KDL_REPO" ]] || fail "payload file missing: ${KDL_REPO}"
actual="$(md5sum "$ROOT/$KDL_REPO" | awk '{print $1}')"
[[ "$actual" == "$md5" ]] || fail "md5 drift in files.tsv for ${KDL_REPO}: manifest ${md5}, file ${actual}"

# 2) 不再纳管包自带的 niri.kdl（否则每次升级都要手工收拾，且清单会永远红）
if awk -F'\t' '$2=="/etc/nwg-hello/niri.kdl" {found=1} END{exit !found}' "$FILES"; then
  fail "files.tsv manages the package-owned /etc/nwg-hello/niri.kdl again — upgrades will overwrite it"
fi
[[ ! -e "$ROOT/payload/system/etc/nwg-hello/niri.kdl" ]] || fail "payload still ships /etc/nwg-hello/niri.kdl (package-owned)"

# 3) greetd 指过去，且 11 步的资产清单认得这个路径
grep -qF "niri -c ${KDL_TARGET}" "$ROOT/payload/system/etc/greetd/config.toml" ||
  fail "payload greetd config does not launch ${KDL_TARGET}"
grep -qF "$KDL_TARGET" "$ROOT/steps/11-greeter.sh" ||
  fail "steps/11-greeter.sh does not check ${KDL_TARGET}"

# 4) 真语法检查（目标机上才有意义）：niri 不接受这份配置就等于登录界面起不来
if command -v niri >/dev/null 2>&1; then
  if ! out="$(niri validate -c "$ROOT/$KDL_REPO" 2>&1)"; then
    fail "niri validate rejected ${KDL_REPO}: ${out}"
  fi
else
  echo "[skip] niri not installed — syntax check skipped"
fi

echo "ok: greeter session config lives at ${KDL_TARGET}, greetd launches it, package file untouched"
