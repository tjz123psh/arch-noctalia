#!/usr/bin/env bash
# 六期验收：pacr 的 AI 残留判定
#
# 验的是：
#   1. 配好 AI 后，候选带上"来源 · 置信度"和一句话理由
#   2. AI 额外想到的路径（不在预筛列表里）经校验后也能列出来
#   3. AI 给的豁免路径（~/.ssh）、家目录外的路径、不存在的路径，全部被丢掉
#   4. --no-ai 时完全不发 AI 请求
#   5. 没配 AI / AI 返回坏 JSON 时，退回按名字匹配，不报错
#
# 全程临时目录：pacman / paru / curl / fzf 都是替身，AI 配置指向假 curl。
#
# 用法: tests/phase6-ai-leftover.sh [pacr 路径]
# shellcheck disable=SC2088  # 断言描述里的 ~ 是给人看的文字

set -euo pipefail

PKG_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PACR="${1:-$PKG_DIR/pacr}"
[[ -x "$PACR" ]] || { echo "找不到可执行脚本: $PACR" >&2; exit 1; }

TMP="$(mktemp -d /tmp/pac-phase6.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT

FAKE_HOME="$TMP/home"
BIN="$TMP/bin"; MINBIN="$TMP/minbin"; CONF_DIR="$TMP/config"; CONF="$CONF_DIR/pac/ai.conf"
mkdir -p "$FAKE_HOME" "$BIN" "$MINBIN" "$CONF_DIR/pac"
for f in /usr/bin/*; do
  [[ -x "$f" && ! -d "$f" ]] || continue
  b="${f##*/}"
  case "$b" in pacman|paru|fzf|curl) continue ;; esac
  ln -sf "$f" "$MINBIN/$b"
done

# 家目录夹具
mkdir -p "$FAKE_HOME/.config/fakeapp" "$FAKE_HOME/.cache/fakeapp" "$FAKE_HOME/.local/share/AIVendorData" "$FAKE_HOME/.ssh/fakeapp"
printf 'c\n' > "$FAKE_HOME/.config/fakeapp/conf"
printf 'x\n' > "$FAKE_HOME/.cache/fakeapp/blob"
printf 'v\n' > "$FAKE_HOME/.local/share/AIVendorData/data"
printf 'KEY\n' > "$FAKE_HOME/.ssh/fakeapp/id_ed25519"

cat > "$BIN/pacman" <<'EOS'
#!/usr/bin/env bash
case "$*" in
  *-Qlq*) printf '/usr/bin/fakeapp\n' ;;
  *-Qi*)  printf 'Name            : fakeapp\nDescription     : Fake application\nURL             : https://github.com/example/fakeapp\n' ;;
  *-Sl*)  printf 'core fakeapp 1.0-1\n' ;;
  *-Q*)   printf 'fakeapp 1.0-1\n' ;;
  *) exit 0 ;;
esac
EOS
cat > "$BIN/paru" <<'EOS'
#!/usr/bin/env bash
printf 'paru %s\n' "$*" >>"${FAKE_PARU_LOG:?}"
exit 0
EOS
cat > "$BIN/fzf" <<'EOS'
#!/usr/bin/env bash
cat
EOS
cat > "$BIN/curl" <<'EOS'
#!/usr/bin/env bash
# 只处理聊天请求（pacr 不查 AUR RPC）：记录调用，回夹具里的内容
printf '%s\n' "$*" >>"${FAKE_CURL_LOG:?}"
out=""; wout=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in
    --output) out="${args[i+1]}" ;;
    --write-out) wout="${args[i+1]}" ;;
  esac
done
body=$(jq -nc --rawfile c "${FAKE_AI_FILE:?}" '{choices:[{message:{content:$c}}]}')
[[ -n "$out" ]] && printf '%s' "$body" >"$out"
if [[ "$wout" == *http_code* ]]; then printf '200'; else [[ -z "$out" ]] && printf '%s' "$body"; fi
exit 0
EOS
chmod +x "$BIN/pacman" "$BIN/paru" "$BIN/fzf" "$BIN/curl"

AI_FILE="$TMP/ai.json"
cat > "$AI_FILE" <<EOS
{"leftovers":[
  {"path":"${FAKE_HOME}/.config/fakeapp","confidence":"high","reason":"配置目录"},
  {"path":"${FAKE_HOME}/.cache/fakeapp","confidence":"medium","reason":"缓存"},
  {"path":"${FAKE_HOME}/.ssh/fakeapp","confidence":"high","reason":"想删密钥"},
  {"path":"/etc/passwd","confidence":"high","reason":"越界"},
  {"path":"${FAKE_HOME}/.config/fakeapp-nonexistent","confidence":"high","reason":"不存在"},
  {"path":"${FAKE_HOME}/.local/share/AIVendorData","confidence":"medium","reason":"厂商数据目录"}
],"notes":["删之前先备份"]}
EOS

export FAKE_PARU_LOG="$TMP/paru.log" FAKE_CURL_LOG="$TMP/curl.log" FAKE_AI_FILE="$AI_FILE"

write_conf() {
  {
    printf 'url   = https://api.example.com/v1\n'
    printf 'model = test-model\n'
    printf 'key   = sk-test\n'
  } > "$CONF"
  chmod 600 "$CONF"
}

run_scan() {  # run_scan [额外参数...]
  : > "$FAKE_PARU_LOG"; : > "$FAKE_CURL_LOG"
  printf '' | env HOME="$FAKE_HOME" XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$CONF_DIR" \
    PATH="$BIN:$MINBIN" FAKE_PARU_LOG="$FAKE_PARU_LOG" FAKE_CURL_LOG="$FAKE_CURL_LOG" \
    FAKE_AI_FILE="$FAKE_AI_FILE" "$PACR" --scan "$@" 2>&1 || true
}

PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
has()    { if grep -qF -- "$1" <<<"$2"; then ok "$3"; else bad "$3"; fi; }
hasnot() { if grep -qF -- "$1" <<<"$2"; then bad "$3"; else ok "$3"; fi; }

write_conf
echo "== 用例 1：配好 AI → 候选带来源/置信度/理由 =="
out="$(run_scan)"
printf '%s\n' "$out" | sed 's/^/    /' | head -12
has "AI 判定的" "$out" "标了来源是 AI 判定的"
has "配置目录" "$out" "带上了 AI 给的理由"
has "同名" "$out" "AI 判高的条目带高置信度标签"
has "可能" "$out" "中等置信度条目正常显示"
hasnot ".ssh/fakeapp" "$out" "豁免路径 ~/.ssh 被丢掉"
hasnot "/etc/passwd" "$out" "家目录外的路径被丢掉"
hasnot "fakeapp-nonexistent" "$out" "不存在的路径被丢掉"
has "AIVendorData" "$out" "AI 额外想到的路径（存在且合法）被采纳"

echo
echo "== 用例 2：AI 请求确实发到了配置的端点 =="
has "https://api.example.com/v1/chat/completions" "$(cat "$FAKE_CURL_LOG")" "打到了配置的地址"

echo
echo "== 用例 3：--no-ai → 不发 AI 请求，仍按名字列出 =="
out="$(run_scan --no-ai)"
if [[ -s "$FAKE_CURL_LOG" ]]; then bad "--no-ai 时不该发请求"; else ok "--no-ai 时没有发请求"; fi
has "~/.config/fakeapp" "$out" "仍然按名字列出了候选"
hasnot "配置目录" "$out" "没有 AI 给的理由"

echo
echo "== 用例 4：没配 AI → 退回名字匹配，不报错 =="
rm -f "$CONF"
out="$(run_scan)"
has "AI 未配置" "$out" "提示了 AI 未配置"
has "~/.config/fakeapp" "$out" "仍然列出了候选"
if [[ -s "$FAKE_CURL_LOG" ]]; then bad "没配置时不该发请求"; else ok "没配置时没有发请求"; fi

echo
echo "== 用例 5：AI 返回坏 JSON → 退回名字匹配，不报错 =="
write_conf
printf '模型今天不想干活。\n' > "$AI_FILE"
out="$(run_scan)"
has "AI 判定失败" "$out" "提示了 AI 判定失败"
has "~/.config/fakeapp" "$out" "仍然列出了候选"

printf '%s' '{"leftovers":[{"path":"'"$FAKE_HOME"'/.config/fakeapp","confidence":"high","reason":"合法"}],"notes":[]}' > "$AI_FILE"

echo
echo "== 汇总：PASS=$PASS FAIL=$FAIL =="
(( FAIL == 0 ))
