---
name: session-context
description: "Recover stable workstation paths and rebuild verified project context after compaction, handoff, or context loss; recheck live facts instead of cached state."
when-to-use: "Use when 长会话压缩、交接或上下文丢失后需要恢复本机路径与已核实的项目上下文，或用户询问本机环境与稳定路径。Do not use when 上下文完整、用户只是说“继续”或要求普通实现工作。"
---

# Session Context

恢复上下文时，把本文件当作**查证入口**，不要当作当前状态快照。

## 恢复顺序

1. 从当前对话恢复用户最新目标、硬约束和待完成事项。
2. 读取项目 `AGENTS.md`、README、架构文档及项目工作状态文件（如 `.ai/WORKING.md`）。
3. 检查 `git status --short --branch`、相关 diff、实际配置和相关源文件。
4. 只重新验证当前任务需要的机器事实，不做全盘扫描。
5. 若摘要、Memory、文档与当前文件或命令结果冲突，以当前文件和成功检查为准，并修正过时记录。

## 不得硬编码的动态事实

不要在本文件记录以下“当前值”：

- 默认模型、上下文窗口或 reasoning effort；
- 已启用、已连接或失败的 MCP；
- 程序版本、软件包状态、PID、监听端口或服务健康状态；
- 当前分支、未提交改动、测试是否通过；
- 临时故障和未经证实的根因。

需要这些信息时现场查询。查询失败必须报告为 `unavailable` 或失败，不能当作空结果。

## 常用查证来源

| 信息 | 优先来源 |
|------|----------|
| Pi 配置 | `~/.pi/agent/settings.json`、`~/.pi/agent/models.json`、当前会话信息和实际命令结果 |
| Pi 版本 | `pi --version` |
| MCP 配置 | `~/.pi/agent/mcp.json`；再单独检查对应进程、端口或握手 |
| 项目状态 | 项目 `AGENTS.md`、工作状态文件、Git 状态、diff、测试 |
| Neovim | `nvim --version`、`~/.config/nvim/` |
| Rust | `rustup show active-toolchain` 及实际工具检查 |
| Niri | `niri msg --json ...`、`~/.config/niri/` |
| 用户服务 | 针对具体单元运行 `systemctl --user show/status` |

## 稳定路径索引

这些路径仅用于定位；使用前仍要检查是否存在：

| 用途 | 路径 |
|------|------|
| Pi 配置与技能 | `~/.pi/agent/`、`~/.pi/agent/skills/`、`~/.pi/agent/APPEND_SYSTEM.md` |
| 共享技能库（DSH + pi 共用，18 个） | `~/.agents/skills/`、`~/.agents/skills/_shared/scripts/` |
| DSH 专属技能 | `~/.dsh/skills/` |
| Neovim 配置 | `~/.config/nvim/` |
| Neovim 文档 | `~/md/nvim/` |
| Linux 文档 | `~/md/linux/` |
| Niri 配置 | `~/.config/niri/` |
| 图形化提权包装器 | `~/scripts/desktop/gsudo` |

## 记忆卫生

- 把稳定约定和架构知识写入项目文档、ADR 或对应 skill/reference。
- 把当前任务进度写入项目工作状态文件，不写入本机长期基线。
- 把 Memory 和压缩摘要当作检索线索，不当作事实源。
- 在压缩或交接前记录：目标、约束、已确认事实、改动路径、PASS/FAIL/UNAVAILABLE 检查、风险和精确下一步。
- 发现本文件或其他记忆资料过期时，在同一任务中删除或修正过时项。

## 安全边界

- 不读取、输出或保存凭据值；只报告位置、权限或是否可用。
- 涉及 Arch Linux 包、服务、启动、磁盘或配置迁移时，先盘点、给出 dry-run/计划并等待明确批准。
- 只加载当前任务必要的领域 skill；本文件不替代项目规则或实时检查。
