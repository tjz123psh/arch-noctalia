# Quality Gate

脚本交付前必须逐项检查。

## 必跑命令

```bash
bash -n <script>
shellcheck <script>
~/.agents/skills/script-composer/scripts/check-script.sh <script>
```

如果 `shellcheck` 不存在，说明未运行原因，但仍必须跑 `bash -n` 和 `check-script.sh`。

## 行为验证

- 有 `--help`：运行 `<script> --help`。
- 有只读/打印模式：运行该模式。
- 有参数解析：至少测试一个错误参数，确认退出非零并输出 usage 或错误。
- 有依赖检查：确认缺依赖路径不会进入主逻辑。
- 有临时文件：确认 `trap cleanup EXIT` 存在。

## 代码复核

- 是否从模板开始，而不是自由发挥。
- 是否有 shebang 和 `set -euo pipefail`。
- 是否所有变量在路径和命令参数里都加了双引号。
- 是否没有 `eval`、反引号、宽泛 `rm -rf`。
- 是否没有自动安装包、删除数据、修改系统配置。
- 是否对 `fzf`、`grep`、`systemctl is-active` 等可能返回非零的命令做了显式处理。

## 交付说明

最终回复写：

```text
脚本：<path>
模板：<simple.sh|fzf-tool.sh|diagnostic.sh>
验证：bash -n 通过；shellcheck 通过；check-script 通过；--help 通过
```
