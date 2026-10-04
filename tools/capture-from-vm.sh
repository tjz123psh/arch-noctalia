#!/usr/bin/env bash
# tools/capture-from-vm.sh — 从测试 VM 导出"已验证样本"到本仓库 payload/，并生成清单。
# 仅在开发宿主机（导出方）使用；目标机安装时不需要本工具。
# 只读 VM：仅 rsync 拉取，不在 VM 上做任何写操作。
# 幂等：可重复运行（重跑会刷新 payload、files.tsv、bin-links.tsv）。
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034  # 由 lib/common.sh（source 时）消费
AN_ROOT_DIR="$ROOT_DIR"
# shellcheck disable=SC1091  # 相对 source；lib 在各检查中以独立目标校验
source "${ROOT_DIR}/lib/common.sh"

VM="${AN_VM_SSH:-vm}"
DEST="${ROOT_DIR}/payload"
FILES_TSV="${ROOT_DIR}/manifests/files.tsv"
LINKS_TSV="${ROOT_DIR}/manifests/bin-links.tsv"
HOME_BASE="/home/pang"

command -v rsync >/dev/null || die "rsync is required"
ssh -o BatchMode=yes -o ConnectTimeout=6 "$VM" true 2>/dev/null || die "ssh ${VM} unreachable"

# --- 捕获清单（home 侧：payload/home/<rel> ←→ /home/pang/<rel>） ---
HOME_DIRS=(
  ".config/niri"
  ".config/noctalia"
  ".config/kitty"
  ".config/fuzzel"
  ".config/gtk-3.0"
  ".config/gtk-4.0"
  ".config/mpv"
  ".config/btop"
  ".config/fastfetch"
  ".config/fcitx5"
  ".config/environment.d"
  ".config/qt5ct"
  ".config/qt6ct"
  ".config/nwg-look"
  ".config/Kingsoft"
  ".config/fontconfig"
  ".config/foot"
  ".config/zellij"
  ".config/papirus-folders"
  ".config/nomacs"
  "scripts"
  "noctalia-plugins"
  "Pictures/wallpapers"
)
HOME_FILES=(
  ".config/fish/config.fish"
  ".config/starship.toml"
  ".config/mimeapps.list"
  ".config/kdeglobals"
  ".config/user-dirs.dirs"
  ".config/user-dirs.locale"
  ".config/QtProject.conf"
  ".config/arkrc"
  ".config/systemd/user/rice-dnd.service"
  ".config/systemd/user/rice-dnd.timer"
  ".local/state/noctalia/settings.toml"
  ".gitconfig"
  ".bash_profile"
)

# --- 捕获清单（system 侧：payload/system/<rel> ←→ /<rel>） ---
SYS_DIRS=(
  "usr/share/fonts/maple-mono-nf-cn"
  "usr/share/fonts/google-sans-flex"
  "usr/share/fonts/resource-han-rounded"
)
SYS_FILES=(
  "etc/greetd/config.toml"
  "etc/nwg-hello/niri.kdl"
  "etc/nwg-hello/nwg-hello.css"
  "etc/nwg-hello/nwg-hello.json"
  "etc/nwg-hello/background.png"
  "var/lib/avatars/pang/.face"
)

# rsync 排除：历史备份 / 生成物 / 缓存 / 插件构建产物
EXCLUDES=(
  '--exclude=*.bak-*' '--exclude=*.bak' '--exclude=*.orig'
  '--exclude=*.vmtest' '--exclude=__pycache__/' '--exclude=*.pyc'
  '--exclude=build/' '--exclude=.backups/'
  '--exclude=cached_layouts'
)

info "capturing HOME dirs from ${VM} ..."
for rel in "${HOME_DIRS[@]}"; do
  mkdir -p "${DEST}/home/${rel}"
  rsync -a --delete "${EXCLUDES[@]}" "${VM}:${HOME_BASE}/${rel}/" "${DEST}/home/${rel}/"
  printf '  [dir]  %s\n' "$rel"
done

info "capturing HOME files ..."
for rel in "${HOME_FILES[@]}"; do
  mkdir -p "$(dirname "${DEST}/home/${rel}")"
  rsync -a "${VM}:${HOME_BASE}/${rel}" "${DEST}/home/${rel}"
  printf '  [file] %s\n' "$rel"
done

info "capturing system dirs ..."
for rel in "${SYS_DIRS[@]}"; do
  mkdir -p "${DEST}/system/${rel}"
  rsync -a --delete "${EXCLUDES[@]}" "${VM}:/${rel}/" "${DEST}/system/${rel}/"
  printf '  [sys]  /%s\n' "$rel"
done

info "capturing system files ..."
for rel in "${SYS_FILES[@]}"; do
  mkdir -p "$(dirname "${DEST}/system/${rel}")"
  rsync -a "${VM}:/${rel}" "${DEST}/system/${rel}"
  printf '  [sys]  /%s\n' "$rel"
done

# --- 意外产物检查：payload 里不允许出现软链（有的话必须显式决策） ---
symlinks="$(find "$DEST" -type l | wc -l | tr -d ' ')"
if [[ "$symlinks" != "0" ]]; then
  find "$DEST" -type l
  die "unexpected symlinks in payload (${symlinks}) — handle them deliberately"
fi

# --- files.tsv ---
info "generating ${FILES_TSV#"$ROOT_DIR"/} ..."
{
  echo "# schema=1"
  echo "# repo_path<TAB>target_path<TAB>mode<TAB>md5"
  echo "# repo_path：本仓库相对路径；target_path：目标机绝对路径；mode：八进制权限（git 只保留可执行位，部署以本表为准）；md5：payload 文件 md5（=VM 原件，经 tools/verify-payload.sh 复核）"
  (cd "$DEST" && find home system -type f) | LC_ALL=C sort | while read -r f; do
    repo_path="payload/$f"
    case "$f" in
      home/*) target="${HOME_BASE}/${f#home/}" ;;
      system/*) target="/${f#system/}" ;;
      *) die "unexpected payload path: $f" ;;
    esac
    mode="$(stat -c '%a' "$DEST/$f")"
    md5="$(md5sum "$DEST/$f" | awk '{print $1}')"
    printf '%s\t%s\t%s\t%s\n' "$repo_path" "$target" "$mode" "$md5"
  done
} > "$FILES_TSV"

# --- bin-links.tsv（~/bin 下的软链层；目标统一为相对 $HOME 的路径） ---
# 注意：VM 的登录 shell 是 fish —— 多语句脚本一律显式走 `bash -s`，不依赖登录 shell。
info "generating ${LINKS_TSV#"$ROOT_DIR"/} ..."
{
  echo "# schema=1"
  echo "# link_name<TAB>target（target 为相对 \$HOME 的路径）"
  sed "s|@HOME@|${HOME_BASE}|g" <<'REMOTE' | ssh "$VM" bash -s | sed "s|\t${HOME_BASE}/|\t|" | LC_ALL=C sort
cd @HOME@/bin
for f in *; do
  if [ -L "$f" ]; then printf '%s\t%s\n' "$f" "$(readlink "$f")"; fi
done
REMOTE
} > "$LINKS_TSV"

# --- 汇总 ---
files=$(manifest_rows "$FILES_TSV" | wc -l | tr -d ' ')
links=$(grep -cvE '^[[:space:]]*(#|$)' "$LINKS_TSV" || true)
bytes=$(du -sb "$DEST" | awk '{print $1}')
size_h="$(numfmt --to=iec "$bytes" 2>/dev/null || echo "${bytes} B")"
info "captured: ${files} files, ${links} symlinks; payload size: ${size_h}"
info "done."
