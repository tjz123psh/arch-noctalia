#!/usr/bin/env bash
# 二期验收：pacr 的家目录残留清单与永久删除
#
# 验的是四件事：
#   1. 按包元数据派生的关键词能枚举出候选（.config/.cache/.local/share 与可见目录）
#   2. 豁免名单里的路径（.ssh、gtk-3.0 等）既不出现在清单里，也不会被删
#   3. 删除是永久删除，且必须输入确认词；确认词不对则一条都不删
#   4. --no-clean / --dry-run 不动任何文件；pacrrr 壳仍然能追踪并清理
#
# 全程在临时 HOME 里跑，不碰真实系统：
#   - 假 pacman / 假 paru：返回固定输出，卸载只记参数
#   - 假 fzf：把输入行原样输出，等价于"全选并回车"
#
# 用法: tests/phase2-leftover.sh [pacr 路径]
# shellcheck disable=SC2088  # 断言描述里的 ~ 是给人看的文字，不参与路径展开

set -euo pipefail

PKG_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PACR="${1:-$PKG_DIR/pacr}"
# pacrrr 已删除：追踪入口就是 pacr --trace-command
[[ -x "$PACR" ]] || { echo "找不到可执行脚本: $PACR" >&2; exit 1; }

TMP="$(mktemp -d /tmp/pacr-phase2.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT

FAKE_HOME="$TMP/home"
# AI 配置隔离：指向空目录，pacr 就不会去读用户真配置、也不会发请求
mkdir -p "$TMP/config"
BIN="$TMP/bin"
MINBIN="$TMP/minbin"
mkdir -p "$FAKE_HOME" "$BIN" "$MINBIN"

# 候选夹具
mkdir -p "$FAKE_HOME/.config/fakeapp" "$FAKE_HOME/.cache/fakeapp" "$FAKE_HOME/.local/share/fakeapp"
mkdir -p "$FAKE_HOME/Documents/FakeApp Data"
printf 'conf\n' > "$FAKE_HOME/.config/fakeapp/conf"
printf 'cache\n' > "$FAKE_HOME/.cache/fakeapp/cache.bin"
printf 'data\n' > "$FAKE_HOME/.local/share/fakeapp/data"
printf 'notes\n' > "$FAKE_HOME/Documents/FakeApp Data/notes.txt"
# 豁免夹具：绝不能出现在清单里、也绝不能被删
mkdir -p "$FAKE_HOME/.ssh/fakeapp" "$FAKE_HOME/.config/gtk-3.0"
printf 'KEY\n' > "$FAKE_HOME/.ssh/fakeapp/id_ed25519"
printf 'gtk\n' > "$FAKE_HOME/.config/gtk-3.0/settings.ini"

# 除 pacman / paru / flatpak / fzf 外，其它工具都软链到 /usr/bin
for f in /usr/bin/*; do
    [[ -x "$f" && ! -d "$f" ]] || continue
    b="${f##*/}"
    case "$b" in pacman|paru|flatpak|fzf) continue ;; esac
    ln -sf "$f" "$MINBIN/$b"
done

cat >"$BIN/pacman" <<'EOS'
#!/usr/bin/env bash
args="$*"
case "$args" in
    *-Qlq*) printf '/usr/bin/fakeapp\n/usr/share/applications/fakeapp.desktop\n' ;;
    *-Qqo*) printf 'fakeapp\n' ;;
    *-Qsq*) printf 'fakeapp\n' ;;
    *-Qi*)  printf 'Name            : fakeapp\nDescription     : Fake application for tests\nURL             : https://github.com/example/fakeapp\n' ;;
    *-Sl*)  printf 'core fakeapp 1.0-1\n' ;;
    *-Q*)   printf 'fakeapp 1.0-1\n' ;;
    *) exit 0 ;;
esac
EOS
chmod +x "$BIN/pacman"

cat >"$BIN/paru" <<'EOS'
#!/usr/bin/env bash
printf 'paru %s\n' "$*" >>"${FAKE_PARU_LOG:?}"
exit 0
EOS
chmod +x "$BIN/paru"

# 假 fzf：把候选行原样输出（等价于真 fzf 的"全选 + 回车"）
cat >"$BIN/fzf" <<'EOS'
#!/usr/bin/env bash
cat
EOS
chmod +x "$BIN/fzf"

export FAKE_PARU_LOG="$TMP/paru.log"

run_pacr() {  # run_pacr <stdin 内容> [参数...]
    local input="$1"; shift
    printf '%s' "$input" | env HOME="$FAKE_HOME" XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config" \
        PATH="$BIN:$MINBIN" FAKE_PARU_LOG="$FAKE_PARU_LOG" "$PACR" "$@" 2>&1 || true
}

PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
assert_contains()     { if grep -qF -- "$1" <<<"$2"; then ok "$3"; else bad "$3"; fi; }
assert_not_contains() { if grep -qF -- "$1" <<<"$2"; then bad "$3"; else ok "$3"; fi; }
assert_exists()       { if [[ -e "$1" ]]; then ok "$2"; else bad "$2"; fi; }
assert_gone()         { if [[ -e "$1" ]]; then bad "$2"; else ok "$2"; fi; }

echo "== 前置检查：测试装置本身可信 =="
PATH="$BIN:$MINBIN" command -v pacman | grep -qF "$BIN/pacman" || { echo "  装置失效：假 pacman 没生效" >&2; exit 1; }
PATH="$BIN:$MINBIN" command -v paru | grep -qF "$BIN/paru" || { echo "  装置失效：假 paru 没生效" >&2; exit 1; }
PATH="$BIN:$MINBIN" command -v flatpak >/dev/null 2>&1 && { echo "  装置失效：flatpak 仍在 PATH 上" >&2; exit 1; }
echo "  OK（pacman/paru/fzf 都是假的，flatpak 不可见）"

echo
echo "== 用例 1：--scan 只列候选，豁免项不出现，什么都不删 =="
out="$(run_pacr '' --scan)"
printf '%s\n' "$out" | sed 's/^/    /' | head -20
assert_contains "~/.config/fakeapp" "$out" "列出了 ~/.config/fakeapp"
assert_contains "~/.cache/fakeapp" "$out" "列出了 ~/.cache/fakeapp"
assert_contains "~/.local/share/fakeapp" "$out" "列出了 ~/.local/share/fakeapp"
assert_contains "Documents/FakeApp Data" "$out" "列出了可见目录里的偏门位置"
assert_not_contains ".ssh" "$out" "豁免项 .ssh 没有出现"
assert_not_contains "gtk-3.0" "$out" "豁免项 gtk-3.0 没有出现"
assert_exists "$FAKE_HOME/.config/fakeapp" "--scan 没有删除任何东西"

echo
echo "== 用例 2：卸载后清理（永久删除，豁免项不动）=="
: >"$FAKE_PARU_LOG"
out="$(run_pacr $'y\ndelete\n')"
printf '%s\n' "$out" | grep -E 'rm -rf|已删除|deleted|准备卸载|Preparing' | sed 's/^/    /' | head -12
assert_contains "paru -Rns fakeapp" "$(cat "$FAKE_PARU_LOG")" "真的调用了 paru -Rns fakeapp"
assert_gone "$FAKE_HOME/.config/fakeapp" "~/.config/fakeapp 已被删除"
assert_gone "$FAKE_HOME/.cache/fakeapp" "~/.cache/fakeapp 已被删除"
assert_gone "$FAKE_HOME/.local/share/fakeapp" "~/.local/share/fakeapp 已被删除"
assert_gone "$FAKE_HOME/Documents/FakeApp Data" "可见目录里的偏门位置也被删除"
assert_exists "$FAKE_HOME/.ssh/fakeapp/id_ed25519" "豁免项 ~/.ssh 完好"
assert_exists "$FAKE_HOME/.config/gtk-3.0/settings.ini" "豁免项 gtk-3.0 完好"

echo
echo "== 用例 3：确认词不对 → 一条都不删 =="
mkdir -p "$FAKE_HOME/.config/fakeapp"; printf 'conf\n' > "$FAKE_HOME/.config/fakeapp/conf"
: >"$FAKE_PARU_LOG"
out="$(run_pacr $'y\nnope\n')"
assert_contains "已取消" "$out" "提示了已取消"
assert_exists "$FAKE_HOME/.config/fakeapp" "文件仍在"

echo
echo "== 用例 4：--no-clean → 不追问、不删除 =="
: >"$FAKE_PARU_LOG"
out="$(run_pacr '' --no-clean)"
assert_not_contains "是否清理家目录残留" "$out" "没有出现清理追问"
assert_exists "$FAKE_HOME/.config/fakeapp" "文件仍在"
assert_contains "paru -Rns fakeapp" "$(cat "$FAKE_PARU_LOG")" "仍然完成了卸载"

echo
echo "== 用例 5：--dry-run → 只打印，不卸载不删除 =="
: >"$FAKE_PARU_LOG"
out="$(run_pacr '' --dry-run)"
assert_contains "[DRY_RUN]" "$out" "打印了 DRY_RUN"
assert_exists "$FAKE_HOME/.config/fakeapp" "文件仍在"
if [[ -s "$FAKE_PARU_LOG" ]]; then bad "dry-run 仍然调用了 paru"; else ok "没有真的调用 paru"; fi

echo
echo "== 用例 6：pacr --trace-command → 追踪到的路径被清理，且可拒绝卸载 =="
TRACE_TARGET="$FAKE_HOME/.config/traceapp"
TRACE_MARKER="$TMP/trace-ran"
cat >"$TMP/traceapp.sh" <<'EOS'
#!/usr/bin/env bash
printf 'ran\n' >>"${PACR_TRACE_MARKER:?}"
mkdir -p "$HOME/.config/traceapp"
printf 'x\n' > "$HOME/.config/traceapp/conf"
sleep 1
EOS
chmod +x "$TMP/traceapp.sh"
rm -f "$TRACE_MARKER"
: >"$FAKE_PARU_LOG"
# 延时喂 stdin：追踪阶段必须拿不到输入，否则 run_trace 里的 read 会立刻返回、
# 目标程序还没写文件就被杀掉（这正是上一轮用例 6 假通过的原因）
out="$( (sleep 5; printf 'delete\nn\n') | env HOME="$FAKE_HOME" XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config" \
    PATH="$BIN:$MINBIN" FAKE_PARU_LOG="$FAKE_PARU_LOG" PACR_TRACE_MARKER="$TRACE_MARKER" \
    "$PACR" --trace-command -t 5 "$TMP/traceapp.sh" 2>&1 || true)"
printf '%s\n' "$out" | grep -E '追踪|traced|已删除|deleted' | sed 's/^/    /' | head -8
assert_exists "$TRACE_MARKER" "追踪目标确实运行过（不是假通过）"
assert_gone "$TRACE_TARGET" "追踪到的 ~/.config/traceapp 已被删除"
assert_not_contains "paru -Rns" "$(cat "$FAKE_PARU_LOG")" "回答了 n，没有真的卸载"

echo
echo "== 用例 7：--trace --dry-run 不得真的启动被追踪的程序 =="
cat >"$BIN/fakeapp" <<'EOS'
#!/usr/bin/env bash
printf 'ran\n' >>"${PACR_TRACE_MARKER:?}"
exit 0
EOS
chmod +x "$BIN/fakeapp"
rm -f "$TRACE_MARKER"
: >"$FAKE_PARU_LOG"
out="$(run_pacr '' --trace --dry-run)"
assert_contains "[DRY_RUN]" "$out" "打印了 DRY_RUN"
assert_exists "$FAKE_HOME/.config/fakeapp" "没有删除任何东西"
if [[ -e "$TRACE_MARKER" ]]; then bad "dry-run 竟然启动了被追踪的程序"; else ok "没有启动被追踪的程序"; fi

echo
echo "== 用例 8：--help 提到新选项 =="
out="$("$PACR" --help 2>&1)"
assert_contains "--no-clean" "$out" "帮助里有 --no-clean"
assert_contains "--scan" "$out" "帮助里有 --scan"
assert_contains "--trace" "$out" "帮助里有 --trace"
assert_contains "--dry-run" "$out" "帮助里有 --dry-run"

echo
echo "== 用例 9：拆出来的弱关键词只认整名（真机踩过的坑）=="
# 真机上 kimi-code-bin 拆出 "code" 后，靠包含匹配把 ~/.config/opencode、~/Projects/punycode.js
# 这类东西全扫了进来。这条用例就是把这个行为钉死。
FAKE_HOME2="$TMP/home2"
mkdir -p "$FAKE_HOME2/.config/kimi" "$FAKE_HOME2/.cache/kimi-code" "$FAKE_HOME2/.kimi" "$FAKE_HOME2/.config/opencode"
mkdir -p "$FAKE_HOME2/Projects" "$FAKE_HOME2/Documents/leetcode" "$FAKE_HOME2/.ssh/kimi"
printf 'x\n' > "$FAKE_HOME2/.config/kimi/config.toml"
printf 'x\n' > "$FAKE_HOME2/.kimi/config.toml"
printf 'x\n' > "$FAKE_HOME2/.cache/kimi-code/blob"
printf 'x\n' > "$FAKE_HOME2/.config/opencode/settings.json"
printf 'x\n' > "$FAKE_HOME2/Projects/code-url-email.js"
printf 'x\n' > "$FAKE_HOME2/Projects/punycode.js"
printf 'x\n' > "$FAKE_HOME2/.ssh/kimi/id_ed25519"

cat >"$BIN/pacman" <<'EOS'
#!/usr/bin/env bash
case "$*" in
    *-Qlq*) printf '/usr/bin/kimi\n' ;;
    *-Qi*)  printf 'Name            : kimi-code-bin\nDescription     : Kimi Code CLI\nURL             : https://github.com/MoonshotAI/kimi-code\n' ;;
    *-Sl*)  printf 'core kimi-code-bin 2.1.1-2\n' ;;
    *-Q*)   printf 'kimi-code-bin 2.1.1-2\n' ;;
    *) exit 0 ;;
esac
EOS
chmod +x "$BIN/pacman"

out="$(printf '' | env HOME="$FAKE_HOME2" XDG_CACHE_HOME="$TMP/cache2" XDG_CONFIG_HOME="$TMP/config" \
    PATH="$BIN:$MINBIN" FAKE_PARU_LOG="$FAKE_PARU_LOG" "$PACR" --scan 2>&1 || true)"
printf '%s\n' "$out" | grep -E 'kimi|code|leetcode' | sed 's/^/    /' | head -10
assert_contains "~/.config/kimi" "$out" "强关键词 kimi 命中 ~/.config/kimi"
assert_contains "~/.cache/kimi-code" "$out" "强关键词 kimi-code 命中缓存目录"
assert_contains "~/.kimi" "$out" "二进制名 kimi 被升级成强关键词，命中 ~/.kimi"
assert_not_contains "opencode" "$out" "弱关键词 code 没有命中 ~/.config/opencode"
assert_not_contains "punycode" "$out" "弱关键词 code 没有命中 punycode.js"
assert_not_contains "code-url-email" "$out" "弱关键词 code 没有命中可见目录里的文件"
assert_not_contains "leetcode" "$out" "弱关键词 code 没有命中 leetcode"
assert_not_contains ".ssh" "$out" "豁免项 .ssh 仍然不出现"

echo
echo "== 汇总：PASS=$PASS FAIL=$FAIL =="
(( FAIL == 0 ))
