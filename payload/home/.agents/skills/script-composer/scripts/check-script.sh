#!/usr/bin/env bash
# 描述：检查 ~/scripts Bash 脚本的基础质量
# Description: Basic quality checks for Bash scripts

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: check-script.sh <script>

Checks:
  - bash syntax
  - shellcheck when available
  - required Bash script header
  - common unsafe patterns
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

SCRIPT="$1"

if [[ ! -f "$SCRIPT" ]]; then
  printf '错误: 文件不存在: %s\n' "$SCRIPT" >&2
  exit 1
fi

fail() {
  printf 'FAIL  %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'WARN  %s\n' "$*" >&2
}

ok() {
  printf 'OK    %s\n' "$*"
}

first_line="$(sed -n '1p' "$SCRIPT")"
[[ "$first_line" == '#!/usr/bin/env bash' ]] || fail "缺少 shebang: #!/usr/bin/env bash"

grep -q '^set -euo pipefail$' "$SCRIPT" || fail "缺少 set -euo pipefail"

if grep -nE '(^|[[:space:]])eval([[:space:]]|$)' "$SCRIPT"; then
  fail "禁止使用 eval"
fi

if grep -n '`' "$SCRIPT"; then
  fail "禁止使用反引号命令替换"
fi

if grep -nE 'rm[[:space:]]+-rf[[:space:]]+["'\'']?\$?\{?HOME\}?(/|[[:space:]]|$)|rm[[:space:]]+-rf[[:space:]]+/' "$SCRIPT"; then
  fail "发现危险 rm -rf 模式，请人工确认并收窄路径"
fi

if grep -nE 'curl .*[\|] *sh|wget .*[\|] *sh' "$SCRIPT"; then
  fail "禁止 curl|sh / wget|sh"
fi

bash -n "$SCRIPT"
ok "bash -n 通过"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$SCRIPT"
  ok "shellcheck 通过"
else
  warn "未找到 shellcheck，已跳过"
fi

if grep -q 'mktemp' "$SCRIPT" && ! grep -q 'trap .*EXIT\|trap .*cleanup' "$SCRIPT"; then
  fail "使用 mktemp 但没有 EXIT trap"
fi

if grep -q 'fzf' "$SCRIPT" && ! grep -q 'set +e' "$SCRIPT"; then
  warn "脚本使用 fzf，但没有显式 set +e 捕获取消/错误状态"
fi

ok "基础质量检查通过"
