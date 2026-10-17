---
name: nvim-troubleshooting
description: Neovim 配置过程遇到的问题与最终解决方案。改配置后发现新问题必须追加，重复问题以最新方案覆盖。配合 nvim-config 使用。
---

> **2026-09-24**：本文件已内嵌进 `nvim-troubleshooting` 技能（`references/nvim-troubleshooting-history.md`），新问题一律追加到本文件。

# Neovim 配置问题排查记录

每次修改配置后必须将新问题追加到此处，重复问题以最新完全解决方案覆盖。

## 环境

| Neovim | 插件管理器 | 终端 | 系统 |
|--------|-----------|------|------|
| 0.12.5 | lazy.nvim | kitty (Wayland) | Arch Linux |

---

## 1. LSP

### 1.1 clangd root_dir 用新 API（Neovim 0.12+）

**问题**：`root_dir` 旧签名 `function(fname) → string`，0.12+ 要求 `function(bufnr, on_dir)`。

**解决**（`lua/plugins/lang/cpp.lua`）：
```lua
root_dir = function(bufnr, on_dir)
  local fname = vim.api.nvim_buf_get_name(bufnr)
  if fname and #fname > 0 then
    on_dir(vim.fs.root(fname, { ".clangd", "compile_commands.json", "build/compile_commands.json", ".git" }) or vim.fn.getcwd())
  end
end,
```
关键：必须调 `on_dir(path)` 传回结果，不能 return；用 `vim.fs.root()` 替代手动遍历父目录。

### 1.2 Mason 重复启动 LSP 客户端

**问题**：mason-lspconfig 自动配置 + 手动 `vim.lsp.config` + `vim.lsp.enable` 导致每个 buffer 两个 LSP 客户端。

**解决**（`lua/plugins/lsp/init.lua`）：
```lua
automatic_enable = false, -- 手动管理，跳过自动启用
```
全靠 `config` 函数内的 `vim.lsp.config` + `vim.lsp.enable` 启动，mason 只负责安装。

### 1.3 LSP 配置从旧 API 迁移到 vim.lsp.config

**问题**：旧版用 `require("lspconfig.configs.X").default` 合并配置，0.12+ 改用 `vim.lsp.config` + `vim.lsp.enable`。

**解决**：`vim.lsp.config(server, config)` → `vim.lsp.enable(server)`。`vim.lsp.enable` 自动处理去重。

### 1.3.1 Mason 未初始化警告

**问题**：启动时出现 `mason.nvim has not been set up. Make sure to set up mason.nvim before mason-lspconfig.nvim.`。

**根因**：mason-lspconfig 的 setup 早于 mason.nvim setup。

**解决**（`lua/plugins/lsp/init.lua`）：
```lua
config = function(_, opts)
  require("mason").setup({ PATH = "prepend" })
  require("mason-lspconfig").setup(opts)
end
```
同时 `mason.lua` 保持 `lazy = false`。

### 1.3.2 Mason health 可选工具警告

**问题**：`:checkhealth mason` 提示 wget、luarocks、Ruby、Composer、PHP、Julia、pip 等缺失。

**判断**：这些是 Mason 对多语言生态的可选探测，不等同于当前 Neovim 配置故障。只要本配置需要的工具链可用即可：git/curl/unzip/tar/bash、node/npm、python、cargo、go、java/javac，以及 Mason 已安装的 LSP/DAP/formatter。

**处理**：不要为了清警告在 Neovim 配置中硬屏蔽；只有实际要安装对应生态的 Mason 包时，再补系统依赖。

### 1.4 jdtls 不由 lspconfig 管理

**问题**：jdtls 由 nvim-jdtls 独立管理，lspconfig 也试图启动会冲突。

**解决**（`lua/plugins/lsp/init.lua`）：
```lua
setup = {
  jdtls = function() return true end, -- 跳过
}
```

---

## 2. 插入模式退出（jk）

### 2.1 timeoutlen 与 jk 冲突

**问题**：`timeoutlen` 设高让 Space leader 能响应多键组合，但 `inoremap jk <Esc>` 导致每次按 `j` 都要等 timeoutlen 才显示字符。

**解决**：换 `better-escape.vim` 插件，监听按键时检查光标前字符，不依赖 `timeoutlen`。
```lua
-- lua/plugins/betterescape.lua
{
  "nvim-zh/better-escape.vim",
  event = "InsertEnter",
  config = function()
    vim.g.better_escape_shortcut = "jk"
    vim.g.better_escape_interval = 200
  end,
}
```
同时删掉 `keymaps.lua` 的 `inoremap jk <Esc>` 和 `autocmds.lua` 的 `timeoutlen` 切换逻辑。

---

## 3. 补全

### 3.1 blink.cmp 双空格触发导致空格延迟

**问题**：`["<Space><Space>"] = { "show", "hide" }` 使每次按空格都要等确认是否为第二个空格。

**解决**：删掉双空格映射，让 blink.cmp 打字时自动触发。

---

## 4. 调试（DAP，C++）

### 4.1 codelldb 未安装

**解决**：`:MasonInstall codelldb`。

### 4.2 DAP UI 闪开闪闭

**问题**：`stopOnEntry = false` 且未设断点时，程序直接跑完退出。

**解决**：保留 `stopOnEntry = false`，调试前 F9 设断点。不要 `stopOnEntry = true`（会停在 ld 的汇编代码中）。正确流程：
```
g++ -g test/Merge-sort.cpp -o bin/Merge-sort
# 打开源文件 → F9 设断点 → F5 输入 bin/程序名
```

### 4.3 "Invalid cursor line: out of range"

**原因**：源代码修改后未重新编译，debug info 与源文件不匹配。

**解决**：`g++ -g` 重新编译。

---

## 5. 调试（DAP，Java）

### 5.1 mainClass 必须为字符串

**问题**：`dap.run()` 将配置序列化为 JSON，函数无法序列化。

**解决**：`vim.fn.input("主类名: ")` 先求值为字符串，再传 `dap.run({ mainClass = 字符串 })`。

### 5.2 java-debug-adapter 必须作为 jdtls bundle 加载

**问题**：不能 `java -jar` 独立运行。

**解决**（`lua/plugins/lang/java.lua`）：
```lua
local java_debug_jar = vim.fn.glob(
  vim.fn.stdpath("data") .. "/mason/packages/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar")
if #java_debug_jar > 0 then
  vim.list_extend(opts.init_options.bundles, java_debug_jar)
end
```

### 5.3 Java 调试必须预先设断点

**问题**：java-debug-adapter 不像 codelldb 自动停在 main。

**解决**：F9 设断点，再 F5。

### 5.4 快捷键重复注册（schedule + autocmd）

**问题**：`ft = "java"` 懒加载导致当前 buffer 的 FileType 事件错过，所以同时用 `vim.schedule` + `FileType` autocmd 处理，导致 `<F5>`、`<leader>co`、`<leader>ot` 注册两次。

**解决**：提取 `setup_java_keys(bufnr)` 函数，两处共用。

---

## 6. UI 与延迟加载

### 6.1 shell = fish 导致构建命令异常

**问题**：`vim.o.shell = fish` 语法与 POSIX sh 不同，lazy.nvim 的 `build` 用 `sh -c` 执行报错。

**解决**：通过 `vim.fn.exepath("bash")` 找 bash，找不到时保留默认 shell。
```lua
vim.o.shell = vim.fn.exepath("bash") ~= "" and vim.fn.exepath("bash") or vim.o.shell
```

### 6.2 Noice 自身即可接管 vim.ui.input

Noice 的 `cmdline.format.input` 默认 `view = "cmdline_input"`，拦截 `vim.fn.input()` 后渲染为圆角浮动窗口，无需 dressing/snacks。`use_popups_for_input = false` 后 neo-tree 也走此路径。

**注意**：neo-tree 会在 prompt 末尾加 `\n`，导致 `cmdline_input` 判定 `use_input = false` → prompt 显示为行内文字而非标题，图标也隐藏。视觉影响可接受。

### 6.3 statusline/lualine 加载时机

**问题**：`event = "VeryLazy"` 使状态栏晚出现。

**解决**：`event = "UIEnter"`（UI 首次绘制后立即加载）。

### 6.4 可视模式 `J`/`K`：noice 闪框 + `'< '>` 未设定导致移动无效

**问题（两阶段）**：

1. 可视模式用 `:m '<-2<CR>gv=gv` 移动行，`: ` 进入命令行模式，noice 渲染为浮动窗口闪一下。
2. 改成 Lua 函数 + `vim.cmd("'<,'>move ...")` 后闪框没了，但**移位本身失效**：报
   `E20: 没有设定标记: '<,'>move '>+1`；更糟的是若 `'<`/`'>` 残留自上一次可视操作，
   命令会**静默移动错误的行**（实测：先对 L2-L3 做过可视操作，再选 L5-L6 按 K，
   被移动的是 L1-L2）。

**根因**：`'<` 与 `'>` 只在**离开可视模式时**才写入；可视模式内 `getpos("'<")` 返回
`[0,0,0,0]`。在 `x` 模式映射的 callback 里展开 `'<,'>` 范围，读到的是未设定值或上次的
残留值。这不是本机配置问题——`nvim --clean` 同样复现。

**解决**：不用标记取范围，直接用 `line("v")` 与 `line(".")` 算行号，以数字范围调 `:move`。
另外三点必须同时处理，否则有新的坑：

- `gv` 在可视模式内只切换 行块/字符，**不按标记恢复**。必须先 `normal! \27` 退出可视模式，
  再写 `'<`/`'>` 并 `gv`，行块选区才不会退化成字符选区。
- 重缩进不能用 `=gv`（也会退出可视模式），改用 `:[range]normal! ==`。
- `= ` 只在有缩进来源时才安全：`indentexpr`/`cindent`/`lisp` 全为空且 `equalprg` 为空时
  （Markdown、纯文本），`=` 会把缩进清成 0——而这类文件的缩进本身就是内容，必须跳过。
- `x` 模式映射不覆盖 select 模式（可视模式内按 `<C-g>`），需另绑 `s` 模式，
  否则 J/K 会被当作输入插入。

```lua
local function can_reindent()
  return vim.o.equalprg == "" and (vim.bo.indentexpr ~= "" or vim.bo.cindent or vim.o.lisp)
end

local function move_visual_lines(direction)
  if not vim.bo.modifiable then
    return
  end
  local first = vim.fn.line("v")
  local last = vim.fn.line(".")
  if first > last then
    first, last = last, first
  end
  local steps = vim.v.count1
  local target, delta
  if direction > 0 then
    target = math.min(last + steps, vim.api.nvim_buf_line_count(0))
    delta = target - last
  else
    target = math.max(first - steps - 1, 0)
    delta = target + 1 - first
  end
  if delta == 0 then
    return -- 已到边界，避免 :move 报 E16
  end
  vim.cmd(("silent keepjumps %d,%dmove %d"):format(first, last, target))
  if can_reindent() then
    vim.cmd(("silent keepjumps %d,%dnormal! =="):format(first + delta, last + delta))
  end
  vim.cmd("normal! \27")
  vim.fn.setpos("'<", { 0, first + delta, 1, 0 })
  vim.fn.setpos("'>", { 0, last + delta, 1, 0 })
  vim.api.nvim_win_set_cursor(0, { last + delta, 0 })
  vim.cmd("normal! gv")
end

for _, mode in ipairs({ "x", "s" }) do
  map(mode, "J", function()
    move_visual_lines(1)
  end, { desc = "下移选中行", silent = true })
  map(mode, "K", function()
    move_visual_lines(-1)
  end, { desc = "上移选中行", silent = true })
end
```

关键：`vim.cmd` 是 Lua API 调用，不经过命令行模式，noice 不拦截。

### 6.4.1 可视模式整块移动的验证要点

`E20` 只在「本次会话还没离开过可视模式」时出现；一旦有过可视操作，就变成静默错误范围，
**不报错但改错行**。因此验证必须覆盖：先在别处做一次可视操作，再选新范围移动。
另需覆盖边界（首/末行 `K`/`J` 应无操作）、计数前缀（`3J`/`3K`）、行块/字符/块三种选区，
以及 Markdown 等无缩进来源的文件类型。

### 6.4.2 三处「审查报告点名、逐条实测复现」的修复（2026-09-28）

背景：一份外部审查报告（`~/.config/nvim/NVIM_CONFIG_AUDIT_REPORT.md`，29 条）经「3 个子代理分组实测 + lead 独立复核」
逐条核实。报告整体靠谱（属实 15 / 部分属实 11 / **不属实 3**），但**机制解释**有 3 处写错、1 条建议**照着做会砸环境**。
下面三条是核实后实际落地的修复，都带复现与回归验证。

#### (a) 行选模式按 `J`/`K` 掉回普通模式（`keymaps.lua`）

**症状**：`V` 选多行后按 `J` 能移动，但选区瞬间消失、退回普通模式，无法连续 `J`/`J`/`J` 拖动。

**根因**：函数末尾 `vim.cmd("normal! \27")`（为写 `'<`/`'>` 标记而先退出可视模式）之后，
`V` 分支用的是 **`normal! gV`** —— 而 `gV` 根本不是「恢复行选」：

- `:help gV` 在 `runtime/doc/visual.txt:538`：它的语义是「映射/菜单结束后**不要**自动重选可视区」，
  必须写在映射末尾，且只在 Select 模式下有意义；在 normal 模式下是合法 **no-op**（`pcall` 不报错）。
- 实测（headless）：`V` 模式内执行 `normal! gV` 后 `mode()` 仍是 `V`（**不退出**）；退到 normal 再 `gV` 后 `mode()` 仍是 `n`。

⇒ 所以「`gV` 会退出可视模式」这个常见说法是**错的**；真正的原因是此时已在 normal 模式，`gV` 什么也不做，
而 `else` 分支（字符/块选择）用的 `gv` 才能按标记恢复。

**修法**：`V` 分支的 `gV` → `gv`。实测 `V` 选 3 行后按 `J`：`mode()` 保持 `V`，`'<`/`'>` 跟着移动到 3..5、选区仍是 3 行；
连按第二次 `J` 正常继续拖动。

**别踩的坑**：`gv` 恢复的是「上一次的可视模式」，所以顺序必须是「先 `normal! \27` 退出 → 写 `'<`/`'>` → `gv`」；
在可视模式内直接 `gv` 只会在 行块/字符 之间切换，不按标记恢复（§6.4 已记）。

#### (b) 取消 `:q!` 会让自动保存**永久失效**（`autocmds.lua`）

**症状**：敲 `:q!` 后反悔按 `<Esc>` 取消，之后继续编辑 —— 所有自动保存静默停止，改动不落盘（用户以为已保存）。

**根因**：`<Esc>` / `<C-c>` 中止命令行**同样触发 `CmdlineLeave`**，且此时：

```text
[2] CmdlineLeave abort=true cmdtype=":" getcmdline="q!"
```

即 `getcmdline()` 仍返回已敲的 `q!`。而 `discard_pending` 的回调只判 `is_bang_quit(getcmdline())`、不判 `abort`，
于是被置成 `true`。此后 `autosave_current_buf` / `autosave_all_bufs` 开头 `if discard_pending then return end`
**直接 return**；`discard_pending` 只有在**下一次 `CmdlineEnter`**（再敲 `:`）时才复位。

**修法**：回调开头加 `if vim.v.event.abort then return end`。

**验证矩阵**（加载真实 `autocmds.lua`，改一个带文件名的 buffer 后切 buffer 触发 `BufLeave`）：

```text
mode=Esc      目标文件存在=false =>  自动保存被 return（不写盘）   ← 修复前
mode=C-c      目标文件存在=false =>  自动保存被 return（不写盘）   ← 修复前
mode=recolon  目标文件存在=true  =>  写盘（再按一次 : 才复位）
mode=search   目标文件存在=true  =>  写盘
mode=control  目标文件存在=true  =>  写盘（对照组：不碰命令行）
```
修复后 Esc 分支落盘，`CmdlineLeave` 事件里 `abort=true` 被正确忽略。

#### (c) `<leader>Jt` 跑错测试方法（`lang/java.lua`）

**症状**：光标在测试方法 A 内按 `<leader>Jt`，终端里跑的却是上方另一个旧测试方法 B（静默、危险）。

**根因**：取方法名的单行正则要求 `)` 之后**紧跟** `{`：

```lua
lines[index]:match("^%s*[%w_%s<>%[%],%.%?]+%s+([%w_]+)%s*%([^;]*%)%s*{%s*$")
```

⇒ 带 `throws Exception` 的方法（JUnit 里绝大多数）一律匹配失败；Allman 风格（`{` 独占一行）也失败。
反向循环不会停，继续向上搜，最终命中上方某个不带 throws 的旧方法。
实测：光标在 `testOrderCreation`（带 throws）内，selector 变成 `com.example.OrderTest#testAlpha`。

**修法**：不再用「单行正则」，改成「声明行 + 下一非空行」拼接后按**语句**判定：

- 先剥注释（`/*…*/`、`//`）与尾部 `{`，再取**标识符开头的一段**当 head（head 里不允许出现 `(`、`=`、`;`
  ⇒ `assertTrue(foo(bar))`、`x = foo()` 这类语句第一关就被挡掉）；
- head 必须以标识符结尾、其后紧跟 `(`，且从 `(` 起的括号必须**配平**（自写 `parens_balanced`，忽略字符串字面量里的括号）；
- head 至少两个 token，且「返回值」位置不是控制流关键字（`if/for/while/switch/catch/return/new/…`）；
- 返回值只取**泛型前的裸类型名**（`Map<String,` 与 `List<Integer>>` 都要还原成 `Map` / `List`）
  —— 这是第一版实现踩的坑：直接用 token 判断会让泛型返回值全部落空；
- 注解与声明同行（`@Test void foo() {`）时放弃：宁可返回 nil 报「未找到」，也不命中错方法。

**验证**：27 个用例（含 throws 多个异常、泛型返回、泛型方法 `<T> T foo()`、控制流语句、`@Override` 同行注解、
注释行）全通过；真机 Java buffer 三处光标分别得到 `#testOrderCreation` / `#testAlpha` / `#testLater`。

**方法论坑（多字节/转义）**：用 `bash <<'EOF'` 或 JS 模板串反复传递含 `\\`、反引号的 Lua 片段会被吃掉一层转义，
导致「测试脚本本身语法坏掉」却看起来像被测代码有问题 —— 先把被测代码**原样从配置文件里切片**再跑（本次最后就是这样定位到自己的 bug）。

#### (d) 顺带记录：报告里 3 条**不属实**的结论（别再按它改）

| 报告主张 | 实测结论 |
|---|---|
| `plugins/lang/init.lua` 100% 冗余、可删 | **错且有破坏性**：lazy 的 import 只扫**一层**（顶层 `*.lua` + 含 `init.lua` 的子目录），`lang/*.lua` 必须靠它加载。删除实测插件 37→34，丢 `nvim-jdtls`、`spring-boot.nvim` |
| `neotab` 覆盖 `blink.cmp` 的 `<Tab>`，snippet 跳转失灵 | **方向相反**：blink 的 `fallback` 在安装时抓取 neotab 的全局映射并**代理执行**；实测占位符内 `Tab` 正常前进（col 4→9→13，模式转 `s`） |
| `3J` 产生 6 次撤销记录、要按 6 次 `u` | `changedtick` 确实 +6，但同一执行上下文的修改被合成**一个撤销块**，1 次 `u` 完整复原 |

另两条「结论对、机制错」的：`:bdelete` 在分屏里**确实会关掉窗口**（真 PTY 实测 3 窗口→1；help `windows.txt:1180-1197` 自相矛盾，以实测为准），
以及 `virtual_lines.format` 用 `wins[1]` 取宽度**方向写反了**（实测 `wins[1]` 恒为首个窗口、不随当前窗口变）。

### 6.4.3 U01 浮窗几何：偏移量 2→4、写死宽度→响应式（2026-09-28）

`core/input_boxes.lua` 是 snacks 输入框与 noice 命令行框的「唯一事实源」。审查报告说「80 列终端下
命令行框被裁边、且窄分屏也会触发」，核实后发现**两个真 bug + 一个错误归因 + 一条遗留**。

#### (a) 盒模型偏移量是 4，不是 2（两个框一直差 2 列）

旧注释按「border 1+1 + padding 1+1 = 4」描述 noice，却写成 `noice_min_width = width − 2`。
实测（真 pty + `nvim_win_get_config`）：

```text
114 列：min_width=78 → 外框 cfg.w=82，内窗实宽=78 ⇒ 78 + 4 = 82
 80 列：min_width=72 → 外框 cfg.w=76，内窗实宽=72 ⇒ 72 + 4 = 76
```

两处都对齐 ⇒ **noice 总宽 = min_width + 4（不含左右边框），再加上边框 2 = min_width + 6**。
而 snacks 总宽 = width + 2。等长条件因此是 `noice_min_width = 内容宽 − 4`。
旧实现少减 2 ⇒ 80 列下输入框 74、命令行 76，**从来没等长过**（用户当初的诉求恰恰是等长）。

#### (b) 写死 80 在 80 列终端上真的被裁掉 2 列

```text
旧配置 80×24：命令行 FLOAT cfg.w=82 而 nvim_win_get_width=80   ← 右边框没了
             屏幕右端出现 @@@ 溢出标记；78 列更糟（col=-2）
新配置 80×24：两个框都是 74，cfg.w=74、实宽=74，完整显示
```

修法：`clamp(columns − 6, 30, 80)`。114 列下结果仍是 82（宽屏零回归），80 列下降到 76。

#### (c) 两个坑

1. **noice 的 `min_width` 只能是数字**（`noice/util/nui.lua:158` 的 minmax 直接进 `math.max`），
   所以 noice 那侧是「配置加载时的快照」——该表达式在模块 load 时求值，终端 resize 后要重启才跟上；
   而 snacks 的 `win.row/width` 支持函数（`snacks/win.lua:1281`），开窗时求值、跟随 resize。
   两边口径不同 ⇒ 想在窄终端也跟随 resize，只能接受重启。
2. **`Snacks.win` 没有 `self.lines/self.columns`**，宽度函数里要用 `vim.o.columns`（不要写 `self.columns`）。

#### (d) 错误归因：窄分屏不会触发裁切

报告说「双列垂直分屏（70 列窗口）也会裁」是错的：浮窗是**屏幕相对**的（noice 的 `position.row/col = "50%"`
按整屏算）。实测 114 列终端里开 70 列 vsplit，命令行框仍按整屏居中、完整渲染。**只有窄终端才会裁**。

#### (e) 遗留未修：两个框差 1 行

实测 80×24：输入框 row=10、命令行边框 row=11；114×30：13 vs 14。旧的宽度配置下同样差 1 行
⇒ **先于本轮存在**，与宽度无关。要对齐得把 `center_row()` 对两侧分别取值（noice 那侧要 −1）。

#### 附带落地的两条（同轮，审查 A03 / F02）

- **`:BufDelete`**（`core/commands.lua`）：原生 `:bdelete` 在这台 nvim 上会**连窗口一起关掉**
  （真 pty 实测 2 窗口→1、3 窗口→1；help `windows.txt:1180-1197` 自相矛盾，以实测为准），
  点 bufferline 的 × 就砸分屏。改用 `Snacks.bufdelete`（删完把窗口切到相邻 buffer），实测 2 窗口→2 窗口。
  ⚠ `snacks.bufdelete.enabled = false` **不影响** `Snacks.bufdelete()` 调用，只是不注册自带键位。
- **`:CheatSheet`**（`core/cheatsheet.lua`）：文件头注释一直写着「`:CheatSheet`」但命令从没注册过，
  `:CheatSheet` 直接报 E492。现就地注册（与 `<leader>hk` 同一入口、同样 toggle 语义）。

#### 附带查证但**故意不改**的一条（审查 G05）

报告说 go 缺格式化链条。实测 `formatters_by_ft` 确实没有 go，但**不能补**：
conform 的 `lsp_format = "fallback"` 判据是 `not any_formatters`（`conform/init.lua:512-518`）——
配了 formatter 就不再走 LSP；而本机 mason 只有 `gopls`、没有 `gofumpt`/`goimports`，
写上 `go = { "gofumpt" }` 会被 `resolve_formatters` 按 `info.available` 过滤掉（`:348`），
结果是保存时**什么都不跑**，比现状更差。现状 go 经 gopls 格式化且 `gofumpt = true`，链条是通的。

### 6.4.4 四项功能落地（2026-09-28）：<leader>fr / grep 预览 / LSP 状态 / lazydev

审查报告里这四条属于「功能缺失或架构建议」而不是 bug，逐条实测后落地。

#### (a) `<leader>fr` 最近文件（审查 G01）

功能一直存在，只是**只挂在启动页**（`dashboard.lua:33` 的 `r` 键）。离开启动页后没有任何热键，
`maparg('<leader>fr')` 在 n/v/x 全为空。补一行映射即可（`require("snacks").picker.recent()`），
并按技能约定同步了 `core/cheatsheet.lua` 的「搜索」小节。

#### (b) grep 单独恢复预览（审查 G02）

全局预设 `picker_compact` 带 `hidden = {"preview"}`，实测 `<leader>fg` 时预览窗**根本没创建**。
这是作者在 `snacks.lua:303` 明确写下的有意取舍，所以**只回滚一半**：给 grep 一个专用预设。

```lua
layouts.grep_split = vim.tbl_deep_extend("force", vim.deepcopy(layouts.picker_compact), {
  hidden = {},                                  -- 关键：不再隐藏 preview
  layout = {
    box = "horizontal",
    { box = "vertical", border = "none", { win = "input", height = 1 }, { win = "list" } },
    { win = "preview", title = " {preview} ", border = "left", width = 0.5 },
  },
})
opts.picker.sources = { grep = { layout = { preset = "grep_split" } } }
```

要点：`picker_compact` 的 `config`（高度修正）只认 list 子窗，对嵌套 box 同样生效，所以能直接当基底。
真 pty 实测（140 列）：grep 出现 `snacks_picker_preview` 窗（w=28 @ col 112），
而 files / recent **仍无**预览窗 ⇒ 改动确实只作用在 grep。

#### (c) 状态栏 LSP 客户端指示（审查 G03）

结论：**不用自己写组件** —— lualine 自带 `lualine/components/lsp_status.lua`，本机实测可 require：

```text
无客户端时 = ""            1 个客户端 = "jdtls "        2 个 = "jdtls gopls "
lualine_x 实际组件 = [diagnostics, lsp_status, filetype]
```

它监听 `LspProgress` 事件（索引时 spinner、就绪 `✓`），且**没有客户端时不占位**。
代价是它带**动画** —— 这条状态栏刚把四个分隔符全设成空串走极简风，
且本项目历史上专门为「颜色变来变去」关过 Java 的语义高亮，所以是否保留属于用户口味：
不想要就删 `lualine_x` 里那一行，其余不受影响。

#### (d) lazydev.nvim（审查 A01）—— 报告的论点被证伪，但仍按建议改

先纠正报告：`nvim_get_runtime_file("", true)` 实测只返回 **25 条**、且**不含插件自己的 `lua/` 子目录**
（插件根目录在 runtimepath 里，但 `require` 用的 `lua/` 是其子目录），
「把所有已安装插件喂给 lua_ls、内存飙到 GB」**没有实测支撑**。

真正改进它的做法（已落地）：

1. 装 `folke/lazydev.nvim`（`~/.local/share/nvim/lazy/lazydev.nvim`，commit `ff2cbcb`）；
2. `lsp/init.lua` 依赖里加 `{ "folke/lazydev.nvim", ft = "lua", opts = {} }`（只在编辑 lua 时加载）；
3. `library` 从 `nvim_get_runtime_file("", true)` 换成 **`nvim_get_runtime_file("lua", true)`**
   —— 实测 25 → **17** 条，拿到的是每个插件的 `lua/` **模块根**（`require()` 补全仍保留），
   去掉的是插件根目录、文档与测试。

lazydev 的工作原理值得记住：它**不是在 setup 时静态塞 settings**，而是接管 lua_ls 的
`workspace/configuration` 请求（`lazydev/lsp.lua` 的 `on_workspace_configuration`），
按 buffer 动态返回 `Lua.workspace.library`；默认库含 `$VIMRUNTIME` ⇒ Neovim API 类型不丢。

验证：打开 `lua/core/keymaps.lua` 后 lua_ls 成功 attach（`root = /home/pang/.config/nvim`），
插件数 37 → 38，启动干净、checkhealth **无新增告警**。

⚠ 副作用（已写进配置注释）：lua_ls 不再把每个插件根目录当库，`require("snacks")` 这类**插件模块**的
补全比原来少；要补回来就注册 lazydev 的 blink source（`lazydev.integrations.blink`），本机暂未注册。
配置文件自己的模块（`require("core.xxx")`）不受影响，走工作区解析。

### 6.4.5 2026-09-28 审查报告的逐条判定索引（报告已删除，编号留此备查）

报告 `NVIM_CONFIG_AUDIT_REPORT.md`（29 条）已于 2026-09-28 删除，正文可从 git 历史取回；
**报告的提交信息会引用下面的编号**，所以把「编号 → 判定 → 去向」留在这里。

| 编号 | 判定 | 去向 |
|---|---|---|
| F01 行选模式按 J/K 掉回普通模式 | 属实（机制描述错） | 已修（`gV`→`gv`），见 §6.4.2(a) |
| F02 `:CheatSheet` 未注册报 E492 | 部分属实（只有源码注释声称） | 已修（就地注册命令），见 §6.4.3 末 |
| F03 Helm 模板标成 `yaml.helm-values` | 属实 | 未改（改 `helm` 需另装 helm_ls） |
| F04 缺 xml/toml/python/dockerfile/sql 解析器 | 属实 | 未改（需联网装解析器） |
| F05 mason 与 mason-tool-installer 互相依赖 | 部分属实（「时序错误」无复现） | 未改（lazy 正常处理，6 次启动全绿） |
| B01 取消 `:q!` 后自动保存永久失效 | **属实（数据安全）** | 已修（判 `abort`），见 §6.4.2(b) |
| B02 `<leader>Jt` 命中错误测试方法 | **属实（跑错测试）** | 已修（重写选择器），见 §6.4.2(c) |
| B03 neotab 覆盖 blink 的 `<Tab>` | **不属实（方向相反）** | 未改，见 §6.4.2(d) |
| B04 `3J` 产生 6 次撤销记录 | **不属实** | 未改，见 §6.4.2(d) |
| B05 virtual_lines 折行破坏缩进/`^` | 部分属实（宽度机制写反） | 文字部分已修；宽度未改，见 §6.4.4 |
| B06 Spring 向导 monkey-patch snacks 列表 | 部分属实（影响被夸大） | 未改（0.479ms/次，可忽略） |
| A01 lua_ls 全量扫 rtp 耗尽内存 | 部分属实（**主论点已证伪**） | 已改进（上 lazydev + 收窄 library），见 §6.4.4(d) |
| A02 Noice 与 nvim-notify 双轨 | 属实 | 未改（观感取舍） |
| A03 `:bdelete` 砸碎分屏 | 属实 | 已修（新增 `:BufDelete`），见 §6.4.3 末 |
| A04 commands.lua 上帝模块 | 部分属实（行数 497 非 498） | 未改（拆分风险 > 收益） |
| A05 `:R` 不刷新 package.loaded | 属实 | 未改（已知限制） |
| G01 缺 `<leader>fr` | 属实 | 已补，见 §6.4.4(a) |
| G02 全局 grep 无预览 | 属实（作者有意取舍） | 已改（只给 grep 开预览），见 §6.4.4(b) |
| G03 状态栏无 LSP 客户端指示 | 属实 | 已加 `lsp_status`，见 §6.4.4(c) |
| G04 全角标点不触发 autopairs | 属实 | 未改（机制不同路径，要另做） |
| G05 go 缺格式化链条 | 部分属实 | **故意不改**（补了会更差），见 §6.4.3 末 |
| R01 `lang/init.lua` 100% 冗余可删 | **不属实且建议有害** | 未改，见 §6.4.2(d) |
| R02 which-key 有永远触发不了的死 spec | 部分属实（gg/ge/gE 是例外） | 未改（`a`/`i` 可用 `:WhichKey a` 手动呼出） |
| R03 `site/pack/core/opt` 空目录致 health 报黄 | 属实 | 未改（删目录会让 lazy 少一条告警，但无常驻影响） |
| R04 Neovide `corner_preference` 仅 Windows 有效 | 属实（官方文档确认） | 未改（无害 no-op） |
| U01 窄终端输入框右边缘被裁 | 部分属实 | 已修（响应式宽度 + 修偏移量 2→4），见 §6.4.3 |
| U02 硬编码实底与透明主题割裂 | 部分属实（**「第三方浮窗为 NONE」是错误推断**） | 未改 |
| U03 which-key `<leader>h` 分组命名 | 事实属实 / 评价主观 | 未改 |
| U04 lualine 分隔符全空 | 事实属实 / 评价主观 | 未改 |

合计：**属实 15 / 部分属实 11 / 不属实 3**。未改动的条目多为「有意取舍」「功能缺失」或「报告论据不足」，
不是遗漏；每条的理由都在上表或对应小节里。

### 6.4.6 vim.ui.select 的回调是**异步**的——别把结果写在 select 返回之后

做 `<leader>ft` 主题选择框时踩的坑，**通用**，任何用 `vim.ui.select` 的地方都可能中招。

**错误写法**（看起来天经地义）：

```lua
local picked
vim.ui.select(items, opts, function(choice) picked = choice end)
apply(picked or original)   -- ← select 已经返回了，picked 还是 nil！
```

**后果**：snacks 的 select 回调走 `vim.schedule`（见 `snacks/picker/select.lua` 的 `confirm`
动作与 `on_close`），即 **select 立刻返回、回调稍后才跑**。于是那条 `apply(picked or original)`
会用**旧值**把用户刚看到的预览顶掉；等回调真跑起来时，`picked` 的赋值虽然发生了，
但已经没有任何代码再去读它 ⇒ **选什么都不会生效**（实测：选 frappe 毫无反应，主题不变）。

**正确写法**：应用逻辑写在 `on_choice` **内部**，不要依赖 select 之后的代码。

```lua
vim.ui.select(items, opts, function(choice)
  if not choice then return end   -- nil = 用户取消（snacks 的 on_close 会调 on_choice()）
  apply(choice)
end)
```

**契约**（读 snacks 源码确认）：`confirm` → `on_choice(item.item, item.idx)`；
`on_close`（Esc / q）→ `on_choice()` **不带参数** ⇒ 用 `if not choice` 判取消即可。

**排查手法**：mock `vim.ui.select` 有两种形态，必须**都测**：

```lua
-- 同步（Neovim 原生风格）
vim.ui.select = function(_, _, cb) cb('latte') end
-- 异步（snacks 风格：先返回，稍后再回调）
local saved; vim.ui.select = function(_, _, cb) saved = cb end
vim.api.nvim_feedkeys('<Space>ft', 'mtx', false); saved('latte')
```

只测同步会全绿、上线却是坏的 —— 这个坑就是这么漏过去的。
### 6.4.7 换主题的可行性：4 个风味可切，**换别的配色方案不行**（2026-09-29）

起因：想给换主题加个选择框，做完后用户决定不要（已 revert 70659d5）。但查证过程有价值，记这里。

#### (a) 四个风味互相切换：完全可以

catppuccin 的 mocha / macchiato / frappe / latte 用的是**同一套高亮组名**，只是取色不同，
所以 `:colorscheme catppuccin-<flavour>` 一敲就整体生效。实测四者都能切：

```text
Catppuccin mocha -> catppuccin-mocha      Catppuccin frappe    -> catppuccin-frappe
Catppuccin macchiato -> catppuccin-macchiato   Catppuccin latte -> catppuccin-latte
```

⚠ `:Catppuccin`（catppuccin 自带命令）**必须带参数**，无参数报 `E471: 需要参数`。

#### (b) 换**别的**配色方案（tokyonight / gruvbox…）：不行，代价在这

本机只装了 catppuccin。默认 mocha ⇒ 编辑区透明 + 浮窗实底 `#1e1e2e`。
实测把 `flavour` 改成 `latte`（XDG 副本，不动真实配置）后的高亮对照：

```text
                    mocha                        latte
Normal            fg=#cdd6f4 bg=NONE          fg=#4c4f69 bg=NONE      ← 跟着变（浅色）
Comment           fg=#9399b2                 fg=#7c7f93              ← 跟着变
Pmenu             fg=#9399b2 bg=NONE          fg=#7c7f93 bg=NONE      ← 跟着变（**透明**）
NormalFloat       bg=#1e1e2e                  bg=#1e1e2e             ← **写死的深色底**
SnacksPickerBox   bg=#1e1e2e                  bg=#1e1e2e             ← 同上（10 处）
NoiceCmdlinePopup bg=#1e1e2e                  bg=#1e1e2e             ← 同上
CheatSheetBg      bg=#1e1e2e                  bg=#1e1e2e             ← 同上
```

⇒ 编辑区变浅色、picker/命令行/速查面板仍是**深色实底**，直接割裂。
根因：`snacks.lua` / `noice.lua` / `cheatsheet.lua` / `bufferline.lua` 里**写死了 79 处颜色字面量**
（其中 `snacks.lua` 63 处；`#1e1e2e` 出现 13 次、`#89b4fa` 18 次、`#7f849c` 15 次），
它们是在 `ColorScheme` 之后手工刷到具体高亮组上的，**不会**跟着主题换。

另外 `Pmenu` 透明也是既有现象：`:303` 那套全局去预览 + 透明主题的组合下，
悬停菜单（LSP 补全文档、部分插件菜单）没有实底 ⇒ 换浅色主题同样会显得脏。

#### (c) 结论

| 想做的事 | 可行性 | 代价 |
|---|---|---|
| 四个风味里挑一个（长期用） | ✅ 可行 | 改 `theme.lua` 的 `flavour` 一行；**但要把那 79 处硬编码色一起调**（否则浮窗颜色不搭） |
| 临时切风味看一眼 | ✅ 可行 | `:Catppuccin <flavour>`（记得带参数）；浮窗仍是深色 |
| 换 tokyonight / gruvbox 等别的方案 | ⚠️ 技术上能装，实际不划算 | 要联网装插件 + 改写 79 处颜色字面量 + 逐个核对 14 项 integrations，等于重做一遍配色层 |

换主题本身**自动重刷**的部分是齐的（三处 `ColorScheme` autocmd：`theme.lua` 的诊断 tag、
`snacks.lua` 的 picker 皮肤、`spring_wizard.lua` 的向导高亮）—— 缺的只是那 79 处字面量。

### 6.5 bufferline 强制关闭未保存 buffer

**问题**：`close_command = "bdelete! %d"` 会丢弃未保存修改。

**解决**：改成不带 bang：
```lua
close_command = "bdelete %d"
right_mouse_command = "bdelete %d"
```
这样有未保存修改时关闭会失败并提示。

---

## 7. 项目管理

### 7.1 project.nvim 使用已废弃 API

**问题**：`vim.lsp.buf_get_clients()` 在 0.10 废弃。

**解决**（`lua/plugins/project.lua`）：运行时 monkey-patch `find_lsp_root`，用 `vim.lsp.get_clients()` 替代。不改插件源文件（防 lazy.nvim dirty）。

### 7.2 project.nvim LSP root 为空

**问题**：某些 LSP client 没有 `client.config.root_dir`，project.nvim 取到 nil/空字符串会影响 CWD 切换。

**解决**：monkey-patch 中只在 `root_dir` 是非空字符串时返回，否则继续找下一个 client 或走 pattern 检测。

### 7.3 项目历史被清空（2026-09-24 两次）

第一次归因为"外部写了插件的内存表 `recent_projects`"（只读历史文件即可避免）；
第二次证明**不碰内存表也会丢**，根因在插件自身的截断写 + 异步读竞态。
完整定位与三层保护见 **§13.1**，审计检查项见 `nvim-config/references/local-checklist.md` §2.1.1。

---

## 8. 系统

### 8.1 未使用的包检查

```bash
pacman -Qtdq
```

可选清理：确认列表无误后再执行 `sudo pacman -Rns $(pacman -Qtdq)`。

---

---

## 9. Java LSP（nvim-jdtls）

### 9.1 Neovim 0.12+ root_dir 函数不生效

**问题**：jdtls 只报语法错误，日志显示 `"No workspace folders or root uri was defined"`。

**根因**：`vim.lsp.start` 不解析函数式 `root_dir`（只在 `vim.lsp.enable` 的 `lsp_enable_callback` 中处理），而 `nvim-jdtls` 直接调 `vim.lsp.start`。函数式 root_dir 传入后一直未被求值，jdtls 收不到 rootUri，降级为 standalone 模式。

**旧代码**（`lua/plugins/lang/java.lua`）：
```lua
opts = {
  root_dir = function(path)
    return vim.fs.root(path, { "pom.xml", ... })
  end,
}
```

**解决**：不在 `opts` 中设 root_dir 函数，在 `config` 函数内预解析为字符串：
```lua
config = function(_, opts)
  local resolve_root = function(bufnr)
    local fname = vim.api.nvim_buf_get_name(bufnr)
    if fname and #fname > 0 then
      return vim.fs.root(fname, { "pom.xml", "build.gradle", "build.gradle.kts", ".git", "src" })
        or vim.fn.getcwd()
    end
    return vim.fn.getcwd()
  end
  opts.root_dir = resolve_root(0)

  -- 后续文件也每次重新解析
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "java",
    callback = function()
      opts.root_dir = resolve_root(0)
      jdtls.start_or_attach(opts)
    end,
  })
end
```

**注意事项**：
- Java 文件需在标准 Maven 目录结构（`src/main/java/`）或 Gradle 项目中才能获得完整语义分析
- 单文件目录下放最小 `pom.xml` + `src/main/java/` 即可触发完整报错

---

### 9.2 jdtls workspace_dir 跨项目不更新

**问题**：`-data` workspace_dir 只在 config 首次执行时算一次，`FileType` autocmd 只更新 `root_dir` 不更新 `cmd`，切 Java 项目时 jdtls 一直用第一个项目的 workspace。

**解决**（`lua/plugins/lang/java.lua`）：
- `cmd_base` 保存基础 cmd（不含 `-data`）
- `build_cmd(dir)` 函数每次重新拼装 `{ cmd_base, "-data", workspace_dir }`
- `start_jdtls(bufnr)` 统一入口：先调 `resolve_root()` 再调 `build_cmd()` 再 `start_or_attach()`
- autocmd 和 `vim.schedule` 都走 `start_jdtls`

---

### 9.3 java-test bundle 版本与 JDTLS 重复依赖

**问题**：运行 Java 测试类时提示 `No LSP client found that supports resolving possible test cases`，同时历史日志出现扩展 bundle 加载失败。

**根因**：Mason 的 `java-test` server 目录同时包含 OSGi bundle、测试运行器普通 JAR、JaCoCo agent 和 ASM 依赖；把所有 JAR 都传给 `init_options.bundles` 会让 JDTLS 尝试加载不适合作为 bundle 的文件，或者重复加载 JDTLS 已提供的 ASM bundle。

**解决**（`lua/plugins/lang/java.lua`）：
- 只从 `java-debug-adapter` 和 `java-test` server 目录收集实际存在的 JAR；
- 排除 `runner-jar-with-dependencies`、`jacocoagent` 和 `org.objectweb.asm`；
- 使用集合去重，避免相同路径重复注入；
- 清理当前项目的 JDTLS workspace 后重新启动，使新的 bundle 列表生效。

**验证**：全新 workspace 中 `vscode.java.test.findTestTypesAndMethods` 已注册；调用 `jdtls.test_class()` 真实运行 `RedisKeysTest`，输出 `Tests finished. Results printed to dap-repl. ✓ 1 succeeded`，未再出现原始提示。`vscode.java.test.search.codelens` 未注册，但不影响当前测试类/测试方法运行路径。

**边界**：Spring Boot Tools 在无完整编辑器 URI 的 headless 会话中仍可能记录 `Expected authority at index 7: file://`，这不是测试 bundle 警告；交互式打开真实项目文件时以 `:LspLog` 和实际功能为准。

## 10. 懒加载与优化

### 10.1 启动页第一次打开项目列表为空

**问题**：启动欢迎页点击"项目列表"时，第一次 Telescope 框内为空，第二次才显示项目。

**根因**：project.nvim 的历史读取是异步的；如果项目插件到第一次点击时才初始化，`Telescope projects` 创建 finder 时可能还没读完 `project_history`。另外，project.nvim 的 Telescope 扩展默认选择项目后会再打开一层 `find_files` picker；从 alpha 用 `:A` 返回后再次选择项目，嵌套 picker 状态容易卡住。

**解决**：
- project.lua 改为 `lazy = false`，启动时先初始化 project.nvim
- 保持 Telescope 扩展注册在 telescope.lua：`setup(opts)` 后 `pcall(require("telescope").load_extension, "projects")`
- 新增 `:Projects` 命令：先加载 project/telescope/neo-tree，再同步读取 project.nvim 历史文件，然后用自定义 Telescope picker 展示项目
- `:Projects` 默认回车只切换 cwd 并打开/刷新 neo-tree，不调用 `Telescope projects` 的默认嵌套 `find_files`
- 启动页 `p` 和 `<leader>fp` 都走 `:Projects`

> 2026-09-24 更新：telescope.nvim 已整包删除，项目列表改用 snacks picker；
> 本节提到的 Telescope 扩展注册与嵌套 picker 问题均已不存在，现状见 §12 / `local-patterns.md`。
>
> ⚠ 同日更正：当时写的自定义源名 `source = "projects"` **是错的**——它撞上 snacks 的内置同名源，
> `:Projects` 选中项目后会报 `Invalid 'dir': Expected Lua string`。现已改名 `project-history`，
> 自定义字段也从 `dir` 改成 `project_dir`（snacks 会把 `dir` 覆盖成布尔"是否目录"）。
> 同类约束见 `nvim-config/references/local-checklist.md` §2.1.1。

### 10.1.1 项目切换后 neo-tree 仍停在 home

**问题**：从项目列表选中项目后，Telescope 已切到项目目录，但左侧 neo-tree 仍停在 `$HOME`。

**根因**：neo-tree `filesystem.bind_to_cwd = false` 时不会监听 cwd 变化；project.nvim 的项目切换只会更新 cwd。

**解决**（`lua/plugins/filetree.lua`）：
```lua
filesystem = {
  bind_to_cwd = true,
}
```
同时在 `lua/plugins/project.lua` 包装 `Project.set_pwd()`：原函数成功返回后，如果 neo-tree 已加载，则对 filesystem state 调 `manager.navigate(state, dir)`，主动把根目录刷新到项目目录。这样既保留 cwd 绑定，也避免 UI 事件时序导致文件树停在旧目录。

### 10.2 格式化超时偏短

**问题**：`format_on_save.timeout_ms = 500`，Java/C++/Rust 大项目容易超时。

**解决**：改为 `2000ms`（`lua/plugins/format.lua`）。

### 10.3 conform 只按 `<leader>F` 懒加载导致首次保存不格式化

**问题**：`format.lua` 只有 `keys = { "<leader>F" }`，lazy.nvim 会把 conform 变成按键懒加载；`format_on_save` 只有插件加载后才注册，首次保存不会自动格式化。

**解决**：增加 `event = { "BufWritePre" }`，保存前加载 conform，保留 `<leader>F` 手动格式化。

### 10.4 checkhealth 警告清理

**解决**：
- `lazy.lua`：加 `rocks = { enabled = false }`，禁用 luarocks/hererocks 检测
- `options.lua`：加 `vim.g.loaded_node_provider = 0` 等 4 行，禁用不用的外部 provider
- 系统：`sudo pacman -S fd`（Telescope find_files 后备索引工具）

### 10.5 LSP health Unknown filetype

**问题**：`checkhealth vim.lsp` 报 `gotmpl`、`markdown.mdx`、`yaml.docker-compose`、`yaml.gitlab`、`yaml.helm-values` 为 Unknown filetype。

**解决**：新增 `lua/core/filetypes.lua`，用 `vim.filetype.add()` 注册这些 filetype，并在 `core/init.lua` 中于 LSP 加载前 require。

### 10.6 诊断跳转 API 废弃

**问题**：Neovim 0.12 中 `vim.diagnostic.goto_prev()` / `goto_next()` 已废弃。

**解决**：
```lua
vim.diagnostic.jump({ count = -1, float = true })
vim.diagnostic.jump({ count = 1, float = true })
```

### 10.7 conform LSP 格式化优先级

**问题**：`lsp_format = "prefer"` 会让 LSP 抢先于显式配置的 google-java-format/clang-format/stylua。

**解决**：改为 `lsp_format = "fallback"`，显式 formatter 优先，缺工具时 LSP 兜底。

### 10.8 alpha 使用 cond 后 :A 失效

**问题**：`cond = function() return vim.fn.argc() == 0 end` 会在带文件启动时禁用整个 alpha spec，虽然避免欢迎页闪烁，但同一会话后续 `:Alpha` / `:A` 也无法按需加载。

**解决**：保留 `cmd = "Alpha"`，只把事件写成 `event = vim.fn.argc() == 0 and "VimEnter" or nil`。有文件参数时不注册启动事件，命令触发器仍存在。

### 10.9 Treesitter 早于 Mason 时误报 CLI 缺失

**问题**：Treesitter 与 Mason 都是启动插件，Treesitter 先执行时 `tree-sitter` 尚未被 Mason setup 加入 `PATH`，导致缺失解析器无法安装并误报 CLI 不存在。

**解决**：安装前检查 `stdpath("data") .. "/mason/bin/tree-sitter"`；存在时先将 Mason bin 加入 `PATH`。JavaScript 解析器已加入清单并完成安装。

### 10.10 小终端 UI 越界与界面行为漂移

**问题**：快捷键速查页的最小宽高可能超过终端；Noice 固定 60 列；neo-tree 的 `r` 实际执行移动但文档写重命名。

**解决**：速查页宽高严格限制在当前终端内；Noice 命令行使用 `width = 78`，窄终端由 UI 后端自动限制；neo-tree 恢复 `r = rename` 并新增 `m = move`。Telescope、bufferline、lualine 的边框和诊断信息也统一为当前圆角 UI 风格。

### 10.11 LuaSnip 存在但片段功能未接入

**问题**：配置安装了 LuaSnip，但 Blink 仍使用默认 `vim.snippet` preset，且没有加载任何 snippet collection；文档声称的语言模板实际不可用。

**解决**：删除 LuaSnip 空配置，改用 Blink 官方支持的原生 `vim.snippet` + `friendly-snippets`。`Tab` 依次执行接受补全、跳到下一占位符、fallback；`Shift-Tab` 反向跳转。

---

## 11. 插件管理器（lazy.nvim 引导）

### 11.1 clone 中断后配置整体失效

**问题**：nvim 完全不用配置文件（无主题、无插件、无选项），`init.lua` 在 `require("lazy")` 处报 `module 'lazy' not found`。

**根因**：`~/.local/share/nvim/lazy/lazy.nvim` 是中断的 clone（只有 `.git`，无工作区文件、无 index）。引导逻辑只用 `vim.uv.fs_stat(lazypath)` 判断目录存在，目录在就跳过重新克隆，于是 `require("lazy")` 永远失败，整个配置初始化中止，nvim 退化为默认配置。

**解决**（`lua/core/lazy.lua`）：用入口文件判断完整性——新版 lazy.nvim（11.x）入口是 `lua/lazy/init.lua`，老版本是 `lua/lazy.lua`，两个都检查；缺失时先 `rm -rf` 残缺目录再重新 clone。

**注意**：
- 新版入口是 `lua/lazy/init.lua`，**不存在** `lua/lazy.lua`。入口路径写错会导致每次启动都 rm + 重新 clone（启动变慢，网络差时直接挂起），验证方式是连续两次启动，第二次应毫秒级完成。
- clone 带 `--filter=blob:none`，中断会留下空 `.git` 目录；`vim.uv.fs_stat` 对空目录也返回真，所以不能只查目录。
- clone 是 `vim.fn.system` 同步阻塞，网络弱时整个事件循环卡死，headless 验证超时优先怀疑引导 clone。

### 11.2 Mason 安装 delve 卡死（Go 模块代理不可达）

**问题**：`:MasonInstall delve` 或 `mason-registry:get_package('delve'):install()` 无限挂起、无任何日志，事件循环被阻塞。

**根因**：delve 的 mason 包走 golang 安装策略（`pkg:golang/github.com/go-delve/delve@v1.27.1#cmd/dlv`），即 `go install`，需要访问 `proxy.golang.org`。该 Google 代理在此网络不可达（`dial tcp ... i/o timeout`），而 GitHub 直连正常——所以其他从 GitHub release 下载的工具都正常，只有 delve 卡死。

**解决**：用国内 Go 代理单次安装，GOBIN 指向 mason/bin（配置硬编码 `stdpath("data") .. "/mason/bin/dlv"`）：
```bash
env GOBIN=$HOME/.local/share/nvim/mason/bin GOPROXY=https://goproxy.cn,direct go install github.com/go-delve/delve/cmd/dlv@v1.27.1
```

---

## 12. 插件精简与启动收尾（2026-09-24）

### 12.1 删掉 Comment.nvim，改用 Neovim 内置注释

**症状**：Comment.nvim（numToStr）长期停维护，但不确定删掉后 `gc`/`gcc` 还灵不灵。

**事实**：内置注释自 Neovim 0.10 起就有（本机 0.12.5，`runtime/lua/vim/_core/defaults.lua:177-193`）：
`gc`（n/x，operator）、`gcc`（n）、operator-pending 的 `gc` textobject。**没有** `gb`/`gbc`（块注释）
和 `gcO`/`gco`/`gcA`——那些是 Comment.nvim 的额外映射，本配置与文档都没用过这些键。

**关键坑**：旧 spec 的 `keys = { "gc" }` 是 lazy 的桩映射，会**顶掉内置 `gc`**，所以"装不装 Comment.nvim"
在按键层面表现不同。删掉 spec 并 `:Lazy! clean` 后，内置 `gc` 自动接管。

**解决**：删除 `lua/plugins/comment.lua` 与对应 spec。

**验证**：`:verbose map gc` / `:verbose map gcc` 指向 `vim/_core/defaults`；`gcc` 可反复切换；
可视模式 `gc` 能注释两行。

**边界**：这是"停维护插件替换"里唯一低代价的一项；project.nvim / bufferline.nvim / toggleterm.nvim
三个仍在用（都没归档，属"事实停更"，替换代价中～高，需用户决定）。

### 12.2 lazy.nvim 的 `cmd` 桩让"插件 setup() 里注册的命令"启动期就存在

**症状**：`JavaHello/spring-boot.nvim` 用 `lazy = false` 启动即加载，把 nvim-jdtls/DAP 一并拖进启动期，
同 spec 里的 `ft` 反而成了死配置；而直接换成 `ft`，全局键 `<leader>sP` 在非 java 缓冲区会报
`E492: Not an editor command`。

**根因**：`<leader>sP` 是全局键，命令 `SpringBootNewProject` 却由 ft-lazy 的另一个插件在 setup() 里注册；
插件没加载时命令不存在 ⇒ E492。

**解决**（`lua/plugins/lang/springboot.lua`）：
- `JavaHello/spring-boot.nvim`：`lazy = false` → `cmd = { "SpringBoot" }, ft = { "java", "yaml", "jproperties" }`
- `elmcgill/springboot-nvim`：加 `cmd = { "SpringBootNewProject" }`

**验证**：启动后 `exists(":SpringBoot")`/`exists(":SpringBootNewProject")`/`exists(":SpringBootCreate")` 均为 2，
而 spring-boot.nvim / nvim-jdtls 不再于启动期加载；`:SpringBoot @` 能把插件拉起来并执行。

### 12.3 解析器装不上 + 每次启动刷 curl 错误（GitHub 需本机 Clash 代理）

**症状**：启动时刷一屏红色 curl 错误，缺失的 Treesitter 解析器始终装不上。

**根因**：`~/.config/fish/conf.d/proxy-env.fish` 只在 7890 端口有人监听时才设
`HTTPS_PROXY`/`HTTP_PROXY=http://127.0.0.1:7890`、`ALL_PROXY=socks5://127.0.0.1:7890`。从 fish 里启动的
nvim 有代理，从别处（headless 脚本、非 fish shell）启动就没有；而 `nvim-treesitter` 的 `install()`
内部用 curl 拉 GitHub tarball，直连超时。配置又会在启动时自动重试缺失解析器 ⇒ **每次启动都联网重试**。

**解决**（`lua/plugins/treesitter.lua`）：加 6 小时节流，stamp 文件
`~/.local/state/nvim/treesitter-install-stamp`；节流期内只留一条 INFO 提示，不再联网。

**手动安装（须带代理，实测 5 个解析器全部 "Language installed"）**：

```bash
HTTPS_PROXY=http://127.0.0.1:7890 nvim --headless \
  -c "lua require('nvim-treesitter').install({'tsx','vue','svelte','scss','typescript'}):wait(420000)" -c "qa!"
```

**排查手法**：`pgrep -f 'tree-sitter-scs[s]'`——方括号让模式本身不匹配 pgrep 自己的命令行，
据此确认是否真的在联网下载。

### 12.4 nvim-treesitter 自带 filetype→parser 别名

**事实**：`nvim-treesitter/plugin/filetypes.lua` 已注册 tsx↔typescriptreact、json↔jsonc、bash↔sh、
xml↔xsd/xslt/svg、properties↔jproperties 等别名。只要解析器装好，`vim.treesitter.start()` 在
.tsx/.jsonc/.sh 上就能用，**不需要**自己写 `vim.treesitter.language.register`。

### 12.5 `:{N}write` 不会写缓冲区 N：退出前保存所有被改缓冲区

**症状**：在后台（非当前窗口）改过的文件，`:qa` 时仍弹 `E37: 已修改但未保存`，自动保存形同虚设。

**根因**：旧实现只保存当前 buffer；换 `:{N}write` 也不行——实测 `:1write` 对被改过的 buffer 1 是
**静默 no-op**（文件没变、`modified` 仍为 true）。要写指定缓冲区必须走 Lua API。

**解决**（`lua/core/autocmds.lua`）：`QuitPre`/`VimLeavePre` 里遍历 `nvim_list_bufs()`，对每个可保存
且被改过的缓冲区执行：

```lua
vim.api.nvim_buf_call(buf, function() vim.cmd("silent! lockmarks write") end)
```

`nvim_buf_call` 让 `:write` 作用在指定缓冲区上，结束后当前缓冲区/窗口不变。

**验证**：两个 buffer 都在内存里改过，`:qa` 无 E37，两个文件都落盘。

### 12.6 lualine `disabled_filetypes` 与 `extensions` 互斥（neo-tree 状态栏空白）

**症状**：切到 neo-tree 时整条状态栏空白。

**根因**：filetype 被写进 `disabled_filetypes` 时 lualine 直接返回空 statusline，对应扩展永远轮不到
生效——原配置同时写了 `disabled_filetypes = { "alpha", "neo-tree" }` 与 `extensions = { "neo-tree" }`；
配合 `globalstatus = true`（真 TTY 里 `laststatus=3`）结果就是一条空白状态栏。

**解决**（`lua/plugins/statusline.lua`）：`disabled_filetypes` 只留 `alpha`。

**验证（真 pty）**：neo-tree 窗口 statusline 非空，渲染出项目路径。

### 12.7 诊断浮窗末尾的 `[code]`：只丢纯数字码

**症状**：jdtls 诊断浮窗末尾跟着噪音 `[603979884]`。

**根因**：这是 Neovim 默认的 `float.suffix`（`runtime/lua/vim/diagnostic.lua:2560-2563`），jdtls 的
code 是内部诊断号。

**解决**（`lua/core/options.lua`）：自定义 `float.suffix`，**纯数字**码返回空串，`E0308`、eslint 规则名
这类有意义的文字码保留。

**验证**：数字码 → 空串；`E0308` → `" [E0308]"`。

### 12.8 `:checkhealth vim.lsp` 报 `Unknown filetype 'xsl'`

**根因**：nvim-lspconfig 给 lemminx 的默认 filetypes 里带了 `xsl`，而 Neovim 的 filetype 检测把
`.xsl`/`.xslt` **都**识别成 filetype `xslt`（`runtime/lua/vim/filetype.lua:1463` 的 `xsl = 'xslt'`）
⇒ "扩展名 ≠ filetype" 的假条目。

**解决**（`lua/plugins/lsp/init.lua`）：显式覆盖
`lemminx = { filetypes = { "xml", "xsd", "xslt", "svg" } }`。

**验证**：`checkhealth vim.lsp` 输出里 `grep -c "Unknown filetype"` = 0。

**通用规律**：任何 server 的默认 filetypes 里出现"扩展名"而不是"真 filetype"都会触发这条警告，
同类历史坑已出现多次（见 §10.5）。

### 12.9 headless 没有 UIEnter ⇒ UI 类结论必须真 pty 复核

**事实**：headless 不触发 `UIEnter`，挂在 `event = "UIEnter"` 上的 lualine、snacks 的 `vim.ui` 接管等
都不会加载；在 headless 里测"状态栏 / 输入框是否生效"必然得到假阴性。

**做法**：这类问题用真 pty 复核。本次 pty 里确认 `LASTSTATUS=3`、`LUALINE_LOADED=true`、
neo-tree statusline 渲染长度 80。

---

## 13. 项目历史二次清空与 snacks picker 细节（2026-09-25）

### 13.1 项目历史第二次被清空：根因在上游 `write_projects_to_history()`

**症状**：`:Projects` 里又只剩当前会话打开过的项目；插件历史文件
`~/.local/share/nvim/project_nvim/project_history` 被截断重写（2026-09-25 00:00 实测，当天第二次）。

**根因（在插件实现里，不是本机配置）**：project.nvim 的
`lua/project_nvim/utils/history.lua` → `write_projects_to_history()`：
`M.recent_projects ~= nil` 时用 **`mode = "w"`（截断）** 重写整个历史文件；而它读文件是**异步**的
（`read_projects_from_history()` 走 `uv.fs_read` 回调 + fs_event 监视）。

危险窗口：实例 A 退出时 `fs_open(..., "w")` 先把文件截成 0 字节、内容还没写回；此时实例 B
的异步读正好完成 → `deserialize_history("")` 得到**空表（非 nil！）** → B 退出时按空表截断写回
→ 整份历史只剩 B 的会话项目。**并发跑多个 nvim 就会踩**（当晚是探针 + 后台任务多实例）。

**与第一次事故的关系**：早些时候那次被归因为"外部写了插件内存表"；这次证明**完全不写
`recent_projects` 也会丢**，机制纯粹是插件自身的截断写 + 异步读竞态。所以"只读历史文件"
是必要但不充分的。

**处理（`lua/core/commands.lua`，三层保护）**：
1. 自维护**只追加**的副本 `~/.local/state/nvim/project-history.list`；
2. `:Projects` 列表 = 副本 ∪ 插件历史文件 ∪ 本会话项目（**并集，永不缩小**）；
3. 每次打开列表把"插件文件缺、副本有"的条目 **append** 回插件文件（append 不截断；
   插件的 fs_event 监视器会因此重读文件，把它的内存一起修好）；
4. 另有 `DirChanged` autocmd 把当前项目追加进副本。

**验证**：把插件历史文件手动截成 0 字节后打开 `:Projects` → 列表仍是 17 条，插件文件被回填成
17 行；重开列表也不缩水。

**恢复**：17 条（用户截图里的 15 个项目 + `~/Projects/Feed stream/feed-java` + `~/.config/nvim`）
已写回插件文件与自有副本。

**边界**：上游写回时只保留最近 100 条（`vim.list_slice`）；目录已不存在的条目在读取时被
`fs_stat` 过滤，不显示也不从副本里删除。

### 13.2 snacks picker 子窗宽度：不要收窄

**事实**：picker 的子窗（input / list）默认与父 `box` **同宽**（实测 box w=52 → list w=52；
snacks 内置默认布局同样是 list w == box w，见 `picker/config/layouts.lua` 的 `M.default`）。

**踩坑**：曾把 list 子窗收窄 2 列，想让选中行底色不压右边框，结果右侧多出一条 2 列宽、
颜色不一致的竖条，比原来更难看 ⇒ 已回退。

**结论**：只调最外层 `layout.width`，不要动子窗宽。选中行底色铺满整行（含边框那一格）是预期效果。

### 13.3 选中行高亮组是 `SnacksPickerListCursorLine`

**症状**：给 picker 选中行配色毫无反应。

**根因**：snacks 的 list 用 **`SnacksPickerListCursorLine`**（`picker/core/list.lua:544`
把 `CursorLine` 设成它；默认 link 到 `Visual`）。只设 `SnacksPickerCursorLine` 是白设。

**处理**（`lua/plugins/snacks.lua`）：**两个一起设**，本机 soft 皮肤为 `bg = #313244, bold = true`。

**验证**：真 pty 打开 picker 看选中行底色（headless 无 UIEnter，见 §12.9）。

### 13.4 自定义 picker 行的富文本

**事实**：source/picker 的 `format = function(item, picker)` 返回 **chunk 数组**
`{ { text, hl }, ... }`（不是字符串）；`opts.format` 一旦提供就**整体替换**内置的文件行格式器
（`picker/config/init.lua` 的 `M.format`：`opts.format` → 源默认 → `Snacks.picker.format.file`）。

两个关键行为：

- `list.lua` 的 `M:format()` 先 `Snacks.picker.util.resolve(item)` 执行每项的
  `resolve = function(max_width)`（chunk 可在其中做宽度感知的截断），再把 chunk 拍平成
  **渲染后的文本**，并在**文本**上重算匹配位置 ⇒ 隐藏字段搜不到高亮，但不影响过滤。
- 行尾纯空白 chunk 会被自动去掉（对齐 padding 放中间 chunk 即可）。

### 13.5 内联 layout 能盖过预设（更正旧说法）

**旧说法**：`nvim-config/references/architecture.md`「picker 皮肤与预设」曾写
"预设里的键会赢过调用处的内联覆盖"。

**更正**：这只对**窗口键位**成立（`win.*.keys` 是整表替换，见 architecture.md 的 snacks keys 坑）；
**布局字段是内联赢**。实测 `layout = { preset = "picker_compact", layout = { width = 61 } }` 生效
（预设给的 53 → 实际 61）；代码里 preset 被 `table.insert(todo, 1, ...)` 后统一 merge，外层内联值保留。

**做法**：改预设前先按**目标字段**实测，不要按"预设一定赢"或"内联一定赢"下结论。

### 13.6 `:Projects` 列表观感

行格式改为"图标 + 项目名（亮）+ 父目录（暗，home 缩成 `~`）"；宽度贴合内容
（`[40, min(96, columns-8)]`，原先固定 0.5 屏宽）；当前项目置顶，名字用蓝色 + `当前` 徽标。
实现见 `lua/core/commands.lua` 的 `format` 与 `window_width`；新增高亮组
`SnacksPickerCurrentProject` / `SnacksPickerCurrentBadge`。

---

## 14. 真机走查探针方法论（2026-09-25，10 条，每条都是本轮真踩的）

> 背景：为了做 Java LSP/DAP 真机走查写了 8 个探针脚本（真 pty 里跑 nvim + 脚本驱动），
> 前 5 个都得到了**错误结论**，全部源于下面的坑。写探针前先看这一节。

### 14.1 jdtls attach ≠ 语义就绪

`vim.lsp.get_clients({name="jdtls"})` 在 ~4s 就有返回，但项目导入还要继续几十秒；**未就绪时请求返回空表而不是 nil**：
hover → `{contents={}}`、documentSymbol → `[]`、definition → `{}`，`vim.lsp.buf_request_sync` 照样正常返回。
拿"请求有返回"当就绪判据会立刻放行，然后得到一堆"LSP 全坏"的假结论。

可靠判据：直接给 jdtls 发 `textDocument/documentSymbol` 并要求**结果非空**；或等 `language/status` 通知里
`type == "ServiceReady"`。

### 14.2 不要用 server_capabilities 的字段做门控（动态注册）

jdtls 通过 `client/registerCapability` **动态注册** hover / rename / codeAction / definition，
这些键在 initialize 的静态 `server_capabilities` 里**永远是 nil**。本轮探针把
`renameProvider ~= nil` 当就绪门控，等了 240s 都等不到（对照：`client:supports_method()` 返回 true）。
本机 `lua/core/lsp_on_attach.lua:19-24` 早有这条记载——又一次踩在同一个地方。

### 14.3 Java buffer 上挂着两个 client：jdtls + spring-boot

`vim.lsp.get_clients({bufnr=0})` 在一个 Java 缓冲区里返回两个：`jdtls` 与 `spring-boot`
（JavaHello/spring-boot.nvim 的 LS，独立进程 `language-server.jar`，命令行 `-Dsts.lsp.client=vscode`）。

`vim.lsp.buf_request` 是**扇出**：两个 client 都会回答，而 spring-boot 对 hover / documentSymbol /
references 返回**空**。所以排查"某个 LSP 功能失灵"必须先看 `vim.lsp.get_clients({bufnr=0})` 有谁、
再用 `client:request(...)` 逐 client 对照。实测同一请求：jdtls 直连 hover =
`int com.example.App.sum(int a, int b)`，扇出结果里 spring-boot 的空回答也在。

### 14.4 vim.wait 不处理 typeahead（按键驱动必须交还主循环）

探针阻塞在 `vim.wait` 里时，pty 注入的按键**不会**被处理（`vim.fn.mode()` 一直是 `n`），
`nvim_feedkeys(..., "m")` 也一样要等主循环。要按键驱动就得用 `vim.defer_fn` 链把控制权交回去，
再在 deferred 回调里检查结果。

### 14.5 nvim_feedkeys 的 mode 字符串：n 是 noremap

`nvim_feedkeys(keys, "nx", false)` 里的 `n` = 不重映射，`x` = 立即执行。想触发**映射**
（which-key 触发器、键位回调）不能用 `n`——本轮因此两次把"修法无效"写进日志，实际是按键没走映射。

### 14.6 -c 'luafile ...' 里的未捕获错误会静默杀死整个探针

屏幕只留一个空闲 nvim，日志停在最后一条成功语句上，看起来像"卡死"。必须整段套
`xpcall(main, debug.traceback)` 并把 ok/err 写进日志文件——本轮两次把探针 bug
（`dap.breakpoints` 为 nil）误判成配置 bug，都是这个原因。

### 14.7 dap.breakpoints 是懒加载字段，直接访问是 nil

本机 nvim-dap（2026-09-11 版，`lua/dap.lua:24  breakpoints = nil`）里 `require("dap").breakpoints`
为 nil；要 `require("dap.breakpoints").get()`。写错就抛错 → 触发 14.6。

### 14.8 长消息触发 hit-enter，把探针冻住

jdtls stderr 的 Spring 相关 WARN、LSP 消息都会进消息区，消息一长就等按键。探针开头固定加：

```lua
vim.o.cmdheight = 12            -- 或 15
vim.o.more = false
vim.o.shortmess = vim.o.shortmess .. "atToOFc"
pcall(vim.lsp.set_log_level, "off")
```

### 14.9 取 toggleterm 终端：require("toggleterm").get() 不存在

主模块只导出 `exec` / `exec_command` 等；终端对象在 `require("toggleterm.terminal").get(id)`。
更稳的做法是按 buffer 名找 `#toggleterm#<id>`（本轮改用它才拿到测试输出）。另外测试跑完后焦点会留在终端
（terminal-insert），后续 `:edit` 会把文件开进那个终端窗口并把模式留在 INSERT——探针里每次按键前先
`vim.cmd("stopinsert")`。

### 14.10 stylua 副本实验必须带 --config-path

把文件复制到 `/tmp` 再跑 `stylua --check`，stylua 找不到 `~/.config/nvim/stylua.toml`，
会退回**默认 tab 缩进**，于是"这份副本也不通过"的结论可能是假的（本轮差点据此推翻一个正确结论）。
正确写法：`stylua --config-path ~/.config/nvim/stylua.toml --check <副本>`。

### 14.11 探针会**改到别的文件**：LSP workspace edit + "退出保存所有被改缓冲区"

LSP 的 rename / organize-imports 是 workspace edit，会同时改**当前没打开**的文件（把它们载入内存并标
`modified`），而本机 `lua/core/autocmds.lua` 有"退出时保存所有被改缓冲区"——
于是探针一退出，这些改动就**落盘**了。本轮真实事故：探针里 rename `sum → sumTotal` 成功，
`edit!` 只回滚了 App.java，AppTest.java 被自动写成 `app.sumTotal(3, 4)`，
导致之后所有测试"编译失败"（而 dap-repl 里的报错长得像插件坏了）。

两条对策：
1. 探针脚本收尾统一清标记：`for _, b in ipairs(vim.api.nvim_list_bufs()) do pcall(function() vim.bo[b].modified = false end) end`
2. 在一次性工程里做破坏性 LSP 实验（rename/format/organize），别在真实项目里做。

顺带确认：这条"自动保存"本身是**按设计工作**的（LSP 跨文件重命名也能落盘）。

---

## 15. which-key 可视模式触发器：旧结论被推翻并修复（2026-09-25）

**症状**：Java 缓冲区在可视（x）模式按 `<leader>` 不弹提示窗（`<leader>Rv/RV/Rc/Rm` 无提示）。

**旧结论（错）**：审查报告 §24 第 2 条判定"上游不支持可视模式触发器"，三种写法
（`mode="x"` / `mode="v"` / `{ "<auto>", mode="x" }`）实测都不注册，列为 ❓ 待查。

**根因**（`lua/plugins/whichkey.lua:12-20`）：`triggers` 两条都只写了 `mode = "n"`，
x 模式根本没有触发器键映射。which-key 只在**该 buffer 对应模式的键树里存在 `<leader>` 前缀映射**时才挂触发器
（`buf.lua` 的 `Mode:attach` → `tree:find("<leader>")`）。因此：

- 在**普通缓冲区**查 `maparg('<Space>','x')` 永远为 nil（那里没有 x 模式的 `<leader>` 映射）——
  旧结论最可能就是在该场景测出来的；
- Java 缓冲区里 `<leader>Rv/RV/Rc/Rm` 是 buffer-local x 键，满足条件。

**修法（已落地）**：

```lua
triggers = {
  { "<leader>", mode = { "n", "v" } },
  { "\\\\",       mode = { "n", "v" } },
},
```

- `v` 与 `x` 等价（which-key 内部把 v/V/C-V 归一成 `"x"`）；官方写法见
  `which-key.nvim/doc/which-key.nvim.txt:357-362`。
- **别用 `{ "<auto>", mode = "x" }`**：实测会给 `g/z/[/]/<C-w>/<Space>` 全建触发器，
  把当初收窄触发器要避免的噪音搬回来。
- 触发器映射是**懒创建**的：按键前 `maparg` 为 nil 不能证明"没生效"，判定必须看真按键后弹不弹。

**A/B 验证（真 pty 170×48，同一个 Java 缓冲区，配置副本 + XDG_CONFIG_HOME 隔离）**：

| 变体 | 按键前 maparg('<Space>','x') | V + <leader> 后浮窗 | 按键后 maparg |
|---|---|---|---|
| 对照 mode = "n" | nil | **0 个** | nil |
| 修法 mode = { "n", "v" } | nil | **2 个**（`+Visual »` 头 + `R ➜ +4 keymaps`） | `which-key-trigger/x` |

### 15.1 2026-09-25 续：`g` 前缀**根本没有触发器**（用户实报「按 g 想看看定义和引用，按下去毫无反应」）

**症状**：Java 类里按 `g` 什么都不弹 —— 用户以为 `gd` / 引用功能坏了。

**诊断（真 pty + 副本工程，别猜）**：

- **`gd` 本身是好的**：把光标放到 `AppProps` 上按 `gd`，缓冲区直接切到 `AppProps.java:6` ✓；
- `grr`/`grn`/`gra`/`gri`/`grt` 是 Neovim 0.12 的**内置** LSP 键，都在（`maparg` 能拿到 desc）。
  ⚠ **踩过的读法坑**：`vim.fn.maparg(k, 'n', false, true).rhs` 对 **Lua callback 映射恒为空**，
  只看 `rhs` 会得出「全都未映射」的错结论 —— 要看 `desc`/`callback` 字段。
- **真因**：`whichkey.lua` 的 `triggers` 当时只写了 `<leader>` 与 `\`（见 §15 正文的历史决定），
  而 `g` 的 40 多条 spec（`gd`/`gh`/`gi`/`gR`/`gO`/`gr` 组…）一直都在 ⇒ 按 `g` 不挂触发器、什么也不弹。

**修法**：`triggers` 里**显式**加 `{ "g", mode = { "n", "v" } }`。
注意**不是** `{ "<auto>" }`：只加 `g`，`z`/`[`/`]`/`<C-w>` 仍然不弹（`<auto>` 会把它们全带上，正是 §15 当初要避免的噪音）。
同时给 `gr*` 补中文 `desc`（内置描述是英文的 `vim.lsp.buf.references()` 之类），`delay = 300` 保证快速连打 `gg`/`ge` 不闪。

**验证（真 pty 140×40，Java 缓冲区）**：

| 按键 | 弹窗内容 |
|---|---|
| `g` | `d ➜ 跳转到定义（LSP）`、`h ➜ 悬停文档（LSP）`、`i ➜ 跳转到实现（LSP）`、`R ➜ 跳转到类型定义（LSP）`、`O ➜ 本文档符号列表（LSP）`、`r ➜ +LSP：引用 / 重命名 / 代码操作（内置）` ✓ |
| `g` 然后 `r` | 子菜单出现 `查找引用` / `重命名符号` / `代码操作`（中文，raw 抓帧命中 3 处）✓ |

**顺带确认**：`gd` 修好后仍正常（跳转 `AppProps.java:6`）。

### 15.2 2026-09-25 复查：`z`/`[`/`]`/`<C-w>` 是**同一类**问题（用户问「别的键位有没有类似的影响」）

**判定方法（可复用，一条命令）**：把 spec 里的**前缀分组**逐个对 `triggers`：

```bash
grep -E '^\s+\{ "[^"]+", group =' ~/.config/nvim/lua/plugins/whichkey.lua
```

凡是有 spec 分组却**不在 triggers 里**的前缀，用户按下去就是「毫无反应」（映射其实好的，只是不弹提示）。

**审查结果**：

| 前缀 | spec | triggers（修前） | 实际映射 | 结论 |
|---|---|---|---|---|
| `<leader>` | 15 组 | ✅ | 28 个自定义 | 正常 |
| `g` / `gr` | ~45 条 | ❌ → ✅ | 1 自定义 + 内置 | §15.1 已修 |
| `z` | 33 条 | ❌ → ✅ | 内置 | **本次修** |
| `[` / `]` | 各 2 条 | ❌ → ✅ | 内置 + `[d`/`]d` | **本次修** |
| `<C-w>` | 12 条 | ❌ → ✅ | 内置 | **本次修** |
| 操作符后 motion（`w/b/e/0/$/gg/G…`，spec `mode="no"`） | 有 | **有意不加** | 内置 | 加了会让每次 `d`/`y`/`c` 都弹 |
| 文本对象 `a`/`i`（spec `mode="xo"`） | 有 | **有意不加** | 内置 | `aw`/`i(` 序列暂停会弹、易打扰；需要时 `:WhichKey a` |
| `\`（localleader） | — | ✅（保留） | **0 个映射**（全局+buffer-local 实测） | 按 `\` 不弹（无内容，符合预期）；触发器留着为将来 |

**验证（真 pty 120×32，普通 lua 文件，无需 jdtls）**：

| 按键 | 结果 |
|---|---|
| `z` | 折叠/滚动菜单弹出（raw 命中「折叠」11 处、「z 前缀」1 处）✓ |
| `[` | 「上一个诊断」菜单 ✓ |
| `]` | 「下一个诊断」菜单 ✓ |
| `<C-w>` | 「窗口操作」菜单 ✓ |
| `<C-w>v`（功能回归） | 真的切成 **2 个非浮窗**（`floats=1` 是 which-key 浮窗）✓ |
| `zz`（快速连打） | `mode=n`、无残留状态 ✓ |
| `]d`（边界） | 提示 `No more valid diagnostics to move to`（正常边界提示，不是报错）✓ |

**教训**：which-key 的 spec 与 triggers 是**两套东西** —— 写了 spec 不等于会弹；改 triggers 时**必须**拿 spec 的前缀分组对一遍。

---

## 16. Java 真机走查结论（2026-09-25，Maven + JUnit5 小工程）

工程：`~/tmp/nvim-probe/java-demo`（`src/main/java/com/example/App.java` +
`src/test/java/com/example/AppTest.java`，含 `pom.xml` 故 jdtls 按 Maven 工程导入）；
探针在真 pty（160×45 / 170×48）里跑。

**能用（都有原始输出或截图）**

- **LSP**：hover = `int com.example.App.sum(int a, int b)`；definition → App.java:18；
  references = 3 处（行 12/18/13）；documentSymbol = `[com.example, App]`；
  inlayHint = `a:/b:/who:/items:`；诊断 = `The import java.util.HashMap is never used`（code 268435844）；
  codeAction 列表正常。
- **测试运行**：`<leader>Jt` → toggleterm 2 号终端跑 `mvn test -Dtest=com.example.AppTest`，
  输出 `Tests run: 1, Failures: 0, Errors: 0, Skipped: 0` + `BUILD SUCCESS`，终端保留可回看。
- **DAP**：`<F9>` 设断点（`buf1:L20`）→ `<F5>` 自动扫主类
  （`mainClass=com.example.App`）→ `stopped{reason="breakpoint", threadId=1, allThreadsStopped=false}`
  → dapui 自动打开（scopes/breakpoints/stacks/watches/repl/console 六个窗口）→ **变量 `a=3 b=4 result=7`、
  调用栈 `sum → main`**、行内虚拟文本（`{ a = 3, b = 4` / `; result = 7`）→
  `step_over` 后第二次 stopped（`reason="step"`）→ `exited` + `terminated`，
  结束时 dapui 自动关闭。
- **bundle**：java-debug + java-test + spring-boot-tools 共 33 个 jar 全部加载成功，jdtls
  `.metadata/.log` 无 bundle 加载失败。

**坑 / 待查**

- ~~jdtls `.metadata/.log` 每次启动记一条 ERROR：`Command _java.reloadBundles.command not supported on client`~~
  ✅ **2026-09-25 已消音**：Neovim 运行时**没有** `workspace/executeClientCommand` 的 handler（grep 过 `runtime/lua/vim/lsp`），
  jdtls 发来的 client 命令拿到 "method not found" 才被记成 ERROR。修法：在 `java.lua` 的 `start_jdtls` 里给 client config 挂 handler——
  该命令回成功（bundles 启动时已通过 `init_options.bundles` 传入），其它命令仍 `error({ code = -32601 })` 保持原语义。
  ⚠ handler 必须写在 `config` 里：这条请求发生在初始化阶段，启动后再补就晚了。验证：ERROR 条目 64→0、该条消息 29→0、功能无回归。
- 探针用 `session:request("threads" / "stackTrace")` 拿到的是**空数组**（`err=nil, n=0`），
  而**同一个会话**里 dapui 面板能显示 3 个线程与变量。**以 dapui/截图为准**；程序化请求路径的差异未查明
  （下次方向：请求时机是否早于 `configurationDone`、`Session:request` 的排队行为）。
- `spring-boot` LS 启动后会通知：`LSP[spring-boot] Embedded Spring Tools MCP server started at port: 39881`。

---

## 17. Java 缓冲区 :e / :e! 之后 LSP 静默失效（2026-09-25 定位，P1，**已修复并落地**）

**症状**：在 Java 文件里做过 `:e` / `:e!`（或任何触发 FileType 的重载）之后，
`gh` 报 `Empty hover response`、`gd` 报 `No locations found`、
`gra` 报 `No code actions available`、
`grn` 报 `no matching language servers with rename capability`。
**不抛错、只是没反应**，重开 nvim 才恢复——非常容易被当成"jdtls 抽风"。

**根因**（真 pty 事件日志，probe_reload.lua）：

```text
attach 后        clients=1:jdtls,2:spring-boot      hover 正常
:e!  → LspDetach  client=1 buf=1                   ← Neovim 重载缓冲区时把所有 client 都 detach
       LspAttach  client=2 buf=1                   ← 只有走 vim.lsp.enable 按 filetype 管理的 spring-boot 自己回来
edit! 后         clients=2:spring-boot             ← jdtls 没回来
hover            → Empty hover response
```

`lua/plugins/lang/java.lua` 的 `started_bufs[bufnr]` 去重守卫让第二次 `start_jdtls()` 直接
`return`，nvim-jdtls 的 `start_or_attach()` 不会被再次调用 ⇒ jdtls 永远不回到这个 buffer。
**jdtls 自己的函数不受影响**（`<leader>ot` 整理 import、`<leader>Jt/Jg/JG`、DAP 都按 client 名字取），
所以"部分功能正常"最容易掩盖这个问题。

**修法**（2026-09-25 已应用到 `lua/plugins/lang/java.lua`；补丁留档 `~/backups/nvim-config-round10-*/java-detach-fix.patch`，6 行）：
命中去重守卫时改为"确保 jdtls 仍挂在这个 buffer 上"：

```lua
if started_bufs[bufnr] then
  local existing = vim.lsp.get_clients({ name = "jdtls" })[1]
  if existing and not (existing.attached_buffers or {})[bufnr] then
    vim.lsp.buf_attach_client(bufnr, existing.id)
  end
  setup_java_keys(bufnr)
  return
end
```

**验证（A/B，真 pty + 配置副本/XDG_CONFIG_HOME）**：

| 配置 | `:edit!` 之后 | hover |
|---|---|---|
| 现状 | `clients=2:spring-boot`（jdtls 掉了） | `Empty hover response` |
| 打补丁 | `clients=1:jdtls,2:spring-boot` | 正常（无告警） |

**不重开 nvim 的应急命令**：
`:lua vim.lsp.buf_attach_client(0, vim.lsp.get_clients({name="jdtls"})[1].id)`

---

## 18. DAP 的两个隐藏陷阱 + pty 探针的 swap 文件陷阱（2026-09-25）

### 18.1 DAP 请求的 arguments 传空表 = 请求永久挂起（`vim.json.encode({}) == "[]"`）

- **症状**：探针里 `session:request("threads", {}, cb)` 永远不回调（20s 超时、`err=nil, n=0`），而**同一个会话**里 dapui 面板正常显示 6 个线程与变量 → 一度被误判成"请求时机早于 configurationDone"。
- **根因链（三段闭环）**：
  1. nvim-dap 把 arguments 直接交给 `vim.json.encode`：`vim.json.encode({})` → `[]`（JSON **数组**）；`vim.json.encode(vim.empty_dict())` → `{}`。
  2. java-debug（jdtls 的 java-debug-adapter，0.53.2）用 Gson 解析 `$.arguments`，遇到数组抛 `JsonSyntaxException: Expected a com.google.gson.JsonObject but was com.google.gson.JsonArray`。
  3. 适配器**静默吞帧、永不回应**：jdtls workspace 的 `.metadata/.log` 里每个 `{}` 请求恰好一条 Error parsing message（栈指向 `AbstractProtocolServer.processData:222`）；DAP TRACE 里那个 `seq` 永远等不到 `request_seq` 相同的响应。
- **正确写法**：`session:request("threads", nil, cb)`（无参数就传 nil）；要传空对象用 `vim.empty_dict()`；非空对象表正常（`{foo=1}` 能解析；用不存在的 command 验证过"能解析就一定回响应"）。
- **为什么 dapui 不受影响**：nvim-dap 自己就是 `self:request('threads', nil, on_threads)`（`lua/dap/session.lua:685`），dapui 只监听响应（`dapui/components/threads.lua:10-12`），不自己发请求。
- **教训**：DAP 探针拿不到响应时，**先看 arguments 是不是被编码成了数组**，而不是怀疑时机/状态机。

### 18.2 stackTrace 的字段名是 `stackFrames` 不是 `frames`

旧探针读 `.frames` ⇒ 即使响应完全正常也永远打印 `frames=0`，制造"适配器返回空数组"的第二个假象。

### 18.3 java-debug 对空 logMessage / condition / hitCondition 的语义（实测，不是文档）

- 原始 `setBreakpoints` 十变体（`logMessage=""` / `condition=""` / `hitCondition=""` / 三个都空 / 空白串 / `hitCondition="abc"`）：适配器**全部不报错**，一律回 `verified=true`。
- 真 JVM 运行行为：`logMessage=""` 的断点**会真的停住**（reason=breakpoint，**不是**日志点）；只有 `logMessage="LOG a={a}"` 这种非空串才是不停的日志点。
- 源码佐证：`SetBreakpointsRequestHandler.handleEvaluationResult` 用 `StringUtils.isNotBlank(getLogMessage())` 分流；`hitCondition` 解析失败即 `hitCount=0`（等于忽略）。
- **结论**：nvim 侧"空输入不建断点"的守卫是对的，但理由不是"假断点无害"，而是"上游会把它当**普通断点**，用户以为设了日志点却会真的停下"（注释已按此订正，`lua/plugins/dap/init.lua:87-90`）。

### 18.4 pty 探针必须用 `nvim -n`（残留 swap 文件会让后续所有探针静默失效）

- **踩法**：探针被 kill（或 `:qa!` 没走完）后残留 `~/.local/state/nvim/swap/%tmp%xxx.swp`；下一次用同一文件起 pty 会停在 `E325: ATTENTION` 提示上，此后发的所有 `S:` 按键都被这个提示吃掉 —— 表现为"探针什么都没干 / 最后屏幕被清空 / 输出文件没生成"，极易误判成"键发送坏了"或"luafile 不能跑"。
- **处理**：探针一律 `nvim -n`（noswapfile）；排障先 `ls ~/.local/state/nvim/swap/`。
- **相关坑**：探针工作目录别一会儿 `/tmp/...` 一会儿 `~/tmp/...`（看着像同一路径，实际是两个目录）；脚本"没生成输出文件"时先核对绝对路径是不是你以为的那个。

### 18.5 blink.cmp 的菜单对 `pumvisible()` / `complete_info()` 恒为空

- 判断"补全菜单是否弹着"**不能**用内置的 `pumvisible()` 或 `complete_info()`——blink.cmp 用自己的浮窗菜单，两者恒为 0/空，会直接误导探针（"明明有菜单却读到没有"）。
- 正确判据：`require("blink.cmp").is_menu_visible()`（`blink.cmp/lua/blink/cmp/init.lua:45`）。
- 附带确认的映射归属链（真机 dump）：buffer-local `<Tab>` = `blink.cmp: Accept, Snippet Forward`（`apply.lua:202` 用 `nvim_buf_set_keymap(0,…)`）优先于 global `<Tab>` = `<Plug>(neotab-out)`（`neotab.lua:85`，InsertEnter 时设）；neotab 只在 blink 的 fallback 路径被调用（`fallback.lua:60`）。所以"括号/引号内 <Tab> 跳外侧"是 neotab 行为，不是缺陷。

### 18.6 nvim-jdtls 上游 `pick_many` 的取消语义（为什么本机要换成 snacks picker）

- 上游 `jdtls/ui.lua:61-111` 的原生 `pick_many` 是 `input()` 循环：**Esc 与空回车等价**，根本没有"取消"通道。
- 上游六个 `pick_many` 调用点里只有三处检查空返回（`jdtls.lua:123` constructors / `:184` delegate / `:777` override 有 `#x==0 then return`）；三处 **fields** 调用点 `jdtls.lua:97`(generateToString) / `:138`(generateConstructors) / `:225`(generateHashCodeEquals) **都不检查** ⇒ "取消"只能退回空选择、动作照常执行。
- 本机 snacks 版已按上游契约在取消时返回空表（`lang/java.lua:287` `finish(nil)` → `:300` `or {}`），保证 `jdtls.lua:782` 的 `#selected` 不炸；剩下那三种 action 的"真取消"要等上游修。

### 18.7 snacks picker 探针自省与 pty 驱动增强（2026-09-25，uirepro/perf 踩到）

- **`pk.input.win` 不是窗口号**：拿它去 `nvim_win_*` 会报 `Invalid win`，被 pcall 一吞就表现成"picker 看不见"，很容易误判。可靠做法：按 **filetype** 找 `snacks_picker_input` / `snacks_picker_list` 缓冲区（等价屏幕内容，还能读到 `○●` 勾选符号与过滤串）。
- **包装 `Snacks.picker.pick` 要在 snacks 加载之后**再包（在 spec 解析期包会拿不到真身）。
- **`XDG_CONFIG_HOME` 必须指向 `nvim` 的父目录**：指错不会报错，而是"静默裸跑默认配置"，性能数字全废 ⇒ 探针开头 `assert_config()`，失败 `cquit 3`。
- **Lua 后置声明的 `local function`** 会被解析成全局 nil（`local function f()` 写在调用点之后）⇒ 探针静默死掉、或退不出 jdtls 留下孤儿 JVM；统一前置声明 + `C.guard()` 包 defer。
- **pty 驱动可加两个 token**：`P:<file>`（每个按键后快照屏幕，逐键取证）、`W<秒>:regex`（长等待，等 jdtls 就绪）。收尾协议：收到 `vim.g.uicheck_done` 就 `stop_client` 全部 + 清 modified + `qa!`，pty 关闭不留孤儿 JVM。
- **多批次共用聚合文件**会被后跑批次 `: >` 清空（perf 的数据就这么丢过一次）⇒ 按 `cfg/case` 分文件写。
### 18.8 清理自己起的语言服务：**按精确 PID**，别用会命中用户 workspace 的模式（2026-09-25 血的教训）

- 踩法：探针脚本里用 `pkill -f "jdtls-workspace/feed-java-"` 收尾自己起的 jdtls —— 这个模式**同时命中用户正在用的 workspace** `feed-java-f631125a78`，把用户会话的 jdtls 一起杀了。
- 正确做法：① 起服务时记下 PID（`vim.fn.jobstart` 的返回值 / `ps` 抓取），收尾只 kill 这些 PID；② 或者把测试工程放在只有自己会用的目录（如 `~/tmp/<unique>/`），用**该全路径**做匹配（`pkill -f "jdtls-workspace/$(sha256 前缀)"` 不行——名字里只有项目名和路径哈希）；③ 更稳的是给测试 workspace 起个唯一项目名（例如 `dapcheck-proj`），模式就天然唯一。
- 附带结论：`-data` workspace 目录名 = `<项目目录名>-<项目绝对路径 sha256 前 10 位>`，所以**同名项目在不同路径下不会互相污染**；可以用 `sha256(path)[:10]` 核对某个 workspace 到底属于谁再决定删不删。
### 18.9 探针收尾会泄漏 Spring Boot 语言服务（`language-server.jar` 变 PPID=847 孤儿）

- **踩法**：探针只 kill nvim / jdtls，但 Spring Boot LS 是 **nvim 直接 spawn** 的子进程；父进程被 SIGKILL/超时杀死后它被 reparent 到 `systemd --user`（PPID=847），于是**一直活着**。一次多轮压测下来能攒出几十个：实测 **28 个、约 8.1GB**，loadavg 被抬到 17，把同机其他测量全污染了。
- **不是配置缺陷**：正常 `:qa` 退出时 nvim 会带走它；只有被强杀的探针才会留。
- **收尾规则**：① 先 kill 自己起的 nvim/jdtls；② 再按自己的 workspace 名或 PID 树补一轮 `language-server.jar` 的清理；③ 断言 `ps -eo pid,ppid,args | awk '$2==847||$2==1' | grep java` 为空。
- **别误杀用户会话**：判断依据是 **PPID** —— 用户会话里的 LS 挂在 `nvim --embed` 的 PID 下，只有 `PPID∈{1,847}` 的才是孤儿（配合 §18.8 的『按精确 PID/唯一目录名』一起用）。
### 18.10 探针纪律补遗（2026-09-25 第二次全面审查，各线共同踩到）

- **探针必须默认隔离 XDG**：用真实 `XDG_STATE_HOME`/`XDG_DATA_HOME` 起 nvim 打开带 `.git`/`pom.xml` 的目录，**会改用户的项目历史**（project.nvim 记一笔）。要动用户数据就显式说明并先备份。
- **uv timer 必须保持引用**：`local t = vim.uv.new_timer()` + `t:start(...)` 在 chunk 结束后可能被 GC ⇒ 回调再也不触发（表现为「埋点什么都没写」）。用 `_G.__timer` 或存进表里。
- **`vim.o.shortmess:append` 不存在**：要写 `vim.opt.shortmess:append(...)`（`vim.o` 返回的是字符串拷贝，改它没用）。
- **nvim 0.12 里 `vim.lsp.set_log_level()` / `vim.lsp.stop_client()` 已废弃**：探针调用会在 `:messages` 留一条 deprecated 提示，属**探针自造噪音**，别记成配置问题。
- **向 pty 注入按键要写 master 端**（`/dev/ptmx` 那一侧）；写 slave 无效，表现为探针一直等到超时。
- **进程归属判定用 `/proc/<pid>/exe`（或 `cwd`），不要用 cmdline 关键字**：否则 `lua-language-server`、甚至审计脚本自己都会被误判成 java。
- **上游 Neovim runtime 的 silent 噪音**：`runtime/ftplugin/java.vim:375` 的 `b:undo_ftplugin` → `JavaFileTypeCleanUp()` 里 `silent! autocmd! java_spotbugs_post User <buffer>` 会把 `E216` 写进 `v:errmsg`（**屏幕不显示**）。探针记录 `v:errmsg` 时会看到它，别当缺陷报。

## 19. LSP 服务端→客户端请求（`workspace/executeClientCommand`）：两条红色报错 + 一个被吞掉的 classpath 握手（2026-09-25，**已修复**）

### 19.1 症状

打开 Java 项目时 noice/`:messages` 里出现两条红框（用户截图报的）：

```text
LSP[jdtls]: Error SERVER_REQUEST_HANDLER_ERROR: { code = -32601, message = "Method not found: vscode-spring-boot.ls.start" }
vim.schedule callback: /usr/share/nvim/runtime/lua/vim/lsp/rpc.lua:400: method "workspace/executeClientCommand": either a result or an error must be sent to the server in response
```

### 19.2 两个坑：nvim 侧 handler 的返回值语义（`rpc.lua:389-406` 源码可证）

`workspace/executeClientCommand` 是**服务端→客户端**的请求（VS Code 里由 Java/Spring 扩展实现）。nvim runtime 的处理是：

- handler **成功返回 nil**（`return` 什么都不给）且 `err == nil` ⇒ nvim **主动抛** `method "…": either a result or an error must be sent to the server in response`（就是上面第二条 traceback），**并且这条请求永远不回、服务端一直挂着**；
- handler 里 `error({ code = -32601, message = "Method not found: …" })` ⇒ 服务端记 `SERVER_REQUEST_HANDLER_ERROR … Method not found`（第一条）。

另外 jdtls 对 `_java.reloadBundles.command` 的返回值做类型分流（`JDTLanguageServer.synchronizeBundles()`：`instanceof List` → loadBundles；`instanceof Map` → logError；**其它含 `null` → `logError("Unexpected result from executeClientCommand: null")`**，用 `javap` 反编译核实）⇒ 回 `null` 也会让 `.metadata/.log` 每次启动记一条 ERROR。

### 19.3 最隐蔽的一层：**client 级 handler 会盖掉全局转发**

- `nvim-jdtls` 本来就在**全局** `vim.lsp.handlers['workspace/executeClientCommand']` 装了转发（`jdtls.lua:854-874`）：先查 `client.commands[cmd]`，再查全局 `vim.lsp.commands[cmd]`，命中就执行并把返回值回给服务端。
- `spring-boot.nvim` 把 `vscode-spring-boot.ls.start`（classpath 握手 → `sts.vscode-spring-boot.enableClasspathListening`）注册在**全局** `vim.lsp.commands`。
- 一旦在 client config 里写 `handlers['workspace/executeClientCommand']`，**client 级优先**（`client.lua:657`）⇒ 全局那个整个失效 ⇒ **握手永远不执行**。

后果远不止日志噪音：**没有 beans / endpoints / `application.yml` 的 `spring.*` 补全**（spring-boot.nvim 源码注释原话）；而且初始化期那条请求永远不回会让 jdtls 停在半初始化状态 —— 本机表现为 `<F5>` 报 `Could not resolve java executable for <主类>`（主类扫得到、javaExec 解析失败）。

### 19.4 正确写法（本机落地在 `lua/plugins/lang/java.lua` 的 `config.handlers`）

```lua
config.handlers = {
  ["workspace/executeClientCommand"] = function(_, params, ctx)
    params = params or {}
    local client = vim.lsp.get_client_by_id(ctx.client_id) or {}
    local commands = client.commands or {}
    local global_commands = vim.lsp.commands or {}
    local fn = commands[params.command] or global_commands[params.command]
    if fn then
      local ok, res = pcall(fn, params.arguments, ctx)
      if ok then return res == nil and vim.NIL or res end
      return vim.lsp.rpc_response_error(vim.lsp.protocol.ErrorCodes.InternalError, tostring(res))
    end
    -- jdtls 认 List：reloadBundles 回空表（JSON []）而不是 null
    if params.command == "_java.reloadBundles.command" then return {} end
    return vim.NIL
  end,
}
```

要点：① **必须自己复刻全局转发**（client.commands → 全局 vim.lsp.commands），否则等于把上游的转发整个盖掉；② 未知命令回 `vim.NIL`（JSON null）而不是 `nil`；③ `_java.reloadBundles.command` 回**空表**。

### 19.5 验证手法（可复用，不用等 jdtls 真的发请求）

```lua
-- 在真 Java 会话里直接调 client handler 做单测
local cl = vim.lsp.get_clients({ name = "jdtls" })[1]
local h = cl.handlers["workspace/executeClientCommand"]
vim.lsp.commands["__probe"] = function() return "OK" end
assert(h(nil, { command = "__probe", arguments = {} }, { client_id = cl.id }) == "OK")
```

配套对照：① `:messages` 里 `SERVER_REQUEST_HANDLER_ERROR` / `rpc.lua:400` / `Method not found` / `either a result or an error` 四个关键词计数；② jdtls `.metadata/.log` 里 `Unexpected result from executeClientCommand` 的**时间戳**（用来区分新旧 handler 各自产生的量）。

### 19.6 顺带：`lsp.log` 启动时容量轮转

只把级别压到 `ERROR` 并不阻止日志增长（本机历史到过 27MB）。`core/options.lua` 现在启动时 `fs_stat`，超过 **5MB** 就把 `lsp.log` 改名成 `lsp.log.1`（覆盖上一份、不删内容）。验证：造一个 6MB 的 `lsp.log` 后启动 nvim ⇒ `lsp.log.1` = 6291456B、新 `lsp.log` = 51B；56B 的小日志不动。

## 20. 「中文标点自动转半角」：没有现成插件，用 InsertCharPre 自己实现（2026-09-25）

### 20.1 需求与调研结论（先查有没有插件）

需求：输入 `，。；：！？` 时**自动**变成 `,.;:!?`（全角 → 半角）。

GitHub 查证结论：**没有做「输入即转」的插件**。

| 找到的东西 | 为什么不合适 |
|---|---|
| `AzarAI-TOP/cpc.nvim`（2★，纯 Lua） | 只能**命令式**整篇/选区手动转，没有输入时转换 |
| `huacnlee/autocorrect`（1.6k★，Rust + LSP） | 规则**恰好相反**：`fullwidth: 1`（CJK 旁边的标点转**全角**）+ `halfwidth-punctuation: 1`（**只在英文内容里**转半角）⇒ 纯中文文本它反而会转成全角 |
| `zenkaku` / `hankaku` 关键词 | 只搜到 Python/JS/Go 库（jaconv、mojimoji、charwidth…），没有 Neovim 插件 |
| `translate.nvim` / `pantran.nvim` 等 | 是「按需翻译文档内容」，不是字符转换 |

### 20.2 正解：`InsertCharPre` + `vim.v.char`（本机落地 `core/cjk_punct.lua`）

Neovim 0.8+ 允许在 `InsertCharPre` 里**改写待插入字符**，所以「输入即转」不需要插件：

```lua
vim.api.nvim_create_autocmd("InsertCharPre", {
  callback = function()
    local repl = map[vim.v.char]
    if repl then vim.v.char = repl end
  end,
})
```

配套：`:CJKPunct` 开关（默认开）、`:CJKPunctFix` 转已有内容（**粘贴不触发 `InsertCharPre`**，只能靠这个补）、
默认在 `markdown`/`text`/`gitcommit`/`help` 里不转（这些场景全角才是对的）。

### 20.3 两个坑（都真踩了）

1. ⚠ **Lua 的 `[...]` 字符类按「单字节」匹配** ⇒ `text:gsub("[，。]", map)` 对多字节汉字**永远匹配不到**
   （会把 UTF-8 序列拆成单字节，查表也查不到），症状是「转换命令报『已转 0 行』」。
   正解：按**一个完整 UTF-8 字符**匹配 ——
   `text:gsub("[\1-\127\194-\244][\128-\191]*", function(c) return map[c] or c end)`。
2. ⚠ **不要用 headless 的 `nvim_feedkeys` 验证多字节输入**：改写 `v:char` 会与按字节喂入的序列互相干扰，
   结果是缓冲区出现乱码（实测 `，〼：！？`），会误判成 bug。**必须用真 pty**，且逐字符/一次性连打各测一遍。

### 20.4 验证（真 pty 100×24）

| 场景 | 结果 |
|---|---|
| `，` `。` `；` `：` `！` `？` `（` `）` 逐个（各自单独会话） | 全部转换成功 ✓ |
| 一次性连打 `，。；：！？` | → `,.;:!?` ✓ |
| `.md` 文件里输入 | 保留全角 `，。` ✓（排除列表生效） |
| `:CJKPunct` 关闭后输入 | 保留全角，`g:cjk_punct=false` ✓ |
| `:CJKPunctFix`（`a，b。c（d）【e】《f》`） | → `a,b.c(d)[e]<f>` ✓ |

---

## 21. 诊断消息太长被「截断」——`virtual_lines` 自身不折行（2026-09-25 用户截图）

### 21.1 症状

光标停在错误行上时，诊断消息显示在**下一行**（以 `└──── ` 开头），但右边被窗口边缘切掉：
`… for the arguments (Instant, OffsetDat`（用户截图）。80 列必现，窗口够宽时看不出来 ⇒ 容易误判成偶发。

### 21.2 根因（先分清是哪条渲染路径）

- 这是 **`virtual_lines`** 渲染的虚拟行（本配置 `current_line = true`），**不是浮窗** ——
  浮窗走 `vim.lsp.util.open_floating_preview`，默认 `wrap = true`，长消息**会正常折行**（别搞混）。
- `render_virtual_lines` 挂 extmark 时用 `virt_lines_overflow = 'scroll'`（`runtime/lua/vim/diagnostic.lua:2157`）
  ⇒ **虚拟行不折行**，超出窗口宽度就被右边缘裁掉。
- 但它**按 `\n` 切分消息**（同文件 :2138 `for msg_line in diagnostic.message:gmatch('([^\n]+)')`），
  且每行都补 `└──── ` 前缀、续行缩进 6 格对齐。

### 21.3 修法（本机落地 `core/options.lua` 的 `virtual_lines.format`）

自己按窗口宽度折行，再用 `\n` 拼回去交给渲染器：

```lua
format = function(d)
  local win = vim.fn.win_findbuf(d.bufnr or 0)[1] or vim.api.nvim_get_current_win()
  local textoff = (vim.fn.getwininfo(win)[1] or {}).textoff or 0
  local width = vim.api.nvim_win_get_width(win) - textoff - 7 -- 7 = "└──── " 前缀 + 1 余量
  return wrap_message(d.message, math.max(20, width))
end,
```

- 宽度用 `win_findbuf(d.bufnr)` 找窗口：`format` 执行时 `nvim_get_current_win()` **不一定**是显示该 buffer 的窗口；
- 折行按**显示宽度**（`strdisplaywidth`，CJK 算 2 列），优先在空格断、超长 token 硬断；
- 超过 12 行截断并追加 `…`（`]d` 弹的浮窗里仍是完整内容）。

### 21.4 验证（真 pty）

| 场景 | 结果 |
|---|---|
| 80 列长英文消息 | 折 2 行，**完整显示**（`└──── …OffsetDateTime is` / 续行 `not applicable for the arguments (Instant, OffsetDateTime, ZoneId)`）✓ |
| 60 列 | 折 3 行 ✓ |
| 30 段超长中文消息 | 12 行 + 末尾 `…` ✓ |
| 短消息 | 仍 1 行（不误折）✓ |
| `]d` 浮窗 | 不受影响（本来就折行）✓ |

### 21.5 教训

修「截断」先定性**哪条渲染路径**：浮窗会折行、**虚拟行不会**（`grep virt_lines_overflow` 一眼定性）。

---

## 22. sidekick.nvim 安装、三个坑与一次清理事故（2026-09-25）

### 22.1 装了什么

`folke/sidekick.nvim`（AI CLI 面板），**只启用 CLI 那一半**：`nes = { enabled = false }`（NES 要 copilot-language-server + GitHub Copilot 订阅，本机都没有）、`cli.mux.backend = "tmux"`。键位用此前空闲的 `<leader>a*` + `<C-.>`。

安装路径（本机没有全局代理，lazy 直接装会失败）：代理 `git clone --depth 1` 到 `~/.local/share/nvim/lazy/sidekick.nvim` → 写 spec → `nvim --headless "+Lazy! install" +qa` 让它写进 `lazy-lock.json`（35 → 36 条，commit `3d80a47`）。

### 22.2 坑 1：`:checkhealth <插件>` 对「纯 lua、无 `plugin/` 目录」的懒加载插件**要先加载**

- sidekick 仓库里**没有 `plugin/` 目录**，healthcheck 只在 `require("sidekick")` 之后才注册 ⇒ 直接 `:checkhealth sidekick` 报 `ERROR No healthcheck found for "sidekick" plugin`（看起来像装坏了，其实是没加载）。
- 正解：`:Lazy load sidekick.nvim`（或按一次它的键）再 `:checkhealth sidekick`。**这条对任何用 `keys`/`event` 懒加载且无 `plugin/` 目录的插件都成立**。

### 22.3 坑 2：`mux.backend = "tmux"` 会真的建 tmux 会话 ⇒ 清理只能清「测试新增的」

- 选工具后 sidekick 会 `tmux new-session` 再在 nvim 终端里 attach（实测会话名形如 `codex 9c6f53cb0da`）。
- 真 pty 测试后要清，但**必须用差集**，不能按名字通杀（见 22.6 事故）：

```bash
tmux ls -F "#{session_name}" > /tmp/tmux-before.txt   # 测试前快照
# ...跑测试...
comm -13 <(sort /tmp/tmux-before.txt) <(tmux ls -F "#{session_name}" 2>/dev/null | sort) \
  | while read s; do tmux kill-session -t "$s"; done
```

### 22.4 坑 3：面板半透明、CLI 的暗色文字糊在壁纸上 —— `SidekickChat` 未定义

> ⚠ **状态：已回退**（2026-09-25 晚，用户要求「恢复到最初始的状态，我对 grok 等换一个主题即可」）——本节记录的**根因与手法保留作知识**，但**本机配置里已经不再有**这段实现，别照它去找代码。

**症状**（用户截图）：sidekick 的 CLI 面板背景透出桌面壁纸，Qwen 之类 CLI 的次要文字（ANSI 8 灰）糊成一片，看着像「主题被 nvim 带跑偏」。

**根因**：sidekick 建终端窗口时设了

```lua
winhighlight = "Normal:SidekickChat,NormalNC:SidekickChat,EndOfBuffer:SidekickChat,SignColumn:SidekickChat"
```
（`lua/sidekick/cli/terminal.lua:47`），**但它自己从不定义 `SidekickChat`**、文档里也没提。未定义的高亮组没有背景色 ⇒ 叠上本机 `transparent_background = true`（全局 `Normal` 的 bg 是 NONE）⇒ 面板完全透明。窗口本身 `winblend = 0`，所以**不是** winblend 的问题。

**修法**（本机在 `plugins/sidekick.lua` 的 config 里）：补一个实底 `SidekickChat`，并在 `ColorScheme` 后重新应用；

```lua
local function solid_panel_bg()
  local ok, pal = pcall(function() return require("catppuccin.palettes").get_palette() end)
  vim.api.nvim_set_hl(0, "SidekickChat", { bg = ok and pal.base or "#1e1e2e", fg = ok and pal.text or "#cdd6f4" })
end
solid_panel_bg()
vim.api.nvim_create_autocmd("ColorScheme", { callback = solid_panel_bg })
```

**验证（真 pty，面板已开）**：`win_ft=sidekick_terminal`、`winhighlight` 指向 `SidekickChat`、`winblend=0`、`SidekickChat_bg=#1e1e2e`，而全局 `Normal_bg=NONE` —— 正是「补了组就不透明」的证据。

### 22.5 验证（真 pty）

| 场景 | 结果 |
|---|---|
| `:checkhealth sidekick`（先 `:Lazy load`） | ✅ Neovim≥0.11.2 / autoread / tmux 集成 / tmux / ps / lsof；工具列表 codex、grok、opencode 均 OK |
| `<leader>as` | 「Select CLI tool」弹窗**只列已安装的 3 个**（codex / grok / opencode，3/3）✓ |
| 选中 codex | 建 tmux 会话并在 nvim 里 attach，出现 codex 真实界面（Trust folder 提示）✓ |
| 5 个键位 | 全部注册、desc 为中文 ✓ |
| 面板背景 | `SidekickChat` 实底 `#1e1e2e`、`winblend=0` ✓（修前透明） |
| ❌ 预期项 | `No Copilot LSP server is enabled` —— 选了「不接 Copilot」就一定有这条，**不是故障** |

### 22.6 ⚠ 事故：按名字模式清 tmux 会话，误杀了用户自己的会话（2026-09-25）

- 我最初用的清理命令是 `grep -iE "codex|sidekick"` 通杀，结果把用户自己开的 **`grok f631125a78ba`**、**`opencode f631125a`**（会话名后缀正是他项目的 hash）一起 kill 了 —— 他当时正在用 sidekick 跑 CLI。
- **教训**：清理「外部可见资源」（tmux 会话、后台进程、系统级 socket）时**绝不能按名字/关键字通杀**；必须「测试前快照 → 只处理差集」，或按创建时间/PID 精确匹配（与 §18.8「清理服务要按精确 PID」同一条纪律）。
- 影响面：CLI 会话没了（对话上下文丢），**项目文件不受影响**；重新 `<leader>as` 即可开新会话。

---

## 23. 透明主题下的「终端底色」：`core/term_bg.lua`（2026-09-25 用户要求）

### 23.1 需求

> ⚠ **状态：已回退**（2026-09-25 晚，用户要求「恢复到最初始的状态，我对 grok 等换一个主题即可」）——本节记录的**根因与手法保留作知识**，但**本机配置里已经不再有**这段实现，别照它去找代码。

用户：AI CLI / 终端面板透出桌面壁纸，CLI 的暗色文字糊在壁纸上，「两种主题叠加」没法看 ⇒ **让终端恢复实底**（编辑区保持透明）。

### 23.2 两个必须知道的事实（都实测踩过）

1. **浮窗的背景高亮是 `NormalFloat`，不只是 `Normal`** —— 只映射 `Normal` 对 `nvim_open_win` 的浮窗**无效**（toggleterm 的浮窗就是这样：`ui.hl_term()` 给浮窗只设 `FloatBorder`/`NormalFloat`）。
2. **toggleterm 在 `open()` 里先 `ui.hl_term()` 覆盖 `winhighlight`、之后才调 `on_open`**（`lua/toggleterm/terminal.lua:504`，`ui.hl_term` 在它上面两行）⇒ 想改它的终端窗口，必须在 **`on_open`** 里补，光靠 `TermOpen` autocmd 会被盖掉。

### 23.3 实现（本机 `core/term_bg.lua`）

```lua
function M.apply(win)            -- 保留原有条目，追加三条映射
  local wh = vim.wo[win].winhighlight or ""
  local add = ("Normal:%s,NormalFloat:%s,NormalNC:%s"):format(HL, HL, HL)
  vim.wo[win].winhighlight = wh ~= "" and (wh .. "," .. add) or add
end
vim.api.nvim_create_autocmd({ "TermOpen", "ColorScheme" }, { ... })  -- 普通 :terminal + 换主题
```

- `TermSolidBg` 取 catppuccin 的 `base`（`#1e1e2e`，与 picker / 状态栏同色）；
- `core/init.lua` 里 `require("core.term_bg").setup()`；
- toggleterm 在 `terminal.lua` 的 setup 里加 `on_open = function(term) require("core.term_bg").apply(term.window) end`；
- sidekick 面板另有 `SidekickChat` 兜底（它自己从不定义那个组，见 §22.4）。

### 23.4 验证（真 pty + pyte 读**单元格背景属性**，能区分「显式背景」与「透明」）

| 位置 | 修前 | 修后 |
|---|---|---|
| toggleterm 浮窗 | `default`（透明） | `1e1e2e` 实底 ✓ |
| sidekick 面板 | 透出壁纸 | 实底（CLI 自己的 `1c1c1c` + 我们补的 `1e1e2e`）✓ |
| 普通编辑区 | `default` | 仍 `default`（透明，壁纸照旧）✓ |

> 方法记录：`pyte` 里 `screen.buffer[y][x].bg == "default"` 就代表该单元格没有显式背景（= 会透出壁纸），有颜色值就代表实底 —— 这比肉眼看截图可靠得多。

---

## 24. AI CLI（全屏 TUI）里「往上翻看输出」——备用屏幕 + sidekick scrollback（2026-09-25 用户提问）

> ⚠ **状态（2026-09-25 晚）**：本机按用户要求**重装干净** sidekick.nvim，§24.4 里的 `<M-u>` 与滚轮 → PageUp/PageDown 翻译**已从配置移除**（本节保留根因与手法作知识）；看历史改用 §24.6.1 的 `:GrokChat`。

### 24.1 症状

在 sidekick 面板里跑 codex / opencode：按 `jk` 回到普通模式后，`k` 和滚轮**都翻不上去**，看着像坏了。

### 24.2 根因：这些 CLI 跑在**备用屏幕**里

- codex / opencode 等是**全屏 TUI**，用终端的 **alternate screen**：历史输出**不进** nvim 的终端缓冲（`scrollback` 只对主屏有意义）⇒ 缓冲里永远只有当前一屏，当然翻不到东西。
- `jk` 只是我们配的「退出终端模式」（`<C-\><C-n>`），不是退出面板 —— 面板还在，只是 CLI 不再收键。

### 24.3 sidekick 的解法：scrollback

- 用 mux（tmux）`dump` 最近 **2000 行**（`cli.mux.dump`），另开一个**可翻可搜的终端缓冲**（`scrollback.lua`：`nvim_open_term` + 把 dump 文本喂进去）；
- 上游**默认只在你用鼠标滚轮滚过面板时**打开（`scrollback.lua` 里 `vim.on_key` 监听 `<ScrollWheelUp/Down>`/`<LeftMouse>`）；
- 前提 `scrollback.is_enabled()`：**有 mux parent**（`cli.mux.enabled = true`）**且**该工具没被标记 `native_scroll`。
  ⚠ **`opencode` 被上游标记 `native_scroll = true`**（`sk/cli/opencode.lua`）⇒ sidekick 不为它提供 scrollback，得用它自己的滚动键。codex / grok 没标记 ⇒ 可用。

### 24.4 本机增强：键盘开关 `<M-u>`

在 `plugins/sidekick.lua` 的 `cli.win.keys.scrollback` 里加了一个键（`mode = "nt"`）：

- 未打开 → `sb:update({ open = true })`，并 `stopinsert()` **直接进普通模式**（可以立刻 `j/k` 翻）；
- 已打开 → `sb:close()` 回实时 CLI；
- 另有自动关闭路径：在 scrollback 里按 `i` 进终端模式 → 内部 `TermEnter` → `update()` 判定 `mode == "t"` → 自动关闭并切回实时缓冲。

### 24.5 使用步骤与注意点（已实测）

1. 面板里按 `<M-u>` → 打开历史副本（tmux dump 最近 2000 行）+ 自动进普通模式；
2. `k`/`j`、`<C-u>`/`<C-d>`、`gg`/`G`、`/` 搜索；
3. 回实时：按 `i`（TermEnter → 内部 `update()` 自动关闭）或再按一次 `<M-u>`。

⚠ 注意点：历史是**打开那一刻的快照**（AI 新回复要重新按）；历史缓冲区继承了面板键位
（`terminal:keys(self.buf)`）⇒ **`q` 会隐藏整个面板**、`<C-b>`/`<C-f>` 会弹 picker，别拿它们翻页。

### 24.6 但不是所有 TUI 都能翻：备用屏幕（2026-09-25 用户实测补充）

用户跑 **grok** 时 `<M-u>` / 滚轮都「翻不动」。查证：

- `tmux display-message -p -t <会话> -F '#{alternate_on}'` = **1**（TUI 在备用屏幕）、`'#{history_size}'` = **0**；
- `tmux capture-pane -S -2000` 只抓到 **45 行（33 非空）**，就是当前一屏 ⇒ **终端里没有历史可翻**；
- 所以 sidekick 的 scrollback（靠 tmux dump）对这类工具**天然无效**；滚轮只会把空的终端缓冲滚上去（用户截图状态栏显示 `Bot 45:1` 即此现象）。

**正解：用 CLI 自己的滚动键**（grok 自带 pager，键位就在它的文档里，可从二进制抽出）：

| 键 | 作用 |
|---|---|
| `PageUp` / `PageDown` | 翻整页（看 AI 回复最常用） |
| `Ctrl+U` | 上半页 |
| `Ctrl+K` / `Ctrl+J` | 上一行 / 下一行 |
| `Ctrl+X` | 打开它自己的快捷键表 |

（本机配置在**终端模式**没有占用这些键，直接按即可。）

**本机实现：滚轮 → PageUp/PageDown 发进 pty**（`plugins/sidekick.lua` 的 `cli.win.keys.wheel_up/wheel_down`，`mode = "nt"`）：

```lua
local function pty_send(t, keys)                 -- ⚠ 必须定义在**文件顶层**
  local chan = t.job or (t.buf and vim.bo[t.buf].channel)
  if chan and chan > 0 then vim.api.nvim_chan_send(chan, keys) end
end
-- wheel_up = { "<ScrollWheelUp>", function(t) pty_send(t, "\x1b[5~") end, mode = "nt" }
```

两个坑（都真踩了）：

1. **不能用 sidekick 的 `t:send()`**：它走 `nvim_put` 模拟键入（`terminal.lua:328-345`），ESC 序列可能被 nvim 当成「退出终端模式」而不是转发给程序 ⇒ 必须 `nvim_chan_send(t.job, ...)` 直接写 pty（`t.job` = `vim.fn.jobstart` 的句柄，`terminal.lua:296`）。
2. **`pty_send` 必须定义在文件顶层**：`opts` 表里的闭包在 **spec 解析期**就建好了，定义在 `config` 里的话闭包捕获到的是 nil（运行时 `attempt to call a nil value`）。

验证：滚轮映射在**终端模式**下也会触发（实测 `fired mode=t`）⇒ 聊天时直接滚即可，不用先 `jk`；`nvim_chan_send` 的送达用 `touch` 文件验证过 ✓。

### 24.6.1 曾经的解法：`:GrokChat`（⚠ **2026-09-25 晚已按用户要求删除**，保留作知识）

既然面板里滚不动（TUI 备用屏幕 + nvim/tmux 两层拦鼠标），本机直接绕开 TUI：`core/grok_chat.lua`
把 `~/.grok/sessions/<cwd 的 URL 编码>/<最新 session>/chat_history.jsonl` 渲染成**只读 markdown 缓冲区**
（`:GrokChat [目录]`；原快捷键 `<leader>ah` 已按用户要求删除，现在只有命令）—— 普通缓冲区 ⇒ 滚轮、`j/k`、`/` 搜索、复制全都能用，打开即跳到最新一条回复。

实现要点：

- 会话目录名 = cwd 做 URL 编码（`/` → `%2F`、空格 → `%20`）：`vim.uri_encode(cwd, "rfc3986")` **不会**编码 `/`，得自己 `gsub`；
- `chat_history.jsonl` 每行一个 JSON，`type` ∈ `system|user|assistant|reasoning|tool_result`；`user` 的 `content` 是**数组**（`[{type="text",text=…}]`），`assistant` 是字符串 + `tool_calls`，`reasoning` 只有 `summary`；
- ⚠ **`s:sub(1, n)` 是按字节截断**，会把中文/emoji 切成半个字（显示成 `<e3><80>` 这种乱码）⇒ 必须 `vim.fn.strcharpart(s, 0, n)` 按字符截；
- ⚠ Lua 里 `tc.function` **是语法错误**（`function` 是关键字）⇒ 写 `tc["function"]`。

**另一条路（更好搜）**：grok 把完整对话写在磁盘上 ——
`~/.grok/sessions/<cwd 的 URL 编码>/<session-id>/chat_history.jsonl`（实测 349KB：system 1 / user 8 / reasoning 41 / assistant 42 / tool_result 63），用 nvim 打开即可 `/` 搜索、`gg/G` 翻。

### 24.7 验证（真 pty）

| 阶段 | `is_open` | mode | 光标 | 缓冲行数 |
|---|---|---|---|---|
| 打开面板后 | nil | `t` | 14/31 | 31（实时 CLI） |
| 按 `<M-u>` | **true** | **`n`** | 24/42 | 42（tmux dump） |
| 按 `gg` | true | `n` | **1/42** | 42 ← **翻到顶了** |
| 再按 `<M-u>` | **false** | `n` | 14/31 | 31（回到实时） |

### 24.6 附带知识（以后配 sidekick 会用到）

- `cli.win.keys` 是**深合并**（`config.lua:187` 的 `vim.tbl_deep_extend`）⇒ 加自定义键**不会**顶掉默认键（与 snacks 的 `win.keys` 整体替换语义**相反**）；
- 自定义键的值可以是函数，签名 `function(t)`，`t` 是该会话的 Terminal 对象（`t.scrollback` 就是它的 Scrollback 实例）；
- 想在别处手动开：`require("sidekick.cli.scrollback").scrollbacks[session_id]:update({ open = true })`，`session_id` 在 `vim.w[winid].sidekick_session_id`。

---

## 25. 「在 CLI 里换了主题，面板还是旧的」——会话是 tmux 保持的（2026-09-25 用户反馈）

### 25.1 症状

用户在自己的终端里换了主题 / 改了 CLI 的主题配置，进 nvim 重开 sidekick 面板 —— **还是旧主题**；感觉「关掉面板不会重新加载」。

### 25.2 根因：`cli.mux.enabled = true` 的会话保持

- CLI 跑在 **tmux 会话**里（本机为了 scrollback 与「关面板不丢上下文」特意开的）；
- `require("sidekick.cli").close()` 的实现是 **`State.detach`**（`cli/init.lua:154-160`）⇒ 只是**断开**，**进程继续活着**；
- 上游**没有 kill/stop API**（全仓搜不到 `kill-session`/`uv.kill`）⇒ 重开面板 = 接回同一个老进程；
- 而 CLI 只在**启动时**读一次自己的主题/配置文件 ⇒ 看到旧主题是必然的。

### 25.3 三种解法（本机选第 1 种）

| 方案 | 做法 | 代价 |
|---|---|---|
| **① 重启会话键（本机已加）** | `<leader>aR`：杀掉该会话的 tmux 会话 → 断开 → 用同一工具重开（= 全新进程，重读主题） | 无（保留 scrollback 与会话保持） |
| ② 手动结束进程 | 在 CLI 里退出，或 `tmux kill-session -t '<工具> <hash>'` | 要记命令 |
| ③ 关掉会话保持 | `cli.mux.enabled = false` ⇒ 关面板即结束 CLI，每次打开都是新进程 | ⚠ **scrollback 也没了**（`is_enabled` 要求有 mux parent 提供 `dump`） |

### 25.4 实现要点（`<leader>aR`）

```lua
local terminals = require("sidekick.cli.terminal").terminals   -- 按 session_id 索引
local sid = vim.w[vim.api.nvim_get_current_win()].sidekick_session_id
local t = (sid and terminals[sid]) or (next(terminals))          -- 面板没聚焦时取任意一个
local name = (t.id or ""):gsub("^terminal: ", "")               -- tmux 会话名 = "<工具> <hash>"
vim.fn.system({ "tmux", "kill-session", "-t", name })
require("sidekick.cli").close()
vim.defer_fn(function() require("sidekick.cli").show({ name = t.tool.name }) end, 150)
```

⚠ `require("sidekick.cli.state").get()` 不带参数时**取不到会话**（实测 nil）⇒ 别用它，用 `terminal.terminals`。

### 25.5 验证（真 pty）

| 阶段 | tmux 会话（名 + 创建时间） |
|---|---|
| 打开 codex 面板后 | `codex a478d02c666 created=1790335297`（用户自己的 `grok … created=1790333361`） |
| 按 `<leader>aR` 之后 | `codex a478d02c666 created=`**`1790335301`** ← **新进程**；grok 那个**没被动** ✓ |

> 注意：会话名由「工具 + cwd 哈希」决定 ⇒ 重启后**名字不变**，只能用 `#{session_created}` 或 PID 判断是否换了进程（第一次我用名字对比，误以为没生效）。

---
## 26. 全面审查新增边界发现（2026-09-25，未修复）

本节是**审查记录，不是修复完成声明**。完整证据、触发条件与限制见当时的配置审查报告
`NVIM_CONFIG_AUDIT_2026-09-25.md` —— ⚠ **该报告已于 2026-09-25 晚按用户要求从配置目录删除**
（15 条已修、2 条因 AI 插件功能删除而作废），需要原文时从 git 历史取回：
`git -C ~/.config/nvim show d3331c5:NVIM_CONFIG_AUDIT_2026-09-25.md`。修复摘要见本文件 §30 与台账 §47。

- **F01/F02 保存与范围**：退出自动保存也覆盖强制退出（隔离 q! 截获到写调用）；CJKPunctFix 只认 range==2，单地址 :2CJKPunctFix 会改全文，双地址 :2,2 才只改该行。不要在用户真实文件上复现。
- **F03 AI 重启目标**：编辑窗口没有 session id 时任取 terminal；kill/close/show 没有绑定同一对象。多会话时有错误中断风险，且未查终止返回码。此前 §25 的单目标成功验证不能证明多会话安全，也不能把重启代价记为“无”。本轮未执行真实 tmux kill。
- **F04/F11 项目历史**：写前比较与原截断写之间仍有 TOCTOU（真实 wrapper/writer + 内存 I/O 定序实验）。镜像过的记录可恢复，未镜像的仍有丢失窗口；副本先去重还会固定旧顺序，后续访问不能更新 MRU。此前并发测试通过不是全时序证明。
- **F05/F06 Java 生命周期**：started_bufs 重入取全局第一个 jdtls，跨项目可能错挂；客户端消失后直接 return 不重启。Java F5 走 dap.run 而非 continue，同名活动配置在当前 DAP 上游会 restart。均已隔离 stub 复现，无真实服务/调试进程。
- **F07 Java DAP 所有权**：当前 nvim-jdtls LspAttach → setup.add_commands 主动 require dap 并默认 setup_dap；后续本地 hotcodereplace=auto 被“adapter 已存在”早退吞掉。真实上游 _on_attach + 替身验证：attach 加载 DAP、BUILD_COMPLETE 无自动 redefineClasses。不能继续仅凭本地 require 延后声称完全按需加载；也不能误报 Jg/JG 必然缺 adapter。
- **F08 RPC 错误通道**：rpc_response_error 仅构造表；回调异常应 return nil,error_table。它与 §19 反对的裸 return nil（无 result 且无 error）不同。成功空值仍用 vim.NIL，reloadBundles 的空数组规则不变。
- **F09 ui.select 布局**：source=select 的专属 preset 覆盖全局 picker_compact；本地 wrapper 又替掉上游按条目数收缩高度的回调。真实 PTY 80/40 列 box.col=-3，120列三个选项 list.height=12。仅身份比较失败仍是 wrapper 的良性 health 提示，但几何问题不良性。
- **F10 选择语义**：J/K 移行正确，但字符/块选择两端列变1，Select 变 Visual。需保留列、方向、子模式，不要把个性化移行键本身当错误。
- **F12/F13/F14 向导**：selected 非数组分支调用未定义 finish，completed 已置位导致取消也不能恢复协程；相对 parent 在 chdir 后重复解析导致主类查找失效；RC1 被预发布正则漏判。契约异常/版本输入用替身验证，未联网生成工程。
- **F15/F16 入口与网络**：Mason tool installer 默认启动检查会 registry.refresh（本机缓存24小时），auto_update=false 不等于不联网；Sidekick 只有 keys 无 cmd 桩，冷启动 exists(':Sidekick')=0，文档直接命令不可达。

验证纪律：43 Lua 语法/StyLua 检查通过；健康与 TUI 使用隔离 XDG、-n/-i NONE、关闭自动安装及自动保存；未启动真实 LSP/DAP/AI 会话。修复时应新增正式回归测试并同步用户文档，不把此审查记录直接复制成“已经修好”。

---

## 27. 在 nvim 里就地读 Markdown：render-markdown.nvim 的选型、安装与验证（2026-09-25）

**需求**：用户「在 nvim 中看 md 文档」（本机 `~/md` 下有一批自己写的 md）。

**选型**（按「是否在 nvim 内」分三类）：

| 插件 | 星数 / 许可 | 形态 | 结论 |
|------|-------------|------|------|
| `MeanderingProgrammer/render-markdown.nvim` | 5105★ / MIT / 活跃（2026-09-15 仍有提交） | **缓冲区就地渲染**（extmark + conceal） | **选它**：无外部依赖、无浏览器；高亮组自动 link `@markup.*`，与 catppuccin / 透明背景都不打架 |
| `OXY2DEV/markview.nvim` | 3647★ / Apache-2.0 | 就地渲染 + 更多语法（LaTeX/Typst/HTML/Asciidoc） | 功能更多但更重，本机用不上 |
| `iamcco/markdown-preview.nvim` | ~6.6k★ | **浏览器**预览（需 node/yarn + 浏览器） | 用户明确要「在 nvim 中」，且本机网络不稳，不选 |

**前置条件**：treesitter 解析器 `markdown` + `markdown_inline`。本机已在
`~/.local/share/nvim/site/parser/`（`plugins/treesitter.lua` 里 `install_dir = stdpath("data").."/site"`）✓；
`nvim-web-devicons` 已有（代码块语言图标）。插件要求 Neovim ≥ 0.9（推荐 0.10+），本机 0.12.5 ✓。

**安装（关键：git 必须走代理）**：

```bash
https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890 GIT_TERMINAL_PROMPT=0 \
  nvim --headless "+Lazy! install render-markdown.nvim" +qa
```

- 直连 GitHub 时 `git clone` **卡在「正克隆到 …」无限挂起**（`git ls-remote` 也是静默无输出、exit 0）；
  `git -c http.version=HTTP/1.1` 也没救；**带 `https_proxy` 后 4.1s 克隆完成**（4590 objects）。
- 对照：`curl` 直连 `codeload.github.com` 是好的（0.55s / 200）——所以「能不能连 GitHub」必须用 **git 自己**测，
  别用 curl 的结果推断（这是对 §22「代理 clone」的精确化）。
- lazy 会自己写 `lazy-lock.json` 条目（本次 `render-markdown.nvim` = `640a3ec`），不需要手工造 git 快照。

**验证（headless 看不到渲染结果，必须两步）**：

1. headless 断言状态：

   ```lua
   vim.cmd("edit /path/to.md"); vim.wait(2000, function() return false end)
   require('render-markdown').get()                   -- true
   vim.wo.conceallevel                                 -- 3
   #vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, {})    -- 126（本机 nvim快捷键.md 实测；该 md 已于 2026-10-04 删除，复现时换任意含表格的 md）
   ```

   命名空间名是 `render-markdown.nvim`（点号，不是下划线）。
2. **真 pty 看画面**（唯一能证明「渲染真的生效」的方式）：

   ```bash
   python3 pty_size.py 120 40 'D:4.0' nvim ~/md/nvim/nvim快捷键.md > raw.bin
   # ⚠ nvim快捷键.md 已于 2026-10-04 删除：换任意 md 文件即可，结论与文件名无关
   /tmp/termvenv/bin/python dump_text.py raw.bin 120 40
   ```

   实测可见：`##`/`**` 被 conceal、表格变 `┌──┬──┐` 方框、`- ` 变图标、`---` 铺满整行、引用变 `▋`。
3. 截图给用户看时：`render_term.py` 用的 JetBrainsMono Nerd Font **没有中文字形**，中文会渲染成方块 ⇒
   用 CJK 版（宽字符走 `/usr/share/fonts/adobe-source-han-sans/SourceHanSansCN-Regular.otf`，
   用 `unicodedata.east_asian_width(ch) in ("W","F")` 判定）。脚本常驻副本：
   `~/backups/nvim-config-round28-20260925-2045/`（`render_term_cjk.py` + `pty_size.py` + `dump_text.py`）。

   ⚠ **探针 venv 建在 `/tmp`（tmpfs = 内存盘），重启或清理后就没了**，重建一行：
   ```bash
   python3 -m venv /tmp/termvenv && /tmp/termvenv/bin/pip -q install pyte pillow
   ```
   （2026-09-25 清理时删掉了那 40MB；脚本本身在 `~/backups` 里，永久保留。）

**本机配置**：`lua/plugins/render-markdown.lua`（约 22 行，**全上游默认值**，不做本地 hack）、
`ft = "markdown"` 懒加载；键位 `<leader>Mt`（切换）/ `<leader>Mp`（预览，实测在侧边开第二个 markdown 缓冲）；
**非 markdown 缓冲区**按 `<leader>Mt` 也能用 —— lazy 的 module 钩子会按需加载插件
（实测：按之前 `package.loaded["render-markdown"] == nil`，按之后为 true）。

**两个行为细节**：

- 光标所在行默认「反渲染」回源码（`anti_conceal.enabled = true`，上游默认）；纯阅读想关掉就设
  `anti_conceal = { enabled = false }`（已写进 `~/md/nvim` 文档）。
- 只渲染**可见范围**、`max_file_size = 10MB`，大文件不会卡。

---

## 28. 透明主题下「就地渲染 md 看着好怪」——换 markview.nvim 并关掉代码块整行底色（2026-09-25）

**症状**：装好 render-markdown.nvim 后用户发来整屏截图：「看着好怪，换一个插件吧」。

**定位（先看证据，别猜）**：把用户截图裁切放大 + 逐行采样像素，看到两层东西叠在一起：

1. **代码块整行底色**：采样到 `rgb(49,50,68)` = `#313244`（catppuccin surface0），横跨整行 —— 这是渲染器画的 `RenderMarkdownCode`（默认 link `ColorColumn`）背景；
2. **壁纸**：本机 `transparent_background = true`（`plugins/theme.lua`）+ Neovide `opacity = 0.80`（`lua/neovide.lua`），窗口里没有实底 ⇒ 底色块、文字、壁纸三层混在一起，文档变成"斑马带 + 脏色块"。

**关键结论**：**这不是某个插件的毛病，而是"透明窗口 + 渲染器画底色"的必然结果**。换插件不解决，改底色才解决。

**处置**：

1. 换成 `OXY2DEV/markview.nvim`（3647★、活跃；render-markdown.nvim 是 5105★）——用户要求换插件，且 markview 的表格是圆角框线、代码块语言标签在右上角，观感不同；
2. 关掉代码块底色（markview 支持）：

   ```lua
   opts = {
     markdown = {
       code_blocks = {
         default = { block_hl = "Normal", pad_hl = "Normal" },
         border_hl = "Normal",
       },
     },
   }
   ```

**验证手法（可复用）**：真 pty 抓屏 → pyte 逐格统计底色，判据是"有没有 `bg != default` 且跨度 > 60 列的整行"：

```python
import pyte, collections
s = pyte.Screen(120, 40)
pyte.Stream(s).feed(open('raw.bin','rb').read().decode('utf-8','replace'))
for y in range(38):
    cells = [s.buffer[y][x] for x in range(120)]
    nondef = sum(1 for c in cells if c.bg != 'default')
    print(y, nondef, collections.Counter(c.bg for c in cells).most_common(2))
```

实测（`~/md/linux/Btrfs快照与滚挂恢复流程.md`）：改前有 5 处整行色块（`2d2d42`，代码块）；改后 **0 处**，只剩：

- 标题那一行 `2e2a38`（markview 上游默认：`MarkviewHeading* → MarkviewPalette*` 自带底色，保留当分节标记）；
- 行内代码的小色块 `34344b`（宽度只有几十列，不是整行）。

**其他可选路线**（当时给用户列的）：`glow`（本机已装 3.0.0）浮动窗口 / `markdown-preview.nvim` 浏览器预览 —— 都是"实底页面"，从根上避开透明混合；代价是离开缓冲区或离开 nvim。上游 `ellisonleao/glow.nvim` **已归档（2025-03）**，要用得自己写包装。

---

## 29. Markdown 预览「四连换」：render-markdown → markview → markdown-preview → md-render（2026-09-25）

> 历史记录：2026-10-04 用户明确改选“直接美化编辑区”，现已换回无整块背景的 render-markdown.nvim，见 §37。下面保留当时反馈，不作为当前预览方式的限制。

用户一句话一路推进：**「在 nvim 中看 md 文档」→「看着好怪，换一个插件吧」→「感觉终端渲染 md 好像不是很行？」→「再换一个插件看看」**。
四个插件各留一条可复用的结论：

| # | 插件 | 结果 | 关键事实 |
|---|------|------|----------|
| 1 | `MeanderingProgrammer/render-markdown.nvim`（5105★） | 装好、渲染正确，**用户："看着好怪"** | 就地渲染；代码块默认 `width='full'` 整行底色（`#313244`）+ 透明主题（`transparent_background` + Neovide `opacity=0.80`）= 一条条"斑马带" |
| 2 | `OXY2DEV/markview.nvim`（3647★ 活跃） | 关掉代码块底色后干净了，**用户仍不满意** | 默认同样画底色（代码块 `2d2d42`、标题 `2e2a38`，实测整行 114 列）；`code_blocks.default.block_hl = "Normal"` 可去掉。**换插件解决不了"透明 + 画底色"这个根因** |
| 3 | `iamcco/markdown-preview.nvim`（8006★，2024 停更） | 能跑，浏览器里是 GitHub 风格（截图验证过） | ① 需要下载 45MB 预编译二进制；② **`app/install.sh` 必须直连**：它先调 GitHub API 取 tag，走本机代理会命中共享出口的 **API rate limit**（直连正常）；③ 预览地址是 `http://localhost:<port>/page/1`（**不是 `/`**，`/` 返回 404） |
| 4 | `delphinus/md-render.nvim`（215★，MIT，当天有提交） | **留下这个** | 渲染到**独立浮动窗/标签页/分屏/pager**，**编辑缓冲区原样不动**；纯 Lua 无外部依赖；要求 nvim ≥ 0.12（`nvim_ui_send`）；中文有禁则处理 + BudouX 断句；图片/视频/Mermaid 需 Kitty 图形协议（Neovide 不支持 ⇒ 自动降级） |

**沉淀下来的判断**：

1. **"就地渲染"这类（render-markdown / markview）本质上会改编辑视图**（conceal 掉 `#`/`**`、插图标、画底色），对"既要读又要改"的人不友好；透明主题下更是必然"花"。
2. 想在终端里要"文档感"，要么**独立窗口**（md-render），要么**实底页面**（浏览器/glow）——不要试图靠调底色去救就地渲染。
3. 换插件前先量一次：**pyte 逐格统计 `bg != default` 的整行跨度**（见 §28），比"看着怪"这种描述精确得多。

**验证手法**：
- 终端内渲染 → 真 pty（`pty_size.py`）+ pyte dump + `render_term_cjk.py` 出图（中文字形要用思源黑体兜底）；
- 浏览器预览 → 起服务后用 **Playwright MCP** 打开 `http://localhost:<port>/page/1` 截图（页面标题能确认内容是否送达）；
- md-render → headless 里按 `<leader>Mp` 前后比较 `package.loaded["md-render"]` 与窗口数（实测 false→true、窗口 +1）。

**卸载要三件套**：删 spec + `:Lazy! clean <name>` + 手工 `rm -rf ~/.local/share/nvim/lazy/<name>`（`:Lazy! clean` 有时只清 lock 条目，目录会留下）。

---

## 30. 按第三方审查报告批量修复 15 条：可复用的六个手法（2026-09-25）

工作目录下的 `NVIM_CONFIG_AUDIT_2026-09-25.md`（17 条：P1×5 / P2×11 / P3×1 组）逐条复核后全修
（该报告随后已按用户要求删除；原文取回：`git -C ~/.config/nvim show d3331c5:NVIM_CONFIG_AUDIT_2026-09-25.md`）。
**先复核再动手**：6 条真机/真 PTY 实测复现 + 9 条源码交叉核对，**没有误报**（AI 插件相关的 F03/F16 因功能已删除而跳过）。

### 30.1 六个可复用手法

1. **想识别 `:q!` 只能靠 CmdlineLeave**：`QuitPre`/`VimLeavePre` 里 `v:cmdbang` 恒为 0、`getcmdline()` 为空
   （实测），`v:exiting` 对 `:q` 与 `:q!` 都是 0。真 pty 里手打命令时 **`CmdlineLeave` 能拿到 `"q!"`** ⇒
   用它记录"放弃退出"状态。⚠ 状态要**粘住整条退出链**（QuitPre → BufLeave → VimLeavePre），
   只在 `CmdlineEnter`（开始敲下一条命令）时复位；只挡 QuitPre 会被 BufLeave 的保存绕过。
2. **Lua 的 `local function` 声明顺序会静默毁掉回调**：把 `vim.api.nvim_create_autocmd` 写在
   `local function f` **之前**，闭包里的 `f` 解析成**全局 nil** ⇒ 回调报错/静默失效。
   本轮就因此让 F01 的修复"看起来生效其实没有"。定义要么前移，要么先 `local f` 前向声明。
3. **"检查后写"必有竞态，改成"只追加"**：项目历史守卫上一版是"先读盘判断会不会丢，不会丢才截断重写"，
   读与写之间没有跨实例锁 ⇒ 别人在这个间隙追加的条目被抹掉。修法是**永不截断**（只 append 缺的），
   把去重/并集放到读取侧。
4. **上游的"早退守卫"会吃掉你的配置**：`jdtls.dap.setup_dap` 有 `if dap.adapters.java then return end`，
   而上游 attach 钩子已经用默认参数注册过 ⇒ 想改成 `hotcodereplace="auto"` 必须先
   `dap.adapters.java = nil` 再注册。验证方式：比较 `dap.listeners.before['event_hotcodereplace']['jdtls']`
   的函数引用是否被替换（实测会变）。
5. **找"谁调用了这个函数"用 traceback 打桩**：把 `M._on_attach` 换成写 traceback 到文件的包装，
   立刻看清链路是 `nvim-jdtls/plugin/jdtls.lua` 的 LspAttach 钩子（而不是我们以为的 start_or_attach）。
   比读源码猜快得多。
6. **验证客户端生命周期用 `stop_client` + 重新触发 FileType**：`vim.lsp.stop_client(c.id, true)` 后
   等 `get_clients() == 0`，再 `:edit!` 触发 FileType，看是否**重新起一个同 root 的 client**
   （实测 id=1 → 空 → id=3）——这比读代码更能证明"客户端没了会重启"。

### 30.2 本轮修的问题（细节见台账 §47）

| 编号 | 一句话 |
|---|---|
| F01 | `:q!`/`:qa!`/`:cq` 尊重放弃语义（CmdlineLeave + 粘住状态） |
| F02 | `:2CJKPunctFix` 单地址不再改全文（`cmd.range > 0`） |
| F04 | 项目历史写守卫改成"只追加、永不截断" |
| F05 | Java 重附加按 root 挑客户端；没有存活客户端就重启 |
| F06 | Java `<F5>` 有会话时 = 继续，不是重启 |
| F07 | 更正"DAP 按需加载"的说法；摘掉旧适配器再注册 hotcodereplace=auto |
| F08 | LSP handler 异常必须 `return nil, err`（单返回值会被当成功 result） |
| F09 | `vim.ui.select` 显式用紧凑预设 + 自己按条目数算高度 |
| F10 | 可视 J/K 保留两端的列与 Select 子模式 |
| F11 | 项目列表合并改"最后出现者更新位置" |
| F12 | 向导契约错误分支不再调未定义的 `finish()` |
| F13 | 向导父目录立刻转绝对路径 |
| F14 | `is_prerelease` 覆盖 RC |
| F15 | Mason `run_on_start = false`（启动不联网） |
| F17 | 配置/文档 7 处说明漂移 |

---

## 31. nvim 终端里的 TUI「只有 2 个主题」——`:terminal` 不设 COLORTERM（2026-09-25）

**症状**（用户）：在 sidekick 的 AI CLI 面板里打开 grok 的主题选择器**只有两个主题**，但在自己的终端里跑 grok 主题更多。

**定位**：`strings ~/.grok/bin/grok` 直接给出规则 —— grok 有 5 个主题，
其中 **TokyoNight / RosePineMoon / OscuraMidnight 标注 "Truecolor Required: Yes"**，
二进制里写着 "the theme picker **hides** them on non-truecolor terminals"。
再用 `grok doctor` 对照两种环境：

| 环境 | `grok doctor` |
|---|---|
| `TERM=xterm-256color`、无 `COLORTERM`（**nvim `:terminal` 的默认**） | `color 256` · `themes 2/5: groknight, grokday` · 提示 `export COLORTERM=truecolor` |
| 加 `COLORTERM=truecolor` | `color truecolor` · `themes all` |

nvim 自己的终端模拟器（以及 Neovide）支持 24 位色，但它**不给子进程设 `COLORTERM`**（实测
`:term echo $COLORTERM $TERM` → `truecolor`(修复后) / `xterm-256color`）。

**修法**（`core/options.lua`）：

```lua
if (vim.env.COLORTERM or "") == "" then
  vim.env.COLORTERM = "truecolor"
end
```

**端到端验证**（真 pty，注意先 `env -u NO_COLOR`，否则 grok 会报 "Colors are off because NO_COLOR is set"）：

```bash
python3 pty_size.py 110 40 'D:4.0|S::term grok doctor\r|D:9.0' nvim   # 修复后: color truecolor / themes all
# 对照：:term env -u COLORTERM grok doctor → color 256 / themes 2/5
```

**顺带**：这条不只影响 grok —— opencode 等任何按 `COLORTERM` 判定色深的 TUI 在 nvim 终端里
都会降级成 256 色。⚠ 例外：如果 nvim 跑在真正的 16 色控制台（`TERM=linux`）里，冒充真彩色
只会让颜色被终端近似，不会崩；本机是 Neovide，无此问题。


### 30.3 探针纪律补遗：**用真实配置跑 pty 探针会污染 shada**（2026-09-25 清理时发现）

本轮为了验证 `:q!`、`vim.ui.select` 几何、`grok doctor` 等，直接用**真实配置**在 pty 里跑 nvim，
结果每个实例退出时都把 shada（`~/.local/state/nvim/shada/main.shada`）重写了一遍：

- `:` 命令历史里混进了 `term grok doctor` / `lua vim.ui.select(...)` / `luafile /home/pang/tmp/...` 等 20 条；
- 文件标记 `'1`–`'9` 指向已删除的 `/home/pang/tmp/fix/*.txt`；
- `:oldfiles`（`Snacks.picker.recent()` 的数据源）8 条里 7 条是探针临时文件；
- shada 体积从 94KB 掉到 11KB（寄存器/跳转列表被探针实例的空状态覆盖）。

**规矩**：探针会话要么加 `-i NONE`（禁用 ShaDa），要么把整个状态目录隔离：

```bash
XDG_STATE_HOME=/tmp/probe-state XDG_DATA_HOME=/tmp/probe-data nvim ...
```

（审查报告 §2.2 早就写了这条纪律，我这次只在"危险操作"上遵守了，普通验证偷懒用了真实配置 ⇒ 踩坑。）

**清理脚本**（可复跑，已存 `~/backups/nvim-config-cleanup-20260925-2250/clean-nvim-state.lua`）：
清文件标记 + `histdel(':', '\V<前缀>')` + 过滤 `vim.v.oldfiles`（`v:oldfiles` **可写**，赋值后
`wshada!` 落盘 —— 注意 `:wshada` 不带 bang 时实测不落盘）。

⚠ **运行中的 nvim 会把内存里的旧状态再写回**：清理必须在用户会话退出**之后**再做一遍，
否则 `:oldfiles` 里的探针路径会被它带回来。

---

## 32. 两个用户实报的「显示层」问题：诊断在普通模式下不显示、Java 代码颜色跳变（2026-09-26）

### 32.1 症状 A：有些位置的红色报错不显示了，但 `]d` 仍能跳到它

**根因是 runtime 时序，不是配置写错。** `vim.diagnostic.config({ update_in_insert = false })` 时
`vim.diagnostic.show()` 的顺序是 **先 `M.hide()` 再判断模式**：

- `runtime/lua/vim/diagnostic.lua:2381` 无条件 `M.hide(namespace, bufnr)`；
- `:2394-2398` 之后才看 `nvim_get_mode()`，在插入模式里只 `schedule_display()` 然后 `return`；
- 排期只挂在 `{ 'InsertLeave', 'CursorHoldI' }`（`:854`）。

⇒ 插入模式中收到 `publishDiagnostics`：**显示类 extmark（signs / underline / virtual_text / virtual_lines）
全被清掉**，数据却留在 `diagnostic_cache` ⇒ `]d` / `vim.diagnostic.get()` 照常工作、屏幕上却没有红色。
正常出口（`<Esc>`）由 InsertLeave 补渲染；**但 `<C-c>` 退出插入模式不触发 `InsertLeave`**
（`:h i_CTRL-C`，autocmd.txt:828-830 「But not for |i_CTRL-C|」）⇒ 那批诊断一直不可见，
直到「下一次在普通模式下收到 publish」。jdtls 一次改动常发两次 publish，第二次落在普通模式就自己好了
—— 这正是用户说的「有时候」。`CursorHoldI` 兜不住：它在插入模式里只会再排期、不渲染。

**修法（`core/options.lua`）**：补一条 `ModeChanged`（pattern `i*:n*`）autocmd，逐个「窗口可见 buffer」
调 `vim.diagnostic.show(nil, bufnr)`。实测 `<Esc>` / `<C-c>` / `<C-[>` / `<C-@>` / `<C-\\><C-n>` /
`<Cmd>stopinsert<CR>` / better-escape `jk` 全部触发 `i*:n*`；插入模式中仍保持隐藏（`update_in_insert`
语义不变）。**逐窗口而不是 `show(nil, nil)`**：20 buffer×30 诊断实测全量 10.9ms、单窗口 0.2-0.6ms；
也不能只用 `show(nil, 0)`（多窗口时另一个窗口的 buffer 会漏）。

**可复用手法**：headless 里 `vim.api.nvim_input("i")` **真能进入插入模式**（`nvim_get_mode()` 返回 i），
所以「插入模式 → 发布诊断 → 各种方式退出」这类时序问题**不需要 pty**，`vim.defer_fn` 链分步驱动即可。
⚠ 探针的步骤队列不要同时用「预排 run」和「回调里 run」两套驱动，否则步骤会乱序消费（本轮踩过：
wait_for 还没回调，预排的 run 已经把后面的步骤弹掉了）。

### 32.2 症状 B：写 Java 时代码颜色变来变去

**根因是两层 LSP 高亮，优先级都高于 treesitter**（ts=100 / semantic_tokens=125 / diagnostics=150-152）：

1. **语义 token**：nvim 0.12 会自动启用服务器支持的全部 capability（`runtime/lua/vim/lsp/client.lua:1187-1198`
   遍历 `vim.lsp._capability.all`；`semantic_tokens` 全局默认 true）⇒ jdtls 的 `@lsp.type.*` 一直开着。
   catppuccin 把绝大多数 `@lsp.type.*` 链回同名 treesitter 组（颜色恰好相同），**唯一不同色的是
   `@lsp.type.property` → `@property`（lavender #b4befe）盖掉全大写常量的 `@constant.java`（teal #94e2d5）**。
   jdtls 的 token 每次编辑后 60~230ms 才到 ⇒ 刚敲下的常量先显 treesitter 色、再跳 LSP 色。
2. **tag 诊断**：带 `unnecessary` tag 的诊断（jdtls 的未使用字段/局部变量/import）会被额外叠一层
   `DiagnosticUnnecessary`（`diagnostic.lua:1832-1856`），而 `runtime/colors/vim.lua:137` 把它 link 到
   `Comment` ⇒ **整段文字**染灰 #9399b2 + 斜体；jdtls 每次编辑后重新发布 ⇒ 刚写的字段变灰再变回来。

⚠ **被证伪的假设**：不是「语义 token 每次编辑先清空再重打」。51 次编辑里
`nvim.lsp.semantic_tokens:<client>` 的 extmark 数恒为 207（新写常量涨到 224），**一次都没归零**。
别把「颜色跳」直接归因于 clear→reapply，先量 extmark 时间序列。

**修法**：
- `lang/java.lua`：`java_on_attach` 里 `vim.lsp.semantic_tokens.enable(false, { bufnr = bufnr })`
  （按 buffer 关；buffer 级标记 `vim.b[bufnr]._lsp_enabled_semantic_tokens=false` 能让**之后**才 attach 的
  spring-boot LS 也不启用 —— 只把 jdtls 的 `semanticTokensProvider` 置 nil 挡不住它）。
  附带收益：`lsp.log` 里 `-32801 Document changed` 由每次运行 6~10 条降到 0。
- `theme.lua`：`colorscheme` 之后 `vim.api.nvim_set_hl(0, "DiagnosticUnnecessary", {})`（+ `ColorScheme` autocmd）。
  文字保持 treesitter 原色，tag 诊断仍有常规严重级别下划线；`DiagnosticDeprecated` 实测只有 `sp`+删除线、
  不染字色，不用动。⚠ 清空的是**文字颜色**，不是诊断本身。

**验证**：真 jdtls + 50ms 采样「有效前景色」（按 priority 折叠所有高亮源，取最高优先级的 fg）。
修复前同一标识符 1 秒内 teal→lavender→灰；修复后只由 treesitter（稳定）+ 诊断下划线决定。

**顺带确认**：0.12 里 codelens / folding_range / inlay_hint 在本机 `is_enabled(bufnr)` 都是 false，不是贡献者；
spring-boot LS 虽声明 `semanticTokensProvider` 但每次都回空（extmark 恒 0）。

---

## 33. 让「输入框」和「命令行框」等长等高：两个浮窗插件的尺寸口径（2026-09-26）

**用户诉求**（截图）：① 文件树里新建文件的输入框贴着屏幕顶部，要放低；② 命令行框太短，要跟上面那个输入框一样长。

### 33.1 三个必须先量清楚的量（别靠肉眼量像素）

真 pty 起 nvim，然后**直接查窗口配置**：

```lua
for _, win in ipairs(vim.api.nvim_list_wins()) do
  local cfg = vim.api.nvim_win_get_config(win)          -- relative/row/col/width/height/title
  local pos = vim.api.nvim_win_get_position(win)        -- 注意：对带边框的浮窗这是**边框行**
  -- 浮窗用 cfg.relative ~= "" 判定；buffer 的 filetype 认身份（snacks_input / noice）
end
```

⚠ **但配置值只能当参考，必须再用 `screenstring()` 读一次真实屏幕帧**（同一会话里就能读，
不用外部截图工具）：

```lua
for r = 1, vim.o.lines do
  local t = {}
  for c = 1, vim.o.columns do t[#t+1] = vim.fn.screenstring(r, c) end
  io.write(string.format("%2d|%s|\n", r, table.concat(t)))
end
```

本轮就是靠它发现"以为对齐了、其实差一行"（见 §33.2 的 ⚠）。

实测（114×30，本机真实配置；行号是屏幕 1 基行）：

| 框 | 来源 | 改前 | 改后 |
|---|---|---|---|
| 新建文件输入框 | `vim.ui.input` → snacks.input | 顶边框在第 3 行（`row=2`），宽 84 | 顶边框在第 14 行，宽 82/84 |
| 命令行 | noice `cmdline_popup`（`:命令`） | 顶边框第 14 行、宽 44 | 顶边框第 14 行、宽 82 |

### 33.2 两条口径差异（改之前必须知道的算术）

- **宽度不是一回事**：`snacks.win.width` 是**内容宽**，边框画在窗口之外 ⇒ 总宽 = width + 2；
  noice 弹窗的 `size.min_width` 也是内容宽，但外面还有 `border.padding`(1+1) + `border`(1+1)
  ⇒ 总宽 = min_width + **4**。**等长条件：`min_width = width − 2`**。
- **垂直位置**：`` **两边配置里的 row 都是「边框行」（0 基）** ``，所以一个公式就重合：
  noice `position.row = "50%"` 落在 `floor((lines − 3) / 2)`（弹窗 3 行 = 边框/内容/边框，它的第 1 行
  缓冲内容就是边框）；snacks 的 `win.row` 同理 —— 配 13 ⇒ 屏幕第 14 行是 `╭`、15 行是内容、16 行是 `╰`。
  ⇒ `center_row() = floor((lines − 3) / 2)`。
  ⚠️ **坑**：别拿 `nvim_win_get_position` 跟 noice 内部那个**无边框**的输入子窗比 —— 前者返回边框行、
  后者返回内容行，会正好差一行。本轮第一版写成 `floor((lines − 1) / 2)`（内容行口径），
  屏幕帧一看是 15/16/17 行 vs 命令行 14/15/16 行。

### 33.3 两个 API 限制（决定了实现形态）

1. `snacks.win` 的 `row` / `width` **支持函数**（`snacks/win.lua:1281` 的 `size()`：`type(s)=="function" and s(self)`），
   在**开窗时**求值 ⇒ 可以按 `vim.o.lines` 算位置；
2. noice 的 `min_width` **只能是数字**（`noice/util/nui.lua:158` 的 `minmax` 直接参与 `math.max`），
   而且 `noice.config.options` 是 `VimEnter` 之后才赋值的（`noice/init.lua` 的 `load()`），
   ⇒ 运行时改 min_width 有先后序问题，**别做**，用常量 + 注释写清窄屏取舍。

落地：新增 `core/input_boxes.lua` 当唯一事实源（`width = 80` / `noice_min_width = 78` / `center_row()`），
`plugins/snacks.lua` 的 `input.win` 与 `plugins/noice.lua` 的两个 `cmdline_*` 视图都从它取。

### 33.4 探针坑（这次踩到）

- **headless 测不到**：snacks 是在 **UIEnter** 才把 `vim.ui.input` 换成自己的（headless 没有 UIEnter），
  必须真 pty；`debug.getinfo(vim.ui.input, "S").short_src` 可以一行确认当前提供者是谁。
- **别在一个会话里连续测两个框**：`nvim_input("<Esc>")` **没有**关掉 snacks 输入框（两次实测都还挂着），
  于是紧接着的 `:` 被打进输入框、相位互相污染（第二次的"命令行框消失"就是这么来的假象）。
  对策：每个相位结束按 filetype 强制 `nvim_win_close(win, true)`，或分成两次 pty 运行。
- snacks 输入框默认 `expand = true`：`width = max(win.width, 文本宽 + 5)`，所以**预填长默认值**（新建文件时
  的目录前缀）会比设定值多撑几列 —— 对比"等长"时要挑同一个场景比。

### 33.5 验证结果（screenstring 读真实屏幕）

| 屏 | 输入框（顶边框行 / 列范围 / 总宽） | 命令行（顶边框行 / 列范围 / 总宽） | 结论 |
|---|---|---|---|
| 114×30 | 14 / 17–98 / 82（短默认值）<br>14 / 16–99 / 84（预填 77 字符路径，expand 撑宽） | 14 / 17–98 / 82 | 顶边框·内容·底边框都在 14/15/16 行；短默认值时**逐列相同**（17–98） |
| 100×40 | 19 / 10–91 / 82 | 19 / 10–91 / 82 | 同上，逐列相同 |

窄屏：总宽 82 ⇒ ≥86 列完整；80~85 列两个框一起贴边（等长的必然代价，取舍写在模块注释里）。

宽度的取舍写在 `core/input_boxes.lua` 注释里：想让 80 列也完整就把 `M.width` 降到 76，
**两边一起改**（只改一边会让两个框又不一样长）。

---

## 34. 32/33 两项修复的独立复验 + 三个探针新坑（2026-09-27）

用户在会话导出后要求「继续处理问题，没有问题了就清理」，于 2026-09-27 用**另写的一套探针**重跑复验
（不是复用 32/33 的脚本），结论全部通过；顺手踩到三个新坑，都属于"探针自己骗自己"的类型：

### 34.1 三个新坑

- **`screenstring()` 在 0.12.5 只吃 2 个参数**：传第三参 `len` 直接 `E118: 函数 screenstring 的参数过多`。
  它在 `vim.schedule_wrap` 回调里被调用 ⇒ 报错被 schedule 吞掉，屏幕上看不到，只留下
  **"文件里只有帧头、没有行内容"** 的假象（第一次跑就是这样，41 行全是帧头）。要整行就读：
  逐列 `screenstring(row, col)` 拼接（只取关心的 7 行 × 114 列，开销可忽略）。
- **回调里报错会连带丢掉已写内容**：stdio 缓冲，`f:close()` 到不了 ⇒ 之前 `f:write` 的内容一起没。
  探针一律 **先在 `pcall` 里组装完整字符串、再一次性 write+close**，失败也要落一行 `FRAME-ERROR: ...`。
- **`vim.lsp.semantic_tokens.is_enabled()`（0.12.5）收的是 filter 表**：正确写法
  `is_enabled({ bufnr = bufnr })`；传裸 bufnr 会在 `_capability.lua:198` 报
  `filter: expected table, got number`（笔记里旧的 `is_enabled(bufnr)` 只适用于别的 capability 入口）。
- **headless 里 `-c 'luafile X'` 中的 uv timer 不会跑**：`--headless` 且 stdin 是管道时，`-c` 执行完
  nvim 立即退出（`sleep 5 | nvim …` 也留不住），timer / `defer_fn` 一个都不触发；`vim.wait` 又不消费
  typeahead（§14）⇒ 会看到"mode 一直是 n、诊断一直没显示"的假象。**分步探针一律上真 pty**：
  `vim.uv.new_timer()` 每 400~450ms 跑一步、结果写文件，driver 轮询文件里的 `DONE` 再收尾。

### 34.2 复验证据（114×30 / 真 pty；jdtls 探针用 /tmp 里的一次性最小工程）

| 项 | 复验方法与结果 |
|---|---|
| 诊断 `<C-c>` 出口（§32.1） | 真 pty：插入模式中发布 → 显示类 extmark **0**（洞原样复现）→ `<C-c>` 后 **4**（signs/underline/virtual_text\|lines/location）；**再临时摘掉 `UserDiagnosticInsertLeaveFallback` 重跑同一路径，又是 0** ⇒ 因果闭环（不是别的东西顺手救回来的）；`<Esc>` 出口 = 4，未回归 |
| Java 语义高亮（§32.2） | 真 jdtls 端到端 **100 帧**：jdtls#1 与 spring-boot#2 **都**声明 `semanticTokensProvider`（`st=true`），但 `is_enabled({bufnr})` 恒 **false**、`vim.b._lsp_enabled_semantic_tokens` 恒 false、语义 token extmark **恒 0**；`GREETING` 的 `inspect_pos` 只有 treesitter 组（`@variable.java,@variable.member.java,@constant.java`），`st=[-]` |
| 两个输入框对齐（§33） | 两轮独立 pty：snacks 输入框 `ft=snacks_input rel=editor w=80 pos={13,16}` ⇒ 屏幕第 **14/15/16** 行、17–98 列（总宽 82）；noice 命令行框同样 14/15/16 行、17–98 列 ⇒ 逐列相同 |
| 无回归 | `checkhealth` 与 `git worktree` 出来的 HEAD 干净副本逐行 diff **零差异**（35 条全是环境项：magick/gs/tectonic/mmdc 缺失、headless 无 UIEnter 导致的 `vim.ui.input` 未接管等）；`stylua --check` 通过 |

### 34.3 清理（同一轮的收尾动作）

- 进程：按 `-data .../jdtls-workspace/javaproj-*` 精确 PID 清掉探针的 jdtls/spring-boot LS，
  复核**只剩用户自己的 jdtls + spring-boot LS**（PPID= 用户 nvim），PPID=1 的孤儿为 0。
- 文件：陈旧 swap（目标已删除的 `%home%pang%tmp%ut%d.txt.swp`）、31 条指向已消失临时路径的 undo 条目、
  探针的 jdtls 工作区、`/tmp` 探针目录与 git worktree 全清；`project_nvim` 历史复核 18 行、无 `/tmp`。
- **只清"探针/临时"**：undo 里 18 条指向用户自己已删工程文件（feed-java 重构掉的文件、rust 练习）的条目**原样保留**。
- 修复本身已落库（仓库按「一个主题一个 commit」）：`ab4d7e3` 显示层两项（诊断兜底 + Java 语义高亮/诊断 tag）、
  `4df4ef2` 输入框与命令行框等长等高；之后工作区干净、`stylua --check` 通过。取回细节：
  `git show ab4d7e3` / `git show 4df4ef2`。

## 35. <leader>sr 从「盲跑」改成「认主类」：双进程项目的启动参数与终端槽（2026-10-02）

用户的项目 ~/Projects/Feed stream/feed-java 是**双进程**（ApiApplication + WorkerApplication），
每次都得手敲 ./mvnw spring-boot:run -Dmain.class=io.github.p_feed.WorkerApplication。
本轮把 <leader>sr 改成：扫 src/main/java 下的 main 入口 → 只有一个直接启动、多个弹选择框，
每个主类固定一个终端槽。下面四条结论都用 /tmp 里的一次性 Boot 4.0.8 工程实测（不碰用户项目）。

### 35.1 主类参数：三个坑连着

- **多 main + 不给参数 = 直接失败**：报错原文
  Unable to find a single main class from the following candidates [p2.B, p1.A]。
  这正是"双进程项目盲跑"的现象，也是这次改动的动机。
- **-Dspring-boot.run.main-class= 能不能用，取决于 pom 有没有自己写 <mainClass>**：
  4.0.8 的 plugin.xml 里**一个 <property> 标签都没有**（spring-boot.run.* 只出现在参数说明文字里），
  属性是靠 mojo 的 configuration 默认值表达式接的：
  <mainClass implementation="java.lang.String">${spring-boot.run.main-class}</mainClass>（plugin.xml:1581），
  spring-boot-starter-parent 的 pluginManagement 里也写着同一句 ⇒ 项目 pom **不写** <mainClass> 时它生效。
  但项目 pom 一旦自己写了 <mainClass>${main.class}</mainClass>，**显式 configuration 盖过它**：
  实测同一句 -Dspring-boot.run.main-class=p2.B 仍然跑出 RAN-A（pom 里 main.class 默认 p1.A）。
  ⇒ core/java_main.lua 先看 pom 的 <mainClass> 是不是 ${某属性}：是就用那个属性名（feed-java 走 -Dmain.class=），
  不是才回退到 spring-boot.run.main-class。
- **没被 pom 覆盖的 spring-boot.run.* 属性依旧可用**：-Dspring-boot.run.arguments=HELLO,WORLD 实测把参数传给了 main
  （文档里"端口被占就换端口跑"的写法在 Boot 4 仍成立）。

### 35.2 终端槽：exec 同 id 是复用，不是新开

toggleterm 的 exec(cmd, num, ...) → Terminal:new({id=num})，而 Terminal:new 在 id 已占用时**直接返回旧终端**
（terminal.lua:203）；M.get(id) 还会把 hidden（被 <leader>th 关掉的）终端当成不存在。
后果：双进程都挤终端 2 时，第二次启动的命令行会被 term:send() **写进正在运行的进程的 stdin** ——
屏幕上能看见命令回显，但什么都没发生。修法两条：
① 每个主类固定一个槽（2,4,5,6,7,8,9；3 留给 <leader>tv）；
② 复用槽之前先 vim.fn.chansend(job_id, string.char(3))（Ctrl-C）；查终端必须 get(id, true)，
   否则 hidden 终端查不到、这一发 Ctrl-C 漏掉。
顺带得到一个符合直觉的语义：**同一个类连按两次 = 重启**。

### 35.3 证据（用户真配置 + 真 maven，headless 驱动）

| 断言 | 实测结果 |
|---|---|
| <leader>sr 的 desc | Spring Boot: 运行（自动识别主类，多个则选择） |
| 选第 2 项 (p2.B) | 终端 **4** 出现 RAN-B，命令行含 -Dmain.class=p2.B；此刻终端 2 还没被创建 |
| 选第 1 项 (p1.A) | 终端 **2** 出现 RAN-A，命令行含 -Dmain.class=p1.A，**终端 4 的 RAN-B 输出还在**（互不干扰） |
| 再启动同一个类 | 终端数量不变（仍 2、4 两个），新进程 SLEEPY-UP 3535304，旧进程打出 shutdown hook SLEEPY-DOWN 3534887 ⇒ Ctrl-C 确实优雅停掉了旧进程 |
| 选择框文案 | "A  p1  [终端 2]  ← pom 默认" / "B  p2  [终端 4]" |
| 扫描/参数解析单测 | 19 条 headless 断言全过（含无空格 main 写法、写死字面量、空项目、mainLoop 不误判） |

⚠ 驱动 headless 时踩到一条**测试写法**的坑（真实用法不受影响）：<leader>sr 是 Java 缓冲区的 buffer-local 映射，
而 toggleterm.exec 会把当前缓冲区切成终端 ⇒ 第二次调用前必须把当前缓冲区切回 Java，否则既拿不到映射、
project_root() 也会因为当前是终端缓冲区而找不到项目根。

### 35.4 落地文件

- 新增 lua/core/java_main.lua（纯逻辑：scan / main_flag / default_main / run_args）
- lua/plugins/lang/java.lua：<leader>sr 改走 spring_boot_run_pick；抽出 detect_tool / ensure_exec 给 run_build 复用
- 同步 core/cheatsheet.lua、~/md/nvim/nvim快捷键.md、~/md/nvim/构建SpringBoot项目实操指南.md
  （后两份 md 已于 2026-10-04 被用户删除；这类改动的同步目标现在只有 `core/cheatsheet.lua` 与 `~/md/nvim/nvim配置架构.md`）
  （那份文档原来写"多入口项目用 spring-boot.run.main-class"，对写了 ${main.class} 的 pom 是错的，已改）

### 35.5 2026-10-03 复验 + 三项增强（用户报「启动两个不行」）

用户报「启动两个不行」。拿**真实项目的一份副本**（rsync 到 /tmp，避开他正在跑的 jdtls 工作区）在 tmux 里
真按键跑完整流程，结论是**功能本身没坏**：选择框列出 Api/Worker → 选 Api，终端 2 出
`Started ApiApplication in 3.09 seconds` + Tomcat 8081；再按 <leader>sr 选 Worker（Down + Enter），
终端 4 出 `Started WorkerApplication in 2.873 seconds` + `mq enabled` + 消费线程 `[mer-like-events]`，
两个进程同时在跑（8081 一直在听）；最后用启动器同款的 Ctrl-C（`chansend(job_id, "\3")`）停掉，
两边都是 `SpringShutdownHook` → `HikariPool-1 - Shutdown completed`、8081 释放。

那"不行"从哪来？最可能是这两个交互坑（都能复现）：

- **第二次又选了默认项**：选择框第一项就是 API（带 `← pom 默认`），回车即"重启 API"——我们会先
  Ctrl-C 再起，看起来就像"两个没起来"。
- **启动后在终端里再按 <leader>sr**：映射是 Java 缓冲区 buffer-local 的，终端里按下去只是把 ` sr`
  当输入送进应用（Spring Boot 不读 stdin），屏幕上自然"没反应"。

于是加了三样（都在 `plugins/lang/java.lua`）：

1. `slot_busy(slot)`：读 `/proc/<shell_pid>/task/<shell_pid>/children` 判空 —— toggleterm 的终端是
   常驻 shell，`job_id` 永远活着，光看它没用。实测：终端 2 的 shell 1419632 children=`1419633`、
   Worker 的 shell 1423302 children=`1423307`，应用停掉后 children 为空。
2. 选择框里给已在跑的入口标 **● 已在跑**，末尾加 **▶ 全部启动**（≥2 入口才出现）。
3. 「全部启动」= 依次起：等前一个终端出现 `Started <类名>`（或失败字样，或 60 秒兜底）再起下一个
   —— 两个 maven 同时编译同一个 `target/` 会打架；已经在跑的入口**跳过**（想重启就单独选它）。
   顺带：只有槽真的忙才发 Ctrl-C，空槽不再多一行 `^C`。

headless 复验（一次性双入口工程：p1.Api / p2.Worker 各打印 `Started X in 0.1 seconds` 后长睡）：

| 断言 | 结果 |
|---|---|
| 选「全部启动」 | 槽 2 出 `Started Api`、槽 4 出 `Started Worker`（第二个确实是等第一个起来之后才起的） |
| 第二次打开选择框 | `Api  p1  [终端 2]  ← pom 默认  ● 已在跑` / `Worker  p2  [终端 4]  ● 已在跑` / `▶ 全部启动  依次启动上面 2 个入口，每个占一个终端` |
| 再点一次「全部启动」 | 两个 `Started …` 计数都还是 1 ⇒ 已在跑的跳过、没有被重启 |
| 收尾 Ctrl-C | 槽 2 出现 `^C`，进程退出 |

**顺带记一条操作纪律（这次自己踩了）**：把 `pgrep -f '<pattern>' | while read p; do kill $p; done` 写在
一行 bash 里时，pattern 会匹配到**执行这条命令的 bash 自己**（它的 cmdline 里就含 pattern）⇒ 清理脚本
把自己杀了、后面的命令全没跑（症状：输出只到 `kill jdtls 1451936` 就断）。要么写成脚本文件再
`bash 脚本`（cmdline 只有脚本路径），要么 `pgrep` 后排除 `$$`。项目 `.ai/WORKING.md` 第 213 行
记的也是同一个坑（当时是 `pkill -f spring-boot:run` 把自己的 bash 杀了）。

---

## 36. grep 布局残留旧节点与配置职责整理（2026-10-04）

**症状**：内容搜索在 80×24 和 160×50 终端中均只剩 1 行结果，预览窗口跑出主框。

**根因**：用 `vim.tbl_deep_extend` 把 select 单列布局合并成双列；带数字键的子节点被逐项合并，左栏残留 `win="input", height=1`，旧的第三个 preview 也被保留。只遍历顶层 list 的高度修正无法命中嵌套列表。

**修法**：`plugins/snacks.lua` 独立构造整棵 grep 布局，不继承 select 数字节点；≥120 列左右分栏，否则上下排列。配置回调按终端尺寸计算内容宽高，为边框、隔线留预算；上游 VimResized 重新调用它。普通 picker / ui.select 保持紧凑布局和原键位。

**本轮真实 PTY 回归**（宽×高，单位：字符格）：

| 终端 | 列表 | 预览 |
|---|---|---|
| 60×18 | 48×5 | 48×5 |
| 80×24 | 64×7 | 64×8 |
| 120×30 | 48×20 | 47×22 |
| 160×50 | 64×34 | 63×36 |

另验证 160×50 → 80×24 真实缩放、无重复 input/list/preview 节点、子窗不越界、普通文件 picker 无预览、三项 ui.select 收缩为三行、选择和输入取消回调。输入取消需用 `win:execute("cancel")` 或真实按键；直接 `win:close()` 只关窗口，不等于执行取消动作，不能据此误报回调丢失。

**整理后的归属**：`core/diagnostics.lua` 管诊断与 LSP 日志，由 core/init 调用 setup；`core/projects.lua` 管历史与 :Projects，由 commands 调用 setup；`core/ui.lua` 管 soft/pink 共享高亮和 PickerSkin，由 snacks 调用 setup。向导仍管理会话内临时高亮与动画。

改前/改后行为快照一致（选项、全局映射、插件触发器、DAP、格式化、诊断格式及 soft/pink 色值）。原、新项目逻辑均在隔离临时目录验证并集、顺序、只追加、历史恢复、重复注册与含空格路径，不动用户真实历史；四层保护保留。

**说明修正**：:R 只执行当前磁盘 Lua，不清 require 缓存、不保证重设插件，插件配置保存后应重启；Conform fallback 在没有可用 CLI formatter 且有格式化 LSP 时生效，CLI 执行失败并非自动回退。相关说明同步到现存四篇用户文档。

---

## 37. Markdown 改为编辑区美化（2026-10-04）

用户不喜欢 md-render.nvim，并在选择框明确选择“直接美化编辑区”；历史 §29 的独立预览取舍不再是当前要求。

当前使用 MeanderingProgrammer/render-markdown.nvim，配置 `lua/plugins/markdown.lua`：Markdown FileType/RenderMarkdown 命令懒加载，复用现有 Treesitter 和 web-devicons，Catppuccin 开 render_markdown 集成。标题 backgrounds={}；代码 style=language、disable_background=true、inline=false、width=block、border=none、highlight_border=false，禁 sign，避免透明主题上的整行色带；LaTeX 暂关，不额外安装转换工具。

n/c 模式渲染，i/v 回源码；光标行 anti_conceal。`<leader>Mp` 调用 buf_toggle，仅当前文档；旧 Mt/Ms/MdRender 移除。插件 enable/disable/toggle 是全局操作，buf_* 才是当前缓冲区。

80×36、120×40 的实际 PTY 验证：打开 Markdown 自动加载，在原窗口出现 31 个渲染标记；插入/可视模式及关闭时标记为0、conceallevel恢复0，返回普通模式或启用后恢复31。窗口始终为1；光标移到一级标题能看到原始 #；切换一份文档不影响另一份；源文件内容和 modified 标记不变；检测到整行背景色带为0。render-markdown 健康检查通过（8.14.0）。

只更新锁文件中的旧 md-render / 新 render-markdown 两项；旧配置及下载目录移到 `/tmp/nvim-markdown-Zq2vdU/` 的 retired-*，同目录另有本轮开始时的完整配置/文档/旧插件备份。前一轮诊断、项目、UI 整理保持不变。现存四篇用户文档、速查和架构同步完成。临时备份会随系统清理而过期；新旧插件也可从各自上游恢复。

---

## 38. Java 测试定位、终端归属和跨项目调试（2026-10-04）

用户确认修复三项审计发现；不改 JDK 选择，不改业务项目，不新增插件。

### 38.1 测试方法不再向上猜

旧 `<leader>Jt` 用“两行拼接＋向上扫描”：多行参数或 `@Test void beta()` 同行注解时仍会跑上面的 alpha。现在 [java_test.lua](</home/pang/.config/nvim/lua/core/java_test.lua>) 使用 Java Treesitter 的包含关系及 name 字段；支持注解、throws、多行参数、成员内部类（`$` 二进制名），完整 selector 用 shellescape。缺解析器、错误方法、方法间空白、匿名类和局部类均拒绝，不能恢复猜测兜底。局部类不仅存在于方法内，也存在于 static/实例初始化块：只接受直接挂在 program/类体的类声明，避免把数字编号的局部类当成员类。

### 38.2 终端必须有项目和用途归属

旧构建/测试固定 2 号，Spring 槽为 2/4/5…9 按扫描下标取模；不仅与测试碰撞，超过 7 个入口、不同项目同名类、扫描顺序改变都会串终端。现在 [java_terminals.lua](</home/pang/.config/nvim/lua/core/java_terminals.lua>) 按真实项目路径＋用途＋主类持有对象，从 4 起避开现有（含 hidden）及本模块已预留编号，保留通用 1/2/3。复用前验证对象身份，不抢其它终端；构建忙时只提示，应用重启先 Ctrl-C 等 shell 空闲（10 秒上限）。每次显式 cd 到捕获的项目根。

“窗口关闭”和“shell 退出”必须区分：toggleterm close_on_exit=false 会保留已退出 shell 的缓冲区，而 open() 只在缓冲区无效时 spawn。用 jobwait(...,0) 检查退出，旧输出保留、后续分配新对象；open/send 失败清除启动标记。只读取本次 on_stdout（64KB 上限）判断 Started，不能扫历史启动输出。通知/选择框显示编号，重开用 `:<编号>ToggleTerm`（如 `:4ToggleTerm`），th 仍只是通用 2 号。

### 38.3 调试只查询当前客户端

旧 F5 复用全局 dap.configurations.java；上游 setup_dap_main_class_configs 只合并主类，重扫不能清掉其它项目。上游 fetch_main_configs 虽捕获 bufnr，但 util.execute_command 在 detach 后可回退到其它 jdtls，且部分错误路径永不回调。现在 [java_debug.lua](</home/pang/.config/nvim/lua/core/java_debug.lua>) 直接向捕获的 client:request 发同样的四类查询，保留精确 LSP root 为 cwd（适配器据此选客户端），错误/15 秒超时统一返回。Java 键位用请求代次、缓冲区名及 client id/root 守卫淘汰过期结果，空列表最多尝试 4 次；不读写全局 DAP 主类表。已有会话 F5 仍 continue；Jd 只报告当前项目主类数量。手动输入兜底也捕获原项目，取消/空输入不运行。

### 38.4 验证与同步

回归脚本留在配置的 [tests](</home/pang/.config/nvim/tests>)：Java 解析器＋模拟接口验证，真实 toggleterm 临时 shell 验证（含 exit 后保留缓冲区），两个临时 Eclipse Java 工程真实 jdtls 查询验证。运行说明在 [配置架构](</home/pang/md/nvim/nvim配置架构.md>) 的“Java 回归检查”。测试隔离 XDG，所有自建终端和客户端在脚本收尾停止；不启动业务 main。速查、语言 LSP 注释、现存用户文档及技能架构同步；原工作区隔离、Lombok、Spring executeClientCommand 转发、Java 手动格式化约定保持不变。

---

## 39. Which-key 区分通用、跨语言能力与专用菜单（2026-10-04）

用户询问哪些功能通用，随后确认优化菜单说明。只改 [whichkey.lua](</home/pang/.config/nvim/lua/plugins/whichkey.lua>) 的 group/desc，不改实际按键：通用、LSP、DAP、Java、Spring、Markdown、Neovide 前缀；o/R 明确标 Java。group 描述覆盖 n/v，已有普通模式单项 e/j/q/F 的虚拟描述仍只注册 n，避免可视模式出现虚假入口。

两点需要保留：① which-key 的 cond 在 mappings.add 注册时求值后被清除，不是每次弹窗判断，因此不能用它按当前 filetype 隐藏后就期待切文件自动恢复。② 空分组已有 tree.fix 按真实子项收起，无需新建文件类型白名单；sp、Java 生成等全局入口虽然用途专用，仍要在其它文件中可见。

[whichkey_scopes.lua](</home/pang/.config/nvim/tests/whichkey_scopes.lua>) 使用真实 which-key 和代表性映射验证多文件类型、普通/可视模式及映射前后不变；不启动语言服务。速查图例、现存用户文档和技能架构同步。

---

## 40. 整理与重构采用跨语言入口，保留 Java 增强（2026-10-04）

用户计划学习 Go/Rust/C/C++，确认新增通用 Ra、扩展 ot，保留 Java 的直接提取键。本轮是功能扩展，不是 §39 的单纯菜单改名。

实测补充：gopls 0.23.0 的 source.organizeImports 可用；rust-analyzer 0.3.3008 与 clangd 22.1.6 未声明/返回该标准整理动作，ot 提示无动作并保持代码不动。Ra 在 Java/Go/Rust/C/C++ 均返回相应重构候选。Rust 必须等项目索引完成：仅 initialized=true 时可能得到 ContentModified 或空重构列表；实服测试用 experimental.serverStatus 的 quiescent 判断就绪，对 ContentModified 做有界测试重试（生产入口仍沿用原生行为）。测试中的 clangd 强制 stop(true) 会产生“Got signal, shutting down / exit 1”的收尾噪音，不是运行故障；正常收尾改用 stop()，3 秒内未退出才强停。

[language_actions.lua](</home/pang/.config/nvim/lua/core/language_actions.lua>) 集中入口，共享 LSP on_attach 在语言缓冲区绑定 Ra（n/x）和 ot（n）；不因初始化静态 capability 缺失而漏绑键。Ra 使用原生 code_action，context.only={"refactor"}、apply=false；ot 在 Java 有当前缓冲区 jdtls 时保留 organize_imports，其余只请求 source.organizeImports，单个动作直接执行、多个时选择。Java 局部 ot 与共享 on_attach 使用同一函数，避免后附加的客户端覆盖成不同语义；Rv/Rc/Rm/RV 的实现保持原样，描述显式标 Java。菜单 o/R 改成“整理/重构 · 按语言”。

不重写 Neovim 的代码操作执行层：本机原生实现会按 kind 和点分隔子类再次过滤，保留选区/编码、codeAction/resolve、WorkspaceEdit、客户端命令与 disabled reason 的处理。拒绝按显示标题猜测、拒绝用整文件格式化或任意 quickfix 代替整理。无客户端时中文提示；无匹配动作时原生提示 No code actions available。Ra 即便只有一个结果也要确认；矩形选区拒绝，字符/整行选区交给原生转换。

[language_actions.lua 测试](</home/pang/.config/nvim/tests/language_actions.lua>) 以真实原生 code_action 加模拟传输验证过滤、单/多动作、取消、disabled、resolve/命令及选区；[菜单测试](</home/pang/.config/nvim/tests/whichkey_scopes.lua>) 覆盖 Java/Go/Rust/C/C++/Lua/Markdown/文本。[Java 实服测试](</home/pang/.config/nvim/tests/java_jdtls_smoke.lua>) 在两个隔离工程里确认 ot 删除未使用 import、保留使用中的 import，Ra 返回 refactor 候选且取消不改代码。全部只用临时项目，不操作用户业务代码。

---

## 41. 整体审查后的退出保护与 Mason 启动策略修复（2026-10-05）

审查复现三项：silent q!/qui!/ZQ 将本应放弃的修改写盘；分屏 q! 后 discard_pending 粘住；mason-lspconfig 启动 setup 仍刷新注册表。用户授权修复并提交。

- [autocmds.lua](</home/pang/.config/nvim/lua/core/autocmds.lua>)：用 nvim_parse_cmd 处理修饰符、计数与合法缩写；quitall 与 qall 是不同的规范命令名，均须支持。CmdlineLeave 仅处理冒号命令并忽略 abort；按 QuitPre 顺序消费直接退出命令（q! 后的普通 q 不能仍跳过保存）；cquit 没有 QuitPre，单独在 VimLeavePre 处理。WinClosed 解除已关闭窗口对剩余会话的保存抑制，SafeState 清理无效/完成命令残留。不能直接用 vim.schedule 清理：其它退出自动命令的 vim.wait 会提前执行它。
- ZQ 由 [keymaps.lua](</home/pang/.config/nvim/lua/core/keymaps.lua>) 调用 quit_without_save；同步保护范围到 quit! 返回或抛错后才解除。只关当前窗口，不改 ZZ/wq!/x! 的保存语义。程序化或 execute 间接退出不靠猜字符串，需显式调用此 API；normal! ZQ 会绕过映射。
- [mason-lspconfig.lua](</home/pang/.config/nvim/lua/plugins/mason-lspconfig.lua>) 独立为命令加载的 spec，移出启动依赖。ensure_installed={} 防止手动装一个又顺带装整组；原 LSP 清单以 Mason 包名迁入 [mason-tool-installer.lua](</home/pang/.config/nvim/lua/plugins/mason-tool-installer.lua>)，关闭其 mason-lspconfig 集成（否则它的 require 会把插件拖回启动）。不全局关 registry.refresh，保留手动安装/更新能力。

验证：[autosave.lua 测试](</home/pang/.config/nvim/tests/autosave.lua>) 的 31 个独立用例在最小环境及完整配置通过（含丢弃/普通退出、计数/修饰符、命令链、取消、分屏恢复、yielding QuitPre、失败清理）。[install_policy.lua](</home/pang/.config/nvim/tests/install_policy.lua>) 完整启动前拦截刷新/安装/卸载，模拟 GUI 和工具缺失，确认启动刷新/包写入为 0，手动批量及 LSP 命令仍可刷新/映射包名；未实际下载/删除工具。QuitPre 自动命令抛错不保证取消退出，测试失败分支要显式模拟 quit 函数抛错，不能用该误假设判断结果。

---

## 42. 用户报「leader + g 和其他键位没有了」：菜单是完整的，`<leader>g` 从不存在（2026-10-07）

用户贴出 Java 缓冲区里的 which-key 弹窗截图（22 项），问「这里的 leader + g + 其他的键位没有了」。**结论：没有丢键，也没有被移除过**（当天用户当场答复「我记错了」，属误报；以后遇到同类报障，先按本节的三步判定法验一遍再动手改配置）。

- 截图里的 22 项 = [whichkey.lua](</home/pang/.config/nvim/lua/plugins/whichkey.lua>) spec 里**全部** 22 个 leader 前缀（单项 e/F/j/q + 分组 a/b/c/d/f/h/r/s/t/u/v/w/G/J/m/M/o/R），一项不多、一项不少。
- `git grep -n '<leader>g' $(git rev-list --all)`（85 个提交）**零命中** ⇒ 本配置里从来没有过 `<leader>g`；配置目录也没有被忽略/未跟踪的键位文件（`git status --ignored` 干净、磁盘上的 lua 文件与已跟踪清单完全一致）。
- 真机 pty 实测（python `pty.fork` 起 `nvim -n`，不经 tmux）：`<leader>`、`g`、`z`、`[`、`]`、`<C-w>` 六个触发器**全部正常弹窗**；其中 `g` 是**独立前缀**（40+ 项：gg/gd/gi/gR/gr*/gA/gu…），本来就不该出现在 leader 弹窗里 —— 「g 相关的键」走的是不带 leader 的 `g` 前缀。
- 关键判据：**which-key 会把没有真实映射的空组自动收起**（[tests/whichkey_scopes.lua](</home/pang/.config/nvim/tests/whichkey_scopes.lua>) 对此有断言）。截图里能看见需要 jdtls 的 `<leader>c/r/o/R/J/m` ⇒ 那批 buffer-local 键当时**全都注册上了**；它们是「再按一个键才展开」，不是「没有」。

**同类历史（记忆里的 g 键多半来自旧文档）**：老 `~/md/nvim/nvim快捷键.md` 写过从未实现的 `<leader>fd`（搜索 `~/md`），2026-09-30 才从文档删除；`gU`（跳父类/接口实现）为让位内置大写转换改成了 `gA`（2026-09-25）。

**可复用的「菜单缺项」判定法**：① 配置侧拿 spec 里的 group 前缀，与 `vim.api.nvim_get_keymap` 的真实 lhs 求并集/差集 —— 差集才是「写了没生效」；② 真机侧用 pty 真按键，剥掉 ANSI 后抓 `+xxx` 分组标题与条目文本对照（本次脚本：`pty.fork` + `select` 读 + 正则剥 ANSI，起真配置、逐前缀发键、每步重开缓冲抓增量）；③ **看得见组名 ⇒ 下面确实有键**；反过来「没看见某项」要先区分是没定义还是被自动收起。

---

## 43. Java / Spring 按职责重构与单文件隔离（2026-10-14）

用户确认保留功能和主要键位后实施。只改 Java/Spring、本机速查、测试和对应文档；已有 Neovide 修改与业务工程不动。改前[备份](</home/pang/.local/state/nvim/java-refactor-20261014-172205.tar.gz>)包含配置与文档。

### 43.1 结构与必须保留的边界

插件声明保持简短，逻辑集中在[core/java](</home/pang/.config/nvim/lua/core/java/>)：init 管 JDTLS/键位；project 管根和构建；files 管单源码运行与四模板；syntax 共用包名/main/测试解析；debug 管固定客户端查询；spring 管启动计划；terminal 管归属；ui 管 Java 多选。旧 java_main/java_test/java_debug/java_terminals 的当前对应位置分别为 spring/syntax/debug/terminal，不再维护两套模块。

- 单文件根不能回落到启动 Neovim 时的 cwd；有包时用源码包根。JavaRun/Jr 明确保存、临时 javac、真实终端 stdin，退出清理产物。项目依赖与项目 JDK 仍走 F5/构建工具。
- nvim-jdtls 的 start_or_attach 已委托原生 vim.lsp.start，可通过 reuse_client 严格比较 root，同时覆盖重复 FileType、重载重附加及停服重启，不再保留另一个 started_bufs 缓存。
- §19/§30 的 executeClientCommand 修复仍必需；异常返回必须是 nil,error，不是一个“看起来像错误”的成功 result。Java/Spring 共享这条 handler。DAP client/buffer/root 与过时回调保护、终端用途/主类归属不能因精简删掉。
- 主类与测试位置统一语法树，避免注释/字符串假 main、嵌套类归错文件名。POM 一次解析主类属性，所有 shell 参数统一引用；写死其它主类和 Gradle 多入口不再“选 A 跑默认 B”。

### 43.2 两个现场问题

旧 elmcgill 插件 setup 除编译外，还注册全局 JavaPackageDetails。已有空算法文件在非 src 目录读入时，get_java_package 返回 nil，拼接 package_location 抛错（安装版 init.lua:121），隔离内存测试已复现。去掉插件声明，模板用一份安全实现；保存编译仅针对已附加的项目 Java 缓冲区。下载目录未卸载。

本机 PATH 中已无旧说明的 spring/mvn/gradle。构建优先 wrapper、再 PATH 和已有 wrapper 缓存；不改项目执行位。Lombok 回落到 Mason jdtls 随附 jar。向导直接调用[Initializr](<https://start.spring.io>)；Gradle Kotlin DSL 的 type 是 gradle-project-kotlin，不是 gradle-project。下载、ZIP 校验、解包有超时；私有暂存完成后无覆盖发布，同名目标与恶意 ZIP 拒绝。

真实 PTY 又发现向导的局部 keys 从默认表复制后覆盖了全局 Esc：默认 Esc 只有普通模式，第一次 Esc 只退出输入，向导仍挂着。显式补 Esc 的 n/i 映射后，一次取消通过。Java 列表空格必须调用 list:select()；actions 没有可直接引用的 select 动作。

### 43.3 验证方式

保留并扩展原回归：[Java 配置测试](</home/pang/.config/nvim/tests/java_config.lua>)、[工作流测试](</home/pang/.config/nvim/tests/java_workflows.lua>)、[源码运行](</home/pang/.config/nvim/tests/java_files_smoke.lua>)、[完整 Java 配置](</home/pang/.config/nvim/tests/java_runtime_smoke.lua>)、[Spring 运行](</home/pang/.config/nvim/tests/spring_runtime_smoke.lua>)、[向导纯测试](</home/pang/.config/nvim/tests/spring_wizard.lua>)、[真实按键](</home/pang/.config/nvim/tests/java_ui_smoke.py>)。

已实测：单文件真实 stdin，F5 在指定行停下并读到输入变量 41，继续输出 42；同名主类跨目录隔离，edit! 重附加不重复启动；Spring 的 Lombok getter、Bean/端点/属性补全，随机端口 HTTP 返回 ok，终端 JUnit 与 JUnit DAP 指定测试行断点。真实 PTY 走 sp/Enter 到依赖步骤、Tab、Esc、缩放，再测 Java 预选/Tab/Enter/Esc/空格，无 Lua/UI 错误。向导另实际生成 Maven/Java 与 Gradle Kotlin/Kotlin 模板，验证 HTTP400、恶意 ZIP、同名发布竞态，不运行用户工程。

所有真实测试使用独立 XDG_DATA/STATE/CACHE，仅复用已安装工具；服务与终端只收尾本轮创建的对象。不能用仅 initialized 或纯 mock 通过来代替运行/断点/真实键盘验收；运行步骤见[用户架构](</home/pang/md/nvim/nvim配置架构.md>)。

---

## 44. 每种语言独立目录与唯一声明来源（2026-10-14）

用户指出语言配置仍散落，明确要求“每种语言一个文件夹，便于扩展”。在已验证 Java/Spring 精简结果上继续迁移，没有回退上一轮功能。

[注册表](</home/pang/.config/nvim/lua/languages/init.lua>)显式登记 19 个语言目录；每个入口统一声明 lsp、工具、树解析器、格式化、局部选项、命令、键位和 dap。共有 on_attach/actions、clangd、codelldb 进入共享目录。Java 的 Spring 服务、运行、向导完整归入 Java 子目录。公共插件只消费声明，旧插件语言目录、core Java/向导/文件类型/语言动作全部删除；Lua :R 和 Markdown Mp 也由对应语言拥有。

### 44.1 结构约束

普通/自管 LSP 不可重复，同名共享配置只能一致；调试配置必须有显式适配器依赖，命令和按键不可重复。注册不加载重实现/插件/进程，配置工厂在消费时执行；加载失败不得缓存半份语言表。M.setup 重入不重复注册。C/C++/Rust 各自声明共享 codelldb，不再靠 C++ 配置先加载；适配器采用 DAP 标准 callback/config 函数，不是零参配置工厂。

Java organize_imports 的专属 guard 进入 Java 入口的 actions.java.organize_imports；共享动作通过注册表调用增强，没有增强则使用标准 LSP。不允许在 core 或公共插件重新夹入 Java 分支。

### 44.2 验证

迁移前后配置快照：LSP、20 个工具、24 个解析器、格式化、高亮/缩进、文件类型、语言键和调试启动/附加配置一致。唯一有意的初始化变化是 lazydev 不再随公共 LSP 提前加载；Java/Spring/DAP/Markdown 仍不在空白启动时加载。无界面相同隔离环境 7 次进程启动，后 6 次中位数 52.43→48.02 ms；不将小样本当作保证提速。

[结构回归](</home/pang/.config/nvim/tests/languages.lua>)通过 132 项；[18 语言声明测试](</home/pang/.config/nvim/tests/language_definitions.lua>)通过 306 项；[Java 声明](</home/pang/.config/nvim/tests/java_declaration.lua>)通过 64 项。声明测试阻止 eager vim/plugin/process 调用、检查反向加载与共享依赖。注意 nvim_get_autocmds 会把多 pattern 展开多条记录，幂等性应比较前后内容，不能错误地要求只有一行。

Java/Spring 全部原回归与真实按键重新通过；Go/Rust/C/C++ 真实共享动作通过；四门语言新的适配器各实际编译无依赖程序、命中指定行、读取 value=41 并继续退出（24 项）。禁止启动时刷新/安装的策略测试仍为 0 次写入。所有实服用临时目录与隔离 XDG，不操作用户业务。归属与扩展规范在[语言 README](</home/pang/.config/nvim/lua/languages/README.md>)；本轮[工作树备份](</home/pang/.local/state/nvim/language-folders-20261014-190810.tar.gz>)包含上一轮未提交配置。

---

## 45. 整体配置去重与 virtual-text 请求监听参数（2026-10-14）

本轮保留功能、外观、主要快捷键与已验证语言目录。项目实现收拢到[项目目录](</home/pang/.config/nvim/lua/core/projects/>)，共享界面到[UI 目录](</home/pang/.config/nvim/lua/core/ui/>)；不为小插件再建框架。18 组 DAP/终端/Sidekick 键壳与实际绑定合为单份 keys，项目最长根计算与树刷新实现共用，历史四层只追加保护不变。

- 非语言运行 Lua：3727→3169 行；整行注释559→61，空白269→251。先对36个只删说明的文件做剥离调试信息后的 LuaJIT 字节码一致性检查，再做行为重构；语言 Lua 文件与本轮前备份逐字一致。目录拆分不是代码减量，新增测试不计入运行配置。
- 真实 Go 调试结束阶段曾出现 virtual-text 的 pairs(nil) 异步错误，原测试虽然退出0仍不算通过。现场锁定 nvim-dap cfa2d58、virtual-text fbdb48c：DAP 请求监听参数是 session,err,response，virtual-text 的 after.stackTrace 却把第二参数当 body。错误对象没有 stackFrames 会崩；成功时 err=nil 又会跳过全栈请求。
- [协议测试](</home/pang/.config/nvim/tests/dap_listener.lua>)在本轮前配置确定性复现两种错误，不依赖偶发时序；[DAP 配置](</home/pang/.config/nvim/lua/plugins/dap/init.lua>)只适配这一处回调，跳过错误/空响应并把有效 response 传给旧实现，不关闭 all_frames。随后 C/C++/Rust/Go 28 项真实断点/变量/退出检查无异步错误，Java23项、Spring30项重新通过。升级插件后检查是否仍需该适配。
- 真实通用 UI 78 项通过，覆盖四种宽高、grep resize、输入/取消、项目/文件树、分屏关闭、UTF-8 输入和终端1/2/3。Snacks 输入框原本就是 Esc 退出插入再 Esc 取消，不可按选择器的一次Esc契约误改配置。PTY按键与RPC不是同一队列，切文件前必须等模式就绪；不同轮测试使用独立历史或唯一搜索词。
- 全局选项、全模式映射、插件集合、皮肤样本、DAP定义前后相同；CJKPunctFix 的默认范围元数据由 . 改为 %，原生范围测试确认使用行为不变。Noice 自动生成的互斥路由顺序和初始化阶段 Lua runtimepath 连重复旧基线都不同，不能把这些顺序差异冒充回归；具体继承/默认项变更仍结合真实 UI/Lua API验证。
- 12轮交错启动各剔除前2次，无界面进程预热中位52.92→53.61ms；约0.69ms差异处于本次样本波动范围，不宣称重构显著提速。LSP、Spring和弃用API健康检查通过；lazy仅提示隔离环境空的site/pack/core，已确认无插件文件。

当前维护规则已在[架构](</home/pang/md/nvim/nvim配置架构.md>)替换旧结论，不再追加互相矛盾的做法。完整配置/文档备份：[config-refactor](</home/pang/.local/state/nvim/config-refactor-20261014-223932.tar.gz>)。

## 46. 项目列表的框太小（2026-10-15）

用户报「项目列表（`:Projects` / 启动页 p）这个框太小」。原因不是 bug，而是[项目列表](</home/pang/.config/nvim/lua/core/projects/picker.lua>)一直沿用共享的 `picker_compact` 预设：宽 55%、高 40%，尺寸只跟窗口走。PTY 实测（140×55）列表只有 44×16。

修复只改尺寸：宽 `max(clamp(columns*0.8, 160, columns-4), 内容宽)`、高 `clamp(lines*0.6, 8, lines-4)`，仍复用同一预设的 config（`height` 走数字分支）。同窗口实测 44×16 → **110×29**（整框 20 → 33 行）；80×24 → 64×10（整框 14 行）；60×18 → 48×6（整框 10 行），小屏不会溢出。其它 picker 与 `vim.ui.select` 保持原紧凑尺寸。

两点值得留下的事实：

- Neovim 侧本身不慢：整表重绘 0.5 ms、光标移动 0.02–0.07 ms、打开 14–23 ms。若仍觉得卡，只可能是 Neovide 渲染侧（railgun 光标特效、透明背景、144 Hz 目标），不在配置的 Lua 逻辑里。
- 中途误判成「框太高 + 全屏压暗」并动了 `backdrop` 与 neo-tree 加载时机，用户澄清后已全部还原，最终 diff 只含尺寸。对着截图猜观感问题时，先确认「太大还是太小」比自行推断更省事。
## 47. AI 面板是一整块实心色（2026-10-16）

用户报「打开 pi 时面板是实心的、四角还是棱形」。两件事分开看：

- **实心（已修）**：sidekick 的面板窗口把 `Normal`/`NormalNC`/`EndOfBuffer`/`SignColumn` 映射到 `SidekickChat`，而**上游从未定义这个组**。WinHighlight 指向未定义的组时，Neovim 退回「UI 默认背景」——即猫猫 base `#1e1e2e`，于是透明主题下编辑区透出桌面、唯独面板是实心矩形。修法：[sidekick.lua](</home/pang/.config/nvim/lua/plugins/sidekick.lua>) 的 `config` 里 `nvim_set_hl(0, "SidekickChat", { link = "Normal" })`。
  证据（都可复跑）：① 用户截图取色，面板区恒为纯 `#1e1e2e`、编辑区是壁纸杂色；② 抓 nvim 写向 PTY 的字节，面板内标记行的 SGR 修复前是 `\x1b[38;2;205;214;244m\x1b[48;2;30;30;46m`，修复后只剩前景色、不再指定背景；③ 把该组临时设成亮紫，面板区立刻变紫，证实映射确实生效。
  ⚠ **反例更正**：旧记录（§22.3）说「SidekickChat 未定义 ⇒ 面板半透明、壁纸透进来」。本次实测相反：未定义是**退回 UI 默认背景**（实心），不是透明。别再按旧结论判断。
- **直角（改不了，除非换窗口类型）**：面板是**分屏**，Neovim 的分屏没有边框，四角必然是直角；`winborder = rounded` 只作用于浮窗。要圆角只能改成浮窗（`cli.win.layout = "float"`），代价是浮在编辑区之上、不再挤压编辑区、分屏导航键失效。2026-10-16 先按浮窗改过一版（还改了宽高与边距），用户要求还原——他要的是「保持原样，只修透明与直角」，而直角在分屏下无解。

回归：[sidekick_panel.lua](</home/pang/.config/nvim/tests/sidekick_panel.lua>) 用假工具（`sh -c sleep 120`）在完整配置下断言「仍是分屏、SidekickChat 链到 Normal、两侧都没有背景色、toggle 只隐藏不杀进程、close 才停 job」，14 项通过，不启动真实 AI 会话。
⚠ 坑：`require("sidekick").setup({...})` 是「默认值 + 传入项」**整体替换**（`sidekick/config.lua`），验证时再调一次 setup 会把 lazy 应用的 `opts` 冲掉、看起来像「配置没生效」；要验证插件配置必须走 `require("lazy").load({ plugins = { "sidekick.nvim" } })`，假工具直接挂到 `require("sidekick.config").cli.tools` 上。


## 48. Markdown 渲染：光标行露源码到底由谁决定（2026-10-16）

需求背景：用户看到渲染后的 md 里光标所在行仍显示 `**加粗**` 源码，问「能不能加个开关让当前行也不显示源码」。

**机制**（render-markdown.nvim 8.14.0，源码 + 真实 UI 实测）——光标行露不露源码由两层叠加决定：

1. `anti_conceal.enabled`（默认 true）：只负责隐藏插件**加出来的装饰**（项目符号 `●`、表格/代码框、缩进线等）；
2. `win_options.concealcursor.rendered`（默认 `''`）：渲染时把窗口 `concealcursor` 设为 `''` ⇒ 按 Neovim 语义「模式未列出时光标行把 conceal 的文本摊开」，**行内标记 `**` / 反引号因此裸露**。这一层才是直接原因。

实测对照（真实 PTY + `screenstring` 读屏，临时文件，未改用户配置）：

| 状态 | 光标行显示 |
|---|---|
| 现状（anti_conceal=true） | `- **MARKA** 单个拦截器…` |
| **只关 anti_conceal** | `● **MARKA** 单个拦截器…` ← **半吊子状态，`**` 依旧露** |
| 关 anti_conceal + `concealcursor.rendered='nvic'` | `● MARKA 单个拦截器…` ✅ |
| 切回开启 | 恢复原文显示 |

⚠ **别再凭直觉以为「关掉 anti_conceal 就不露源码」**——实验证明不够。正解是配置 `anti_conceal = { enabled = false }`（一行）：插件在 `lib/presets.lua:155-160` 会为这个状态自动把 `win_options.concealcursor.rendered` 设成 `'nvic'`。

若以后要做运行时开关：必须**同时**改 `anti_conceal.enabled` 与 `win_options.concealcursor.rendered`，再对相关窗口调 `require("render-markdown").render({ buf = ..., win = ... })`（`win_options` 每次渲染由 `core/ui.lua` 应用；实测切换与回切都生效）。只改前者就是上表第二行那个半吊子状态。2026-10-16 用户最终选择**保持现状**（不关 anti-conceal、不加开关）。

**接口清单**（8.14.0，供以后查）：

- 命令 `:RenderMarkdown [方法] [true|false]`，支持除 `render` 外的全部 API 方法，方法名与布尔参数都有补全。
- API（`require("render-markdown")`）：`enable/disable/toggle/set/get`、`buf_enable/buf_disable/buf_toggle/set_buf`、`render({buf,win?,event?,config?})`、`expand()/contract()`（anti_conceal 的 above/below 各 ±1，临时多露/少露源码）、`preview()`（内置并排预览窗口，跟随光标、纯离线）、`log()`、`debug()`（显示渲染标记）、`config()`（打印与默认值的差异）。
- 扩展点：`preset`（obsidian/lazy/none）、`overrides`（按语言/文件类型）、`custom_handlers`、`injections`、`patterns`、`on`、`completions`（lsp/blink/coq/cmp）、`win_options`、以及 `debounce/file_types/max_file_size/change_events/restart_highlighter/log_level` 等运行参数。
- 插件**不预设任何快捷键**（源码里没有 `keymap.set`），`<leader>Mp` 完全来自本机配置。

**`.mdx` 不渲染（2026-10-16 已修）**：根因是插件生效的 `file_types` 来自 lazy spec 的 `ft`（插件在没有 user.file_types 时直接取它），原先只有 `"markdown"`，而本机把 `.mdx` 映射成 `markdown.mdx`，两者对不上——**沿用旧配置的行为**，不是语言目录重构引入的。修法：`languages/markdown/render.lua` 改成 `ft = { "markdown", "markdown.mdx" }`（不必再重复写 `opts.file_types`，否则两处要同时维护）。验证：真实界面打开 `.mdx` 后 `ft=markdown.mdx`、渲染器 attached、标题行显示 ` 标题B`（`##` 已隐藏）、列表显示 `●`；`tests/editor_languages_smoke.lua` 增加「renderer attaches to .mdx buffers」断言并通过。

**`<leader>M` 组现状**：`Mp` 开关当前文档美化、`Me` 多露一行源码（`expand()`）、`Mc` 撤回一行（`contract()`）——后两个 2026-10-16 按用户要求加上，读长段落时对照原文用。三者共用 `markdown_buffer()` 守卫（`markdown` 与 `markdown.mdx` 都算），非 Markdown 缓冲区只提示、不加载渲染器。which-key 分组名「Markdown · 美化」。

## 49. 在笔记库里打开文件，工作目录/文件树跳到库根（2026-10-16）

现象：用户在 `~/obsidian/学习笔记/java学习笔记/kafka` 里启动 nvim，打开一个文件后 **cwd 与 neo-tree 根目录一起跳到 `~/obsidian/学习笔记`**（`.git` 所在层），看起来像"文件树倒退"。

**链路四环**（逐环验证过）：

1. 笔记库根 `~/obsidian/学习笔记` 有 `.git`（整库做了版本控制）；
2. project.nvim 的 `patterns` 含 `.git`：`on_buf_enter()` 打开任意真实文件时，用**文件所在目录**向上找最近的标记 ⇒ 命中库根；
3. `manual_mode = false` ⇒ 上游在 `init()` 里注册 `autocmd VimEnter,BufEnter * ++nested lua require("project_nvim.project").on_buf_enter()`，命中后执行 `nvim_set_current_dir(root)`（`scope_chdir` 默认 `global`）；
4. neo-tree 配了 `filesystem.bind_to_cwd = true`，加上 [core/projects/init.lua](</home/pang/.config/nvim/lua/core/projects/init.lua>) 的 `refresh_tree` 补丁 ⇒ 文件树跟着 cwd 搬走。

⇒ **不是 neo-tree 的 bug，也不是刷新补丁的 bug**：补丁只是忠实同步 cwd 的变化，真正切目录的是上游。

**复现脚手架**：真实 PTY + RPC（等 `vim.v.vim_did_enter == 1` 后依次 `:Neotree` → `:edit note.md`，每步打印 `getcwd()` 和 `require("neo-tree.sources.manager").get_state("filesystem").path`）。

⚠ **两个坑**：

- 别用 `nvim --headless -c 'luafile …'` 复现：`-c` 在 **VimEnter 之前**执行，而 `on_buf_enter()` 开头就是 `if vim.v.vim_did_enter == 0 then return end`，永远不触发，会误判成"没问题"（本次就踩了一次）；而且 headless 无文件启动会立刻退出，`vim.defer_fn` 都来不及跑。必须用真实 UI（PTY）。
- `luaeval` 传中文参数必须 `json.dumps(..., ensure_ascii=False)`：Lua 不认 `\uXXXX` 转义（报 `invalid escape sequence`）。

**修法（2026-10-16 采用）**：`plugins/project.lua` 加 `exclude_dirs = { "~/obsidian/*" }`。该选项的 glob 经 `globtopattern` 转成**锚定的 Lua 模式**且 `*` → `.*`（可跨 `/`），编译结果是 `^/home/pang/obsidian/.*$`，覆盖其下任意深度；`is_excluded()` 检查的是**文件所在目录**，所以库里任何位置打开文件都不再触发切目录，真工程照旧自动跟根。

备选（未采用）：`manual_mode = true` 全局关掉自动切目录——代价是正牌工程也不再自动跟根。

**验证**：① fixture（`/tmp/nvim-java-vault-probe`：`vault/.git` + `vault/java学习笔记/kafka/note.md`）三组对照——现状跳根 / `manual_mode = true` 不跳 / 只加排除也不跳；② 真实配置下打印编译后的模式并对 6 条真实路径跑 `is_excluded`：笔记库三条 `true`，普通工程（含带空格路径）`false`；③ 回归 `tests/projects.lua`（31）、`config_structure`（56）、`core_workflows`（50）全绿。

| 日期 | 内容 |
|------|------|
| 2026-10-16 | 添加 49：笔记库被自动跳到 .git 根（project.nvim 自动切目录 + neo-tree 跟随 cwd），用 `exclude_dirs` 豁免笔记库 |
| 2026-10-16 | 添加 48：Markdown 光标行露源码的归属（`concealcursor` 而非 anti-conceal）、插件接口清单、`.mdx` 不渲染现状 |
| 2026-10-14 | 添加 44：每种语言独立目录、统一声明、共享后端解耦、功能快照及启动开销和真实调试回归。 |
| 2026-10-14 | 添加 43：Java/Spring 按职责重构、单文件隔离、Initializr 直连与完整运行/断点/真实按键验证。 |
| 2026-10-07 | 添加 42：**「leader + g 和其他键位没有了」实测为误报**（弹窗 22 项 = spec 全量；85 个提交内 `<leader>g` 零命中；pty 实测 6 个触发器全正常；which-key 自动收起空组 ⇒ 看得见组名就说明下面有键）+ 两个同类旧文档漂移（`<leader>fd` 从未实现、`gU`→`gA`） |
| 2026-10-03 | 添加 35.5：**`<leader>sr` 复验 + 三项增强** —— 用户报「启动两个不行」，用真实项目副本在 tmux 真按键复现：两个进程都起得来（Api 8081 + Worker 消费线程），问题出在交互（第二次回车又选了默认项 = 重启；在终端里按 <leader>sr 映射根本不存在）⇒ 加 `slot_busy`（读 `/proc/<pid>/task/<pid>/children` 判槽里有没有活儿子，因为 toggleterm 的常驻 shell 让 `job_id` 恒活）、选择框标 `● 已在跑` + 新增 `▶ 全部启动`（等前一个 `Started …` 再起下一个，已在跑的跳过）；另记 `pgrep -f` 自匹配把清理脚本自己杀掉的纪律坑 |
| 2026-10-02 | 添加 35：**`<leader>sr` 认主类**（双进程项目：Api + Worker）—— 多 main 不给参数直接报 `Unable to find a single main class`；Boot 4 的 `spring-boot.run.*` 属性改由 mojo 的 `configuration` 默认值表达式接出（`plugin.xml` 里已无 `<property>`），**pom 自己写了 `<mainClass>` 就盖过它**（实测传 `-Dspring-boot.run.main-class=` 仍跑 RAN-A）⇒ 按 pom 形态在 `-Dmain.class=` / `-Dspring-boot.run.main-class=` 之间选；**toggleterm 的 `exec` 同 id 复用同一个 shell** ⇒ 每个主类一个终端槽 + 复用前先 Ctrl-C（顺带得到「同一个类连按两次 = 重启」）；含 headless 驱动的四条断言表 |
| 2026-09-27 | 添加 34：**32/33 两项修复的独立复验**（另写探针重跑：诊断 `<C-c>` 出口摘掉 autocmd 即复现洞、真 jdtls 100 帧语义 token 恒 0、两个输入框第 14/15/16 行 17–98 列；`checkhealth` 与 HEAD 干净副本零差异）+ 三个探针新坑（`screenstring()` 只吃 2 参、schedule 回调报错静默且丢已写内容、`semantic_tokens.is_enabled` 收 filter 表、headless 里 uv timer 不跑 ⇒ 分步探针必须上真 pty） |
| 2026-09-26 | 添加 33：**输入框与命令行框等长等高** —— snacks 输入框样式写死 `row = 2`（贴顶）；两个插件的宽度口径差 2 列（snacks 总宽 = width+2，noice 总宽 = min_width+4）⇒ 等长条件 `min_width = width − 2`；**两边配置里的 row 都是边框行** ⇒ 重合条件是 `floor((lines − 3) / 2)`。含 `screenstring()` 读真实屏幕帧的取证法（与 `nvim_win_get_position` 差一行的坑就是靠它发现的）、noice `min_width` 只能是数字、探针里 `<Esc>` 关不掉 snacks 输入框 |
| 2026-09-26 | 添加 32：**两个显示层问题** —— ① 诊断在普通模式下不显示但 `]d` 仍可跳（`update_in_insert=false` 下 runtime 先 hide 再判断插入模式 + `<C-c>` 不触发 InsertLeave ⇒ 用 `ModeChanged i*:n*` 兜底；含 headless 用 `nvim_input` 就能进插入模式的可复用手法）；② 写 Java 时代码颜色跳变（0.12 自动开启的语义 token 优先级 125 盖 treesitter 100 + `DiagnosticUnnecessary` 把整段文字染灰；含被证伪的 clear→重打假设与 50ms 有效前景色采样法） |
| 2026-09-25 | 添加 31：**nvim 终端里的 TUI 只有 2 个主题** —— `:terminal` 不设 `COLORTERM` ⇒ grok 隐藏 3 个 truecolor 主题；修法是 `vim.env.COLORTERM = "truecolor"`；含 `grok doctor` 对照表与"验证前先 `env -u NO_COLOR`"的坑 |
| 2026-09-25 | 添加 30：**按审查报告批量修复 15 条**的六个可复用手法（`CmdlineLeave` 才能识别 `:q!`；Lua `local function` 声明顺序会静默毁掉回调；"检查后写"改"只追加"；上游早退守卫要先摘适配器；traceback 打桩找调用方；`stop_client` + `:edit!` 验证重启）+ 15 条修复一览 |
| 2026-09-25 | 添加 29：**Markdown 预览四连换**（render-markdown → markview → markdown-preview → md-render）的取舍表 + 三条结论（就地渲染必然改编辑视图、透明主题下别靠调底色救、换插件前先用 pyte 量底色）+ 卸载三件套与三种验证手法（pty/pyte、Playwright 截图、headless 窗口数） |
| 2026-09-25 | 添加 28：**透明主题下就地渲染 md「好怪」的根因**（不是插件的锅：透明窗口 + 渲染器画的整行底色 + 壁纸三层混合）⇒ 换 markview.nvim 并 `block_hl = "Normal"` 关掉代码块底色；含"pyte 逐格统计整行色块"的可复用验证法与实测数据 |
| 2026-09-25 | 添加 27：**在 nvim 里就地读 Markdown**（render-markdown.nvim 选型 / git 必须带 `https_proxy` 才能 clone（直连会静默挂起，curl 却正常）/ headless 断言 + 真 pty 看画面的两步验证 / 截图脚本缺中文字形要用思源黑体兜底） |
| 2026-09-25 | 添加 15.2：which-key spec × triggers 全面复查（`z`/`[`/`]`/`<C-w>` 与 `g` 同类：有 spec 但没触发器 ⇒ 按下去毫无反应；含可复用的一行判定命令与有意不加的两类） |
| 2026-09-25 | 添加 25：**关了面板重开还是旧主题** —— 会话由 tmux 保持、`close()` 只是 detach、上游无 kill API ⇒ 加 `<leader>aR` 重启会话（杀 tmux 会话 + 重开）。附：会话名是「工具 + cwd 哈希」，重启后名字不变，判断要用 `#{session_created}` |
| 2026-09-25 | 添加 24：AI CLI（全屏 TUI/备用屏幕）里翻不上去的根因与解法 —— sidekick scrollback（tmux dump 2000 行）、`opencode` 被标记 `native_scroll` 没有 scrollback、本机加了 `<M-u>` 键盘开关；另记 `cli.win.keys` 是**深合并**（与 snacks 相反） |
| 2026-09-25 | 添加 23：透明主题下让**终端恢复实底**（`core/term_bg.lua`）—— 两个关键事实：浮窗背景用 `NormalFloat` 而非 `Normal`；toggleterm 的 `ui.hl_term()` 在 `on_open` **之前**覆盖 winhighlight，必须用 `on_open` 补。验证用 pyte 读单元格 bg（`default` = 透明） |
| 2026-09-25 | 添加 22：sidekick.nvim 安装（代理 clone + `:Lazy! install` 写 lock）与两个坑：① 无 `plugin/` 目录的懒加载插件 `:checkhealth` 要先 `:Lazy load`；② `mux=tmux` 会真建 tmux 会话，探针测后必须清理 |
| 2026-09-25 | 添加 21：诊断消息被「截断」的根因 —— virtual_lines 用 virt_lines_overflow=scroll **自身不折行**（浮窗才折行，别搞混），修法是在 format 里按窗口宽度插换行（渲染器按换行切分、每行带 └──── 前缀） |
| 2026-09-25 | 添加 20：「中文标点自动转半角」调研（无现成插件；cpc.nvim 命令式、autocorrect 规则相反）+ `InsertCharPre`/`v:char` 实现 + 两个坑（Lua 字符类单字节匹配、headless feedkeys 不能测多字节）+ 真 pty 验证表 |
| 2026-09-25 | 添加 19：`workspace/executeClientCommand` 的两类红色报错（`return nil` 让 nvim 抛 `rpc.lua:400` 且请求永不回；`error(-32601)` 让服务端记 `Method not found`）、**client 级 handler 盖掉全局转发 ⇒ spring-boot classpath 握手被吞**（后果：无 beans/endpoints/yml 补全 + `<F5>` javaExec 解析失败）、reloadBundles 必须回**空表**、client handler 单测手法、`lsp.log` 启动轮转 |
| 2026-09-25 | 添加 18.10：探针纪律补遗（默认隔离 XDG / uv timer 引用 / `vim.opt.shortmess` / 0.12 弃用的 `set_log_level`·`stop_client` / pty 写 master / 归属用 `/proc/<pid>/exe` / 上游 java ftplugin 的 silent E216） |
| 2026-09-25 | 添加 18.9：探针收尾泄漏 Spring Boot LS（`language-server.jar` 变 PPID=847 孤儿，实测 28 个/8.1GB，按 PPID 精确清理并断言无残留） |
| 2026-09-25 | 添加 18.8：清理自己起的语言服务必须按精确 PID（`pkill -f` 短模式误杀用户会话 jdtls）＋ `-data` workspace 命名规则（项目名 + 路径 sha256 前 10 位，可据此核对归属） |
| 2026-09-25 | 添加 18.7：snacks picker 探针自省（`input.win` 不是窗口号、按 filetype 读 picker 缓冲）、`XDG_CONFIG_HOME` 指错=静默裸跑、后置声明 `local function` 变全局 nil、pty 驱动 `P:`/`W<秒>:` token 与收尾协议、聚合文件被 `: >` 清空 |
| 2026-09-25 | 添加 18：DAP arguments 空表被编码成 JSON 数组 ⇒ 适配器静默丢帧、永不回调（`session:request` 的正确用法）、`stackFrames` 字段名、java-debug 空 logMessage 的实测语义、pty 探针残留 swap 文件导致 E325 静默吃掉按键；18.5 blink.cmp 菜单对 `pumvisible()` 恒为空（判据是 `blink.cmp.is_menu_visible()`）；18.6 上游 `pick_many` 无取消通道（三处 fields 调用点不检查空返回） |
| 2026-09-25 | 添加 14.11（探针的 LSP workspace edit + 退出自动保存会改到别的文件）、17 Java 缓冲区 `:e`/`:e!` 后 LSP 静默失效（去重守卫导致 jdtls 不回来，含 6 行补丁与真 pty A/B） |
| 2026-09-25 | 添加 14.1–14.10 真机走查探针方法论（就绪判据、双 client 扇出、vim.wait 不处理按键、feedkeys mode、静默死亡、dap.breakpoints 懒加载、hit-enter、toggleterm.get、stylua 副本配置）、15 which-key 可视模式触发器根因与修法（含真 pty A/B）、16 Java 真机走查结论 |

| 日期 | 内容 |
|------|------|
| 2026-09-25 | 添加 13.1–13.6：项目历史第二次被清空定位到上游 `write_projects_to_history()` 的截断写 + 异步读竞态（三层保护：只追加副本 / 并集 / append 回填，`DirChanged` 兜底）、snacks picker 子窗宽度与选中行高亮组 `SnacksPickerListCursorLine`、自定义行富文本、内联 layout 覆盖预设的更正、`:Projects` 列表观感 |
| 2026-09-24 | 添加 12.1–12.9：删 Comment.nvim 改用内置注释、springboot `cmd` 桩懒加载、Treesitter 需 Clash 代理与 6 小时节流、`{N}write` 空操作与全缓冲区退出保存、lualine 扩展互斥、诊断 code 后缀、Unknown filetype 'xsl'、headless 无 UIEnter |
| 2026-08-17 | 添加 11.1–11.2：lazy.nvim clone 中断导致配置失效与入口检查、delve 安装卡死的 Go 代理问题 |
| 2026-07-14 | 添加 10.8–10.11：alpha 条件事件、Treesitter/Mason 时序、小终端 UI、文件树键位与片段功能修复 |
| 2026-06-22 | 添加 9.2：jdtls workspace_dir 跨项目不更新 |
| 2026-06-22 | 添加 10：Telescope/project 懒加载解耦、格式化超时、conform 首次保存、provider/rocks 警告清理 |
| 2026-06-29 | 添加 Mason 初始化顺序、filetype health、诊断跳转废弃 API、bufferline 非强制关闭、format fallback |
| 2026-06-19 | 添加 9：nvim-jdtls root_dir 函数在 Neovim 0.12+ 不生效 |
| 2026-06-05 | 添加 6.4：可视模式 `J`/`K` 映射触发 noice 命令行闪框 |
| 2026-06-04 | 初始创建 |
