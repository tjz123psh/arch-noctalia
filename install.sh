#!/usr/bin/env bash
# install.sh — arch-noctalia 主入口。
# 默认 = 预览（只读）。实装：./install.sh --run [--yes] [--machine physical|vm] [--from NN]
set -Eeuo pipefail

AN_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AN_ROOT_DIR
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"
# shellcheck source=lib/detect.sh
source "${AN_ROOT_DIR}/lib/detect.sh"
# shellcheck source=lib/plan.sh
source "${AN_ROOT_DIR}/lib/plan.sh"

AN_TARGET_USER="pang"
MODE="preview"
AN_ASSUME_YES="${AN_ASSUME_YES:-0}"
MACHINE_OVERRIDE=""
FROM_STAGE=""

usage() {
  cat <<'EOF'
arch-noctalia installer

Usage:
  ./install.sh                        preview (read-only, default)
  ./install.sh --run [options]        perform the installation

Options:
  --run             perform the installation (steps in order, resumable)
  --preview         read-only: render the full stage plan, change nothing (default)
  --machine M       force machine type (physical|vm) instead of auto-detection
  --from NN         start from stage NN (resume helper; earlier stages skipped)
  --yes, -y         non-interactive: auto-confirm prompts
  -h, --help        this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preview) MODE="preview"; shift ;;
    --run) MODE="run"; shift ;;
    --yes|-y) AN_ASSUME_YES=1; shift ;;
    --machine) MACHINE_OVERRIDE="${2:?--machine needs a value}"; shift 2 ;;
    --from) FROM_STAGE="${2:?--from needs a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

user="$(current_user)"
virt="$(detect_virt)"
machine="${MACHINE_OVERRIDE:-$(detect_machine)}"

if [[ "$MODE" == "preview" ]]; then
  render_plan "preview" "$machine" "$virt" "$user"
  exit 0
fi

# ---------- run mode ----------
[[ "$user" == "$AN_TARGET_USER" ]] || die "run as the target user '${AN_TARGET_USER}' (current: '${user}')."
[[ "$machine" != "unknown" ]] || die "machine type unknown — pass --machine physical|vm."
have sudo || die "sudo is required (the base install provides it)."
have pacman || die "pacman is required (Arch base system)."
have git || die "git is required (manual §9.1 installs it)."
# 免密 sudo（NOPASSWD）环境跳过交互校验；否则校验一次并缓存时间戳（交互 TTY 下提示输入密码）。
if ! sudo -n true 2>/dev/null; then
  sudo -v || die "sudo authentication failed."
fi

render_plan "run" "$machine" "$virt" "$user"
printf '\n'
if [[ "${AN_ASSUME_YES}" != "1" ]]; then
  confirm "Proceed with the installation?" || die "aborted by user."
fi

mkdir -p "$AN_STATE_DIR"
DONE_FILE="${AN_STATE_DIR}/steps.done"
touch "$DONE_FILE"

have_from=0
if [[ -n "$FROM_STAGE" ]]; then
  for id in $(stage_ids); do
    [[ "$id" == "$FROM_STAGE" ]] && have_from=1
  done
  [[ "$have_from" == "1" ]] || die "--from ${FROM_STAGE}: no such stage."
fi

for id in $(stage_ids); do
  name="$(stage_name "$id")"
  if [[ -n "$FROM_STAGE" && "$id" < "$FROM_STAGE" ]]; then
    info "stage ${id} ${name}: skipped (--from ${FROM_STAGE})"
    continue
  fi
  if grep -qx "$id" "$DONE_FILE" 2>/dev/null; then
    info "stage ${id} ${name}: already done (resume)"
    continue
  fi
  step_file=""
  for f in "${AN_ROOT_DIR}/steps/${id}-"*.sh; do
    [[ -e "$f" ]] && step_file="$f" && break
  done
  [[ -n "$step_file" ]] || die "stage ${id}: step script not found"
  info "=== stage ${id} ${name} ==="
  if ! AN_RUN=1 AN_MACHINE="$machine" AN_ASSUME_YES="$AN_ASSUME_YES" bash "$step_file"; then
    die "stage ${id} ${name} failed — fix the issue and re-run: ./install.sh --run  (done stages are skipped)"
  fi
  echo "$id" >> "$DONE_FILE"
  ok "stage ${id} ${name}: done"
done

ok "all stages complete."
info "next: reboot / re-login. The desktop (niri + Noctalia) is ready; see README for post-install notes."
