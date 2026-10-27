#!/usr/bin/env bash
# 一期验收：pac 的 --skipreview 门禁
#
# 验的是一条规则：只有本批每个 AUR 包都真的跑出过 AI 审查结论，才允许跳过
# paru 自带的 PKGBUILD 复核；其余情况（--no-ai、用户跳过、没 opencode、
# 没提示词、审查失败）都必须保留那道复核。
#
# 全程只在临时目录里跑，不装、不删任何系统包：
#   - 假 paru：-G 时造一个 PKGBUILD，-S 时只把参数写进日志，从不真装
#   - 假 opencode：输出一份固定格式的低风险报告
#   - 悬空软链 opencode：让 command -v opencode 失败，用来模拟"没装 opencode"
#
# 用法: tests/phase1-review-gate.sh [pac 路径]

set -euo pipefail

UI="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/pac}"
[[ -x "$UI" ]] || { echo "找不到可执行脚本: $UI" >&2; exit 1; }

TMP="$(mktemp -d /tmp/pac-phase1.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT

export XDG_CACHE_HOME="$TMP/cache"
export FAKE_PARU_LOG="$TMP/paru.log"

BIN="$TMP/bin"; BINAI="$TMP/bin-ai"; MINBIN="$TMP/minbin"
mkdir -p "$BIN" "$BINAI" "$MINBIN" "$XDG_CACHE_HOME"

# 造一条"除了 opencode 什么都有"的 PATH：把 /usr/bin 下的可执行文件全部软链过来，
# 唯独跳过 opencode。这样不用动系统就能真实模拟"没装 opencode"。
for f in /usr/bin/*; do
  [[ -x "$f" && ! -d "$f" ]] || continue
  b="${f##*/}"
  [[ "$b" == "opencode" ]] && continue
  ln -sf "$f" "$MINBIN/$b"
done

cat >"$BIN/paru" <<'EOS'
#!/usr/bin/env bash
printf 'paru %s\n' "$*" >>"${FAKE_PARU_LOG:?}"
if [[ "$*" == *" -G "* ]]; then
  pkg="${!#}"
  mkdir -p -- "$pkg"
  printf 'pkgname=%s\npkgver=1.0-1\n' "$pkg" >"$pkg/PKGBUILD"
fi
exit 0
EOS
chmod +x "$BIN/paru"

# 五期之后 AI 后端是直连 HTTP：写一份临时配置（配好 / 空目录 两种模式），curl 全由替身应答
mkdir -p "$TMP/config/pac" "$TMP/config-empty"
cat >"$TMP/config/pac/ai.conf" <<'EOS'
url   = https://api.example.com/v1
model = test-model
key   = test-key
EOS
chmod 600 "$TMP/config/pac/ai.conf"

cat > "$BIN/curl" <<'EOS'
#!/usr/bin/env bash
# curl 替身：认得 --output（响应体写文件）和 --write-out（状态码打 stdout），按 URL 分流
out=""; wout=""; url=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in
    --output)    out="${args[i+1]}" ;;
    --write-out) wout="${args[i+1]}" ;;
    http*|https*) url="${args[i]}" ;;
  esac
done
body=""
if [[ "$url" == *"aur.archlinux.org"* ]]; then
  body='{"resultcount":0,"results":[]}'
else
  body='{"choices":[{"message":{"content":"{\"intent\":\"验收用的假包，不做任何事。\",\"findings\":[],\"notes\":[]}"}}]}'
fi
[[ -n "$out" ]] && printf '%s' "$body" >"$out"
if [[ "$wout" == *http_code* ]]; then printf '200'; else [[ -z "$out" ]] && printf '%s' "$body"; fi
exit 0
EOS
chmod +x "$BIN/curl"

PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
assert_contains()     { if grep -qF -- "$1" <<<"$2"; then ok "$3"; else bad "$3"; fi; }
assert_not_contains() { if grep -qF -- "$1" <<<"$2"; then bad "$3"; else ok "$3"; fi; }

install_line() { grep -E '^paru -S' "$FAKE_PARU_LOG" 2>/dev/null | tail -n 1 || true; }

run_ui() {  # run_ui <withai|noai> <stdin 内容> [选项...]
  local mode="$1" input="$2"; shift 2
  local path="$BIN:$MINBIN"
  local conf="$TMP/config"
  [[ "$mode" == "noai" ]] && conf="$TMP/config-empty"
  printf '%s' "$input" | env PATH="$path" XDG_CONFIG_HOME="$conf" "$UI" "$@" --install aur/testpkg 2>&1 || true
}

echo "== 前置检查：测试装置本身可信 =="
if PATH="$BIN:$MINBIN" command -v opencode >/dev/null 2>&1; then
  echo "  装置失效：这条 PATH 上仍然能找到 opencode" >&2; exit 1
fi
[[ -r "$TMP/config/pac/ai.conf" ]] || { echo "  装置失效：没造出 AI 配置" >&2; exit 1; }
[[ ! -e "$TMP/config-empty/pac/ai.conf" ]] || { echo "  装置失效：空配置目录不空" >&2; exit 1; }
PATH="$BIN:$MINBIN" command -v paru | grep -qF "$BIN/paru" || { echo "  装置失效：假 paru 没有优先于真 paru" >&2; exit 1; }
echo "  OK（有 AI = 临时配置；无 AI = 空配置目录；paru 用假 paru）"

echo
echo "== 用例 1：没配 AI 后端 → 保留 paru 自带复核 =="
: >"$FAKE_PARU_LOG"
out="$(run_ui noai '')"
line="$(install_line)"
printf '  实际调用: %s\n' "${line:-（没有调用 paru -S）}"
assert_contains "-S --" "$line" "确实是 -S 安装"
assert_not_contains "--skipreview" "$line" "调用里没有 --skipreview"
assert_contains "后端还没配好" "$out" "提示了后端没配好"

echo
echo "== 用例 2：配好后端，审查跑完，用户继续 → 允许跳过复核 =="
: >"$FAKE_PARU_LOG"
out="$(run_ui withai $'y\ny\n')"
line="$(install_line)"
printf '  实际调用: %s\n' "${line:-（没有调用 paru -S）}"
assert_contains "--skipreview" "$line" "调用里有 --skipreview"

echo
echo "== 用例 3：配好后端，用户在追问里选 n → 保留复核 =="
: >"$FAKE_PARU_LOG"
out="$(run_ui withai $'n\n')"
line="$(install_line)"
printf '  实际调用: %s\n' "${line:-（没有调用 paru -S）}"
assert_contains "是否先进行 PKGBUILD 审查" "$out" "确实问过是否审查"
assert_not_contains "--skipreview" "$line" "调用里没有 --skipreview"

echo
echo "== 用例 4：--no-ai → 不追问、保留复核 =="
: >"$FAKE_PARU_LOG"
out="$(run_ui withai '' --no-ai)"
line="$(install_line)"
printf '  实际调用: %s\n' "${line:-（没有调用 paru -S）}"
assert_not_contains "是否先进行 PKGBUILD 审查" "$out" "没有出现审查追问"
assert_not_contains "--skipreview" "$line" "调用里没有 --skipreview"

echo
echo "== 用例 5：PARU_UI_DRY_RUN=1 → 只打印、不调用 paru =="
: >"$FAKE_PARU_LOG"
out="$(PATH="$BIN:$MINBIN" PARU_UI_DRY_RUN=1 "$UI" --install aur/testpkg </dev/null 2>&1 || true)"
printf '  打印内容: %s\n' "$(grep -F 'DRY_RUN' <<<"$out" | head -n 1)"
assert_contains "DRY_RUN" "$out" "打印了将要执行的命令"
if [[ -z "$(install_line)" ]]; then ok "没有真的调用 paru -S"; else bad "仍然调用了 paru -S"; fi

echo
echo "== 汇总：PASS=$PASS FAIL=$FAIL =="
(( FAIL == 0 ))
