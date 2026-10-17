# Bash Style

这些规则用于约束生成质量。写 `~/scripts/` 脚本时优先遵守它们。

## 文件头

```bash
#!/usr/bin/env bash
# 描述：简要描述
# Description: Brief description

set -euo pipefail
```

- shebang 必须是 `#!/usr/bin/env bash`。
- `set -euo pipefail` 靠近文件头，只出现一次。
- 个人脚本可以只写中文 usage，但文件头尽量中英双语。
- 注释解释原因、边界和非显然行为，不复述代码。

## 命名和结构

- 函数名、变量名用英文。
- 段标题用中文，例如 `# --- 参数解析 ---`、`# --- 主逻辑 ---`。
- 常量用大写，例如 `CONFIG_FILE`、`TMP_DIR`。
- 临时局部变量用 `local`。
- 复杂逻辑拆函数，主流程放在文件末尾。

## 参数解析

默认使用 `while [[ $# -gt 0 ]]; do case "$1" in ... esac done`。

- 不用 `getopt` / `getopts`。
- 每个分支自己 `shift`。
- 带值参数必须先检查 `${2:-}`。
- 不接受位置参数时，未知参数报错、打印 usage、退出 `2`。

## 输出

- 人类可读状态输出用 `printf`，不要用 `echo -e`。
- 错误输出写 stderr：`printf '错误: ...\n' >&2`。
- 缺依赖退出 `127`。
- 参数错误退出 `2`。
- 一般失败退出 `1`。

## 颜色

只有终端输出需要颜色。输出被管道或重定向时禁用颜色。

```bash
BOLD=$'\033[1m'
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
CYAN=$'\033[36m'
NC=$'\033[0m'

if [[ ! -t 1 ]]; then
  BOLD=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; NC=""
fi
```

## 依赖

- 主逻辑前检查所有外部命令。
- 能降级就降级，不能降级就明确报错。
- 不自动安装依赖，除非用户明确要求。

## 临时文件

- 用 `mktemp` 创建临时文件或目录。
- 用 `trap cleanup EXIT` 清理。
- `cleanup` 中删除临时路径前确认变量非空。
- 不对用户目录做宽泛 `rm -rf`。

## 禁止

- 禁止 `eval`。
- 禁止反引号命令替换。
- 禁止未引用变量参与路径、命令参数、删除操作。
- 禁止全文件级 `shellcheck disable`。
- 禁止无理由引入 Python。
- 禁止 `source` 用户配置，除非脚本目标就是加载该配置。
