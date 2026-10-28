--!nonstrict
-- pang/tide-sidebar — 「窗口」页的声明式 UI 原型（Noctalia 5.4 / plugin_api 42）
--
-- 目的：用 [[panel]] + ui.* 复刻正式侧栏「窗口」页的核心体验，作为是否整体迁移到
-- 声明式面板的试点。数据来源与正式版完全相同（helpers/system.py 内部走 niri IPC），
-- 两边看到的窗口列表、焦点标记、关闭行为一致。
--
-- 打开：noctalia msg panel-open pang/tide-sidebar:windows-proto
-- 交互：点一行 = 切到该窗口；行尾 × = 关闭该窗口；顶部「刷新」重读；Esc 关闭面板。

local helper = noctalia.pluginDir() .. "/helpers/system.py"
local MAX_ROWS = 40

local rows = {}
local errorText = nil
local loading = true
local generation = 0
local busy = false
local render

local function decode(result)
  if type(result) ~= "table" or result.exitCode ~= 0 then return nil end
  if type(result.stdout) ~= "string" or result.stdout == "" then return nil end
  local ok, value = pcall(noctalia.json.decode, result.stdout)
  if not ok or type(value) ~= "table" then return nil end
  return value
end

local function applySnapshot(value)
  loading = false
  rows = {}
  if not value or value.ok ~= true then
    errorText = "读取窗口失败：niri IPC 没有响应"
    render()
    return
  end
  errorText = type(value.windowsError) == "string" and value.windowsError or nil
  for _, item in ipairs(value.windows or {}) do
    local ident = type(item) == "table" and tonumber(item.id) or nil
    if ident and #rows < MAX_ROWS then
      rows[#rows + 1] = {
        id = ident,
        title = tostring(item.title or ""),
        appId = tostring(item.appId or ""),
        focused = item.focused == true,
      }
    end
  end
  if type(noctalia.log) == "function" then noctalia.log("windows-proto: " .. tostring(#rows) .. " windows") end
  render()
end

local function refresh()
  generation = generation + 1
  local mine = generation
  loading = true
  render()
  local started = noctalia.runAsync({ "python", helper, "snapshot" }, function(result)
    if mine ~= generation then return end
    applySnapshot(decode(result))
  end)
  if not started then
    loading = false
    errorText = "无法启动窗口查询（python）"
    render()
  end
end

local function focusWindow(id)
  if busy then return end
  busy = true
  noctalia.runAsync({ "python", helper, "focus", tostring(id) }, function(result)
    busy = false
    if type(result) == "table" and result.exitCode == 0 then
      panel.close()
    else
      errorText = "切换到该窗口失败"
      render()
    end
  end)
end

local function closeWindow(id)
  if busy then return end
  busy = true
  noctalia.runAsync({ "python", helper, "close", tostring(id) }, function(result)
    busy = false
    if type(result) == "table" and result.exitCode ~= 0 then errorText = "关闭该窗口失败" end
    refresh()
  end)
end

render = function()
  local children = {
    ui.row({ height = 32, align = "center", justify = "space_between", gap = 8 }, {
      ui.label({
        text = loading and "窗口 · 读取中…" or ("窗口 · " .. tostring(#rows) .. " 个"),
        fontSize = 13,
        color = "on_surface",
        maxLines = 1,
      }),
      ui.button({ text = "刷新", variant = "ghost", controlSize = "sm", onClick = function() refresh() end }),
    }),
  }
  if errorText then
    children[#children + 1] = ui.label({ text = errorText, fontSize = 11, color = "on_surface_variant", maxLines = 2 })
  end

  local list = {}
  for index, row in ipairs(rows) do
    list[#list + 1] = ui.row({ key = "row" .. tostring(index), height = 34, gap = 6, align = "center" }, {
      ui.button({
        key = "focus" .. tostring(index),
        text = (row.focused and "● " or "") .. (row.title ~= "" and row.title or row.appId),
        tooltip = row.appId,
        variant = row.focused and "secondary" or "ghost",
        controlSize = "sm",
        contentAlign = "start",
        flexGrow = 1,
        onClick = function() focusWindow(row.id) end,
      }),
      ui.button({
        key = "close" .. tostring(index),
        glyph = "x",
        variant = "ghost",
        controlSize = "sm",
        width = 32,
        tooltip = "关闭窗口",
        onClick = function() closeWindow(row.id) end,
      }),
    })
  end
  if #list == 0 and not loading then
    list[1] = ui.label({ text = "没有可管理的窗口", fontSize = 11, color = "on_surface_variant" })
  end
  -- 显式给滚动区高度：面板 height="content" 时这样高度可预测，也便于对比不同条目数的观感。
  local listHeight = math.max(36, math.min(#rows * 36, 420))
  children[#children + 1] = ui.scroll({ height = listHeight, gap = 2 }, list)

  panel.render(ui.column({ width = 396, padding = 12, gap = 8 }, children))
end

local function guard(name, fn)
  local ok, err = pcall(fn)
  if not ok and type(noctalia.log) == "function" then noctalia.log("tide-sidebar windows prototype: " .. name .. ": " .. tostring(err)) end
end

function onOpen(context)
  guard("onOpen", function()
    generation = generation + 1
    loading = true
    errorText = nil
    render()
    refresh()
  end)
end

function onClose()
  guard("onClose", function()
    generation = generation + 1
    busy = false
  end)
end

function onIpc(event, payload)
  guard("onIpc", function()
    if event == "refresh" then refresh() end
  end)
end
