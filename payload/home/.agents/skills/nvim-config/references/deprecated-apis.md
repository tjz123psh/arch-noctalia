# Deprecated APIs by Neovim Version

Reference for identifying deprecated and removed APIs. Check user's Neovim version first, then flag applicable deprecations.

## Version Detection

```bash
# Get Neovim version
nvim --version | head -1
# Example: NVIM v0.10.0

# Check version in Lua
nvim --headless -c "lua print(vim.version().major, vim.version().minor)" -c "qa" 2>&1
```

---

## Neovim 0.9 Deprecations（已从 0.12.5 移除）

本机 0.12.5 中这些 API **已不存在**：调用是硬报错（nil value），不是废弃告警。
保留迁移对照，供阅读旧代码/旧博客时参考。

| 已移除 API | 废弃于 | 移除于 | 替代 |
|------------|--------|--------|------|
| `vim.lsp.buf.formatting()` | 0.8 | 0.9 | `vim.lsp.buf.format()` |
| `vim.lsp.buf.formatting_sync()` | 0.8 | 0.9 | `vim.lsp.buf.format({ async = false })` |
| `vim.lsp.buf.range_formatting()` | 0.9 | 0.10 | `vim.lsp.buf.format({ range = { ... } })` |
| `vim.treesitter.query.get_query()` | 0.9 | 0.10 | `vim.treesitter.query.get()` |
| `vim.treesitter.query.parse_query()` | 0.9 | 0.10 | `vim.treesitter.query.parse()` |

核验（应全部为 false）：
```bash
nvim --headless --clean "+lua for _,n in ipairs({'range_formatting','formatting','formatting_sync'}) do print(n..'='..tostring(vim.lsp.buf[n]~=nil)) end" "+lua print('get_query='..tostring(vim.treesitter.query.get_query~=nil))" "+qa!"
```

---

## Neovim 0.10 Deprecations

APIs deprecated in 0.10.

### vim.api.nvim_buf_set_option()

| Field | Value |
|-------|-------|
| Deprecated | 0.10 |
| Removed | Not yet (soft deprecation) |
| Detection | `grep -rn "nvim_buf_set_option\s*(" --include="*.lua"` |
| Replacement | `vim.bo[bufnr].option = value` |

```lua
-- Old
vim.api.nvim_buf_set_option(bufnr, "filetype", "lua")

-- New
vim.bo[bufnr].filetype = "lua"
```

---

### vim.api.nvim_win_set_option()

| Field | Value |
|-------|-------|
| Deprecated | 0.10 |
| Removed | Not yet (soft deprecation) |
| Detection | `grep -rn "nvim_win_set_option\s*(" --include="*.lua"` |
| Replacement | `vim.wo[winid].option = value` |

```lua
-- Old
vim.api.nvim_win_set_option(winid, "wrap", false)

-- New
vim.wo[winid].wrap = false
```

---

### vim.api.nvim_set_option()

| Field | Value |
|-------|-------|
| Deprecated | 0.10 |
| Removed | Not yet (soft deprecation) |
| Detection | `grep -rn "nvim_set_option\s*(" --include="*.lua"` |
| Replacement | `vim.o.option = value` |

---

### vim.api.nvim_buf_get_option()

| Field | Value |
|-------|-------|
| Deprecated | 0.10 |
| Removed | Not yet |
| Detection | `grep -rn "nvim_buf_get_option\s*(" --include="*.lua"` |
| Replacement | `vim.bo[bufnr].option` |

---

### vim.api.nvim_win_get_option()

| Field | Value |
|-------|-------|
| Deprecated | 0.10 |
| Removed | Not yet |
| Detection | `grep -rn "nvim_win_get_option\s*(" --include="*.lua"` |
| Replacement | `vim.wo[winid].option` |

---

### vim.lsp.get_active_clients()

| Field | Value |
|-------|-------|
| Deprecated | 0.10 |
| Removed | Not yet |
| Detection | `grep -rn "get_active_clients\s*(" --include="*.lua"` |
| Replacement | `vim.lsp.get_clients()` |

```lua
-- Old
local clients = vim.lsp.get_active_clients({ bufnr = 0 })

-- New
local clients = vim.lsp.get_clients({ bufnr = 0 })
```

---

### vim.lsp.for_each_buffer_client()

| Field | Value |
|-------|-------|
| Deprecated | 0.10 |
| Removed | Not yet |
| Detection | `grep -rn "for_each_buffer_client\s*(" --include="*.lua"` |
| Replacement | Use `vim.lsp.get_clients()` with loop |

---

### vim.diagnostic.disable() / enable() signature change

| Field | Value |
|-------|-------|
| Deprecated | 0.10 |
| Removed | Not yet |
| Detection | `grep -rn "diagnostic\.disable\s*(\s*[0-9]\|diagnostic\.enable\s*(\s*[0-9]" --include="*.lua"` |
| Note | First argument changed from bufnr to namespace |

```lua
-- Old (0.9)
vim.diagnostic.disable(bufnr)
vim.diagnostic.enable(bufnr)

-- New (0.10+)
vim.diagnostic.enable(false, { bufnr = bufnr })
vim.diagnostic.enable(true, { bufnr = bufnr })
```

---

### vim.treesitter.get_node_text() table parameter

| Field | Value |
|-------|-------|
| Deprecated | 0.10 |
| Removed | Not yet |
| Detection | Pattern changed, check for third non-table arg |
| Replacement | Pass options as table |

```lua
-- Old
vim.treesitter.get_node_text(node, bufnr, { concat = false })

-- Still works, but signature is now:
vim.treesitter.get_node_text(node, source, opts)
```

---

## Neovim 0.11 Deprecations

APIs deprecated in 0.11.

### vim.lsp.buf.execute_command()

| Field | Value |
|-------|-------|
| Deprecated | 0.11 |
| Removed | Not yet |
| Detection | `grep -rn "lsp\.buf\.execute_command\s*(" --include="*.lua"` |
| Replacement | Use client-specific method |

---

### vim.lsp.util.make_position_params() without arguments

| Field | Value |
|-------|-------|
| Deprecated | 0.11 |
| Removed | Not yet |
| Detection | `grep -rn "make_position_params\s*()" --include="*.lua"` |
| Replacement | Pass window and client explicitly |

```lua
-- Old
local params = vim.lsp.util.make_position_params()

-- New
local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
```

---

### vim.lsp.util.make_range_params() without arguments

| Field | Value |
|-------|-------|
| Deprecated | 0.11 |
| Removed | Not yet |
| Detection | `grep -rn "make_range_params\s*()" --include="*.lua"` |
| Replacement | Pass window and client explicitly |

---

### vim.lsp.start_client()

| Field | Value |
|-------|-------|
| Deprecated | 0.11 |
| Removed | Not yet |
| Detection | `grep -rn "lsp\.start_client\s*(" --include="*.lua"` |
| Replacement | `vim.lsp.start()` |

---

## Neovim 0.12 Deprecations

APIs deprecated in 0.12。

> 覆盖说明：官方 0.12.5 的 `DEPRECATED IN 0.12` 节有 26 条，这里只列本机可能触及的项。
> 完整权威清单以 `:help deprecated` 或
> `sed -n '/DEPRECATED IN 0.12/,/DEPRECATED IN 0.11/p' /usr/share/nvim/runtime/doc/deprecated.txt` 为准。

### vim.diagnostic.goto_prev() / goto_next()

| Field | Value |
|-------|-------|
| Deprecated | 0.12 |
| Removed | 未移除（实测 0.12.5 仍告警：Feature will be removed in Nvim 0.13） |
| Detection | `grep -rn "diagnostic\.goto_prev\\|diagnostic\.goto_next" --include="*.lua"` |
| Replacement | `vim.diagnostic.jump({ count = -1, float = true })` / `vim.diagnostic.jump({ count = 1, float = true })` |

```lua
-- Old
vim.diagnostic.goto_prev()
vim.diagnostic.goto_next()

-- New
vim.diagnostic.jump({ count = -1, float = true })
vim.diagnostic.jump({ count = 1, float = true })
```

### vim.lsp.util.stylize_markdown()

| Field | Value |
|-------|-------|
| Deprecated | 0.12 |
| Removed | 计划 0.14 |
| Detection | `grep -rn "stylize_markdown" --include="*.lua" ~/.config/nvim` |
| Replacement | 无需替换：noice 会用自身实现**覆盖**该函数（见下方说明） |

**本机现状（已核验，无需处理）**：`lua/plugins/noice.lua:77` 的
`["vim.lsp.util.stylize_markdown"] = true` 是 noice 自己的 override 开关，不是调用废弃 API。
noice 在 `lsp/override.lua:22-24` 把 `vim.lsp.util.stylize_markdown` **替换**为自身实现，
因此内置的废弃实现根本不会被调用，也不会产生告警。

**验证方式**：废弃告警只在**真正调用**时才出现。空转 `checkhealth` 永远是
`✅ OK No deprecated functions detected`——必须实际触发对应功能才能看到告警：

```bash
# 只有当配置里真的调用了该 API，才会出现 WARNING
nvim --headless -u ~/.config/nvim/init.lua "+lua pcall(vim.diagnostic.goto_next)" \
  "+checkhealth vim.deprecated" "+w! /dev/stdout" "+qa!" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
```

**本机全量核查结论**：`goto_prev`/`goto_next`/`get_active_clients`/`start_client`/
`for_each_buffer_client`/`stylize_markdown` 在 `~/.config/nvim/lua` 中命中数均为 0，
即本机配置未使用任何 0.12 废弃 API。

### vim.treesitter.get_parser() 显式传 bufnr（建议，非废弃）

**注意**：此条不是 Neovim 废弃项。`vim.treesitter.get_parser()` 未被 `vim.deprecate()` 标注，
官方 `deprecated.txt` 中也没有该符号（已核验：`grep -rn "get_parser" /usr/share/nvim/runtime/doc/deprecated.txt` 无命中）。
显式传缓冲区（`vim.treesitter.get_parser(0)`）是更稳妥的写法，但省略参数仍受支持，不会产生告警。

| Field | Value |
|-------|-------|
| Deprecated | 否（本机约定，非上游废弃） |
| Removed | 不适用 |
| Detection | `grep -rn "treesitter\.get_parser\s*()" --include="*.lua"` |
| Recommendation | 显式传缓冲区：`vim.treesitter.get_parser(0)` |

---

## Quick Audit Script

Run this to check for common deprecated APIs:

```bash
#!/bin/bash
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"

echo "=== Deprecated API Audit ==="
echo "Config: $CONFIG_DIR"
echo ""

# 0.10 deprecations (most common)
echo "--- nvim_*_set/get_option (deprecated 0.10) ---"
grep -rn "nvim_buf_set_option\|nvim_win_set_option\|nvim_set_option\|nvim_buf_get_option\|nvim_win_get_option" "$CONFIG_DIR" --include="*.lua" 2>/dev/null || echo "None found"
echo ""

echo "--- get_active_clients (deprecated 0.10) ---"
grep -rn "get_active_clients" "$CONFIG_DIR" --include="*.lua" 2>/dev/null || echo "None found"
echo ""

# 0.9 deprecations
echo "--- formatting_sync/range_formatting (removed 0.9-0.10) ---"
grep -rn "formatting_sync\|range_formatting" "$CONFIG_DIR" --include="*.lua" 2>/dev/null || echo "None found"
echo ""

# 0.11 deprecations
echo "--- make_position_params/make_range_params without args (deprecated 0.11) ---"
grep -rn "make_position_params\s*()\|make_range_params\s*()" "$CONFIG_DIR" --include="*.lua" 2>/dev/null || echo "None found"
echo ""

echo "--- diagnostic goto_prev/goto_next (deprecated 0.12) ---"
grep -rn "diagnostic\.goto_prev\|diagnostic\.goto_next" "$CONFIG_DIR" --include="*.lua" 2>/dev/null || echo "None found"
echo ""

# 0.9 deprecations (removed in 0.10)
echo "--- get_query/parse_query (deprecated 0.9, removed 0.10) ---"
grep -rn "query\.get_query\|query\.parse_query" "$CONFIG_DIR" --include="*.lua" 2>/dev/null || echo "None found"
echo ""

echo "=== Audit Complete ==="
```

---

## Summary Table

| API | Deprecated | Removed | Severity |
|-----|------------|---------|----------|
| `vim.lsp.buf.formatting()` | 0.8 | 0.9 | Critical |
| `vim.lsp.buf.formatting_sync()` | 0.8 | 0.9 | Critical |
| `vim.lsp.buf.range_formatting()` | 0.9 | 0.10 | Critical |
| `nvim_buf_set_option()` | 0.10 | — | Warning |
| `nvim_win_set_option()` | 0.10 | — | Warning |
| `nvim_set_option()` | 0.10 | — | Warning |
| `get_active_clients()` | 0.10 | — | Warning |
| `vim.diagnostic.disable/enable()` sig | 0.10 | — | Warning |
| `make_position_params()` no args | 0.11 | — | Warning |
| `lsp.start_client()` | 0.11 | — | Warning |
| `vim.diagnostic.goto_prev/next()` | 0.12 | — | Warning |
| `query.get_query()` | 0.9 | 0.10 | Critical |
| `query.parse_query()` | 0.9 | 0.10 | Critical |
