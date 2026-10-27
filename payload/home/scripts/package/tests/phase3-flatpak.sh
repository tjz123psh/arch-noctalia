#!/usr/bin/env bash
# 三期验收：pac 的 Flatpak 支持（原 pak 已并入）
#
# 验的是四件事：
#   1. 索引里同时出现官方源 / AUR / Flatpak 三种来源，Flatpak 行带 origin 与已安装标记
#   2. 预览按来源分派：Flatpak 行走 flatpak remote-info，别的走 pacman/paru
#   3. 安装按来源分派：Flatpak 行走 flatpak install，官方源行走 paru -S
#   4. flatpak 不存在时静默退回纯 pacman/AUR，不报错也不卡住
#
# 全程在临时目录里跑，不装不删任何东西：pacman / paru / flatpak / fzf 都是替身。
#
# 用法: tests/phase3-flatpak.sh [pac 路径]

set -euo pipefail

PKG_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PAC="${1:-$PKG_DIR/pac}"
[[ -x "$PAC" ]] || { echo "找不到可执行脚本: $PAC" >&2; exit 1; }

TMP="$(mktemp -d /tmp/pac-phase3.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT

BIN="$TMP/bin"
BINNOFP="$TMP/bin-nofp"
MINBIN="$TMP/minbin"
mkdir -p "$BIN" "$BINNOFP" "$MINBIN"

# 除 pacman / paru / flatpak / fzf 外，其余工具软链到 /usr/bin
for f in /usr/bin/*; do
    [[ -x "$f" && ! -d "$f" ]] || continue
    b="${f##*/}"
    case "$b" in pacman|paru|flatpak|fzf) continue ;; esac
    ln -sf "$f" "$MINBIN/$b"
done

cat >"$BIN/pacman" <<'EOS'
#!/usr/bin/env bash
case "$*" in
    *-Qq*) printf 'bash\n' ;;
    *-Sl*) printf 'core bash 5.3.20-1\n' ;;
    *-Si*) printf 'Repository      : core\nName            : bash\nVersion         : 5.3.20-1\n' ;;
    *-Qi*) printf 'Name            : bash\nVersion         : 5.3.20-1\n' ;;
    *) exit 0 ;;
esac
EOS
cat >"$BIN/paru" <<'EOS'
#!/usr/bin/env bash
printf 'paru %s\n' "$*" >>"${FAKE_PARU_LOG:?}"
exit 0
EOS
cat >"$BIN/flatpak" <<'EOS'
#!/usr/bin/env bash
printf 'flatpak %s\n' "$*" >>"${FAKE_FLATPAK_LOG:?}"
case "$*" in
    *remotes*)       printf 'flathub\n' ;;
    *"remote-ls"*)   printf 'flathub\torg.example.App\tExample App\nflathub\torg.example.Other\tOther App\n' ;;
    *"list --app"*)  printf 'org.example.App\n' ;;
    *"remote-info"*) printf 'ID: org.example.App\n名称: Example App\n版本: 1.2.3\n' ;;
    *"info"*)        printf 'ID: org.example.App\n名称: Example App\n' ;;
    *) exit 0 ;;
esac
EOS
cat >"$BIN/fzf" <<'EOS'
#!/usr/bin/env bash
cat
EOS
chmod +x "$BIN/pacman" "$BIN/paru" "$BIN/flatpak" "$BIN/fzf"
cp "$BIN/pacman" "$BIN/paru" "$BIN/fzf" "$BINNOFP/"

export FAKE_PARU_LOG="$TMP/paru.log"
export FAKE_FLATPAK_LOG="$TMP/flatpak.log"

run_pac() {  # run_pac <bin 目录> [参数...]
    local bindir="$1"; shift
    env XDG_CACHE_HOME="$TMP/cache" PATH="$bindir:$MINBIN" \
        FAKE_PARU_LOG="$FAKE_PARU_LOG" FAKE_FLATPAK_LOG="$FAKE_FLATPAK_LOG" \
        "$PAC" "$@" 2>&1 || true
}

seed_aur_cache() {
    mkdir -p "$TMP/cache/pac"
    printf 'testpkg\n' > "$TMP/cache/pac/aur-packages.txt"
    touch "$TMP/cache/pac/aur-packages.txt"
}

PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
assert_contains()     { if grep -qF -- "$1" <<<"$2"; then ok "$3"; else bad "$3"; fi; }
assert_not_contains() { if grep -qF -- "$1" <<<"$2"; then bad "$3"; else ok "$3"; fi; }

echo "== 前置检查：装置可信 =="
PATH="$BIN:$MINBIN" command -v flatpak | grep -qF "$BIN/flatpak" || { echo "  装置失效：假 flatpak 没生效" >&2; exit 1; }
if PATH="$BINNOFP:$MINBIN" command -v flatpak >/dev/null 2>&1; then echo "  装置失效：无 fp 的 PATH 上仍有 flatpak" >&2; exit 1; fi
echo "  OK（flatpak 是替身；另一条 PATH 上确实没有 flatpak）"

echo
echo "== 用例 1：索引里三种来源同屏 =="
seed_aur_cache
out="$(run_pac "$BIN" --index)"
printf '%s\n' "$out" | grep -E 'flathub/|core/bash|aur/testpkg' | sed 's/^/    /' | head -6
assert_contains "flathub/org.example.App" "$out" "Flatpak 行在索引里"
assert_contains "[installed]" "$out" "已安装的 Flatpak 有标记"
assert_contains "Example App" "$out" "Flatpak 行带应用名"
assert_contains "core/bash" "$out" "官方源行还在"
assert_contains "aur/testpkg" "$out" "AUR 行还在"

echo
echo "== 用例 2：预览按来源分派 =="
out="$(run_pac "$BIN" --preview flathub/org.example.App flathub)"
assert_contains "Example App" "$out" "Flatpak 预览有内容"
assert_contains "1.2.3" "$out" "Flatpak 预览显示版本"
out="$(run_pac "$BIN" --preview core/bash)"
assert_contains "5.3.20-1" "$out" "官方源预览仍走 pacman -Si"

echo
echo "== 用例 3：安装按来源分派 =="
: >"$FAKE_FLATPAK_LOG"; : >"$FAKE_PARU_LOG"
out="$(run_pac "$BIN" --install flathub/org.example.App)"
assert_contains "flatpak install org.example.App" "$(cat "$FAKE_FLATPAK_LOG")" "Flatpak 走 flatpak install"
assert_not_contains "paru -S" "$(cat "$FAKE_PARU_LOG")" "没有误调 paru"
out="$(run_pac "$BIN" --install core/bash)"
assert_contains "paru -S -- core/bash" "$(cat "$FAKE_PARU_LOG")" "官方源走 paru -S"

echo
echo "== 用例 4：dry-run 不真的装 =="
: >"$FAKE_FLATPAK_LOG"
out="$(env XDG_CACHE_HOME="$TMP/cache" PATH="$BIN:$MINBIN" FAKE_FLATPAK_LOG="$FAKE_FLATPAK_LOG" \
    PARU_UI_DRY_RUN=1 "$PAC" --install flathub/org.example.App 2>&1 || true)"
assert_contains "[DRY_RUN]" "$out" "打印了 DRY_RUN"
# 注意：is_flatpak_origin 会调 flatpak remotes 做只读探测，这里只断言没有真的安装
if grep -q '^flatpak install' "$FAKE_FLATPAK_LOG" 2>/dev/null; then bad "dry-run 仍然调用了 flatpak install"; else ok "没有真的调用 flatpak install"; fi

echo
echo "== 用例 5：pak 壳只列 Flatpak =="
seed_aur_cache
out="$(run_pac "$BIN" --flatpak --index)"
printf '%s\n' "$out" | head -3 | sed 's/^/    /'
assert_contains "flathub/org.example.App" "$out" "有 Flatpak 行"
assert_not_contains "core/bash" "$out" "没有官方源行"
assert_not_contains "aur/testpkg" "$out" "没有 AUR 行"

echo
echo "== 用例 6：没有 flatpak 时静默退回 =="
seed_aur_cache
# 必须清掉索引缓存，否则会直接复用上一轮含 Flatpak 行的缓存
rm -f "$TMP/cache/pac/package-index.tsv" "$TMP/cache/pac/flatpak-index.tsv"
out="$(run_pac "$BINNOFP" --index)"
assert_contains "core/bash" "$out" "官方源行正常"
assert_not_contains "flathub/" "$out" "没有 Flatpak 行"
assert_not_contains "未找到" "$out" "没有报错"

echo
echo "== 汇总：PASS=$PASS FAIL=$FAIL =="
(( FAIL == 0 ))
