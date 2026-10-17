---
name: nvim-troubleshooting
description: "Diagnose and fix Neovim faults on this workstation: new errors, keymaps, plugin loading, LSP/DAP, performance, UI, plus retrieval of previously solved incidents."
when-to-use: "Use when nvim 出问题要定位根因，或疑似以前修过的老问题复发。改配置本身用 `nvim-config`。"
---

# NVIM Troubleshooting

本机 Neovim 的**排障流水线**：新故障先复现定位，历史故障直接取方案。

## 使用原则

1. 记录可观察症状、触发步骤和期望行为，先用 headless/静态检查复现。
2. 形成一个最可能假设，设计能区分它与其他原因的检查，再逐步缩小范围。
3. 修复后重跑原触发路径和相邻边界；只有确实需要交互状态时才询问用户。
4. 定位到根因后，若值得留存，追加到本技能内的 `references/nvim-troubleshooting-history.md`
   （不要把长记录塞回本入口文件）。

## 第一步：判断是新问题还是历史问题

**像历史问题**（用户说"之前修过""又出现/还是报错"，或症状匹配已知插件）→ 跳到第 2 步直接取方案。

**新问题** → 按下面分类定位：

| 问题类型 | 起点 |
|----------|------|
| **Lua 错误**（`E5108`） | 先看错误里的文件:行号，判断是自己配置还是插件代码；`:messages` 与 `checkhealth` 佐证 |
| **按键无效 / 与预期不符** | `:verbose nmap <键>` 查是谁最后定义了它；再核 `nvim-config` 的快捷键约定 |
| **插件未加载 / 本机特殊配置** | `references/local-patterns.md` 对应插件；再查下面第 2 步是否已有记录 |
| **性能问题** | `startuptime`（见 `local-patterns.md` 启动性能基线）、`:Lazy profile` |
| **UI / 显示异常** | `checkhealth` 看依赖；`local-patterns.md` 的 Noice / statusline / bufferline 小节 |
| **LSP 红色报错 / spring 补全缺失 / Java 调试起不来** | 先看 `19`（`workspace/executeClientCommand` 的 handler 写法 + classpath 握手）；带 `Method not found` 字样基本就是这个 |
| **配置该改成什么样** | 不属于排障 → 用 `nvim-config` |

## 第二步：查历史方案

历史故障全文**就在本技能内**（`references/nvim-troubleshooting-history.md`，按章节组织）：

```text
~/.agents/skills/nvim-troubleshooting/references/nvim-troubleshooting-history.md
```

先按症状/插件名定位标题，**只读对应章节**：

```bash
H=~/.agents/skills/nvim-troubleshooting/references/nvim-troubleshooting-history.md
grep -nE '^##|^###|<症状关键词>' "$H"
```

章节速查（直接 grep 这些名字必有命中）：

- `45. 整体配置去重与 virtual-text 请求监听参数`（当前目录归属；DAP 请求监听 session/err/response 的旧签名不兼容；UI 探针模式同步）

- `37. Markdown 改为编辑区美化`（render-markdown 克制样式；模式切换、anti-conceal、当前缓冲区开关和源文件保真验证）
- `36. grep 布局残留旧节点与配置职责整理`（搜索列表仅一行 / 预览越界；独立布局树、resize 回归；diagnostics/projects/ui 新归属）
- `1. LSP`（clangd / Mason / jdtls）
- `2. 插入模式退出（jk）`（timeoutlen 冲突）
- `3. 补全`（blink.cmp）
- `4. 调试（DAP，C++）` / `5. 调试（DAP，Java）`
- `6. UI 与延迟加载`（Noice / statusline / bufferline / 可视模式移动）
- `7. 项目管理`（project.nvim / LSP root）
- `8. 系统`（未使用的包检查）
- `9. Java LSP（nvim-jdtls）`（root_dir / workspace_dir / bundle）
- `10. 懒加载与优化`（格式化 / conform / 启动页 / Treesitter 时序）
- `11. 插件管理器（lazy.nvim 引导）`
- `12. 插件精简与启动收尾`（Comment→内置 gc / springboot `cmd` 桩 / Treesitter 代理与 6 小时节流 / 退出保存所有缓冲区 / lualine 与 neo-tree / 诊断 code 后缀 / Unknown filetype 'xsl'）
- `13. 项目历史二次清空与 snacks picker 细节`（`write_projects_to_history()` 截断写 + 异步读竞态 ⇒ 只追加副本 / 并集 / append 回填；picker 子窗宽度、`SnacksPickerListCursorLine`、自定义行富文本、内联 layout 盖过预设、`:Projects` 观感）
- `14. 真机走查探针方法论`（就绪判据 / 双 client 扇出 / vim.wait 不处理按键 / 静默死亡 / hit-enter / toggleterm.get / stylua 副本要带 --config-path）
- `15. which-key 可视模式触发器`（旧结论被推翻：根因是 triggers 只写了 mode="n"）
- `16. Java 真机走查结论` / `17. Java 缓冲区 :e/:e! 之后 LSP 静默失效`
- `18. DAP 两个隐藏陷阱 + pty 探针 swap 陷阱 + 探针纪律补遗`（§18.1 DAP arguments 空表 = 请求永久挂起；§18.2 `stackFrames`；§18.3 空 logMessage 语义；§18.4 必须 `nvim -n`；§18.5 blink 菜单判据；§18.6 上游 pick_many 无取消通道；§18.7 picker 自省与 pty 驱动；§18.8 清理服务要按精确 PID；§18.9 spring-boot LS 孤儿；§18.10 探针纪律 7 条）
- `25. 换了 CLI 主题但面板还是旧的`（会话由 **tmux 保持**、`close()` 只是 detach、上游无 kill API ⇒ 用 `<leader>aR` 重启会话；⚠ 关掉 `mux` 会让 scrollback 一起失效）
- `24. AI CLI 里「往上翻看输出」`（**备用屏幕**：TUI 的历史不进 nvim 终端缓冲 ⇒ `jk` 后翻不到东西；用 sidekick scrollback（tmux dump 2000 行）；`opencode` 被标记 `native_scroll` 没有 scrollback；本机键盘开关 `<M-u>`。附：`cli.win.keys` 是深合并，与 snacks 相反）
- `23. 透明主题下的「终端底色」`（⚠ **实现已按用户要求回退**，只保留知识：让 `:terminal`/toggleterm 浮窗/sidekick 面板恢复实底、编辑区仍透明。两个关键事实：**浮窗背景用 `NormalFloat` 而非 `Normal`**；**toggleterm 的 `ui.hl_term()` 在 `on_open` 之前覆盖 winhighlight**，必须用 `on_open` 补。验证手法：pyte 读单元格 bg，`default` 即透明）
- `22. sidekick.nvim 安装、三个坑与一次清理事故`（⚠ 其中 22.4 的 `SidekickChat` 修复已回退；① 无 `plugin/` 目录的懒加载插件 `:checkhealth` 要先 `:Lazy load`；② `mux=tmux` 会真建会话，清理**只能清测试新增的差集**；③ **面板半透明 = sidekick 从不定义 `SidekickChat`** 而 `winhighlight` 指向它，透明主题下壁纸透进面板 ⇒ 自己补实底；④ 事故：按名字通杀 tmux 会话误杀用户自己的会话）（① **无 `plugin/` 目录的懒加载插件 `:checkhealth` 必须先 `:Lazy load`**，否则报「No healthcheck found」；② `mux=tmux` 会**真建 tmux 会话**，探针测完必须 `tmux kill-session` + `pkill` 清理，否则留后台 AI 进程）
- `21. 诊断消息被「截断」`（**`virtual_lines` 自身不折行**：`virt_lines_overflow='scroll'`，超宽被窗口右边缘裁掉；浮窗才会折行 —— 别搞混。修法：在 `virtual_lines.format` 里按窗口宽度插换行，渲染器按换行切分且每行带 `└────` 前缀）
- `20. 中文标点自动转半角`（**没有现成插件**：cpc.nvim 是命令式、autocorrect 规则相反；正解是 `InsertCharPre` + `vim.v.char`。含两个坑：Lua `[...]` 字符类按单字节匹配多字节汉字永远匹配不到；headless `feedkeys` 不能验证多字节输入，必须真 pty）
- `19. LSP 服务端→客户端请求（workspace/executeClientCommand）`（**打开 Java 项目弹红色报错 / spring 补全缺失 / <F5> javaExec 解析失败** 都看这节：`return nil` 与 `error(-32601)` 两个坑、client 级 handler 盖掉全局转发、reloadBundles 要回空表、单测手法、`lsp.log` 轮转）

## 快速命令

```bash
# 插件能否 require（加载失败常是目录被 clone 中断）
nvim --headless -c "lua print(pcall(require, 'PLUGIN'))" -c "qa" 2>&1
# lazy 的加载统计（哪些插件启动即加载）
nvim --headless -c "lua print(vim.inspect(require('lazy').stats()))" -c "qa" 2>&1
# 某个键到底被谁定义了（会显示来源文件:行号）
nvim --headless -c "verbose nmap <键>" -c "qa" 2>&1
# LSP 客户端是否附加到当前 buffer
nvim --headless '+e <file>' '+sleep 2' '+lua for _, c in ipairs(vim.lsp.get_clients({bufnr=0})) do print(c.name) end' '+qa' 2>&1
# 健康检查（保存到文件便于 grep）
nvim --headless '+checkhealth' '+write! /tmp/nvim-health.txt' '+qa'
# UI 类问题（statusline / vim.ui 接管）：headless 不触发 UIEnter，必须真 pty 复核（见 §12.9）
```

## 按需参考

| 文档 | 用途 |
|------|------|
| `references/local-patterns.md` | 本机目录、插件归属、已踩过的坑（最常用） |
| `references/nvim-troubleshooting-history.md` | 历史故障的完整根因与解决方案（已内嵌，按编号章节组织） |
| `nvim-config` | 配置应有的形态、约定、审计清单（改配置时用） |

## 修好之后

配置改动落地后，按 `nvim-config` 的同步规则更新 `~/md/nvim` 用户文档（现只有命令 / 自定义命令 / 插件介绍 / 配置架构 4 份；快捷键速查在 `<leader>hk`，不再有独立快捷键 md）；
值得留存的新坑追加到 `references/nvim-troubleshooting-history.md`。
