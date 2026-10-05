#!/usr/bin/env bash
# steps/07-config.sh — Stage 07: 部署配置与资产（dotfiles / 字体 / greeter 等）。
# 按 manifests/files.tsv（repo_path<TAB>target_path<TAB>mode<TAB>md5）逐行部署：
#   1) 预检：payload 文件存在且 md5 与清单一致，否则 die（仓库拷贝不完整）；
#   2) 部署：install -D -m <mode> —— $HOME 内用当前用户，其余（/etc、/usr/share、/var/lib）走 sudo；
#   3) 每行部署后立即复核 md5 与 mode；不一致 → warn + 计数，继续后续行，不中断；
#   4) 幂等：目标是常规文件且 md5 + mode 双比对一致 → 跳过（unchanged），重复运行收敛为全量跳过。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator

MANIFEST="${AN_ROOT_DIR}/manifests/files.tsv"
[[ -f "$MANIFEST" ]] || die "missing manifest: ${MANIFEST}"

md5_of() { local f="$1"; md5sum "$f" 2>/dev/null | awk '{print $1}'; }
mode_of() { local f="$1"; stat -c '%a' "$f" 2>/dev/null; }

# --- 1) 预检：payload 完整性（存在 + md5） ---
rows=0
payload_bad=0
while IFS=$'\t' read -r repo_path _target _mode md5; do
  if [[ -z "$repo_path" || "$repo_path" == "#"* ]]; then
    continue
  fi
  rows=$((rows + 1))
  src="${AN_ROOT_DIR}/${repo_path}"
  if [[ ! -f "$src" ]]; then
    payload_bad=$((payload_bad + 1))
    warn "payload missing: ${repo_path}"
    continue
  fi
  actual="$(md5_of "$src")" || actual=""
  if [[ "$actual" != "$md5" ]]; then
    payload_bad=$((payload_bad + 1))
    warn "payload md5 mismatch: ${repo_path}"
  fi
done < "$MANIFEST"

if (( payload_bad > 0 )); then
  die "payload incomplete — the repository copy is broken; re-clone it"
fi
info "Stage 07 config: ${rows} files to deploy; payload verified"

# --- 2) 部署 + 3) 逐行复核 ---
checked=0
deployed=0
unchanged=0
failed=0
while IFS=$'\t' read -r repo_path target mode md5; do
  if [[ -z "$repo_path" || "$repo_path" == "#"* ]]; then
    continue
  fi
  checked=$((checked + 1))
  src="${AN_ROOT_DIR}/${repo_path}"

  exists=0
  if [[ -e "$target" || -L "$target" ]]; then
    exists=1
  fi

  # 幂等跳过：常规文件（非软链）且内容与权限位都与清单一致。
  actual_md5=""
  if [[ -f "$target" ]]; then
    actual_md5="$(md5_of "$target")" || actual_md5=""
  fi
  if [[ -f "$target" && ! -L "$target" ]]; then
    actual_mode="$(mode_of "$target")" || actual_mode=""
    if [[ "$actual_md5" == "$md5" && "$actual_mode" == "$mode" ]]; then
      unchanged=$((unchanged + 1))
      continue
    fi
  fi

  if (( exists == 1 )); then
    if [[ "$actual_md5" == "$md5" ]]; then
      info "re-installing (mode or type differs): ${target}"
    else
      info "overwriting changed file: ${target}"
    fi
  fi

  if [[ "$target" == "$HOME"/* ]]; then
    if ! install -D -m "$mode" "$src" "$target"; then
      warn "install failed: ${target}"
      failed=$((failed + 1))
      continue
    fi
  else
    if ! as_root install -D -m "$mode" "$src" "$target"; then
      warn "install failed (sudo): ${target}"
      failed=$((failed + 1))
      continue
    fi
  fi

  actual_md5="$(md5_of "$target")" || actual_md5=""
  actual_mode="$(mode_of "$target")" || actual_mode=""
  if [[ "$actual_md5" != "$md5" || "$actual_mode" != "$mode" ]]; then
    warn "post-install verify failed (md5/mode): ${target}"
    failed=$((failed + 1))
    continue
  fi
  deployed=$((deployed + 1))
done < "$MANIFEST"

printf '[info]  files: %d checked, %d deployed, %d unchanged, %d failed\n' "$checked" "$deployed" "$unchanged" "$failed"
if (( failed > 0 )); then
  die "Stage 07 config: ${failed} file(s) failed"
fi
ok "Stage 07 config: done"
