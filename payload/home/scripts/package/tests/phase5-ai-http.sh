#!/usr/bin/env bash
# 五期验收：AI 审查后端改为直连 HTTP（URL + 模型名 + key）
#
# 验的是：pac ai init/show、url 归一化、鉴权头、非 2xx 处理（且不泄漏 key）、
#         pac ai model/models 改配置、权限告警、没配置时不阻塞安装。
#
# 全程临时目录：pacman / paru / curl / fzf 都是替身。
#
# 用法: tests/phase5-ai-http.sh [pac 路径]

set -euo pipefail

PKG_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PAC="${1:-$PKG_DIR/pac}"
[[ -x "$PAC" ]] || { echo "找不到可执行脚本: $PAC" >&2; exit 1; }

TMP="$(mktemp -d /tmp/pac-phase5.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT

BIN="$TMP/bin"; MINBIN="$TMP/minbin"; CONF_DIR="$TMP/config"; CONF="$CONF_DIR/pac/ai.conf"
mkdir -p "$BIN" "$MINBIN" "$CONF_DIR/pac"
for f in /usr/bin/*; do
  [[ -x "$f" && ! -d "$f" ]] || continue
  b="${f##*/}"
  case "$b" in pacman|paru|fzf|curl) continue ;; esac
  ln -sf "$f" "$MINBIN/$b"
done

cat > "$BIN/pacman" <<'EOS'
#!/usr/bin/env bash
exit 0
EOS

cat > "$BIN/paru" <<'EOS'
#!/usr/bin/env bash
printf 'paru %s\n' "$*" >>"${FAKE_PARU_LOG:?}"
if [[ "$*" == *" -G "* ]]; then
  d="$PWD/testpkg"; mkdir -p "$d"
  printf "pkgname=testpkg\npkgver=1.0\nsource=('https://example.com/t.tar.gz')\nsha256sums=('SKIP')\n" > "$d/PKGBUILD"
  printf 'pkgbase = testpkg\n\tsource = https://example.com/t.tar.gz\n' > "$d/.SRCINFO"
fi
exit 0
EOS

cat > "$BIN/fzf" <<'EOS'
#!/usr/bin/env bash
head -n1
EOS

cat > "$BIN/curl" <<'EOS'
#!/usr/bin/env bash
# 替身 curl：记录调用参数、按 URL 分流、支持 --output/--write-out、可用 FAKE_HTTP_CODE 模拟错误
printf '%s\n' "$*" >>"${FAKE_CURL_LOG:?}"
out=""; wout=""; url=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in
    --output)    out="${args[i+1]}" ;;
    --write-out) wout="${args[i+1]}" ;;
    http*|https*) url="${args[i]}" ;;
  esac
done
code="${FAKE_HTTP_CODE:-200}"
body=""
if [[ "$url" == *"aur.archlinux.org"* ]]; then
  body='{"resultcount":0,"results":[]}'; code=200
elif [[ "$url" == *"/models"* ]]; then
  body='{"data":[{"id":"model-a"},{"id":"model-b"}]}'; code=200
elif [[ "$code" == "200" ]]; then
  body=$(jq -nc --rawfile c "${FAKE_REVIEW_FILE:?}" '{choices:[{message:{content:$c}}]}')
else
  body='{"error":{"message":"invalid api key"}}'
fi
[[ -n "$out" ]] && printf '%s' "$body" >"$out"
if [[ "$wout" == *http_code* ]]; then printf '%s' "$code"; else [[ -z "$out" ]] && printf '%s' "$body"; fi
exit 0
EOS
chmod +x "$BIN/pacman" "$BIN/paru" "$BIN/fzf" "$BIN/curl"

REVIEW_JSON="$TMP/review.json"
printf '%s' '{"intent":"测试包。","findings":[],"notes":[]}' > "$REVIEW_JSON"
export FAKE_PARU_LOG="$TMP/paru.log" FAKE_CURL_LOG="$TMP/curl.log"

write_conf() {  # write_conf <url> <model> <key> [protocol] [权限]
  local perm="600"
  [[ $# -ge 5 ]] && perm="$5"
  {
    printf '# 注释要保留\n'
    printf 'url   = %s\n' "$1"
    printf 'model = %s\n' "$2"
    printf 'key   = %s\n' "$3"
    if [[ -n "${4:-}" ]]; then printf 'protocol = %s\n' "$4"; fi
  } > "$CONF"
  chmod "$perm" "$CONF"
}

run_review() {  # run_review [FAKE_HTTP_CODE]
  : > "$FAKE_PARU_LOG"; : > "$FAKE_CURL_LOG"
  printf 'y\n\n' | env XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$CONF_DIR" PATH="$BIN:$MINBIN" \
    FAKE_PARU_LOG="$FAKE_PARU_LOG" FAKE_CURL_LOG="$FAKE_CURL_LOG" FAKE_REVIEW_FILE="$REVIEW_JSON" \
    FAKE_HTTP_CODE="${1:-200}" "$PAC" --install aur/testpkg 2>&1 || true
}

PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
has()      { if grep -qF -- "$1" <<<"$2"; then ok "$3"; else bad "$3"; fi; }
hasnot()   { if grep -qF -- "$1" <<<"$2"; then bad "$3"; else ok "$3"; fi; }
file_has() { if grep -qF -- "$1" "$2" 2>/dev/null; then ok "$3"; else bad "$3"; fi; }

echo "== 用例 1：pac ai init 生成模板（600）=="
rm -f "$CONF"
out="$(env XDG_CONFIG_HOME="$CONF_DIR" PATH="$BIN:$MINBIN" "$PAC" --ai-init 2>&1 || true)"
has "已生成" "$out" "提示已生成"
if [[ -f "$CONF" ]]; then ok "配置文件已创建"; else bad "配置文件已创建"; fi
if [[ "$(stat -c %a "$CONF" 2>/dev/null)" == "600" ]]; then ok "权限是 600"; else bad "权限是 600"; fi
file_has "url" "$CONF" "模板里有 url"
file_has "model" "$CONF" "模板里有 model"
file_has "key" "$CONF" "模板里有 key"

echo
echo "== 用例 2：pac ai show 打码显示 key =="
write_conf "https://api.example.com/v1" "model-a" "sk-supersecret-1234"
out="$(env XDG_CONFIG_HOME="$CONF_DIR" PATH="$BIN:$MINBIN" "$PAC" --ai-show 2>&1 || true)"
has "https://api.example.com/v1" "$out" "显示了 url"
has "model-a" "$out" "显示了 model"
hasnot "sk-supersecret-1234" "$out" "没有回显完整 key"
has "…1234" "$out" "key 打码了"

echo
echo "== 用例 3：url 三种写法都归一化成同一个地址 =="
for form in "https://api.example.com" "https://api.example.com/v1" "https://api.example.com/v1/chat/completions"; do
  write_conf "$form" "model-a" "sk-test"
  run_review >/dev/null
  if grep -q 'https://api.example.com/v1/chat/completions' "$FAKE_CURL_LOG"; then
    ok "$form → /v1/chat/completions"
  else
    bad "$form → /v1/chat/completions（实际打到了别的地址）"
  fi
done

echo
echo "== 用例 4：鉴权头 =="
write_conf "https://api.example.com/v1" "model-a" "sk-test"
run_review >/dev/null
file_has "Authorization: Bearer sk-test" "$FAKE_CURL_LOG" "用了 Bearer 鉴权"

echo
echo "== 用例 5：401 → 审查失败、默认不装、且不泄漏 key =="
write_conf "https://api.example.com/v1" "model-a" "sk-leak-check-9999"
out="$(run_review 401)"
has "HTTP 401" "$out" "报了 401"
has "key 不对" "$out" "提示了 key 可能不对"
hasnot "sk-leak-check-9999" "$out" "报错里没有 key"
if grep -qE '^paru -S( --skipreview)? -- ' "$FAKE_PARU_LOG"; then bad "401 时默认没有安装"; else ok "401 时默认没有安装"; fi

echo
echo "== 用例 6：anthropic 协议走 /v1/messages + x-api-key =="
write_conf "https://api.example.com" "claude-x" "sk-anthropic" "anthropic"
run_review >/dev/null
file_has "https://api.example.com/v1/messages" "$FAKE_CURL_LOG" "打到了 /v1/messages"
file_has "x-api-key: sk-anthropic" "$FAKE_CURL_LOG" "用了 x-api-key"

echo
echo "== 用例 7：pac ai model 改配置，保留注释与其它字段 =="
write_conf "https://api.example.com/v1" "old-model" "sk-keep"
out="$(env XDG_CONFIG_HOME="$CONF_DIR" PATH="$BIN:$MINBIN" "$PAC" --ai-model new-model 2>&1 || true)"
file_has "model = new-model" "$CONF" "model 已更新"
file_has "url   = https://api.example.com/v1" "$CONF" "url 没被动"
file_has "# 注释要保留" "$CONF" "注释还在"
file_has "key   = sk-keep" "$CONF" "key 没被动"
has "new-model" "$out" "提示里说了新模型"

echo
echo "== 用例 8：pac ai models 从 /models 拉列表并写回配置 =="
write_conf "https://api.example.com/v1" "old-model" "sk-test"
: > "$FAKE_CURL_LOG"
out="$(env XDG_CONFIG_HOME="$CONF_DIR" PATH="$BIN:$MINBIN" FAKE_CURL_LOG="$FAKE_CURL_LOG" "$PAC" --ai-models 2>&1 || true)"
has "model-a" "$out" "选中了列表里的第一个（model-a）"
file_has "model = model-a" "$CONF" "配置已写入所选模型"
file_has "https://api.example.com/v1/models" "$FAKE_CURL_LOG" "请求了 /models"

echo
echo "== 用例 9：配置权限 644 会被警告 =="
write_conf "https://api.example.com/v1" "model-a" "sk-test" "" "644"
out="$(env XDG_CONFIG_HOME="$CONF_DIR" PATH="$BIN:$MINBIN" "$PAC" --ai-show 2>&1 || true)"
has "建议 chmod 600" "$out" "提示了权限问题"

echo
echo "== 用例 10：没有配置 → 不阻塞安装（保留 paru 复核）=="
rm -f "$CONF"
: > "$FAKE_PARU_LOG"
out="$(run_review)"
has "后端还没配好" "$out" "提示后端没配好"
if grep -qE '^paru -S -- testpkg' "$FAKE_PARU_LOG"; then ok "仍然装了（且没有 --skipreview）"; else bad "仍然装了（且没有 --skipreview）"; fi

echo
echo "== 汇总：PASS=$PASS FAIL=$FAIL =="
(( FAIL == 0 ))
