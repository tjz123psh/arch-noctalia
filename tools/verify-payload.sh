#!/usr/bin/env bash
# tools/verify-payload.sh — 逐行复核 manifests/files.tsv：
#   1) payload 文件存在且与 files.tsv 记录的 md5 一致（本地）；
#   2) VM 原件与记录 md5 一致（经 ssh 批量 md5sum）。
# 全匹配 → 0；任何失配/缺失 → 1（逐条列出）。
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034  # 由 lib/common.sh（source 时）消费
AN_ROOT_DIR="$ROOT_DIR"
# shellcheck disable=SC1091  # 相对 source；lib 在各检查中以独立目标校验
source "${ROOT_DIR}/lib/common.sh"

VM="${AN_VM_SSH:-vm}"
FILES="${ROOT_DIR}/manifests/files.tsv"
[[ -f "$FILES" ]] || die "missing ${FILES}"

mapfile -t rows < <(manifest_rows "$FILES")
if (( ${#rows[@]} == 0 )); then
  die "files.tsv has no data rows"
fi

declare -A want_md5=()
declare -A want_repo=()
targets=()
for row in "${rows[@]}"; do
  IFS=$'\t' read -r repo target _mode md5 <<<"$row"
  want_md5["$target"]="$md5"
  want_repo["$target"]="$repo"
  targets+=("$target")
done

total=${#targets[@]}
local_bad=0
local_missing=0
vm_bad=0
vm_err=0

info "local check: payload vs files.tsv md5 (${total} rows)"
for t in "${targets[@]}"; do
  r="${want_repo[$t]}"
  if [[ ! -f "$ROOT_DIR/$r" ]]; then
    local_missing=$((local_missing + 1))
    printf '[missing-local] %s\n' "$r"
    continue
  fi
  m="$(md5sum "$ROOT_DIR/$r" | awk '{print $1}')"
  if [[ "$m" != "${want_md5[$t]}" ]]; then
    local_bad=$((local_bad + 1))
    printf '[md5-diff-local] %s\n' "$r"
  fi
done

info "VM check: ssh md5sum vs files.tsv md5"
ssh -o BatchMode=yes -o ConnectTimeout=6 "$VM" true 2>/dev/null || die "ssh ${VM} unreachable"
i=0
n=${#targets[@]}
while (( i < n )); do
  batch=("${targets[@]:i:120}")
  while IFS= read -r line; do
    m="${line%% *}"
    f="${line#* }"
    f="${f# }"
    if [[ -z "${want_md5[$f]:-}" ]]; then
      continue
    fi
    if [[ "$m" != "${want_md5[$f]}" ]]; then
      vm_bad=$((vm_bad + 1))
      printf '[md5-diff-vm] %s\n' "$f"
    fi
  done < <(ssh "$VM" md5sum -- "${batch[@]}" 2>&1)
  i=$((i + 120))
done

printf '\n===== verify-payload summary =====\n'
printf 'rows:                 %d\n' "$total"
printf 'local md5 mismatches: %d\n' "$local_bad"
printf 'local missing:        %d\n' "$local_missing"
printf 'vm md5 mismatches:    %d\n' "$vm_bad"
printf 'vm read errors:       %d\n' "$vm_err"

if (( local_bad > 0 || local_missing > 0 || vm_bad > 0 || vm_err > 0 )); then
  error "verify-payload: FAIL"
  exit 1
fi
ok "verify-payload: all ${total} files byte-identical (payload == VM originals)"
