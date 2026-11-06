#!/usr/bin/env bash
# tests/test-tide-sidebar-install.sh — 侧边栏插件在安装器里的「契约」回归（离线、零副作用）。
# 目的：`pang/tide-sidebar` 是唯一带原生 GTK4 前端的插件，它的失败形态是**静默**的
#       （Super+Shift+W 无反应，只有插件日志里报一句“原生侧栏无法启动”）。所以把安装器
#       这一侧的保证逐条钉死，避免“清单删了一行/改了路径 → 装完才发现面板起不来”。
#
# 锁五件事：
#   1) 09 预检列表里的每个插件文件都真实存在于 payload，且都在 files.tsv 里（07 会部署它）；
#      ——防止“09 检查一个没人部署的路径”。
#   2) 原生前端运行时 gjs 与 gtk4-layer-shell 都在 packages.tsv 里显式声明（不靠传递依赖）。
#   3) workspaces.json 同时登记在 files.tsv 与 seed.tsv（07 缺失时初始化、存在即保持）。
#   4) 行为：插件目录缺失时 09 必须以非零退出并指向 stage 07（不能静默放行）。
#   5) 行为：插件文件齐全但 gjs 不在 PATH 时 09 必须明确报 gjs 并失败。
# 所有写入都在 mktemp 沙箱内（HOME / AN_TARGET_ROOT / AN_STATE_DIR），不碰真实系统。
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STEP="$ROOT_DIR/steps/09-noctalia.sh"
FILES="$ROOT_DIR/manifests/files.tsv"
SEED="$ROOT_DIR/manifests/seed.tsv"
PACKAGES="$ROOT_DIR/manifests/packages.tsv"

fail=0
bad() { echo "[FAIL] $*"; fail=1; }

# --- 0) 玻璃材质依赖 niri 图层规则与 Inter 字体 ---
LAYER_RULES="$ROOT_DIR/payload/home/.config/niri/conf.d/layer-rules.kdl"
if ! grep -q 'noctalia-tide-sidebar' "$LAYER_RULES" 2>/dev/null; then
  bad "layer-rules.kdl 缺少 noctalia-tide-sidebar 规则（玻璃会退回不透明）"
elif ! awk '/match namespace="\^noctalia-tide-sidebar\$"/,/^}/' "$LAYER_RULES" | grep -q 'blur true'; then
  bad "noctalia-tide-sidebar 规则没有 blur true"
fi
grep -q '^inter-font' "$PACKAGES" || bad "packages.tsv 缺少 inter-font（排印会回落到 Adwaita Sans）"

# --- 1) 09 的预检列表 ⊆ payload ⊆ files.tsv ---
# 从步骤脚本里抽出 plugin_files=( ... ) 数组（唯一事实来源就是它，不在测试里另抄一份）。
mapfile -t preflight < <(
  awk '
    /^plugin_files=\(/ { inside = 1; next }
    inside && /^\)/ { inside = 0; next }
    inside {
      line = $0
      sub(/#.*/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line == "") next
      gsub(/^"|"$/, "", line)
      print line
    }
  ' "$STEP"
)
if (( ${#preflight[@]} == 0 )); then
  bad "cannot extract plugin_files from steps/09-noctalia.sh"
fi
checked_preflight=0
for entry in "${preflight[@]}"; do
  # 只保留 tide-sidebar 的条目；magnifier 由它自己的历史负责。
  case "$entry" in
    *tide-sidebar*) ;;
    *) continue ;;
  esac
  checked_preflight=$((checked_preflight + 1))
  # ${PLUGINS_DIR} → ~/noctalia-plugins ⇒ payload/home/noctalia-plugins
  rel="payload/home/noctalia-plugins${entry#\$\{PLUGINS_DIR\}}"
  [[ -f "$ROOT_DIR/$rel" ]] || bad "09 preflight references a file that is not in the repo: ${rel}"
  target="/home/pang/noctalia-plugins${entry#\$\{PLUGINS_DIR\}}"
  grep -qF "$(printf '%s\t%s\t' "$rel" "$target")" "$FILES" \
    || bad "09 preflight file is not deployed by 07 (missing from files.tsv): ${rel}"
done
(( checked_preflight >= 17 )) \
  || bad "09 preflight covers only ${checked_preflight} tide-sidebar files - the list looks truncated"

# --- 2) 原生运行时必须在 packages.tsv 里显式声明 ---
for pkg in gjs gtk4-layer-shell; do
  grep -qP "^${pkg}\t" "$PACKAGES" || bad "packages.tsv does not declare ${pkg} (native frontend runtime)"
done

# --- 3) workspaces.json：07 部署 + seed 语义（用户改过的永不被覆盖） ---
ws_repo="payload/home/.config/noctalia/workspaces.json"
ws_target="/home/pang/.config/noctalia/workspaces.json"
grep -qF "$(printf '%s\t%s\t' "$ws_repo" "$ws_target")" "$FILES" \
  || bad "workspaces.json is not in files.tsv (07 would not deploy the template)"
grep -qF "${ws_repo}	" "$SEED" \
  || bad "workspaces.json is not a seed row (a user-edited workspace list would be overwritten on re-run)"

# --- 4)/5) 行为：在沙箱里真跑 09 ---
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
case "$sandbox" in /tmp/*|/var/tmp/*) ;; *) echo "[FAIL] sandbox is not under /tmp: $sandbox"; exit 1;; esac
cd "$sandbox"

repo="$sandbox/repo"; root="$sandbox/root"; home="$root/home/pang"
shim="$sandbox/shim"
mkdir -p "$repo/manifests" "$home" "$root/etc" "$shim"
ln -s "$ROOT_DIR/lib" "$repo/lib"
ln -s "$ROOT_DIR/payload" "$repo/payload"
cp -a "$ROOT_DIR/steps" "$repo/steps"
cp -- "$ROOT_DIR"/manifests/*.tsv "$repo/manifests/"

# 沙箱 PATH 只放必要符号链接（**不含 /usr/bin**）：否则真实 gjs 会一直被 command -v 找到，
# “缺 gjs 必须报错”这条断言就永远测不到。缺了什么命令，对照组（要求 rc=0）会立即报错。
for c in bash sh timeout mkdir rmdir find dirname basename cat head tail rm cp mv chmod touch ls \
         sed awk grep tr cut sort wc id uname date sleep printf echo test true false; do
  src="$(command -v "$c" 2>/dev/null || true)"
  [[ -n "$src" ]] && ln -sf "$src" "$shim/$c"
done
printf '#!/bin/sh\nexit 0\n' > "$shim/noctalia"; chmod +x "$shim/noctalia"

run_09() { # 输出到 $sandbox/out, 退出码到 stdout
  local rc=0
  (
    cd "$sandbox"
    env -u AN_MACHINE \
        HOME="$home" PATH="$shim" \
        AN_RUN=1 AN_MACHINE=physical \
        AN_ROOT_DIR="$repo" AN_TARGET_ROOT="$root" AN_STATE_DIR="$sandbox/state" \
        timeout 30 "$shim/bash" "$repo/steps/09-noctalia.sh"
  ) > "$sandbox/out" 2>&1 || rc=$?
  printf '%s' "$rc"
}

# 4) 插件目录缺失 → 必须失败，且提示与 stage 07 有关。
rc="$(run_09)"
if [[ "$rc" == "0" ]]; then
  bad "09 exited 0 although ~/noctalia-plugins is empty (silent broken install)"
elif ! grep -qiE "plugin|07" "$sandbox/out"; then
  bad "09 failed for an unexpected reason (missing-note is not about plugins/stage 07): $(tail -1 "$sandbox/out")"
fi

# 铺好插件目录（从 payload 复制，路径与真实部署一致）+ 预置可执行的 cursor-track，
# 让 09 跳过编译分支（本测试不依赖 gcc/wayland-scanner）。
mkdir -p "$home/noctalia-plugins" "$home/bin" "$home/.local/state/noctalia"
cp -a "$ROOT_DIR/payload/home/noctalia-plugins/." "$home/noctalia-plugins/"
printf '#!/bin/sh\nexit 0\n' > "$home/bin/cursor-track"; chmod +x "$home/bin/cursor-track"
touch "$home/.local/state/noctalia/settings.toml"
# 让二进制比源码新，命中 "up to date" 分支。
find "$home/noctalia-plugins/magnifier/tools/cursor-track" -maxdepth 1 -type f \
  -exec touch -d '2020-01-01' {} + 2>/dev/null || true

# 5) 文件齐全但 gjs 缺失 → 必须失败并点名 gjs。
rm -f "$shim/gjs"
rc="$(run_09)"
if [[ "$rc" == "0" ]]; then
  bad "09 exited 0 without gjs in PATH (native frontend would not start)"
elif ! grep -qi "gjs" "$sandbox/out"; then
  bad "09 did not mention gjs when it is missing: $(tail -1 "$sandbox/out")"
fi

# 对照组：文件 + gjs 都齐 → 09 必须成功（否则上面的失败断言毫无意义）。
printf '#!/bin/sh\nexit 0\n' > "$shim/gjs"; chmod +x "$shim/gjs"
rc="$(run_09)"
if [[ "$rc" != "0" ]]; then
  bad "09 failed with a complete plugin tree and gjs present: $(tail -2 "$sandbox/out")"
fi

if (( fail == 0 )); then
  echo "ok: tide-sidebar installer contract - ${checked_preflight} preflight files deployed, gjs/gtk4-layer-shell declared, workspaces.json seeded, 09 fails loudly on a broken tree"
fi
exit "$fail"
