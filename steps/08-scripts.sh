#!/usr/bin/env bash
# steps/08-scripts.sh — Stage 08: ~/bin 软链层。
# 按 manifests/bin-links.tsv（link_name<TAB>target，target 相对 $HOME）：
#   1) mkdir -p ~/bin；
#   2) 逐条：目标缺失 → warn + 失败计数；目标不可执行 → warn（不致命）；
#      已是正确软链（readlink 相等）→ 跳过（unchanged）；
#      其余 ln -sfn 并复核 readlink；原位置有既有条目被替换 → 计入 replaced；
#   3) 结尾汇总；failed>0 → die。
# 幂等：正确软链重复运行全部跳过。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator

MANIFEST="${AN_ROOT_DIR}/manifests/bin-links.tsv"
[[ -f "$MANIFEST" ]] || die "missing manifest: ${MANIFEST}"

mkdir -p "${HOME}/bin"

checked=0
linked=0
unchanged=0
replaced=0
failed=0
while IFS=$'\t' read -r name target; do
  if [[ -z "$name" || "$name" == "#"* ]]; then
    continue
  fi
  checked=$((checked + 1))
  lib="${HOME}/bin/${name}"
  tgt="${HOME}/${target}"

  if [[ ! -e "$tgt" && ! -L "$tgt" ]]; then
    warn "link target missing: ${tgt}"
    failed=$((failed + 1))
    continue
  fi
  if [[ ! -x "$tgt" ]]; then
    warn "link target not executable: ${tgt}"
  fi

  # 幂等跳过：已是正确软链。
  current=""
  if [[ -L "$lib" ]]; then
    current="$(readlink "$lib" 2>/dev/null)" || current=""
  fi
  if [[ "$current" == "$tgt" ]]; then
    unchanged=$((unchanged + 1))
    continue
  fi

  had_entry=0
  if [[ -e "$lib" || -L "$lib" ]]; then
    had_entry=1
    info "replacing existing entry: ${lib}"
  fi

  if ! ln -sfn "$tgt" "$lib"; then
    warn "ln failed: ${lib}"
    failed=$((failed + 1))
    continue
  fi

  current="$(readlink "$lib" 2>/dev/null)" || current=""
  if [[ "$current" != "$tgt" ]]; then
    warn "post-link verify failed: ${lib}"
    failed=$((failed + 1))
    continue
  fi
  linked=$((linked + 1))
  if (( had_entry == 1 )); then
    replaced=$((replaced + 1))
  fi
done < "$MANIFEST"

printf '[info]  links: %d checked, %d linked, %d unchanged, %d replaced, %d failed\n' "$checked" "$linked" "$unchanged" "$replaced" "$failed"
if (( failed > 0 )); then
  die "Stage 08 scripts: ${failed} link(s) failed"
fi
ok "Stage 08 scripts: done"
