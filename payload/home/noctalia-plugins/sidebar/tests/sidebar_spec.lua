-- Offline host simulation: no desktop commands, subprocesses, or user files are touched.
-- Run from workspace root: lua sidebar/tests/sidebar_spec.lua
local SOURCE = arg[1] or "sidebar/panel.luau"
local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {} for k, x in pairs(v) do t[k] = copy(x) end return t
end
local function find(tree, key)
  if not tree then return end
  if tree.props and tree.props.key == key then return tree end
  for _, child in ipairs(tree.children or {}) do local v = find(child, key) if v then return v end end
end
local function visit(tree, fn)
  fn(tree)
  for _, child in ipairs(tree.children or {}) do visit(child, fn) end
end
local function harness(motion, layout)
  local h = { now = 1000000, renders = 0, nodes = 0, built = 0, frame = false, async = {}, encoded = {}, files = {}, fs = {}, errors = {} }
  local function ioCall(name) h.fs[name] = (h.fs[name] or 0) + 1 end
  if layout then h.files["/data/panel_layout.json"] = "layout" h.encoded.layout = layout end
  h.encoded.wins = { { id = 1, title = "Example", app_id = "example", is_focused = true, workspace_id = 1 } }
  h.encoded.workspaces = { { id = 1, idx = 1 } }
  local env = setmetatable({}, { __index = _G })
  env.ui = setmetatable({}, { __index = function(_, kind) return function(props, children)
    h.built = h.built + 1
    return { type = kind, props = props or {}, children = children or {} }
  end end })
  env.panel = {
    render = function(tree)
      h.renders = h.renders + 1 h.tree = copy(tree)
      visit(tree, function(n) h.nodes = h.nodes + 1 end)
    end,
    setNeedsFrameTick = function(v) h.frame = v end,
    setWantsSecondTicks = function(v) h.seconds = v end,
    close = function() env.onClose() end,
    openContextMenu = function() return true end,
  }
  env.noctalia = {
    getConfig = function(k) if k == "motion" then return motion or "light" end return nil end,
    pluginDataDir = function() return "/data" end,
    pluginDir = function() return "/plugin" end,
    nowMs = function() return h.now end,
    setUpdateInterval = function() end,
    formatTime = function(pattern) return pattern == "%H:%M" and "12:00" or "10 / 06 · 12:00" end,
    readFile = function(p) ioCall("read") if h.failRead and h.failRead[p] then return nil, "simulated read failure" end return h.files[p] end,
    writeFile = function(p, text) ioCall("write") if h.failWrite then return false, "simulated failure" end h.files[p] = text return true end,
    listDir = function(dir) ioCall("list") local names = {} for p in pairs(h.files) do local name = p:match("^" .. dir .. "/([^/]+)$") if name then names[#names + 1] = name end end return names end,
    mkdirAll = function() ioCall("mkdir") return true end,
    fileExists = function(p) ioCall("exists") return h.files[p] ~= nil end,
    renameFile = function() error("unexpected migration") end,
    removeFile = function(p) if not h.allowRemove then error("unexpected deletion: " .. p) end h.files[p] = nil return true end,
    expandPath = function(p) return p end,
    appIconPath = function() ioCall("icon") return nil end,
    fuzzyScore = function(q, name) if name:lower():find(q:lower(), 1, true) then return 1 end end,
    runAsync = function(cmd, cb) if h.rejectAsync then return false end h.async[#h.async + 1] = { command = cmd, callback = cb } return true end,
    runInTerminal = function() error("unexpected command execution") end,
    notifyError = function(_, msg) h.errors[#h.errors + 1] = msg end,
    notify = function() end,
    openSettings = function() end,
    copyToClipboard = function() return true end,
    systemStats = function() return { sampledAtMs = 10, cpu = { usagePercent = 5 }, ram = { usagePercent = 20, totalMb = 100, usedMb = 20 } } end,
    diskStats = function() ioCall("disk") return { usagePercent = 25 } end,
    string = { urlDecode = function(v) return (v:gsub("%%(%x%x)", function(x) return string.char(tonumber(x, 16)) end)) end },
    json = {
      encode = function(v) local k = "json-" .. tostring(#h.encoded + 1) h.encoded[#h.encoded + 1] = k h.encoded[k] = copy(v) return k end,
      decode = function(v) return copy(h.encoded[v]) end,
    },
  }
  assert(loadfile(SOURCE, "t", env))()
  h.env = env
  function h:deliver()
    local pending = self.async self.async = {}
    for _, req in ipairs(pending) do
      if req.callback then
        local cmd, result = req.command, { exitCode = 0, stdout = "" }
        if type(cmd) == "string" then
          if cmd:find("niri msg -j windows", 1, true) then result.stdout = [[wins
###
workspaces]]
          elseif cmd:find("XDG_DATA_HOME", 1, true) and cmd:find("applications", 1, true) then result.stdout = [[Example	example	example	0	/usr/share/applications/example.desktop	example.desktop	1
]]
          elseif cmd:find("playerctl metadata --format", 1, true) then result.exitCode = 1
          end
        end
        req.callback(result)
      end
    end
  end
  function h:step(ms)
    self.now = self.now + (ms or 16)
    if self.frame then self.env.onFrameTick(tostring(ms or 16)) end
  end
  function h:settle()
    for _ = 1, 80 do self:step(16) self:deliver() end
  end
  function h:layout() return self.encoded[self.files["/data/panel_layout.json"]] end
  function h:height(key) local n = find(self.tree, "body-" .. key) return n and n.props.visible ~= false and n.props.height or 0 end
  return h
end
if arg[2] == "--harness" then return { harness = harness, find = find, visit = visit, copy = copy } end
if arg[2] == "--bench" then
  local h = harness() h.fs = {} h.env.onOpen()
  local firstIO = 0 for _, count in pairs(h.fs) do firstIO = firstIO + count end
  h:settle()
  print(string.format("source=%s first_open_sync_io=%d open_renders=%d open_submitted_nodes=%d", SOURCE, firstIO, h.renders, h.nodes))
  local built = h.built
  h.env.onTimerSetSec(900)
  print("timer_action_built_nodes=" .. (h.built - built))
  local card = find(h.tree, "card-wins")
  card.children[1].props.onClick()
  local frames, nodes = h.renders, h.nodes
  h:settle()
  print(string.format("fold_renders=%d fold_submitted_nodes=%d", h.renders - frames, h.nodes - nodes))
  return
end

if arg[2] == "--collapse" then
  local h = harness() h.env.onOpen() h:settle()
  h.env.onIpc("toggle", "wins") h:settle() -- open the wins card first
  print("open height: " .. string.format("%.1f", h:height("wins")))
  local seq = {}
  h.env.onIpc("toggle", "wins") -- collapse it
  for _ = 1, 30 do
    h:step(16)
    seq[#seq + 1] = string.format("%.1f", h:height("wins"))
  end
  print("collapse heights: " .. table.concat(seq, " "))
  return
end

local passed = 0
local function test(name, fn) fn() passed = passed + 1 print("PASS " .. name) end

test("first frame precedes subprocess IO", function()
  local h = harness() h.fs = {} h.env.onOpen()
  assert(h.renders == 1 and #h.async == 0)
  assert(not h.fs.mkdir and not h.fs.list and not h.fs.write)
  assert((h.fs.read or 0) == 1, "only layout read is allowed before first frame")
  visit(h.tree, function(n) assert(n.props.opacity == nil or n.props.opacity == 1, "no group alpha animation") end)
  h:settle() assert(not h.frame and h.seconds)
end)

test("rapid reversal is continuous and ends at the latest target", function()
  local h = harness("soft") h.env.onOpen() h:settle()
  h.env.onIpc("toggle", "wins") h:step() h:step(64)
  local mid = h:height("wins") assert(mid > 0 and mid < 100)
  h.env.onIpc("toggle", "wins") assert(math.abs(h:height("wins") - mid) < 1)
  h:step() h:step(32) assert(h:height("wins") < mid)
  h.env.onIpc("toggle", "wins") h:settle()
  assert(h:height("wins") > 0 and not h.frame)
end)

test("animation frames build no controls and perform no IO", function()
  local h = harness("soft") h.env.onOpen() h:settle()
  h.env.onIpc("toggle", "wins")
  local built, fs = h.built, copy(h.fs)
  h:step() h:step(48) h:step(48)
  assert(h.built == built)
  for k, v in pairs(h.fs) do assert(fs[k] == v, "IO during animation: " .. k) end
end)

test("focus mode restores the previous layout", function()
  local h = harness() h.env.onOpen() h:settle()
  h.env.onIpc("focus") h:settle()
  assert(h:height("search") > 0 and h:height("timer") == 0)
  h.env.onIpc("toggle", "timer") h:settle()
  assert(h:height("timer") > 0 and h:height("search") == 0)
  h.env.onIpc("focus") h:settle()
  assert(h:height("search") > 0 and h:height("timer") == 0)
end)

test("pins persist; drag validates keys and crosses groups", function()
  local h = harness() h.env.onOpen() h:settle()
  h.env.onIpc("pin", "timer") h:settle()
  assert(h:layout().pinned.timer)
  local list = find(h.tree, "cards").children[1].children
  assert(list[1].props.key == "pinned-label" and list[2].props.key == "card-timer")
  h.env.onCardDrop("wins", "before|timer") h:settle() assert(h:layout().pinned.wins)
  local before = h.renders h.env.onCardDrop("invalid", "before|search") assert(h.renders == before)
end)

test("motion off creates no animation frames; close flushes layout", function()
  local h = harness("off") h.env.onOpen() h:settle()
  h.env.onIpc("toggle", "wins") assert(h:height("wins") > 0)
  local renders = h.renders h:step(16) assert(h.renders == renders)
  h.env.onClose() assert(not h.frame and not h.seconds and h:layout().open.wins)
end)

test("focus is a one-shot request, never repeated by cached renders", function()
  local h = harness() h.env.onOpen()
  assert(find(h.tree, "search-1").props.focus)
  h:settle() assert(not find(h.tree, "search-1").props.focus)
  h.env.onIpc("toggle", "wins") h:step(16) h:step(32)
  assert(not find(h.tree, "search-1").props.focus)
end)

test("closing invalidates pending callbacks and stops ticks", function()
  local h = harness() h.env.onOpen() h:step(300) h:step(16)
  assert(#h.async > 0) h.env.onClose()
  local renders = h.renders h:deliver() h:step(100)
  assert(h.renders == renders and not h.frame)
  h.env.onOpen() h:settle() assert(not h.frame)
end)

test("legacy and malformed layout migration is complete and unique", function()
  local h = harness(nil, { order = { "timer", "timer", "unknown", 1 }, open = { search = false }, pinned = { timer = true } })
  h.env.onOpen() h:settle()
  assert(h:height("search") == 0)
  local seen, count = {}, 0
  visit(h.tree, function(n) local k = n.props.key if k and k:match("^card%-") then assert(not seen[k]) seen[k] = true count = count + 1 end end)
  assert(count == 6)
end)

test("stable idle update does not rebuild unrelated cards", function()
  local h = harness() h.env.onOpen() h:settle()
  h.env.update() h:deliver() h:settle()
  local renders, built = h.renders, h.built
  h.env.update() h:deliver() h:settle()
  assert(h.renders == renders and h.built == built)
end)

print(string.format("%d tests passed", passed))
