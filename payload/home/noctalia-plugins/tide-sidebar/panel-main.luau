--!nonstrict
-- pang/tide-sidebar — 统一声明式侧栏（窗口 / 工具 / 便签）
--
-- 由 panel-windows / panel-tools / panel-notes 三个原型合并而来：一个面板、三个标签页，
-- 数据与原生前端共享同一份服务状态（private/frontend/*.json 读，IPC 写）。
-- 原生 GTK 前端仍保留在 native/ 作为回退：把 shortcut.luau / widget.luau 的 onClick
-- 改回 noctalia.state.set("command",{action="frontend-toggle"}) 即可。
--
-- 打开：快捷键 Super+Shift+W、状态栏「侧栏」按钮，或 noctalia msg panel-open pang/tide-sidebar:side-panel

local tab = "windows"                  -- windows | tools | notes
local timer, stopwatch, hotspot, model, noteError, calc
local editingId, draft, noteDirty = nil, "", false
local busy = false
local pendingRefresh = true

local function num(v) return type(v) == "number" and v or 0 end

-- 数据来自服务写入的共享内存状态（noctalia.state），因此原生前端不启动也能用。
local function read(name)
  local value = noctalia.state.get(name .. "_snapshot")
  if type(value) ~= "table" then return nil end
  return value
end

local function clock(ms)
  local total = math.max(0, math.floor(num(ms) / 1000))
  return string.format("%02d:%02d", math.floor(total / 60), total % 60)
end

local function stopClock(ms)
  local cs = math.max(0, math.floor(num(ms) / 10))
  return string.format("%02d:%02d.%02d", math.floor(cs / 6000), math.floor(cs / 100) % 60, cs % 100)
end

local function send(event, args)
  local argv = { "noctalia", "msg", "plugin", "pang/tide-sidebar:backend", "all", event }
  if args ~= nil then argv[#argv + 1] = noctalia.json.encode(args) end
  noctalia.runAsync(argv, function() end)
  pendingRefresh = true
end

local function cmd(event, value)
  local argv = { "noctalia", "msg", "plugin", "pang/tide-sidebar:backend", "all", event }
  if value ~= nil then argv[#argv + 1] = tostring(value) end
  noctalia.runAsync(argv, function() end)
  pendingRefresh = true
end

local function refreshAll()
  timer = (read("timer") or {}).timer
  stopwatch = (read("stopwatch") or {}).stopwatch
  hotspot = (read("system") or {}).hotspot
  calc = read("calc")
  local notes = read("notes")
  if notes then
    model = notes.model or model
    noteError = (type(notes.error) == "string" and notes.error ~= "") and notes.error or nil
  end
  pendingRefresh = false
end

-- ---------------------------------------------------------------- shared bits

local function switchTab(id)
  tab = id
  send("preferences", { tab = id })
  render()
end

local function tabButton(id, text)
  return ui.button({
    text = text,
    variant = tab == id and "secondary" or "ghost",
    controlSize = "sm",
    width = 96,
    onClick = function() switchTab(id) end,
  })
end

local function card(title, value, controls, extra)
  local rows = {
    ui.row({ justify = "space_between", align = "end" }, {
      ui.label({ text = title, fontSize = 12, color = "on_surface_variant" }),
      ui.label({ text = value, fontSize = 22, color = "on_surface" }),
    }),
  }
  if extra then rows[#rows + 1] = extra end
  rows[#rows + 1] = ui.row({ gap = 6 }, controls)
  return ui.column({ fill = "surface_container/0.5", radius = 12, padding = 10, gap = 8 }, rows)
end

-- ---------------------------------------------------------------- page: windows

local function pageWindows()
  local data = read("windows") or read("system") or {}
  local list = data.windows or {}
  local rows = {}
  for index, item in ipairs(list) do
    local id = tonumber(item.id)
    if id then
      rows[#rows + 1] = ui.row({ key = "win" .. tostring(index), height = 34, gap = 6, align = "center" }, {
        ui.button({
          text = (item.focused and "● " or "") .. (tostring(item.title or "") ~= "" and tostring(item.title) or tostring(item.appId or "")),
          tooltip = tostring(item.appId or ""),
          variant = item.focused and "secondary" or "ghost",
          controlSize = "sm",
          contentAlign = "start",
          flexGrow = 1,
          onClick = function()
            send("focus-window", tostring(id))
            panel.close()
          end,
        }),
        ui.button({
          glyph = "x", variant = "ghost", controlSize = "sm", width = 32, tooltip = "关闭窗口",
          onClick = function() send("close-window", tostring(id)) end,
        }),
      })
    end
  end
  if #rows == 0 then rows[1] = ui.label({ text = "没有可管理的窗口", fontSize = 11, color = "on_surface_variant" }) end
  return {
    ui.row({ justify = "space_between", align = "center" }, {
      ui.label({ text = "窗口 · " .. tostring(#list) .. " 个", fontSize = 12, color = "on_surface_variant" }),
      ui.button({ text = "刷新", variant = "ghost", controlSize = "sm", onClick = function() refreshAll(); render() end }),
    }),
    ui.scroll({ height = math.max(36, math.min(#rows * 36, 360)), gap = 2 }, rows),
  }
end

-- ---------------------------------------------------------------- page: tools

local function pageTools()
  local t, w, h = timer or {}, stopwatch or {}, hotspot or {}
  local remaining, duration, status = num(t.remainingMs), num(t.durationMs), (t.status or "idle")

  local timerButtons = {}
  if status == "running" then
    timerButtons[#timerButtons + 1] = ui.button({ text = "暂停", variant = "ghost", controlSize = "sm", onClick = function() cmd("timer-pause") end })
  elseif status == "paused" then
    timerButtons[#timerButtons + 1] = ui.button({ text = "继续", variant = "primary", controlSize = "sm", onClick = function() cmd("timer-resume") end })
  else
    timerButtons[#timerButtons + 1] = ui.button({ text = "开始", variant = "primary", controlSize = "sm", onClick = function() cmd("timer-start", math.max(1, math.floor(duration / 1000))) end })
  end
  timerButtons[#timerButtons + 1] = ui.button({ text = "重置", variant = "ghost", controlSize = "sm", onClick = function() cmd("timer-reset", 1500) end })
  local cfg = noctalia.state.get("config")
  local presets = type(cfg) == "table" and type(cfg.timerPresets) == "table" and #cfg.timerPresets > 0 and cfg.timerPresets or { "5", "15", "25", "60" }
  for _, preset in ipairs(presets) do
    local minutes = tonumber(preset) or 25
    timerButtons[#timerButtons + 1] = ui.button({ text = tostring(preset), variant = "ghost", controlSize = "sm", onClick = function() cmd("timer-start", minutes * 60) end })
  end

  local progress = duration > 0
      and ui.progress({ progress = math.max(0, math.min(1, 1 - remaining / duration)), height = 6, radius = 3 })
      or nil

  return {
    card("倒计时", clock(remaining), timerButtons, progress),
    card("秒表", stopClock(w.elapsedMs), {
      ui.button({ text = w.status == "running" and "暂停" or "开始", variant = "primary", controlSize = "sm",
        onClick = function() cmd(w.status == "running" and "stopwatch-pause" or "stopwatch-start") end }),
      ui.button({ text = "重置", variant = "ghost", controlSize = "sm", onClick = function() cmd("stopwatch-reset") end }),
    }),
    card("热点", h.on and ("已开启 · " .. tostring(h.ssid or "")) or "已关闭", {
      ui.button({ text = h.on and "关闭热点" or "开启热点", variant = h.on and "destructive" or "default", controlSize = "sm",
        onClick = function() cmd("hotspot", h.on and "off" or "on") end }),
    }),
  }
end

-- ---------------------------------------------------------------- page: notes

local function findNote(id)
  for _, note in ipairs(model and model.notes or {}) do
    if note.id == id then return note end
  end
end

local function pageCalc()
  local value = type(calc) == "table" and calc or {}
  local history = type(value.history) == "table" and value.history or {}
  local rows = {}
  for index, item in ipairs(history) do
    rows[#rows + 1] = ui.button({
      key = "calc" .. tostring(index),
      text = tostring(item.expression or "") .. " = " .. tostring(item.result or ""),
      variant = "ghost", controlSize = "sm", contentAlign = "start",
      onClick = function() send("calc-evaluate", { expression = tostring(item.expression or ""), commit = true }); render() end,
    })
  end
  if #rows == 0 then rows[1] = ui.label({ text = "还没有计算记录", fontSize = 11, color = "on_surface_variant" }) end
  return {
    ui.input({
      value = "",
      placeholder = "输入表达式，回车计算（支持单位/常量，libqalculate）",
      focus = true,
      onSubmit = function(text) send("calc-evaluate", { expression = text, commit = true }); render() end,
    }),
    ui.label({ text = tostring(value.result or "0"), fontSize = 26, color = "on_surface", maxLines = 1 }),
    ui.label({ text = tostring(value.error or ""), fontSize = 11, color = "on_surface_variant", maxLines = 2 }),
    ui.scroll({ height = math.max(36, math.min(#rows * 34, 200)), gap = 2 }, rows),
  }
end

local function pageNotes()
  if editingId then
    local note = findNote(editingId)
    return {
      ui.row({ justify = "space_between", align = "center" }, {
        ui.button({ text = "返回", variant = "ghost", controlSize = "sm", onClick = function()
          if noteDirty then send("note-edit", { id = editingId, body = draft }); noteDirty = false end
          editingId = nil; render()
        end }),
        ui.label({ text = tostring(note and note.title or "便签"), fontSize = 13, color = "on_surface" }),
        ui.button({ text = "删除", variant = "destructive", controlSize = "sm", onClick = function()
          send("note-delete", { id = editingId }); noteDirty = false; editingId = nil; render()
        end }),
      }),
      ui.input({
        value = draft, multiline = true, height = 380, focus = true, placeholder = "写点什么…",
        onChange = function(text) draft = text; noteDirty = true end,
      }),
      ui.row({ justify = "space_between", align = "center" }, {
        ui.label({ text = tostring(#draft) .. " 字", fontSize = 10, color = "on_surface_variant" }),
        ui.label({ text = noteDirty and "未保存（每秒自动保存）" or "已保存", fontSize = 10, color = "on_surface_variant" }),
      }),
    }
  end
  local notes = model and model.notes or {}
  local rows = {}
  for _, note in ipairs(notes) do
    local first = tostring(note.body or ""):gsub("%s+", " ")
    if #first > 40 then first = first:sub(1, 40) .. "…" end
    rows[#rows + 1] = ui.button({
      key = "note-" .. note.id,
      text = tostring(note.title or "便签") .. "   " .. first,
      variant = (note.id == (model.activeId or "")) and "secondary" or "ghost",
      controlSize = "sm", contentAlign = "start",
      onClick = function()
        editingId = note.id; draft = tostring(note.body or ""); noteDirty = false
        send("note-select", { id = note.id }); render()
      end,
    })
  end
  if #rows == 0 then rows[1] = ui.label({ text = "还没有便签", fontSize = 11, color = "on_surface_variant" }) end
  return {
    ui.row({ justify = "space_between", align = "center" }, {
      ui.label({ text = "便签 · " .. tostring(#notes) .. " 条", fontSize = 12, color = "on_surface_variant" }),
      ui.button({ text = "新建", variant = "primary", controlSize = "sm", onClick = function() send("note-add", { title = "新便签" }); render() end }),
    }),
    ui.scroll({ height = math.max(36, math.min(#notes * 36, 380)), gap = 4 }, rows),
    ui.label({ text = "回收区 " .. tostring(model and model.trash and #model.trash or 0) .. " 条", fontSize = 10, color = "on_surface_variant" }),
  }
end

-- ---------------------------------------------------------------- shell

function render()
  local body
  local okp, res = pcall(function()
    if tab == "tools" then return pageTools()
    elseif tab == "calc" then return pageCalc()
    elseif tab == "notes" then return pageNotes()
    else return pageWindows() end
  end)
  if okp then body = res else
    noctalia.writeFile("/tmp/side-debug.txt", "page error: " .. tostring(res))
    body = ui.label({ text = "页面渲染失败", fontSize = 11, color = "on_surface_variant" })
  end

  local children = {
    ui.row({ justify = "space_between", align = "center" }, {
      ui.row({ gap = 6 }, {
        tabButton("windows", "窗口"),
        tabButton("tools", "工具"),
        tabButton("calc", "计算"),
        tabButton("notes", "便签"),
      }),
      ui.label({ text = "Ctrl+1..3 切换", fontSize = 10, color = "on_surface_variant" }),
    }),
  }
  if type(body) == "table" then
    for _, node in ipairs(body) do children[#children + 1] = node end
  elseif body then
    children[#children + 1] = body
  end
  panel.render(ui.column({ width = 436, height = 520, padding = 12, gap = 10 }, children))
end

local function guard(name, fn)
  local ok, err = pcall(fn)
  if not ok and type(noctalia.log) == "function" then noctalia.log("tide-sidebar side-panel: " .. name .. ": " .. tostring(err)) end
end

local function restoreTab()
  local prefs = noctalia.state.get("preferences")
  local last = type(prefs) == "table" and prefs.tab or nil
  local cfg = noctalia.state.get("config")
  local fallback = type(cfg) == "table" and cfg.defaultTab or "notes"
  local wanted = last or fallback
  if wanted == "notes" then tab = "notes"
  elseif wanted == "tools" or wanted == "hotspot" then tab = "tools"
  else tab = "windows" end
end

function onOpen(context)
  guard("onOpen", function()
    noctalia.state.set("side_panel_open", true)
    restoreTab()
    panel.setWantsSecondTicks(true)
    refreshAll()
    render()
  end)
end

function update()
  guard("update", function()
    if tab == "notes" and editingId and noteDirty then
      send("note-edit", { id = editingId, body = draft })
      noteDirty = false
    end
    if pendingRefresh or tab ~= "notes" then
      refreshAll()
      if not (tab == "notes" and editingId) then render() end
    end
  end)
end

function onKey(chord, pressed)
  guard("onKey", function()
    if not pressed then return end
    if chord == "escape" then panel.close()
    elseif chord == "ctrl+1" then switchTab("windows")
    elseif chord == "ctrl+2" then switchTab("tools")
    elseif chord == "ctrl+3" then switchTab("calc")
    elseif chord == "ctrl+4" then switchTab("notes") end
  end)
end

function onClose()
  guard("onClose", function()
    noctalia.state.set("side_panel_open", false)
    if editingId and noteDirty then send("note-edit", { id = editingId, body = draft }); noteDirty = false end
    panel.setWantsSecondTicks(false)
  end)
end
