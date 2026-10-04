#!/usr/bin/env bash
# tools/selfcheck.sh — 仓库轻量自检（全部只读）：
#   1) 语法：全部 *.sh 的 bash -n（有 shellcheck 则逐个跑）
#   2) 映射一致性：files.tsv ↔ payload（存在 + md5）、bin-links.tsv 目标在 payload 内
#   3) 密钥卫生：tracked 文件中不得有凭据类文件名 / token 模式；
#      excluded.tsv(kind=file) 声明的文件不得出现在 payload
# 任何一节失败 → 非零退出。
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034  # 由 lib/common.sh（source 时）消费
AN_ROOT_DIR="$ROOT_DIR"
# shellcheck disable=SC1091  # 相对 source；lib 在各检查中以独立目标校验
source "${ROOT_DIR}/lib/common.sh"

fail=0
bad() { printf '[FAIL]  %s\n' "$*"; fail=1; }

# ---------- 1) 语法 ----------
syntax_count=0
while IFS= read -r f; do
  bash -n "$f" || bad "bash -n: ${f#"$ROOT_DIR"/}"
  syntax_count=$((syntax_count + 1))
done < <(find "$ROOT_DIR" -name '*.sh' -type f -not -path '*/.git/*' | LC_ALL=C sort)
info "syntax: ${syntax_count} scripts checked with bash -n"

if have shellcheck; then
  sc_count=0
  while IFS= read -r f; do
    shellcheck "$f" || bad "shellcheck: ${f#"$ROOT_DIR"/}"
    sc_count=$((sc_count + 1))
  done < <(find "$ROOT_DIR" -name '*.sh' -type f -not -path '*/.git/*' | LC_ALL=C sort)
  info "syntax: ${sc_count} scripts checked with shellcheck"
else
  warn "shellcheck not available — skipped"
fi

# ---------- 2) 映射一致性 ----------
FILES="${ROOT_DIR}/manifests/files.tsv"
LINKS="${ROOT_DIR}/manifests/bin-links.tsv"
[[ -f "$FILES" ]] || bad "missing manifests/files.tsv"
[[ -f "$LINKS" ]] || bad "missing manifests/bin-links.tsv"

rows=0
if [[ -f "$FILES" ]]; then
  while IFS=$'\t' read -r repo _target _mode md5; do
    if [[ -z "$repo" ]]; then continue; fi
    rows=$((rows + 1))
    f="$ROOT_DIR/$repo"
    if [[ ! -f "$f" ]]; then
      bad "payload missing: $repo"
      continue
    fi
    m="$(md5sum "$f" | awk '{print $1}')"
    if [[ "$m" != "$md5" ]]; then
      bad "md5 drift: $repo"
    fi
  done < <(manifest_rows "$FILES")
fi
info "mapping: ${rows} payload rows checked"

links=0
if [[ -f "$LINKS" ]]; then
  while IFS=$'\t' read -r name target; do
    if [[ -z "$name" ]]; then continue; fi
    links=$((links + 1))
    if [[ ! -f "$ROOT_DIR/payload/home/$target" ]]; then
      bad "bin-link target not in payload: ${name} -> ${target}"
    fi
  done < <(manifest_rows "$LINKS")
fi
info "mapping: ${links} bin links checked"

# ---------- 3) 密钥卫生 ----------
cred_re='(^|/)(proxy-env|age-env|anyrouter-env)\.fish$|(^|/)hosts\.yml$|(^|/)cookie$|(^|/)id_(rsa|ed25519)$|\.pem$'
tok_re='ghp_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9]{20,}|BEGIN (RSA|OPENSSH|EC|PGP) PRIVATE KEY|xox[bpas]-[A-Za-z0-9-]{10,}'
tracked_n=0
while IFS= read -r f; do
  tracked_n=$((tracked_n + 1))
  if [[ "$f" =~ $cred_re ]]; then
    bad "credential-like tracked file: $f"
    continue
  fi
  if [[ -f "$ROOT_DIR/$f" ]] && grep -qIE "$tok_re" "$ROOT_DIR/$f" 2>/dev/null; then
    bad "token pattern in tracked file: $f"
  fi
done < <(git -C "$ROOT_DIR" ls-files)
info "secrets: ${tracked_n} tracked files scanned"

if [[ -f "${ROOT_DIR}/manifests/excluded.tsv" ]]; then
  while IFS=$'\t' read -r kind item _reason; do
    if [[ "$kind" != "file" || -z "$item" ]]; then continue; fi
    case "$item" in
      /home/pang/*) rel="payload/home/${item#/home/pang/}" ;;
      /*) rel="payload/system/${item#/}" ;;
      *) rel="" ;;
    esac
    if [[ -n "$rel" && -e "$ROOT_DIR/$rel" ]]; then
      bad "excluded file present in payload: $item"
    fi
  done < <(manifest_rows "${ROOT_DIR}/manifests/excluded.tsv")
fi

printf '\n===== selfcheck summary =====\n'
if (( fail > 0 )); then
  error "selfcheck: FAIL"
  exit 1
fi
ok "selfcheck: all checks passed"
