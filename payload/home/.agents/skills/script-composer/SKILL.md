---
name: script-composer
description: "Create or maintain reusable Bash tools under `~/scripts`, including terminal/fzf utilities and diagnostics. Not for project build scripts or one-off commands."
when-to-use: "Use when 用户明确要求写个人 Bash 脚本、终端/fzf 工具或系统诊断脚本并放入 `~/scripts`。不要用于项目仓库已有的构建脚本、一次性命令或其他 shell。"
---

# Script Composer

为 `~/scripts/` 产出可运行、可维护、失败行为明确的 Bash 脚本。

## 流程

1. 读取目标脚本及同目录现有脚本，确认调用方式、输入、输出和副作用。
2. 选择最接近的起点：
   - 普通命令：`templates/simple.sh`
   - fzf/交互：`templates/fzf-tool.sh`
   - 系统诊断：`templates/diagnostic.sh`
   - 没有合适模板时可新建，但仍遵守 `references/bash-style.md`。
3. 仅按需要读取：
   - 常用实现模式：`references/patterns.md`
   - 完整交付门槛：`references/quality-gate.md`
4. 实现参数解析、依赖检查、清晰错误、退出码和临时资源清理；有副作用时提供 `--dry-run` 或明确确认边界。
5. 运行：

```bash
bash -n <script>
shellcheck <script>  # 系统存在时
~/.agents/skills/script-composer/scripts/check-script.sh <script>
<script> --help     # 提供该选项时
```

## 禁止模式

- 未引用变量、反引号、`eval`、未清理的 `mktemp`。
- 吞掉依赖缺失或关键失败后仍返回成功。
- 宽泛 `rm -rf`、未经用户要求的安装/系统配置修改、不可审计的远程执行。

交付时说明脚本路径、选用的模板/参考以及实际验证结果。
