---
name: nvim-config
description: "Understand, modify, or audit this workstation's Neovim configuration: architecture, plugins, keymaps, commands, version compatibility, deprecated APIs, and the documentation sync chain."
when-to-use: "Use when 改本机 nvim 配置、查配置归属/约定，或体检配置健康度。单个明确故障使用 `nvim-troubleshooting`。"
---

# NVIM Config

本机 Neovim 配置的**正确形态**：结构、约定、修改规则、审计清单。

目标：改配置时先读现场、按现有模块改、小步验证，并同步 `~/md/nvim` 用户文档；
体检时对照清单逐项核对，findings 按严重度和可复现证据排序。

## 关键路径

```text
~/.config/nvim       配置本体
~/md/nvim            用户文档（必须同步）
```

入口：

- `init.lua`：加载 `core` 和 `core.lazy`
- `lua/core/`：编辑器通用选项、诊断、全局键、自动保存与标点；移动行在 movement，项目在 projects/，共享界面和 Neovide 在 ui/；不放语言实现。
- `lua/plugins/`：主题、LSP、补全、Treesitter、snacks picker、DAP、UI、终端等（telescope.nvim 已删除）
- `lua/languages/<语言>/init.lua`：每种语言一个目录，统一声明 LSP、DAP、格式化、工具、语法、文件类型、命令和按键；`lua/languages/init.lua` 注册与校验，`lua/plugins/languages.lua` 只接入声明的插件。

具体插件、快捷键和版本以 `~/.config/nvim` 当前文件为准，本 skill 只记约定与理由。

## 参考路由

按需读取，不要一次全读：

| 需要 | 读取 |
|------|------|
| 完整目录树、加载顺序、快捷键表、设计理由 | `references/architecture.md` |
| 本机审计：逐项 grep 与严重度分级 | `references/local-checklist.md` |
| deprecated/removed 警告、版本兼容 | `references/deprecated-apis.md` |

通用 Neovim / lazy.nvim 常识（`vim.opt` vs `vim.o`、懒加载触发器等）不在此维护：
任何模型都已知，且容易与本机实际做法冲突。需要时查 `:help` 或上游文档。

## 修改规则

1. 先读实际文件，不凭记忆改。
2. 新快捷键必须同步：
   - 实际所属模块（通用键在 `lua/core/keymaps.lua`，插件用 keys，语言在各自目录）
   - `lua/core/ui/reference.lua`
   - `lua/plugins/whichkey.lua`（如属于提示菜单）
3. 新命令必须同步：
   - 实际所属模块（通用命令 / 诊断 / 项目 / 语言入口），不强制重复注册到总表
   - `lua/core/ui/reference.lua`（如需要速查）
4. 改语言支持只在 `lua/languages/<语言>/` 的入口和实现中维护；公共插件读取注册表，不再另放语言清单。新增语言在注册表 names 加一项，运行 tests/languages.lua 与该语言回归。
5. 改完必须同步 `~/md/nvim`。
6. 新发现的坑写入 `nvim-troubleshooting` 技能内的 `~/.agents/skills/nvim-troubleshooting/references/nvim-troubleshooting-history.md`，不要写回本入口文件。

文档同步的完整对照表见 `references/architecture.md` 的「文档同步规则」。

## 当前重要约定

- `J`：普通模式下移当前行；`K`：上移当前行。
- `J/K`：可视/选择模式下移/上移整块选中行，支持数字前缀（如 `3J`）。
- `gh`：LSP 悬浮文档。
- `<leader>j`：合并下一行。
- Java 由 `nvim-jdtls` 管理，`jdtls` 不交给 lspconfig 启动。
- Rust LSP 需要系统 `rustc` 和 `cargo` 存在；缺失时跳过 rust-analyzer。
- project.nvim 的根兼容/树刷新在 `core/projects/init.lua`，历史并集/副本/回填/永不截断写守卫在 `core/projects/history.lua`；不能换回上游截断写，也不能以初始化检查代替追加保护。
- 注释统一用 Neovim 内置 `gc`/`gcc`（0.10+），未安装 Comment.nvim；没有 `gb`/`gbc` 块注释。
- 启动期不联网：Treesitter 解析器自动安装有 6 小时节流，GitHub 下载需本机 Clash 代理（非 fish 启动的 nvim 默认没有代理）；lazy.nvim 的**更新检查器已关**（`core/lazy.lua` 的 `checker.enabled = false`）—— 它默认会在启动时对全部插件跑 `git fetch`。要看更新手动 `:Lazy check`。
- Java 服务端→客户端命令由 `languages/java/lsp.lua` 转发：先 client.commands，再全局 vim.lsp.commands；成功空值返回 vim.NIL，reloadBundles 返回空表，异常返回 nil,error 对象。不能裸 return nil，也不能吞掉 classpath 握手；以当前实现与协议测试为准，不照抄历史 §19 的旧错误返回示例。
- Java DAP 接线在 `languages/java/debug.lua`；F5/Jg/JG/Jd 调用 `ensure()`。安装版 nvim-jdtls 的 LspAttach 仍会加载 DAP，**不能宣称打开 Java 不加载调试插件**。首次接线重建上游默认 Java 适配器，以启用自动热替换。
- `lsp.log` 的 ERROR 级别与 5MB 轮转在 `core/diagnostics.lua`。

## 审计顺序

审计（而非单纯修改）时额外执行：

1. 先跑最小健康检查：

```bash
nvim --headless '+checkhealth' '+write! /tmp/nvim-health.txt' '+qa'
```

2. 按用户范围读取 `references/local-checklist.md`，逐项跑其中的 grep 并核对预期。
3. findings 按严重度和可复现证据排序；**只有用户要求修复时才修改**。
4. 需要判断废弃 API 时查 `references/deprecated-apis.md` 对应版本。

## 完成标准

- 配置类 health warning 已解释或清除；系统可选依赖与真实配置问题分开。
- 所有 Lua 文件通过 stylua 检查。
- 配置行为、`core/ui/reference.lua` 与 `~/md/nvim` 描述一致。
- 新发现的问题写入 `nvim-troubleshooting` 技能内的 `~/.agents/skills/nvim-troubleshooting/references/nvim-troubleshooting-history.md`。

## 最小验证

按改动选择：

```bash
nvim --headless '+checkhealth' '+write! /tmp/nvim-health.txt' '+qa'
find ~/.config/nvim -type f -name '*.lua' -print0 | xargs -0 ~/.local/share/nvim/mason/bin/stylua --check
```
