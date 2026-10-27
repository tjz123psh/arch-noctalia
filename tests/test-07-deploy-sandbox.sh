#!/usr/bin/env bash
# tests/test-07-deploy-sandbox.sh — 07 的端到端沙箱回归（不碰真机）。
#   1) 全量部署：真实 manifests/files.tsv 的每一行全部落到 <沙箱 root> 之下，
#      逐个核对「存在 + 权限位 == 清单 mode + md5 == 清单 md5」（预置的 seed 目标只核存在性），
#      且部署循环零 warn；
#   2) seed：预置用户内容的种子文件必须保持原样（kept (seed)）；
#   3) 幂等：第二次运行全 unchanged；
#   4) 失败路径：目标目录不可写 → 必须 rc≠0 且摘要行体现 failed（守住「装坏了要报错」）；
#   5) 目标白名单：相对路径 / 白名单外（/tmp/…）目标必须在部署前被拒；
#   6) terminal-tools：部署完成后 Git 半边（6 个全局键 + 回退状态文件）必须到位，
#      且重跑 07 不得重写它们（首次启用前的旧值要能留到 --disable）。
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
           glib-compile-schemas setfacl getfacl mkinitcpio fc-cache update-desktop-database gsettings \
           bat zoxide delta fish; do
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
# 行数不再写死：清单增行时自动跟随（写死过一次，加脚本目录时全员变红）。
total_rows="$(awk -F'\t' '!/^#/ && NF>1' "$arepo/manifests/files.tsv" | wc -l)"
kept_total="$( { awk -F'\t' '!/^#/ && NF>1' "$arepo/manifests/seed.tsv"; awk -F'\t' '!/^#/ && NF>1' "$arepo/manifests/runtime-regenerated.tsv"; } | wc -l )"
exp1="files: ${total_rows} checked, $((total_rows - 1)) deployed, 0 unchanged, 1 kept (seed/runtime), 0 failed"
grep -qF -- "$exp1" <<<"$out1" \
  || bad "unexpected summary: $(grep 'files:' <<<"$out1" | tail -1) (want: $exp1)"

deploy_warn="$(grep -cE '^\[warn\].*(install failed|post-install verify failed|payload md5 mismatch|payload missing)' <<<"$out1" || true)"
(( deploy_warn == 0 )) || bad "${deploy_warn} deploy warning(s) during the sandbox run"

# 终端效率工具的两半边：config.fish 自带其管理块（Fish 半边），07 结尾要调 terminal-tools --enable
# 把 Git 半边（6 个全局键）补进 ~/.gitconfig。少了这一步，重装后状态页报 6 条 warn、git diff 不走 delta，
# 而 12 步与部署复核全绿——2026-10-26 真实重装就是这样静默半天初始化。
tt_state="$ahome/.local/state/maintenance/terminal-tools-git-before.tsv"
tt_conf="$ahome/.gitconfig"
[[ -f "$tt_conf" ]] || bad "terminal-tools: stage 07 did not write ~/.gitconfig (git half of the integration missing)"
tt_bad=""
for kv in 'core.pager=delta' 'interactive.diffFilter=delta --color-only' 'delta.navigate=true' \
          'delta.side-by-side=true' 'merge.conflictstyle=zdiff3' 'diff.colorMoved=default'; do
  k="${kv%%=*}"; v="${kv#*=}"
  # 逐键 --get：git config --list 会把变量名转成小写（interactive.difffilter），不能拿来比对。
  got="$(env HOME="$ahome" git config --global --get "$k" 2>/dev/null || true)"
  [[ "$got" == "$v" ]] || tt_bad="${tt_bad}${k}=[${got}] (want [${v}]) "
done
[[ -z "$tt_bad" ]] || bad "terminal-tools: git keys not applied: ${tt_bad}"
[[ -f "$tt_state" ]] || bad "terminal-tools: rollback state file was not created"
[[ "$(head -n 1 "$tt_state" 2>/dev/null)" == "# maintenance-terminal-tools-v1" ]] \
  || bad "terminal-tools: rollback state file has an unexpected header"
tt_state_md5="$(md5sum -- "$tt_state" 2>/dev/null | awk '{print $1}')"
tt_conf_md5="$(md5sum -- "$tt_conf" 2>/dev/null | awk '{print $1}')"

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
[[ "$n" == "$total_rows" ]] || bad "iterated $n rows, expected $total_rows"

[[ "$(cat "$aroot$seed_target")" == "USER EDIT" ]] || bad "seed file was overwritten"
grep -q 'kept (seed' <<<"$out1" || bad "kept (seed) message missing"

# runtime（桌面/程序自行改写的文件，如 Noctalia 主题产物、登录背景）：内容被改过后重跑必须保持，
# 不许被打回仓库快照（否则 --redo 07 会静默回退主题与壁纸，并连带丢掉 11 步加的 ACL）。
rt_repo="$(awk -F'\t' '!/^#/ && NF>1 {print $1; exit}' "$arepo/manifests/runtime-regenerated.tsv")"
rt_target="$(awk -F'\t' -v r="$rt_repo" '!/^#/ && $1==r {print $2; exit}' "$arepo/manifests/files.tsv")"
[[ -n "$rt_target" ]] || bad "cannot resolve a runtime target for the keep-assertion"
printf 'RUNTIME EDIT\n' > "$aroot$rt_target"

if ! out2="$(run_a 2>&1)"; then bad "second (idempotent) run exited non-zero"; fi
# 第二次：34 个 seed + 26 个 runtime 目标都已存在 → 60 个 kept，其余 460 个 unchanged（幂等）。
exp2="files: ${total_rows} checked, 0 deployed, $((total_rows - kept_total)) unchanged, ${kept_total} kept (seed/runtime), 0 failed"
grep -qF -- "$exp2" <<<"$out2" \
  || bad "second run is not idempotent: $(grep 'files:' <<<"$out2" | tail -1) (want: $exp2)"
[[ "$(cat "$aroot$rt_target")" == "RUNTIME EDIT" ]] || bad "runtime-regenerated file was overwritten by a re-run"
grep -q 'kept (runtime' <<<"$out2" || bad "kept (runtime) message missing"

# terminal-tools：重跑 07 不得重现刷 git 配置，也不得覆盖首次启用时记下的回退值（否则 --disable 回错值）。
grep -q 'terminal-tools: git integration already applied' <<<"$out2" \
  || bad "second run did not report the terminal-tools git half as already applied"
[[ "$(md5sum -- "$tt_state" 2>/dev/null | awk '{print $1}')" == "$tt_state_md5" ]] \
  || bad "second run rewrote the terminal-tools rollback state (first-enable values must survive)"
[[ "$(md5sum -- "$tt_conf" 2>/dev/null | awk '{print $1}')" == "$tt_conf_md5" ]] \
  || bad "second run rewrote ~/.gitconfig (the git half should be a no-op when already applied)"

# runtime 的例外：/etc/supergfxd.conf 的 hotplug_type=Asus 是安装器保证值，写错了必须被修回来（
# 不能被「运行时文件保持现状」放过，否则 README 里那个「切集显重启又回混合」的坑会复发）。
printf '{"mode": "Hybrid", "hotplug_type": "None"}\n' > "$aroot/etc/supergfxd.conf"
if ! run_a >/dev/null 2>&1; then bad "third run (supergfxd repair) exited non-zero"; fi
grep -q '"hotplug_type": "Asus"' "$aroot/etc/supergfxd.conf" \
  || bad "supergfxd.conf hotplug_type was not repaired back to Asus"

# ---------- D. 软链：内容一致保持链接；内容不同才替换，并留下「原本指向哪」 ----------
dstore="$sandbox/d-store"; mkdir -p "$dstore"
link_t="$aroot/home/pang/.bash_profile"
cp -p -- "$link_t" "$dstore/same.conf"
printf 'LOCAL OVERRIDE\n' > "$dstore/diff.conf"
rm -f -- "$link_t"; ln -s "$dstore/same.conf" "$link_t"
if ! outd1="$(run_a 2>&1)"; then bad "symlink(identical) run exited non-zero"; fi
[[ -L "$link_t" ]] || bad "identical-content symlink was replaced by a regular file"
grep -q 'kept (symlink, identical content)' <<<"$outd1" || bad "kept (symlink) message missing"

rm -f -- "$link_t"; ln -s "$dstore/diff.conf" "$link_t"
if ! run_a >/dev/null 2>&1; then bad "symlink(differs) run exited non-zero"; fi
[[ ! -L "$link_t" ]] || bad "a symlink with different content should have been replaced"
[[ "$(cat "$link_t")" == "$(cat "$ROOT_DIR/payload/home/.bash_profile")" ]] || bad "symlink target was not restored to the manifest content"
link_rec="$(find "$ahome/.local/state/arch-noctalia/overwritten" -name '*.symlink' -print -quit 2>/dev/null || true)"
[[ -n "$link_rec" ]] || bad "no *.symlink record was written for the replaced symlink"
[[ "$(cat "$link_rec")" == "$dstore/diff.conf" ]] || bad "the *.symlink record does not point at the original target"

# ---------- E. 备份失败 → 不覆盖（fail-closed） ----------
E="$sandbox/e"; erepo="$E/repo"; eroot="$E/root"; ehome="$eroot/home/pang"; estub="$E/stub-bin"; estate="$E/state-ro"
mkdir -p "$ehome" "$estate"; make_repo "$erepo"; make_stubs "$estub" "$eroot" "$erepo"
m="$(md5sum "$ROOT_DIR/payload/home/.bash_profile" | awk '{print $1}')"
printf 'payload/home/.bash_profile\t/home/pang/keep.conf\t644\t%s\n' "$m" > "$erepo/manifests/files.tsv"
printf 'USER DATA\n' > "$eroot/home/pang/keep.conf"
chmod 500 "$estate"
rc=0
oute="$(env HOME="$ehome" PATH="$estub:$PATH" AN_RUN=1 AN_MACHINE=physical AN_ROOT_DIR="$erepo" \
        AN_TARGET_ROOT="$eroot" AN_TARGET_ALLOW=/ AN_STATE_DIR="$estate/state" \
        bash "$erepo/steps/07-config.sh" 2>&1)" || rc=$?
chmod 700 "$estate"
[[ "$rc" != 0 ]] || bad "a failed backup must make 07 exit non-zero (fail-closed)"
[[ "$(cat "$eroot/home/pang/keep.conf")" == "USER DATA" ]] || bad "the file was overwritten even though the backup failed"
grep -q 'refusing to overwrite without a backup copy' <<<"$oute" || bad "missing fail-closed message"

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
  grep -q 'files: 1 checked, 0 deployed, 0 unchanged, 0 kept (seed/runtime), 1 failed' <<<"$outb" \
    || bad "failure summary wrong: $(grep 'files:' <<<"$outb" | tail -1)"
fi

# ---------- C. 目标白名单：相对路径 / 白名单外目标 ----------
C="$sandbox/c"; crepo="$C/repo"; croot="$C/root"; chome="$croot/home/pang"; cstub="$C/stub-bin"
mkdir -p "$chome"; make_repo "$crepo"; make_stubs "$cstub" "$croot" "$crepo"
m="$(md5sum "$ROOT_DIR/payload/home/.bash_profile" | awk '{print $1}')"
{
  printf 'payload/home/.bash_profile\trelative/path\t644\t%s\n' "$m"
  printf 'payload/home/.bash_profile\t/tmp/arch-noctalia-should-not-be-written\t644\t%s\n' "$m"
  # "/opt/../tmp/x" 归一化后就是 /tmp/x：白名单必须按归一化后的路径判断，否则 ".." 能绕过。
  printf 'payload/home/.bash_profile\t/opt/../tmp/arch-noctalia-should-not-be-written\t644\t%s\n' "$m"
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
echo "ok: ${total_rows}-row sandbox deploy (modes+md5+seed+idempotent), failure path exits non-zero, unsafe targets rejected"
