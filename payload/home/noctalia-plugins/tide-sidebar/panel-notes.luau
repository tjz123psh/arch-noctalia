--!nonstrict
-- pang/tide-sidebar — 「便签」页的声明式 UI 原型（Noctalia 5.4 / plugin_api 42）
--
-- 目的：验证 ui.input(multiline) 能不能撑起居中的便签编辑。数据与原生前端同源：
-- 读服务发布的 private/frontend/notes.json（含 revision/trash），写回走 note-* IPC。
--
-- 已知取舍（相对原生 TextView）：没有撤销栈；保存粒度是"每秒最多一次"；
-- 不支持富文本/自动增高。列表与回收区逻辑完全复用服务。
--
-- 打开：noctalia msg panel-open pang/tide-sidebar:notes-proto

local dataRoot = noctalia.pluginDataDir()
local dataDir = (type(dataRoot) == "string" and dataRoot or "") .. "/private"

local model = nil
local view = "list"
local editingId = nil
local draft = ""
local dirty = false
local errorText = nil
local pending = false

local function read(name)
  local raw = noctalia.readFile(dataDir .. "/frontend/" .. name .. ".json")
  if type(raw) ~= "string" or raw == "" then return nil end
  local ok, value = pcall(noctalia.json.decode, raw)
  if not ok or type(value) ~= "table" then return nil end
  return type(value.data) == "table" and value.data or value
end

local function send(event, args)
  local argv = { "noctalia", "msg", "plugin", "pang/tide-sidebar:backend", "all", event }
  if args ~= nil then argv[#argv + 1] = noctalia.json.encode(args) end
  noctalia.runAsync(argv, function() end)
  pending = true
end

local function findNote(id)
  for _, note in ipairs(model and model.notes or {}) do
    if note.id == id then return note end
  end
  return nil
end

local function preview(body)
  local first = tostring(body or ""):gsub("%s+", " ")
  first = first:gsub("^%s+", "")
  if #first > 42 then first = first:sub(1, 42) .. "…" end
  return first
end

local render

local function listView()
  local notes = model and model.notes or {}
  local rows = {}
  for _, note in ipairs(notes) do
    rows[#rows + 1] = ui.button({
      key = "note-" .. note.id,
      text = tostring(note.title or "便签") .. "   " .. preview(note.body),
      variant = (note.id == (model.activeId or "")) and "secondary" or "ghost",
      controlSize = "sm",
      contentAlign = "start",
      tooltip = "打开这条便签",
      onClick = function()
        editingId = note.id
        draft = tostring(note.body or "")
        dirty = false
        view = "edit"
        send("note-select", { id = note.id })
        render()
      end,
    })
  end
  if #rows == 0 then
    rows[1] = ui.label({ text = "还没有便签", fontSize = 11, color = "on_surface_variant" })
  end

  panel.render(ui.column({ width = 436, padding = 12, gap = 8 }, {
    ui.row({ justify = "space_between", align = "center" }, {
      ui.label({ text = "便签 · " .. tostring(#notes) .. " 条", fontSize = 13, color = "on_surface" }),
      ui.button({
        text = "新建", variant = "primary", controlSize = "sm",
        onClick = function() send("note-add", { title = "新便签" }); render() end,
      }),
    }),
    ui.scroll({ height = math.max(36, math.min(#notes * 36, 360)), gap = 4 }, rows),
    ui.label({ text = "回收区 " .. tostring(model and model.trash and #model.trash or 0) .. " 条 · Esc 关闭", fontSize = 10, color = "on_surface_variant" }),
  }))
end

local function editView()
  local note = findNote(editingId)
  local chars = #draft
  panel.render(ui.column({ width = 436, padding = 12, gap = 8 }, {
    ui.row({ justify = "space_between", align = "center" }, {
      ui.button({
        text = "返回", variant = "ghost", controlSize = "sm",
        onClick = function()
          if dirty then send("note-edit", { id = editingId, body = draft }); dirty = false end
          view = "list"; render()
        end,
      }),
      ui.label({ text = tostring(note and note.title or "便签"), fontSize = 13, color = "on_surface" }),
      ui.button({
        text = "删除", variant = "destructive", controlSize = "sm",
        onClick = function()
          send("note-delete", { id = editingId })
          dirty = false; view = "list"; render()
        end,
      }),
    }),
    ui.input({
      value = draft,
      multiline = true,
      height = 400,
      focus = true,
      placeholder = "写点什么…",
      onChange = function(text) draft = text; dirty = true end,
    }),
    ui.row({ justify = "space_between", align = "center" }, {
      ui.label({ text = tostring(chars) .. " 字", fontSize = 10, color = "on_surface_variant" }),
      ui.label({ text = dirty and "未保存（每秒自动保存）" or "已保存", fontSize = 10, color = "on_surface_variant" }),
    }),
  }))
end

render = function()
  if view == "edit" then editView() else listView() end
end

local function guard(name, fn)
  local ok, err = pcall(fn)
  if not ok and type(noctalia.log) == "function" then
    noctalia.log("tide-sidebar notes prototype: " .. name .. ": " .. tostring(err))
  end
end

local function refresh()
  local snapshot = read("notes")
  if snapshot then
    model = snapshot.model or model
    errorText = type(snapshot.error) == "string" and snapshot.error ~= "" and snapshot.error or nil
  end
  pending = false
end

function onOpen(context)
  guard("onOpen", function()
    view = "list"
    editingId = nil
    dirty = false
    panel.setWantsSecondTicks(true)
    refresh()
    render()
  end)
end

function update()
  guard("update", function()
    if dirty and view == "edit" and editingId then
      send("note-edit", { id = editingId, body = draft })
      dirty = false
    end
    if pending or view == "list" then
      refresh()
      if view == "list" then render() end
    end
  end)
end

function onClose()
  guard("onClose", function()
    if dirty and view == "edit" and editingId then
      send("note-edit", { id = editingId, body = draft })
      dirty = false
    end
    panel.setWantsSecondTicks(false)
  end)
end
