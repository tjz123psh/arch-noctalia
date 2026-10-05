#!/usr/bin/env bash
# bootstrap.sh — 引导入口（curl 一行 / 或直接执行）。
# 仅依赖 git（与 curl 拉取本脚本本身）。
#
# 用法：
#   curl -fsSL <raw-url> | bash                    # 一键：clone + 直接实装（--run --yes）
#   curl -fsSL <raw-url> | bash -s -- --no-aur     # 一键实装但跳过 AUR 阶段（进桌面后再补）
#   curl -fsSL <raw-url> | bash -s -- --preview    # 只预览：clone + 渲染计划，不动系统
#   bash bootstrap.sh [--src <git-url|path>] [--dest <dir>] [install.sh 参数...]
#
# 例：
#   bash bootstrap.sh --src /home/pang/Projects/arch-noctalia --dest ~/arch-noctalia-test --preview
set -Eeuo pipefail

DEFAULT_SRC="${ARCH_NOCTALIA_SRC:-https://github.com/tjz123psh/arch-noctalia.git}"
SRC="$DEFAULT_SRC"
DEST="${ARCH_NOCTALIA_DIR:-$HOME/arch-noctalia}"
PASSTHROUGH=()

usage() {
  cat <<'EOF'
arch-noctalia bootstrap

Usage:
  bash bootstrap.sh [--src <git-url|path>] [--dest <dir>] [install.sh args...]

Options:
  --src SRC   git source (URL or local path). Default: https://github.com/tjz123psh/arch-noctalia.git
  --dest DIR  where to clone. Default: ~/arch-noctalia
  -h, --help  this help

All other arguments are passed straight to install.sh (e.g. --no-aur, --preview, --machine vm).
With no install.sh args, the full install runs right away (= install.sh --run --yes).

Examples:
  curl ... | bash                  full install
  curl ... | bash -s -- --no-aur   full install, skip AUR (finish later from the desktop)
  curl ... | bash -s -- --preview  dry run
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --src) SRC="${2:?--src needs a value}"; shift 2 ;;
    --dest) DEST="${2:?--dest needs a value}"; shift 2 ;;
    --) shift; PASSTHROUGH+=("$@"); break ;;
    -h|--help) usage; exit 0 ;;
    *) PASSTHROUGH+=("$1"); shift ;;  # 其余参数原样转交 install.sh（由它做严格校验）
  esac
done

# 默认 = 一键实装：没给参数、或只给了修饰参数（如 --no-aur）且未显式 --run/--preview 时，补 --run --yes。
if [[ ${#PASSTHROUGH[@]} -eq 0 ]]; then
  PASSTHROUGH=(--run --yes)
  echo "[info] no install args -> one-click install (--run --yes); dry run: bash -s -- --preview"
else
  has_mode=0
  for a in "${PASSTHROUGH[@]}"; do
    if [[ "$a" == "--run" || "$a" == "--preview" ]]; then
      has_mode=1
    fi
  done
  if [[ "$has_mode" == "0" ]]; then
    PASSTHROUGH=(--run --yes "${PASSTHROUGH[@]}")
    echo "[info] no run/preview mode given -> one-click install (--run --yes)"
  fi
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

echo "[info] handing over to install.sh (${PASSTHROUGH[*]})"
# ⚠ 不要在脚本中途 `exec < 某个文件` 换本进程的 stdin：curl|bash 时脚本流走的就是 stdin，
#    换掉后 bash 会转去从终端读“下一行脚本”——静默挂死（2026-10-05 实测事故）。
#    只把 /dev/tty 挂给子进程，sudo 密码等交互提示照常可用。
if [[ ! -t 0 ]] && (: </dev/tty) 2>/dev/null; then
  exec bash "$DEST/install.sh" "${PASSTHROUGH[@]}" </dev/tty
fi
exec bash "$DEST/install.sh" "${PASSTHROUGH[@]}"
