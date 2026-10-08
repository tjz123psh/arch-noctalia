-- Deterministic offline regressions; never runs desktop commands or writes user data.
local env = setmetatable({ arg = { arg[1] or "sidebar/panel.luau", "--harness" } }, { __index = _G })
local H = assert(loadfile("sidebar/tests/sidebar_spec.lua", "t", env))()
local harness, find, visit = H.harness, H.find, H.visit
local passed = 0
local function test(name, fn) fn() passed = passed + 1 print("PASS " .. name) end
local function ready(motion, layout) local h = harness(motion, layout) h.env.onOpen() h:settle() return h end
local function take(h, predicate)
  for i, req in ipairs(h.async) do if predicate(req.command) then return table.remove(h.async, i) end end
  error("expected request not queued")
end
local function input(h)
  local result
  visit(h.tree, function(n) if n.type == "input" and n.props.multiline then result = n end end)
  return result
end
local function text(h, needle)
  local found = false
  visit(h.tree, function(n) if n.props.text and n.props.text:find(needle, 1, true) then found = true end end)
  return found
end

test("light expansion fixes geometry immediately, not on every frame", function()
  local h = ready("light") local built = h.built
  h.env.onIpc("toggle", "wins") local height = h:height("wins")
  assert(height > 0 and h.built == built, "warm click should reuse control descriptions")
  for _ = 1, 24 do h:step(8) assert(h:height("wins") == height) end
  h.env.onIpc("toggle", "wins") assert(h:height("wins") == 0)
end)

test("soft cold expansion starts near zero rather than jumping open", function()
  local h = harness("soft") h.env.onOpen() h.env.onIpc("toggle", "wins")
  assert(h:height("wins") < 1)
  h:step(48) assert(h:height("wins") > 1 and h:height("wins") < 48)
  h:settle() assert(h:height("wins") > 0 and not h.frame)
end)

test("soft high-refresh ticks have a bounded submit rate", function()
  local h = ready("soft") h.env.onIpc("toggle", "wins") local renders = h.renders
  for _ = 1, 55 do h:step(4) end
  assert(h.renders - renders <= 15, "must not submit at 250Hz")
  h:settle() assert(not h.frame)
end)

test("closing halfway through soft motion reopens at the saved target", function()
  local h = ready("soft") h.env.onIpc("toggle", "wins") h:step(48)
  h.env.onClose() h.env.onOpen() assert(h:height("wins") > 0)
  h:settle() assert(not h.frame and h:layout().open.wins)
end)

test("toolbar count follows header toggles immediately", function()
  local h = ready() assert(find(h.tree, "toolbar-status").props.text == "1 项展开")
  h.env.onIpc("toggle", "wins") assert(find(h.tree, "toolbar-status").props.text == "2 项展开")
end)

test("end drop exits the pinned group and malformed drops do nothing", function()
  local h = ready() h.env.onIpc("pin", "wins") h:settle()
  h.env.onCardDrop("wins", "end") h:settle() assert(not h:layout().pinned.wins)
  local n = h.renders
  h.env.onCardDrop(nil, nil) h.env.onCardDrop("wins", "garbage|timer") h.env.onCardDrop("wins", "before|bad")
  assert(h.renders == n)
end)

test("collapsed inputs are detached and stale input callbacks are ignored", function()
  local h = ready() h.env.onIpc("toggle", "search") assert(not find(h.tree, "search-1"))
  h.env.onSearchChanged("invisible") h.env.onIpc("toggle", "search")
  assert(find(h.tree, "search-1").props.value == "")
end)

test("desktop IDs apply tombstones but keep distinct same-name apps", function()
  local h = harness() h.env.onOpen() h:step(300) h:step(16)
  local req = take(h, function(c) return type(c) == "string" and c:find("XDG_DATA_DIRS", 1, true) end)
  req.callback({ exitCode = 0, stdout = table.concat({
    "Hidden\texec\t\t0\t/user/hidden.desktop\thidden.desktop\t0",
    "Hidden\texec\t\t0\t/system/hidden.desktop\thidden.desktop\t1",
    "Same\texec\t\t0\t/one.desktop\tone.desktop\t1",
    "Same\texec\t\t0\t/two.desktop\ttwo.desktop\t1",
  }, "\n") })
  h:settle() h.env.onSearchChanged("Same")
  assert(find(h.tree, "res-one") and find(h.tree, "res-two"))
  h.env.onSearchChanged("Hidden") assert(not find(h.tree, "res-hidden"))
end)

test("application launch uses desktop file argv rather than raw shell Exec", function()
  local h = ready() h.env.onSearchChanged("Example") h.env.onSearchSubmit()
  local req = take(h, function(c) return type(c) == "table" and c[1] == "gio" end)
  assert(req.command[2] == "launch" and req.command[3] == "/usr/share/applications/example.desktop")
end)

test("recent file localhost authority and XML entities decode exactly once", function()
  local h = ready() h.env.update()
  local req = take(h, function(c) return type(c) == "string" and c:find("recently-used.xbel", 1, true) end)
  req.callback({ exitCode = 0, stdout = '<bookmark href="file://localhost/tmp/a%20b%2B&amp;x.txt" visited="2026"/>\n<bookmark href="file://remote/tmp/no.txt" visited="2027"/>' })
  h.env.onIpc("toggle", "recent") h:settle()
  local row = assert(find(h.tree, "rec-1")) assert(not find(h.tree, "rec-2"))
  row.props.onClick()
  local open = take(h, function(c) return type(c) == "string" and c:find("xdg-open", 1, true) end)
  assert(open.command == "xdg-open '/tmp/a b+&x.txt'")
end)

-- v2.2 计时器：自由时长解析 / 启动参数与到点文案 / 运行中延长
test("timer free-duration input parses flexible syntaxes", function()
  local h = ready(nil, { open = { timer = true } })
  for _, c in ipairs({
    { "90s", "1:30" }, { "25m", "25:00" }, { "1h30m", "1:30:00" }, { "1:30", "1:30" },
    { "1:30:00", "1:30:00" }, { "2时", "2:00:00" }, { "90", "1:30:00" }, { "90分30秒", "1:30:30" },
    { "1小时15分", "1:15:00" },
  }) do
    h.env.onTimerDurInput(c[1])
    assert(text(h, c[2]), "expected " .. c[2] .. " for " .. c[1])
  end
  for _, bad in ipairs({ "abc", "0", "1:70", "-5", "25x" }) do
    h.env.onTimerDurInput(bad)
    assert(text(h, "无法识别的时长"), "expected error hint for " .. bad)
  end
end)

test("timer start passes seconds and readable message", function()
  local h = ready()
  h.env.onTimerSetSec(90)
  h.env.onTimerToggle()
  local start = take(h, function(cmd) return type(cmd) == "string" and cmd:find("action='start'", 1, true) end)
  assert(start.command:find("secs='90'", 1, true))
  assert(start.command:find("1 分钟 30 秒到了", 1, true))
end)

test("timer extend restarts with remaining plus added time", function()
  local h = ready()
  h.env.onTimerSetSec(600)
  h.env.onTimerToggle()
  local start = take(h, function(cmd) return type(cmd) == "string" and cmd:find("action='start'", 1, true) end)
  assert(start.command:find("secs='600'", 1, true))
  start.callback({ exitCode = 0, stdout = "LIVE 4242 8888 mock-round" })
  h:step(60000)
  h.env.onTimerExtend(300)
  local stop = take(h, function(cmd) return type(cmd) == "string" and cmd:find("action='stop'", 1, true) end)
  stop.callback({ exitCode = 0, stdout = "STOPPED" })
  local restart = take(h, function(cmd) return type(cmd) == "string" and cmd:find("action='start'", 1, true) end)
  assert(restart.command:find("secs='840'", 1, true), "expected remaining 540 + 300")
end)

test("timer ipc channel starts and stops", function()
  local h = ready()
  h.env.onIpc("timer", "start:2m")
  local start = take(h, function(cmd) return type(cmd) == "string" and cmd:find("action='start'", 1, true) end)
  assert(start.command:find("secs='120'", 1, true))
  start.callback({ exitCode = 0, stdout = "LIVE 4242 8888 mock-round" })
  h:settle()
  h.env.onIpc("timer", "stop")
  local stop = take(h, function(cmd) return type(cmd) == "string" and cmd:find("action='stop'", 1, true) end)
  assert(stop.command:find("action='stop'", 1, true))
end)

print(passed .. " regressions passed")
