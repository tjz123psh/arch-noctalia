# Common Patterns

## usage

```bash
usage() {
  cat <<'EOF'
Usage: script-name [options]

Options:
  -h, --help    显示帮助并退出
EOF
}
```

## 依赖检查

```bash
require_deps() {
  local missing=()
  local cmd

  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done

  if (( ${#missing[@]} > 0 )); then
    printf '错误: 缺少依赖: %s\n' "${missing[*]}" >&2
    exit 127
  fi
}
```

## 参数解析

```bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --option)
      if [[ -z "${2:-}" ]]; then
        printf '错误: --option 需要参数\n' >&2
        exit 2
      fi
      OPTION="$2"
      shift 2
      ;;
    --flag)
      FLAG=true
      shift
      ;;
    *)
      printf '错误: 未知参数: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done
```

## 安全 cleanup

```bash
TMP_DIR=""

cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf -- "$TMP_DIR"
  fi
}
trap cleanup EXIT

TMP_DIR="$(mktemp -d /tmp/script-name.XXXXXX)"
```

## fzf 捕获取消

```bash
set +e
selection="$(printf '%s\n' "$items" | fzf --ansi --height=95% --layout=reverse --border=rounded)"
fzf_status=$?
set -e

case "$fzf_status" in
  0) ;;
  1|130) exit 0 ;;
  *) printf '错误: fzf 失败，退出码 %s\n' "$fzf_status" >&2; exit "$fzf_status" ;;
esac
```

## 自重载路径

只有脚本会 `exec "$SELF"` 或被 fzf reload 调用时使用。

```bash
SELF="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || printf '%s\n' "$0")"
readonly SELF
```

## 诊断状态函数

```bash
ok() { printf '%sOK%s    %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%sWARN%s  %s\n' "$YELLOW" "$NC" "$*"; }
miss() { printf '%sMISS%s  %s\n' "$RED" "$NC" "$*"; }
info() { printf '%sINFO%s  %s\n' "$CYAN" "$NC" "$*"; }
```

## Arch 包管理工具发现

```bash
PKG_TOOL=""
if command -v paru >/dev/null 2>&1; then
  PKG_TOOL="paru"
elif command -v yay >/dev/null 2>&1; then
  PKG_TOOL="yay"
elif command -v pacman >/dev/null 2>&1; then
  PKG_TOOL="pacman"
fi
```

不要自动安装、删除或升级软件，除非用户明确要求。
