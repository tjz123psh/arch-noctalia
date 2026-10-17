# 本机调试模式

本机 Neovim 配置的事实与已解决问题，供调试时快速参考。

## 环境

| 项目 | 内容 |
|------|------|
| Neovim | 0.12.5 |
| 插件管理器 | lazy.nvim |
| Leader/Localleader | 空格 / `\` |
| 主题 | catppuccin-mocha |
| 终端 | kitty (Wayland), JetBrainsMono Nerd Font |
| 系统 | Arch Linux |
| 配置路径 | `~/.config/nvim/` |

版本号随升级变化，需要时以 `nvim --version` 为准。

## 目录结构与加载顺序

完整目录树、模块职责和加载顺序见 `nvim-config` 的 `references/architecture.md`（本文件不再重复，避免两处不同步）。

调试时只记两点：

1. `lua/core/` 与 `lua/plugins/` 是实际路径；`require("core.X")` 对应 `lua/core/X.lua`。
   注意 `lazy.nvim` 引导入口是 `lua/core/lazy.lua`（不是仓库根的 `lazy.lua`）。
2. 加载顺序：`init.lua` 设 leader → `require("core")`（options → filetypes → keymaps → commands → autocmds）
   → `require("core.lazy")` 加载 `lua/plugins/` → 仅 Neovide 时 `require("neovide")`。

## 已踩坑问题

### jdtls root_dir（Neovim 0.12+）

`vim.lsp.start` 不解析函数式 `root_dir`，必须在 `config()` 中预求值为字符串再传入。详见 `nvim-troubleshooting-history.md` §9.1。

### jdtls workspace_dir 跨项目

`cmd` 每次 `start_or_attach` 时重新拼装 `-data` 参数，不同项目用独立 workspace 目录。详见 `nvim-troubleshooting-history.md` §9.2。

### project.nvim 项目列表（snacks picker）

project.lua 用 `lazy = false`，启动即初始化项目历史。项目列表入口统一走 `:Projects`：先 `lazy.load` project/neo-tree/snacks，再读历史，用 snacks picker（`source = "project-history"`；**不能**用 snacks 内置同名源 `projects`，自定义字段也不能叫 `dir`）展示项目；回车只切 cwd 并打开/刷新 neo-tree。telescope.nvim 已随 dressing 一起删除，不要再按旧文档去 `telescope.lua` 找扩展注册。详见 `nvim-troubleshooting-history.md` §10.1。

**项目历史是易失数据，靠三层保护**（2026-09-25 二次清空后加固，详见 §13.1）：project.nvim 的
`write_projects_to_history()` 在 `recent_projects ~= nil` 时用 `mode="w"` **截断**重写历史文件，
而它读文件是**异步**的；并发跑多个 nvim 时，一个实例退出瞬间的空文件会被另一个实例读成空表，
再被截断写回 ⇒ 历史清空。现在 `lua/core/commands.lua` 自维护只追加副本
`~/.local/state/nvim/project-history.list`，`:Projects` 列表 = 副本 ∪ 插件文件 ∪ 会话项目（并集，
永不缩小），每次打开还把插件文件缺的条目 **append** 回插件文件（append 不截断，插件的 fs_event
会因此重读并修好它的内存表），另有 `DirChanged` autocmd 兜底。

**`:Projects` 观感**：行 = 图标 + 项目名（亮）+ 父目录（暗，home 缩成 `~`）；宽度贴合内容
（`[40, min(96, columns-8)]`，原固定 0.5 屏宽）；当前项目置顶，蓝名字 + `当前` 徽标
（高亮组 `SnacksPickerCurrentProject` / `SnacksPickerCurrentBadge`）。实现见 `lua/core/commands.lua`
的 `format` 与 `window_width`。详见 §13.6。

### snacks picker 的显示细节（踩过的坑）

- **子窗宽度**：input / list 子窗默认与父 `box` **同宽**（实测 box w=52 → list w=52）。曾把 list
  收窄 2 列想让选中行底色不压边框，结果右侧多出一条 2 列宽、颜色不一致的竖条 ⇒ **别收窄**，
  只调最外层 `layout.width`。详见 §13.2。
- **选中行高亮组**：list 用的是 `SnacksPickerListCursorLine`（默认 link 到 `Visual`），只设
  `SnacksPickerCursorLine` 是白设；本机 soft 皮肤两个一起设成 `bg=#313244, bold`。详见 §13.3。
- **自定义行富文本**：`format = function(item, picker)` 返回 chunk 数组 `{ {text, hl}, ... }`；
  `list.lua` 在**渲染后的文本**上重算匹配位置（隐藏字段不高亮但不影响过滤）；每项的
  `resolve = function(max_width)` 可做宽度感知截断；`opts.format` 会**整体替换**内置文件行格式器。详见 §13.4。
- **内联 layout 盖过预设**：`layout = { preset = "picker_compact", layout = { width = 61 } }` 实测生效
  （53 → 61）。"预设的键赢过内联覆盖"**只对窗口键位成立**，布局字段是内联赢；改预设前按目标字段
  实测。详见 §13.5。

### neo-tree 跟随项目切换

`filetree.lua` 使用 `filesystem.bind_to_cwd = true`。项目列表选中项目后，project.nvim 会设置 cwd；本机还包装了 `Project.set_pwd()`，成功切换后主动调用已加载的 neo-tree filesystem state 刷新到项目目录，不应继续停在 `$HOME`。

### conform 首次保存加载

`event = { "BufWritePre" }` 确保 `format_on_save` 在首次保存前生效。保留 `<leader>F` 手动格式化。详见 `nvim-troubleshooting-history.md` §10.3。

### 可视模式 J/K 与 noice

不要用 `'<`/`'>` 取范围：这两个标记只在离开可视模式时才写入，在 `x` 模式回调里展开 `'<,'>` 会报 E20，或静默移动上一次可视操作的行。改用 `line("v")`/`line(".")` 算行号后以数字范围调 `:move`，并注意 `gv` 在可视模式内只切换 行块/字符、不恢复标记（需先退出可视模式）。Lua 函数 + `vim.cmd` 直调也避免走命令行模式，noice 不拦截闪框。详见 `nvim-troubleshooting-history.md` §6.4。

### alpha 自动加载与 :A

`dashboard.lua` 只在无文件参数时注册 `VimEnter` 事件，不能用 `cond = argc == 0` 禁用整个插件，否则带文件启动后 `:A` 无法按需加载。

### Treesitter 与 Mason CLI 时序

Treesitter 和 Mason 都会在启动阶段加载。发现缺失解析器时，先检测 `stdpath("data")/mason/bin/tree-sitter` 并补入 `PATH`，避免 Mason 尚未 setup 时误报 CLI 缺失。

### Treesitter 解析器下载需要本机 Clash 代理

`nvim-treesitter` 的 `install()` 用 curl 拉 GitHub tarball。**2026-10-16：`~/.config/fish/conf.d/proxy-env.fish` 已恢复**（只在 `127.0.0.1:7890` 有监听时才设 `HTTP(S)_PROXY` / `ALL_PROXY`，大小写都设；实测走它拉 github 返回 200）⇒ **从 fish 启动的 nvim 有代理**；但 headless 脚本、非 fish shell（含 agent 自己的 bash）**没有** ⇒ 那些场景要手动带 `HTTPS_PROXY=http://127.0.0.1:7890`（无 tun 网卡，直连 google/github 均超时），而配置启动时会自动重试 ⇒ 每次启动刷一屏 curl 错误。`treesitter.lua` 已加 6 小时节流（stamp：`~/.local/state/nvim/treesitter-install-stamp`），节流期内只留一条 INFO 不联网。手动装须带代理：

```bash
HTTPS_PROXY=http://127.0.0.1:7890 nvim --headless \
  -c "lua require('nvim-treesitter').install({'tsx','vue','svelte','scss','typescript'}):wait(420000)" -c "qa!"
```

是否真在联网下载用 `pgrep -f 'tree-sitter-scs[s]'` 确认（方括号让模式不匹配 pgrep 自己的命令行）。详见 `nvim-troubleshooting-history.md` §12.3。

### Treesitter filetype 别名（不用自己 register）

`nvim-treesitter/plugin/filetypes.lua` 已注册 tsx↔typescriptreact、json↔jsonc、bash↔sh、xml↔xsd/xslt/svg、properties↔jproperties 等别名，解析器装好后 `vim.treesitter.start()` 在 .tsx/.jsonc/.sh 上直接可用；不要再写 `vim.treesitter.language.register`。详见 §12.4。

### Mason 初始化顺序 + 不管理 LSP 启动

`mason.nvim` 为 `lazy = false`，`mason-lspconfig` config 里先 `require("mason").setup({ PATH = "prepend" })` 再 setup，避免启动提示 mason 未初始化。`automatic_enable = false`，Mason 只负责安装；全靠 `vim.lsp.config` + `vim.lsp.enable` 或 nvim-jdtls 手动启动。详见 `nvim-troubleshooting-history.md` §1.2–§1.3。

### 自定义 filetype 识别

`core/filetypes.lua` 注册 `gotmpl`、`markdown.mdx`、`yaml.docker-compose`、`yaml.gitlab`、`yaml.helm-values`。LSP health 不应再出现这些 Unknown filetype 警告。

另一类假条目来自 server 默认 filetypes 写了**扩展名**而非真 filetype：lemminx 默认带 `xsl`，而 Neovim 把 .xsl/.xslt 都识别成 filetype `xslt`，已在 `lsp/init.lua` 覆盖为 `{ "xml", "xsd", "xslt", "svg" }`。详见 §12.8。

### jdtls 跳过 lspconfig

`setup = { jdtls = function() return true end }`，避免双重启动。详见 `nvim-troubleshooting-history.md` §1.4。

### Java DAP 注意事项

- `mainClass` 必须是字符串（函数不可 JSON 序列化）
- java-debug-adapter 必须作为 jdtls bundle 加载
- 必须先 F9 设断点（不停 main）
- 快捷键重复注册问题：用 `setup_java_keys(bufnr)` 函数复用
详见 `nvim-troubleshooting-history.md` §5.1–§5.4。

### Spring Boot 插件懒加载（cmd 桩）

`lang/springboot.lua` 里两个插件不再用 `lazy = false`：spring-boot.nvim 用 `cmd = { "SpringBoot" }, ft = { "java", "yaml", "jproperties" }`，springboot-nvim 用 `cmd = { "SpringBootNewProject" }`。命令在插件 setup() 里注册，必须用 `cmd` 桩保证启动期就存在，否则全局键 `<leader>sP` 在非 java 缓冲区按出 E492。这样 nvim-jdtls/DAP 也不会被拖进启动期。详见 §12.2。

### C++ DAP

cpp.lua 配置了 cpp 3 种、c 2 种运行配置；多配置时 F5 弹出 picker。

### blink.cmp 双空格映射

`["<Space><Space>"]` 导致空格延迟，已删，改打字时自动触发。

### blink.cmp 片段来源

使用 Blink 内置 snippets source + Neovim 原生 `vim.snippet`，片段数据来自 `friendly-snippets`。`Tab` 优先接受补全，其次跳到下一个占位符；`Shift-Tab` 跳到上一个占位符。不再保留未接入 Blink 的 LuaSnip 空配置。

### timeoutlen 与 jk 冲突

已换用 `better-escape.vim` 插件（不依赖 timeoutlen），删掉 `keymaps.lua` 中的 `inoremap jk <Esc>`。

### 格式化统一

全部统一 4 格缩进：clang-format（`~/.clang-format`）、google-java-format（`--aosp`）、stylua、rustfmt。（**2026-10-16 核对：本机只装了 `rustfmt`；`clang-format` / `google-java-format` / `stylua` 均未安装，`~/.clang-format` 也不存在** —— 这几条当前只是「规则约定」，实际靠项目内自带配置或按需安装）`format_on_save.timeout_ms = 2000`，`lsp_format = "fallback"`，显式格式化器优先，LSP 兜底。

### bufferline 不强制关闭未保存 buffer

`bufferline.lua` 使用 `bdelete %d`，不是 `bdelete! %d`。关闭有未保存修改的 buffer 会失败并提示，而不是直接丢内容。
`options.lua` 同时设置 `confirm = true`，退出或关闭含未保存修改的缓冲区时要求明确确认。

### 退出时保存所有被修改的缓冲区

`:{N}write` 不会写第 N 个缓冲区（实测 `:1write` 对被改过的 buffer 1 是静默 no-op），要写指定缓冲区必须用 `vim.api.nvim_buf_call(buf, function() vim.cmd("silent! lockmarks write") end)`。`core/autocmds.lua` 因此在 `QuitPre`/`VimLeavePre` 遍历所有 buffer 保存，`:qa` 不再因后台改过的文件弹 E37。详见 §12.5。

### 状态栏与 neo-tree 扩展

`statusline.lua` 的 `disabled_filetypes` 只保留 `alpha`：lualine 对被禁用的 filetype 直接返回空 statusline，写进这里的扩展（如 `neo-tree`）永远不生效。详见 §12.6。

### 诊断浮窗的 code 后缀

`core/options.lua` 自定义 `vim.diagnostic.config` 的 `float.suffix`：纯数字 code（jdtls 内部诊断号）不显示，`E0308`、eslint 规则名这类文字码保留。详见 §12.7。

### which-key 关键设置

- `triggers` 配置了 `\\` 触发 localleader 自动展开
- `desc` 优先级：spec 配置 > `vim.keymap.set` 的 desc
- 每个 keymap 需独立 opts 表（用辅助函数 `desc(d)`）
- 配置在 `lua/plugins/whichkey.lua`

### project.nvim 使用已废弃 API

`patch`：运行时 monkey-patch `find_lsp_root`，用 `vim.lsp.get_clients()` 替代。不修改插件源文件。

### 快捷键冲突

- `s/S` 被 flash 接管，原功能可用 `xi`/`cc` 替代
- `K` 在普通模式中为上移当前行；LSP 悬浮文档改为 `gh`
- `H/L` 被 bufferline 接管为切换缓冲区
- `<leader>F` 格式化 vs `<leader>f` 前缀给 snacks picker 搜索
- 注释用 Neovim 内置 `gc`（n/x，operator）/`gcc`（n），已删除 Comment.nvim；没有 `gb`/`gbc` 块注释和 `gcO`/`gco`/`gcA`。详见 §12.1

### 启动性能基线

```bash
nvim --startuptime /tmp/startup.log -c q
# 按第一列（clock，毫秒）降序取最慢的项
sort -k1 -n -r /tmp/startup.log | head -20
```

判定标准：单项 <100ms 正常、100–300ms 可接受、>300ms 需调查、>1000ms 明显有问题。
最后一行 `--- NVIM STARTED ---` 的 clock 值即总启动耗时。
本机启动即加载的插件应是必要项：catppuccin、mason 三件套、blink.cmp（含 friendly-snippets）、noice、nvim-lspconfig、nvim-treesitter、project.nvim、snacks（含 devicons/nui/notify 依赖）。spring-boot.nvim 已从 `lazy = false` 改为 `cmd`/`ft`，不应出现在启动加载里。

### UI 类结论必须真 pty 复核

headless 不触发 `UIEnter`，挂在 `event = "UIEnter"` 上的 lualine、snacks 的 `vim.ui` 接管等都不会加载，用 headless 测"状态栏 / 输入框是否生效"必然假阴性。本次真 pty 里确认 `LASTSTATUS=3`、`LUALINE_LOADED=true`、neo-tree statusline 渲染长度 80。详见 §12.9。

## 调试检查清单

当面对一个问题时：

1. 读 `nvim-config` → 了解本机结构和插件加载规则
2. 查 `references/nvim-troubleshooting-history.md` → 是否已有踩坑记录
3. 查本文件 → 针对性的本机事实
4. 都没有 → 用 `--headless` 最小复现（UI / 状态栏 / `vim.ui` 接管类问题改真 pty），定位后再写入 `references/nvim-troubleshooting-history.md`

## 相关文档

| 文档 | 用途 |
|------|------|
| `~/.agents/skills/nvim-config/SKILL.md` | 目录结构、加载顺序、快捷键体系、审计 |
| `~/.agents/skills/nvim-troubleshooting/SKILL.md` | 本 skill 入口：排障流水线 |
| `~/.agents/skills/nvim-troubleshooting/references/local-patterns.md` | 本文件：本机调试事实 |
