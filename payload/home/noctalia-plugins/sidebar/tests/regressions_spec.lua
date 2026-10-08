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
  local h = ready() assert(find(h.tree, "toolbar-status").props.text == "3 项展开")
  h.env.onIpc("toggle", "wins") assert(find(h.tree, "toolbar-status").props.text == "4 项展开")
end)

test("end drop exits the pinned group and malformed drops do nothing", function()
  local h = ready() h.env.onIpc("pin", "wins") h:settle()
  h.env.onCardDrop("wins", "end") h:settle() assert(not h:layout().pinned.wins)
  local n = h.renders
  h.env.onCardDrop(nil, nil) h.env.onCardDrop("wins", "garbage|note") h.env.onCardDrop("wins", "before|bad")
  assert(h.renders == n)
end)

test("collapsed inputs are detached and stale input callbacks are ignored", function()
  local h = ready() h.env.onNoteEdited("keep me")
  h.env.onIpc("toggle", "note") assert(not input(h))
  h.env.onNoteEdited("hidden edit") h.env.onIpc("toggle", "note")
  assert(input(h).props.value == "keep me")
  h.env.onIpc("toggle", "search") assert(not find(h.tree, "search-1"))
  h.env.onSearchChanged("invisible") h.env.onIpc("toggle", "search")
  assert(find(h.tree, "search-1").props.value == "")
end)

test("typing is reflected in retained descriptions before unrelated renders", function()
  local h = ready() h.env.onNoteEdited("new text")
  h.env.onIpc("toggle", "wins") assert(input(h).props.value == "new text")
end)

test("initial read failure never becomes an editable empty note", function()
  local h = harness() h.failRead = { ["/notes/second.md"] = true }
  h.env.onOpen() h:settle() assert(not input(h) and #h.errors > 0)
  h.env.onNoteEdited("must not save") h.env.onClose()
  assert(h.files["/notes/second.md"] == "second note")
end)

test("failed note switch keeps buffer, selection and save destination", function()
  local h = ready() h.failRead = { ["/notes/便签.md"] = true }
  h.env.onNoteSwitch("1") assert(find(h.tree, "note-select").props.selectedIndex == 0)
  assert(input(h).props.value == "second note")
  h.env.onNoteEdited("safe edit") h.env.onClose()
  assert(h.files["/notes/second.md"] == "safe edit" and h.files["/notes/便签.md"] == "existing note")
end)

test("new note creation is exclusive and cannot clear an external file", function()
  local h = ready() h.files["/notes/便签-2.md"] = "external valuable text"
  h.env.onNoteSwitch("2")
  local req = take(h, function(c) return type(c) == "table" and c[4] == "sidebar-note-create" end)
  assert(req.command[3]:find("set -C", 1, true) and req.command[5] == "/notes")
  assert(h.files["/notes/便签-2.md"] == "external valuable text")
  h.files["/notes/便签-3.md"] = "" req.callback({ exitCode = 0, stdout = "便签-3.md\n" })
  h:settle() h.env.onNoteEdited("my new note") h.env.onClose()
  assert(h.files["/notes/便签-2.md"] == "external valuable text")
  assert(h.files["/notes/便签-3.md"] == "my new note")
end)

test("new note launch failure leaves existing notes intact", function()
  local h = ready() h.rejectAsync = true h.env.onNoteSwitch("2")
  assert(#h.errors > 0 and input(h).props.value == "second note")
  assert(h.files["/notes/便签.md"] == "existing note")
end)

test("invalid note selection cannot create or switch files", function()
  local h = ready() local n = #h.async
  h.env.onNoteSwitch("-1") h.env.onNoteSwitch("1.5") h.env.onNoteSwitch("1000")
  assert(#h.async == n and input(h).props.value == "second note")
end)

test("delete requires confirmation and cannot delete the last note", function()
  local h = ready() h.env.onDeleteConfirm() assert(h.files["/notes/second.md"])
  h.files["/notes/便签.md"] = nil h.env.onClose() h.env.onOpen() h:settle()
  h.env.onNoteMenuAction("delete") h.env.onDeleteConfirm()
  assert(h.files["/notes/second.md"])
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

test("note placeholder reserves final geometry before data arrives", function()
  local h = harness() h.env.onOpen() local height = h:height("note")
  assert(height == 240) h:settle() assert(h:height("note") == height)
end)

test("legacy migration keeps original and exclusively creates a copy", function()
  local h = harness() h.files["/notes/second.md"], h.files["/notes/便签.md"] = nil, nil
  h.files["~/Documents/scratchpad.md"] = "legacy valuable content"
  h.env.onOpen() h:step(300)
  local req = take(h, function(c) return type(c) == "table" and c[4] == "sidebar-note-create" end)
  h.files["/notes/便签.md"] = "" req.callback({ exitCode = 0, stdout = "便签.md" })
  h:settle() assert(h.files["~/Documents/scratchpad.md"] == "legacy valuable content")
  assert(h.files["/notes/便签.md"] == "legacy valuable content")
end)

test("reopen read failure locks stale cached note against overwriting disk", function()
  local h = ready() h.env.onClose()
  h.files["/notes/second.md"] = "external changed content" h.failRead = { ["/notes/second.md"] = true }
  h.env.onOpen() h:settle() assert(not input(h))
  h.env.onNoteEdited("unsafe") h.env.onClose()
  assert(h.files["/notes/second.md"] == "external changed content")
end)

test("panel open reclaims orphaned cover files but keeps real data", function()
  local h = harness() h.allowRemove = true
  h.files["/data/sidebar-art-A1b2C3d4E5"] = "orphaned cover"
  h.files["/data/art_0.jpg"] = "legacy slot"
  h.files["/data/app_usage.json"] = "{}"
  h.env.onOpen() h:settle()
  assert(h.files["/data/sidebar-art-A1b2C3d4E5"] == nil and h.files["/data/art_0.jpg"] == nil)
  assert(h.files["/data/app_usage.json"] == "{}" and h.files["/notes/便签.md"] == "existing note")
end)

test("cover sweep runs after the first frame, not during it", function()
  local h = harness() h.allowRemove = true h.files["/data/sidebar-art-Zz9Yy8Xx7W"] = "orphan"
  h.fs = {} h.env.onOpen()
  assert(h.fs.list == nil and h.files["/data/sidebar-art-Zz9Yy8Xx7W"] == "orphan")
  h:settle() assert(h.files["/data/sidebar-art-Zz9Yy8Xx7W"] == nil)
end)

print(passed .. " regressions passed")
