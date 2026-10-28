--!nonstrict
-- pang/tide-sidebar — 「工具」页的声明式 UI 原型（Noctalia 5.4 / plugin_api 42）
--
-- 倒计时 / 秒表 / 热点三块，全部读服务发布的快照（private/frontend/*.json），
-- 操作则通过 `noctalia msg plugin pang/tide-sidebar:backend all <event>` 回到服务，
-- 和原生前端走同一份状态与同一套动作，不存在两套数据。
--
-- 打开：noctalia msg panel-open pang/tide-sidebar:tools-proto

local dataRoot = noctalia.pluginDataDir()
local dataDir = (type(dataRoot) == "string" and dataRoot or "") .. "/private"
local timer, stopwatch, hotspot

local function num(value)
  return type(value) == "number" and value or 0
end

local function read(name)
  local raw = noctalia.readFile(dataDir .. "/frontend/" .. name .. ".json")
  if type(raw) ~= "string" or raw == "" then return nil end
  local ok, value = pcall(noctalia.json.decode, raw)
  if not ok or type(value) ~= "table" then return nil end
  return type(value.data) == "table" and value.data or value
end

local function clock(ms)
  local total = math.max(0, math.floor(num(ms) / 1000))
  return string.format("%02d:%02d", math.floor(total / 60), total % 60)
end

local function stopClock(ms)
  local cs = math.max(0, math.floor(num(ms) / 10))
  return string.format("%02d:%02d.%02d", math.floor(cs / 6000), math.floor(cs / 100) % 60, cs % 100)
end

local function send(event, value)
  local argv = { "noctalia", "msg", "plugin", "pang/tide-sidebar:backend", "all", event }
  if value ~= nil then argv[#argv + 1] = tostring(value) end
  noctalia.runAsync(argv, function() end)
end

local function button(text, onClick, variant)
  return ui.button({ text = text, variant = variant or "ghost", controlSize = "sm", onClick = onClick })
end

local render

function render()
  local t = timer or {}
  local w = stopwatch or {}
  local h = hotspot or {}
  local remaining = num(t.remainingMs)
  local duration = num(t.durationMs)
  local status = t.status or "idle"

  local timerButtons = {}
  if status == "running" then
    timerButtons[#timerButtons + 1] = button("暂停", function() send("timer-pause") end)
  elseif status == "paused" then
    timerButtons[#timerButtons + 1] = button("继续", function() send("timer-resume") end, "primary")
  else
    timerButtons[#timerButtons + 1] = button("开始", function()
      send("timer-start", math.max(1, math.floor(duration / 1000)))
    end, "primary")
  end
  timerButtons[#timerButtons + 1] = button("重置", function() send("timer-reset", 1500) end)
  for _, minutes in ipairs({ 5, 15, 25, 60 }) do
    timerButtons[#timerButtons + 1] = button(tostring(minutes), function() send("timer-start", minutes * 60) end)
  end

  local stopwatchButtons = {
    button(w.status == "running" and "暂停" or "开始", function()
      send(w.status == "running" and "stopwatch-pause" or "stopwatch-start")
    end, "primary"),
    button("重置", function() send("stopwatch-reset") end),
  }

  local hotspotButton = button(h.on and "关闭热点" or "开启热点", function()
    send("hotspot", h.on and "off" or "on")
  end, h.on and "destructive" or "default")

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

  local progress = duration > 0
      and ui.progress({ progress = math.max(0, math.min(1, 1 - remaining / duration)), height = 6, radius = 3 })
      or nil

  panel.render(ui.column({ width = 396, padding = 12, gap = 10 }, {
    ui.row({ justify = "space_between", align = "center" }, {
      ui.label({ text = "工具", fontSize = 13, color = "on_surface" }),
      ui.label({ text = "声明式原型", fontSize = 11, color = "on_surface_variant" }),
    }),
    card("倒计时", clock(remaining), timerButtons, progress),
    card("秒表", stopClock(w.elapsedMs), stopwatchButtons),
    card("热点", h.on and ("已开启 · " .. tostring(h.ssid or "")) or "已关闭", { hotspotButton }),
  }))
end

local function refresh()
  timer = (read("timer") or {}).timer
  stopwatch = (read("stopwatch") or {}).stopwatch
  hotspot = (read("system") or {}).hotspot
  render()
end

local function guard(name, fn)
  local ok, err = pcall(fn)
  if not ok and type(noctalia.log) == "function" then
    noctalia.log("tide-sidebar tools prototype: " .. name .. ": " .. tostring(err))
  end
end

function onOpen(context)
  guard("onOpen", function()
    panel.setWantsSecondTicks(true)
    refresh()
  end)
end

function update()
  guard("update", function()
    refresh()
  end)
end

function onClose()
  guard("onClose", function()
    panel.setWantsSecondTicks(false)
  end)
end
