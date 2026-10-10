#!/usr/bin/env bash
# tools/selfcheck.sh — 仓库轻量自检（全部只读）：
#   1) 语法：全部 *.sh 的 bash -n（有 shellcheck 则逐个跑）
#   2) 映射一致性：files.tsv ↔ payload（存在 + md5）、bin-links.tsv 目标在 payload 内
#   2b) 清单约束：target 白名单/唯一性、mode 为八进制、seed/runtime 名单引用存在的行、
#      packages/aur 的词表与重叠、excluded 的 kind 与重复
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
# bash -n：全部 *.sh（项目代码 + payload 样本脚本）——0 错误为通过。
all_count=0
while IFS= read -r f; do
  bash -n "$f" || bad "bash -n: ${f#"$ROOT_DIR"/}"
  all_count=$((all_count + 1))
done < <(find "$ROOT_DIR" -name '*.sh' -type f -not -path '*/.git/*' | LC_ALL=C sort)
info "syntax: ${all_count} scripts checked with bash -n (project + payload)"

# 风格检查只跑项目自有代码；payload/ 是原样入仓的样本（用户脚本，不改不评风格）。
# 批量传入（含 lib/*.sh）可避免逐一执行时对相对 source 的 SC1091 误报。
our_files=()
while IFS= read -r f; do
  our_files+=("$f")
done < <(find "$ROOT_DIR" -name '*.sh' -type f -not -path '*/.git/*' -not -path "${ROOT_DIR}/payload/*" | LC_ALL=C sort)
if have shellcheck; then
  if (( ${#our_files[@]} > 0 )); then
    shellcheck "${our_files[@]}" || bad "shellcheck: project scripts (see output above)"
  fi
  info "syntax: shellcheck over ${#our_files[@]} project scripts (payload excluded by design)"
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

# seed.tsv（个人数据种子清单）：每行必须是 files.tsv 第 1 列里存在的 repo 路径。
SEED="${ROOT_DIR}/manifests/seed.tsv"
seed_rows=0
if [[ -f "$SEED" ]]; then
  while IFS=$'\t' read -r p _note; do
    if [[ -z "$p" || "$p" == "#"* ]]; then continue; fi
    seed_rows=$((seed_rows + 1))
    if ! awk -F'\t' -v p="$p" '$1==p {found=1} END{exit !found}' "$FILES"; then
      bad "seed.tsv references a path not in files.tsv: $p"
    fi
  done < <(manifest_rows "$SEED")
fi
info "mapping: ${seed_rows} seed rows checked against files.tsv"

# payload 必须全部进 git：注意 payload 内自带 .gitignore（样本原样），
# 被其命中的文件要 `git add -f`，否则"磁盘上有、提交里没有"。
ignored="$(git -C "$ROOT_DIR" ls-files --others --ignored --exclude-standard payload/ || true)"
untracked="$(git -C "$ROOT_DIR" ls-files --others --exclude-standard payload/ || true)"
if [[ -n "$ignored" ]]; then
  while IFS= read -r f; do bad "ignored payload file not committed (needs git add -f): $f"; done <<< "$ignored"
fi
if [[ -n "$untracked" ]]; then
  while IFS= read -r f; do bad "untracked payload file: $f"; done <<< "$untracked"
fi
tracked_payload="$(git -C "$ROOT_DIR" ls-files payload/ | grep -cv '\.gitkeep$' || true)"
if [[ "$tracked_payload" -ne "$rows" ]]; then
  bad "tracked payload files ($tracked_payload) != files.tsv rows ($rows)"
fi
info "mapping: tracked payload files = ${tracked_payload}"

# ---------- 2b) 清单约束 ----------
# 只校验『形状与交叉引用』，不碰内容：target 必须绝对且在允许的顶层目录内、repo/target 不许重复、
# mode 必须是八进制；seed/runtime 名单必须引用 files.tsv 里存在的行；packages/aur 的词表与重叠；
# excluded 的 kind 词表与重复行。这些正是变异实验里『怎么改都全绿』的空洞。
PKGS="${ROOT_DIR}/manifests/packages.tsv"
AUR="${ROOT_DIR}/manifests/aur.tsv"
RUNTIME="${ROOT_DIR}/manifests/runtime-regenerated.tsv"
EXCL="${ROOT_DIR}/manifests/excluded.tsv"

if [[ -f "$FILES" ]]; then
  declare -A seen_repo=() seen_target=()
  frows=0
  while IFS=$'\t' read -r repo target mode _md5; do
    [[ -z "$repo" || "$repo" == "#"* ]] && continue
    frows=$((frows + 1))
    if [[ -n "${seen_repo[$repo]:-}" ]]; then bad "duplicate repo path in files.tsv: $repo"; fi
    seen_repo["$repo"]=1
    if [[ -n "${seen_target[$target]:-}" ]]; then bad "duplicate target in files.tsv: $target"; fi
    seen_target["$target"]=1
    case "$target" in
      /home/*|/etc/*|/usr/share/*|/usr/local/*|/var/lib/*|/var/cache/*|/boot/*|/opt/*) ;;
      *) bad "files.tsv target outside the allowed prefixes (or not absolute): $target" ;;
    esac
    if [[ ! "$mode" =~ ^[0-7]{3,4}$ ]]; then bad "files.tsv mode is not octal: $repo -> '$mode'"; fi
  done < <(manifest_rows "$FILES")
  info "constraints: files.tsv ${frows} rows (target whitelist / uniqueness / mode) checked"
fi

for spec in "seed:${SEED:-}" "runtime:${RUNTIME}"; do
  label="${spec%%:*}"
  mf="${spec#*:}"
  [[ -n "$mf" && -f "$mf" ]] || continue
  n=0
  while IFS=$'\t' read -r p _note; do
    [[ -z "$p" || "$p" == "#"* ]] && continue
    n=$((n + 1))
    awk -F'\t' -v p="$p" '$1==p {found=1} END{exit !found}' "$FILES" || bad "${label} list references a path not in files.tsv: $p"
  done < <(manifest_rows "$mf")
  info "constraints: ${label} list rows checked (${n})"
done

if [[ -f "$PKGS" ]]; then
  declare -A seen_pkg=()
  pk=0
  while IFS=$'\t' read -r pkg repo module _purpose; do
    [[ -z "$pkg" || "$pkg" == "#"* ]] && continue
    pk=$((pk + 1))
    [[ -n "${seen_pkg[$pkg]:-}" ]] && bad "duplicate package in packages.tsv: $pkg"
    seen_pkg["$pkg"]=1
    [[ -n "$repo" ]] || bad "packages.tsv row without repo: $pkg"
    # 注意：IFS 折叠会把「空的 module 列」挪位（read 把连续 TAB 当一个分隔符），所以这里只在
    # 值**长得像一个模块 token**（纯小写字母/数字/连字符）时才判定为未知模块；中文说明文字跳过。
    if [[ "$module" =~ ^[a-z][a-z0-9-]*$ ]]; then
      case "$module" in
        drivers|desktop|audio|vmware-guest|physical-only) ;;
        *) bad "packages.tsv unknown module '${module}': $pkg" ;;
      esac
    fi
  done < <(manifest_rows "$PKGS")
  info "constraints: packages.tsv ${pk} rows (repo/module/uniqueness) checked"
  # 字段数（用 awk，避免 read 的空列折叠）
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    bad "packages.tsv row is not 4 fields: $line"
  done < <(awk -F'\t' '!/^#/ && NF && NF != 4 {print}' "$PKGS")

  if [[ -f "$AUR" ]]; then
    declare -A seen_aur=()
    an=0
    while IFS=$'\t' read -r pkg channel role _purpose; do
      [[ -z "$pkg" || "$pkg" == "#"* ]] && continue
      an=$((an + 1))
      [[ -n "${seen_aur[$pkg]:-}" ]] && bad "duplicate package in aur.tsv: $pkg"
      seen_aur["$pkg"]=1
      case "$channel" in aur|archlinuxcn) ;; *) bad "aur.tsv unknown channel '$channel': $pkg" ;; esac
      case "${role:-}" in explicit|dependency) ;; *) bad "aur.tsv unknown role '${role}': $pkg" ;; esac
    done < <(manifest_rows "$AUR")
    for p in "${!seen_aur[@]}"; do
      [[ -n "${seen_pkg[$p]:-}" ]] && bad "package listed in both packages.tsv and aur.tsv: $p"
    done
    info "constraints: aur.tsv ${an} rows (channel/role/uniqueness/overlap) checked"
  fi
fi

if [[ -f "$EXCL" ]]; then
  declare -A seen_ex=()
  ex=0
  while IFS=$'\t' read -r kind item _reason; do
    [[ -z "$kind" || "$kind" == "#"* ]] && continue
    ex=$((ex + 1))
    case "$kind" in
      package|file|dir|pattern) ;;
      *) bad "excluded.tsv unknown kind '${kind}': $item" ;;
    esac
    [[ -n "$item" ]] || bad "excluded.tsv row without item (kind=${kind})"
    [[ -n "${seen_ex[${kind}|${item}]:-}" ]] && bad "duplicate excluded row: ${kind} ${item}"
    seen_ex["${kind}|${item}"]=1
  done < <(manifest_rows "$EXCL")
  info "constraints: excluded.tsv ${ex} rows (kind vocabulary / duplicates) checked"
fi


# ---------- 3) 密钥卫生 ----------
cred_re='(^|/)(proxy-env|age-env|anyrouter-env)\.fish$|(^|/)hosts\.yml$|(^|/)cookie$|(^|/)id_(rsa|ed25519)$|\.pem$'
# 现代 token 格式一并覆盖：GitHub 细粒度 PAT、OpenAI/Anthropic 系 sk-/sk-proj-/sk-ant-、
# AWS AKIA/ASIA、Google AIza、Slack xox*（含 xoxc/xoxd）、JWT、PEM/PKCS#8 私钥头。
tok_re='ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|sk-proj-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|xox[bpasrcd]-[A-Za-z0-9-]{10,}|eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{5,}|BEGIN (RSA|OPENSSH|EC|PGP|PRIVATE) (PRIVATE )?KEY'
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
  # core.quotePath=false：非 ASCII 路径默认会被 git 做 C 转义，导致 [[ -f ]] 判定失败、该文件被静默跳过扫描。
done < <(git -C "$ROOT_DIR" -c core.quotePath=false ls-files)
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
