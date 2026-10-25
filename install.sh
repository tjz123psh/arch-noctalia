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
REDO_STAGE=""
SKIP_AUR=0

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
  --from NN         resume: skip stages before NN (done stages are still skipped)
  --redo NN         repair: clear the done-record of stages >= NN and re-run them
  --no-aur          skip stage 05 (AUR packages); finish it later: ./install.sh --run
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
    --redo) REDO_STAGE="${2:?--redo needs a value}"; shift 2 ;;
    --no-aur) SKIP_AUR=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

if [[ -n "$FROM_STAGE" && -n "$REDO_STAGE" ]]; then
  die "use either --from or --redo, not both."
fi

user="$(current_user)"
virt="$(detect_virt)"
machine="${MACHINE_OVERRIDE:-$(detect_machine)}"

# --machine 只在显式传入时校验（自动探测可能返回 unknown，那种情况留给 run 模式下面报错）。
if [[ -n "${MACHINE_OVERRIDE}" ]]; then
  case "$machine" in
    physical|vm) ;;
    *) die "--machine must be physical or vm (got: ${machine})" ;;
  esac
  if [[ "$machine" == "physical" && "$virt" == "vmware" ]]; then
    warn "machine type forced to physical, but systemd-detect-virt says vmware — drivers will be installed on a VM."
  fi
fi

# --from / --redo 的取值在预览里也要校验：预览是最先跑的，错误参数不该等到 run 才发现。
if [[ -n "$FROM_STAGE" || -n "$REDO_STAGE" ]]; then
  want="${FROM_STAGE:-$REDO_STAGE}"
  stage_ok=0
  for known in $(stage_ids); do
    [[ "$known" == "$want" ]] && stage_ok=1
  done
  if (( stage_ok == 0 )); then
    if [[ -n "$FROM_STAGE" ]]; then
      die "--from ${FROM_STAGE}: no such stage (want 01..12)."
    else
      die "--redo ${REDO_STAGE}: no such stage (want 01..12)."
    fi
  fi
fi

if [[ "$MODE" == "preview" ]]; then
  render_plan "preview" "$machine" "$virt" "$user" "$SKIP_AUR"
  if [[ -n "$REDO_STAGE" ]]; then
    info "note: --redo ${REDO_STAGE} — in run mode, the done-record of stages >= ${REDO_STAGE} is cleared and they run again"
  fi
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

render_plan "run" "$machine" "$virt" "$user" "$SKIP_AUR"
printf '\n'
if [[ "${AN_ASSUME_YES}" != "1" ]]; then
  confirm "Proceed with the installation?" || die "aborted by user."
fi

mkdir -p "$AN_STATE_DIR"
DONE_FILE="${AN_STATE_DIR}/steps.done"
touch "$DONE_FILE"

# --redo NN：视同 --from NN，并先把 >= NN 的完成记录清掉（强制重跑；用于"重跑修复"场景）。
START_LABEL="--from"
if [[ -n "$REDO_STAGE" ]]; then
  START_LABEL="--redo"
  FROM_STAGE="$REDO_STAGE"
fi

if [[ -n "$REDO_STAGE" ]]; then
  info "redo: clearing done-records for stages >= ${REDO_STAGE} (they will re-run)"
  redo_tmp="${DONE_FILE}.redo.tmp"
  # 这里失败必须当场停：静默 no-op 的话，屏幕上已经打印过 "clearing"，用户会以为重跑发生了。
  if ! awk -v r="$REDO_STAGE" '$1 < r' "$DONE_FILE" > "$redo_tmp"; then
    rm -f -- "$redo_tmp"
    die "redo: cannot rewrite ${DONE_FILE} — nothing was cleared, nothing will re-run."
  fi
  if ! mv -- "$redo_tmp" "$DONE_FILE"; then
    rm -f -- "$redo_tmp"
    die "redo: cannot replace ${DONE_FILE} — nothing was cleared."
  fi
fi

for id in $(stage_ids); do
  name="$(stage_name "$id")"
  if [[ -n "$FROM_STAGE" && "$id" < "$FROM_STAGE" ]]; then
    info "stage ${id} ${name}: skipped (${START_LABEL} ${FROM_STAGE})"
    continue
  fi
  if grep -qx "$id" "$DONE_FILE" 2>/dev/null; then
    info "stage ${id} ${name}: already done (resume)"
    continue
  fi
  if [[ "$SKIP_AUR" == "1" && "$id" == "05" ]]; then
    info "stage ${id} ${name}: skipped (--no-aur) — finish it later: ${AN_ROOT_DIR}/install.sh --run --yes"
    continue
  fi
  # 唯一性：多一个 07-config-old.sh 就会按字典序抢占 07-config.sh，装出来的东西全错。
  step_files=()
  for f in "${AN_ROOT_DIR}/steps/${id}-"*.sh; do
    [[ -e "$f" ]] && step_files+=("$f")
  done
  (( ${#step_files[@]} == 1 )) || die "stage ${id}: expected exactly one steps/${id}-*.sh, found ${#step_files[@]}"
  step_file="${step_files[0]}"
  info "=== stage ${id} ${name} ==="
  if ! AN_RUN=1 AN_MACHINE="$machine" AN_ASSUME_YES="$AN_ASSUME_YES" bash "$step_file"; then
    die "stage ${id} ${name} failed — fix the cause, then resume: ./install.sh --run  (done stages are skipped; to force stages again: ./install.sh --run --redo ${id})"
  fi
  echo "$id" >> "$DONE_FILE"
  ok "stage ${id} ${name}: done"
done

# 结尾状态以完成记录（DONE_FILE）为准，而不是以本次运行的参数为准——
# 例如先 --no-aur、后 --redo 07 时，05 依旧未装，必须如实报告（不能误报"全部完成"）。
missing_stages=()
for id in $(stage_ids); do
  if ! grep -qx "$id" "$DONE_FILE" 2>/dev/null; then
    missing_stages+=("$id")
  fi
done
if (( ${#missing_stages[@]} == 0 )); then
  ok "all stages complete."
elif (( ${#missing_stages[@]} == 1 )) && [[ "${missing_stages[0]}" == "05" ]]; then
  if [[ "$SKIP_AUR" == "1" ]]; then
    ok "all stages complete except AUR (--no-aur: deferred by design)."
  else
    ok "all stages complete except AUR (not installed yet)."
  fi
  info "after login, finish the AUR packages with: ${AN_ROOT_DIR}/install.sh --run --yes"
else
  warn "stages not completed: ${missing_stages[*]}"
  info "finish them with: ${AN_ROOT_DIR}/install.sh --run   (or force a stage again: ./install.sh --run --redo NN)"
fi
info "next: reboot / re-login. The desktop (niri + Noctalia) is ready; see README for post-install notes."
