#!/usr/bin/env bash
# bootstrap.sh — 引导入口（curl 一行 / 或直接执行）。
# 仅依赖 git（与 curl 拉取本脚本本身）。
#
# 用法：
#   curl -fsSL <raw-url> | bash                    # 一键：clone + 直接实装（--run --yes）
#   curl -fsSL <raw-url> | bash -s -- --preview    # 只预览：clone + 渲染计划，不动系统
#   bash bootstrap.sh [--src <git-url|path>] [--dest <dir>] [-- <install.sh 参数...>]
#
# 例：
#   bash bootstrap.sh --src /home/pang/Projects/arch-noctalia --dest ~/arch-noctalia-test -- --preview
set -Eeuo pipefail

DEFAULT_SRC="${ARCH_NOCTALIA_SRC:-https://github.com/tjz123psh/arch-noctalia.git}"
SRC="$DEFAULT_SRC"
DEST="${ARCH_NOCTALIA_DIR:-$HOME/arch-noctalia}"
PASSTHROUGH=()

usage() {
  cat <<'EOF'
arch-noctalia bootstrap

Usage:
  bash bootstrap.sh [--src <git-url|path>] [--dest <dir>] [-- <install.sh args...>]

Options:
  --src SRC   git source (URL or local path). Default: https://github.com/tjz123psh/arch-noctalia.git
  --dest DIR  where to clone. Default: ~/arch-noctalia
  --          everything after is passed to install.sh (e.g. -- --preview)
  -h, --help  this help

不带 install.sh 参数时 = 一键实装（等价于 install.sh --run --yes）；
只想预览用：bash bootstrap.sh -- --preview
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --src) SRC="${2:?--src needs a value}"; shift 2 ;;
    --dest) DEST="${2:?--dest needs a value}"; shift 2 ;;
    --) shift; PASSTHROUGH=("$@"); break ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[error] unknown option: $1 (pass install.sh args after --)" >&2; exit 2 ;;
  esac
done

# 默认 = 一键实装；只想预览时走 `-- --preview`。
if [[ ${#PASSTHROUGH[@]} -eq 0 ]]; then
  PASSTHROUGH=(--run --yes)
  echo "[info] 无 install 参数 → 一键实装（--run --yes）；只看计划请用: bash -s -- --preview"
fi

if ! command -v git >/dev/null 2>&1; then
  echo "[error] git is required. Install it first (the manual §9.1 step installs git)." >&2
  exit 1
fi

if [[ -d "$DEST/.git" ]]; then
  echo "[info] repo already present at $DEST — updating (git pull --ff-only)"
  git -C "$DEST" pull --ff-only || echo "[warn] pull failed; using the existing checkout as-is"
else
  echo "[info] cloning $SRC -> $DEST"
  case "$SRC" in
    http://*|https://*|git@*|ssh://*) git clone --depth=1 "$SRC" "$DEST" ;;
    *) git clone "$SRC" "$DEST" ;;
  esac
fi

# curl|bash 时 stdin 是脚本管道；把终端还给 install.sh，交互提示（如 sudo 密码）才可用。
if [[ ! -t 0 ]] && (: </dev/tty) 2>/dev/null; then
  exec </dev/tty
fi

echo "[info] handing over to install.sh (${PASSTHROUGH[*]})"
exec bash "$DEST/install.sh" "${PASSTHROUGH[@]}"
