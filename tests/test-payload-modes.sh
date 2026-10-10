#!/usr/bin/env bash
# tests/test-payload-modes.sh — payload 可执行位三处一致（只读）：
#   1) git 索引里的模式（100644/100755，git 只记这一个位）；
#   2) 工作区文件的实际执行位；
#   3) manifests/files.tsv 的 mode 列（部署时 install -m 用的就是它）。
# 规则：清单 mode 的 owner 位带 x ⇔ 索引 100755 ⇔ 磁盘可执行。
# 任何一处漂移都说明「采集/入仓/清单」三者不一致——部署到目标机后权限就会跟清单说的不一样。
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
errs="$(mktemp)"
trap 'rm -f "$errs"' EXIT
note() { printf '%s\n' "$*" >> "$errs"; }

declare -A IDX=()
# -z + core.quotePath=false：路径里可能有空格/非 ASCII；
#   * 默认 core.quotePath 会把非 ASCII 转义成 \345\210\235…，查找必然落空；
#   * 不用 -z 时 awk 的字段切分会把带空格的路径截断。
while IFS= read -r -d '' rec; do
  IDX["${rec#*$'\t'}"]="${rec%% *}"
done < <(git -C "$ROOT_DIR" -c core.quotePath=false ls-files -s -z payload)

checked=0
while IFS=$'\t' read -r rp _tp mode _md5; do
  if [[ -z "$rp" || "$rp" == "#"* ]]; then continue; fi
  checked=$((checked + 1))
  owner="${mode: -3:1}"
  case "$owner" in
    1|3|5|7) want=100755 ;;
    *)       want=100644 ;;
  esac
  idx="${IDX[$rp]:-MISSING}"
  if [[ "$idx" == MISSING ]]; then
    note "not in the git index: $rp"
    continue
  fi
  [[ "$idx" == "$want" ]] || note "git index mode $idx != $want (manifest mode $mode): $rp"
  if [[ -x "$ROOT_DIR/$rp" ]]; then disk=100755; else disk=100644; fi
  [[ "$disk" == "$want" ]] || note "on-disk exec bit $disk != $want (manifest mode $mode): $rp"
done < <(grep -vE '^[[:space:]]*(#|$)' "$ROOT_DIR/manifests/files.tsv")

if [[ -s "$errs" ]]; then
  head -30 "$errs"
  echo "test-payload-modes: FAIL ($(wc -l < "$errs") drift(s) over ${checked} rows)"
  exit 1
fi
echo "ok: payload exec bits agree across git index, working tree and files.tsv (${checked} rows)"
