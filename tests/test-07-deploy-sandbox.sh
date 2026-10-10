#!/usr/bin/env bash
# tests/test-07-deploy-sandbox.sh — 07 的端到端沙箱回归（不碰真机）。
#   1) 全量部署：真实 manifests/files.tsv 的 341 行全部落到 <沙箱 root> 之下，
#      逐个核对「存在 + 权限位 == 清单 mode + md5 == 清单 md5」（预置的 seed 目标只核存在性），
#      且部署循环零 warn；
#   2) seed：预置用户内容的种子文件必须保持原样（kept (seed)）；
#   3) 幂等：第二次运行全 unchanged；
#   4) 失败路径：目标目录不可写 → 必须 rc≠0 且摘要行体现 failed（守住「装坏了要报错」）；
#   5) 目标白名单：相对路径 / 白名单外（/tmp/…）目标必须在部署前被拒。
# 安全：所有写入都发生在 mktemp 沙箱内（AN_TARGET_ROOT + HOME 都在沙箱里，
#       且 sandbox-sudo 只放行沙箱内的绝对路径）；脚本开头有自检，沙箱路径异常直接退出。
set -Eeuo pipefail
# 夹具权限必须确定：调用方 umask 可能是 077，会让"预置的 seed 文件"变成 600 而与清单的 644 冲突
# （seed 是用户数据，部署时保持原样，权限由用户/夹具决定，不该当成部署失败）。
umask 022
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
bad() { echo "[FAIL] $*"; fail=1; }

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

# 安全自检：沙箱必须在 mktemp 目录内（防止变量写错导致真机被写）。
case "$sandbox" in /tmp/*|/var/tmp/*) ;; *) echo "[FAIL] sandbox is not under /tmp: $sandbox"; exit 1;; esac
# 所有步骤都在沙箱目录里执行：清单万一出现相对路径目标，落点也在沙箱内而不是仓库 cwd（2026-10-10 教训）。
cd "$sandbox"

make_stubs() { # $1=stubdir $2=root $3=repo
  local d="$1"
  mkdir -p "$d"
  local c
  for c in pacman paru yay systemctl snapper usermod locale-gen grub-mkconfig \
           glib-compile-schemas setfacl getfacl mkinitcpio fc-cache update-desktop-database gsettings; do
    printf '#!/bin/sh\nexit 0\n' > "$d/$c"; chmod +x "$d/$c"
  done
  sed -e "s|@ROOT@|$2|" -e "s|@REPO@|$3|" > "$d/sudo" <<'STUB'
#!/bin/sh
root="@ROOT@"; repo="@REPO@"
case "$1" in
  install|cp|mv|tee|cat|rm|mkdir|ln|touch|chmod|chown|md5sum|stat)
    for a in "$@"; do
      # 含 "/" 的参数（绝对或相对）都必须落在沙箱/仓库副本内 → 相对路径不再能穿透。
      case "$a" in */*) case "$a" in "$root"/*|"$repo"/*) ;; *) echo "sandbox-sudo: refuse $a" >&2; exit 1;; esac;; esac
    done ;;
esac
exec "$@"
STUB
  chmod +x "$d/sudo"
}

make_repo() { # $1=repo 沙箱仓库目录（steps/lib/payload 就位）
  mkdir -p "$1/manifests"
  ln -sfn "$ROOT_DIR/lib" "$1/lib"
  ln -sfn "$ROOT_DIR/payload" "$1/payload"
  cp -a "$ROOT_DIR/steps" "$1/steps"
}

# ---------- A. 全量部署 ----------
A="$sandbox/a"; arepo="$A/repo"; aroot="$A/root"; ahome="$aroot/home/pang"; astub="$A/stub-bin"
mkdir -p "$ahome"; make_repo "$arepo"; make_stubs "$astub" "$aroot" "$arepo"
for m in "$ROOT_DIR"/manifests/*.tsv; do cp -- "$m" "$arepo/manifests/"; done

seed_row="$(grep -vE '^[[:space:]]*(#|$)' "$arepo/manifests/seed.tsv" | head -1)"
seed_repo="$(printf '%s' "$seed_row" | cut -f1)"
seed_target="$(awk -F'\t' -v p="$seed_repo" '$1==p {print $2; exit}' "$arepo/manifests/files.tsv")"
[[ -n "$seed_target" ]] || { echo "[FAIL] cannot resolve the first seed row"; exit 1; }
mkdir -p "$(dirname "$aroot$seed_target")"
printf 'USER EDIT\n' > "$aroot$seed_target"

run_a() { env HOME="$ahome" PATH="$astub:$PATH" AN_RUN=1 AN_MACHINE=physical AN_ROOT_DIR="$arepo" \
             AN_TARGET_ROOT="$aroot" AN_TARGET_ALLOW=/ bash "$arepo/steps/07-config.sh"; }

if ! out1="$(run_a 2>&1)"; then
  printf '%s\n' "$out1" | tail -20
  bad "first full sandbox deploy exited non-zero"
fi
grep -q '^\[info\]  files: 341 checked, 340 deployed, 0 unchanged, 1 kept (seed), 0 failed$' <<<"$out1" \
  || bad "unexpected summary: $(grep 'files:' <<<"$out1" | tail -1)"

deploy_warn="$(grep -cE '^\[warn\].*(install failed|post-install verify failed|payload md5 mismatch|payload missing)' <<<"$out1" || true)"
(( deploy_warn == 0 )) || bad "${deploy_warn} deploy warning(s) during the sandbox run"

n=0; nbad=0
while IFS=$'\t' read -r rp tp mode md5; do
  if [[ -z "$rp" || "$rp" == "#"* ]]; then continue; fi
  n=$((n + 1))
  t="$aroot$tp"
  if [[ ! -f "$t" ]]; then bad "not deployed: $tp"; nbad=$((nbad + 1)); continue; fi
  if [[ "$tp" != "$seed_target" ]]; then
    # seed 目标是"存在即保持"的用户数据：权限与内容都由用户决定，不参与部署断言。
    am="$(stat -c '%a' -- "$t")"
    [[ "$am" == "$mode" ]] || { bad "mode mismatch (on disk $am, manifest $mode): $tp"; nbad=$((nbad + 1)); }
    amd5="$(md5sum -- "$t" | awk '{print $1}')"
    [[ "$amd5" == "$md5" ]] || { bad "md5 mismatch: $tp"; nbad=$((nbad + 1)); }
  fi
done < "$arepo/manifests/files.tsv"
[[ "$n" == 341 ]] || bad "iterated $n rows, expected 341"

[[ "$(cat "$aroot$seed_target")" == "USER EDIT" ]] || bad "seed file was overwritten"
grep -q 'kept (seed' <<<"$out1" || bad "kept (seed) message missing"

if ! out2="$(run_a 2>&1)"; then bad "second (idempotent) run exited non-zero"; fi
# 第二次：32 个新初始化的种子 + 预置的那个 = 33 个 seed 目标都已存在 → 全部 kept，其余 unchanged。
grep -q '^\[info\]  files: 341 checked, 0 deployed, 308 unchanged, 33 kept (seed), 0 failed$' <<<"$out2" \
  || bad "second run is not idempotent: $(grep 'files:' <<<"$out2" | tail -1)"

# ---------- B. 失败路径：目标目录不可写 ----------
if [[ "$EUID" == 0 ]]; then
  echo "[skip] failure-path case needs a non-root user (root ignores directory permissions)"
else
  B="$sandbox/b"; brepo="$B/repo"; broot="$B/root"; bhome="$broot/home/pang"; bstub="$B/stub-bin"
  mkdir -p "$bhome/blocked"; make_repo "$brepo"; make_stubs "$bstub" "$broot" "$brepo"
  m="$(md5sum "$ROOT_DIR/payload/home/.bash_profile" | awk '{print $1}')"
  printf 'payload/home/.bash_profile\t/home/pang/blocked/f.txt\t644\t%s\n' "$m" > "$brepo/manifests/files.tsv"
  chmod 500 "$bhome/blocked"
  rc=0
  outb="$(env HOME="$bhome" PATH="$bstub:$PATH" AN_RUN=1 AN_MACHINE=physical AN_ROOT_DIR="$brepo" \
           AN_TARGET_ROOT="$broot" AN_TARGET_ALLOW=/ bash "$brepo/steps/07-config.sh" 2>&1)" || rc=$?
  chmod 700 "$bhome/blocked"
  [[ "$rc" != 0 ]] || bad "a failing install must make 07 exit non-zero"
  grep -q 'install failed' <<<"$outb" || bad "'install failed' warning missing on the failure path"
  grep -q 'files: 1 checked, 0 deployed, 0 unchanged, 0 kept (seed), 1 failed' <<<"$outb" \
    || bad "failure summary wrong: $(grep 'files:' <<<"$outb" | tail -1)"
fi

# ---------- C. 目标白名单：相对路径 / 白名单外目标 ----------
C="$sandbox/c"; crepo="$C/repo"; croot="$C/root"; chome="$croot/home/pang"; cstub="$C/stub-bin"
mkdir -p "$chome"; make_repo "$crepo"; make_stubs "$cstub" "$croot" "$crepo"
m="$(md5sum "$ROOT_DIR/payload/home/.bash_profile" | awk '{print $1}')"
{
  printf 'payload/home/.bash_profile\trelative/path\t644\t%s\n' "$m"
  printf 'payload/home/.bash_profile\t/tmp/arch-noctalia-should-not-be-written\t644\t%s\n' "$m"
} > "$crepo/manifests/files.tsv"
rc=0
outc="$(env HOME="$chome" PATH="$cstub:$PATH" AN_RUN=1 AN_MACHINE=physical AN_ROOT_DIR="$crepo" \
         AN_TARGET_ROOT="$croot" bash "$crepo/steps/07-config.sh" 2>&1)" || rc=$?
[[ "$rc" != 0 ]] || bad "unsafe manifest targets must be rejected before deploying"
grep -q 'manifest target(s) rejected' <<<"$outc" || bad "rejection message missing: $(tail -2 <<<"$outc")"
[[ ! -e /tmp/arch-noctalia-should-not-be-written ]] || bad "a target outside the sandbox was written"
[[ -z "$(find "$croot" -type f -print -quit)" ]] || bad "nothing may be deployed when the manifest is rejected"

if (( fail > 0 )); then
  echo "test-07-deploy-sandbox: FAIL"
  exit 1
fi
echo "ok: 341-row sandbox deploy (modes+md5+seed+idempotent), failure path exits non-zero, unsafe targets rejected"
