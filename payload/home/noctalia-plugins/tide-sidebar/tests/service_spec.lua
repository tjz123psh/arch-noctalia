-- Execute the REAL service entry and its registered callbacks, not a rewritten service.
-- Run: lua tide-sidebar/tests/service_spec.lua (or lua tests/service_spec.lua).
-- All Noctalia APIs are mocked. No shell, network, window or real data-file operation runs.
local source = debug.getinfo(1, "S").source
local directory = source:match("^@(.*/)") or "./"
local BASE = "/mock/plugin-data/private"
local EPOCH = 1700000000000
local passed, failed, assertions = 0, 0, 0

local function check(condition, message)
    assertions = assertions + 1
    if not condition then error(message or "assertion failed", 2) end
end
local function equal(actual, expected, message)
    check(actual == expected, (message or "values differ") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, run)
    local ok, err = pcall(run)
    if ok then passed = passed + 1 else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

-- Deterministic JSON-shaped round-tripping is the mocked host codec, not a JSON
-- parser under test. Decode returns a fresh value; unknown/corrupt raw data throws.
-- The registry survives a new service VM just as the mocked disk survives it.
local encodedValues = {}
local function encode(value)
    local seen = {}
    local function quoted(text)
        local output = { '"' }
        for index = 1, #text do
            local byte = text:byte(index)
            if byte == 34 then output[#output + 1] = '\\"'
            elseif byte == 92 then output[#output + 1] = '\\\\'
            elseif byte < 32 then output[#output + 1] = string.format('\\u%04x', byte)
            else output[#output + 1] = string.char(byte) end
        end
        output[#output + 1] = '"'
        return table.concat(output)
    end
    local visit
    visit = function(item)
        local kind = type(item)
        if kind == "nil" then return "null" end
        if kind == "boolean" then return tostring(item) end
        if kind == "string" then return quoted(item) end
        if kind == "number" then
            assert(item == item and math.abs(item) < math.huge, "non-finite JSON number")
            return string.format("%.17g", item)
        end
        assert(kind == "table" and not seen[item], "invalid JSON value")
        seen[item] = true
        local array, length = true, #item
        for key in pairs(item) do
            if type(key) ~= "number" or key < 1 or key > length or key % 1 ~= 0 then array = false end
        end
        local parts = {}
        if array then
            for index = 1, length do parts[#parts + 1] = visit(item[index]) end
        else
            local keys = {}
            for key in pairs(item) do assert(type(key) == "string"); keys[#keys + 1] = key end
            table.sort(keys)
            for _, key in ipairs(keys) do parts[#parts + 1] = quoted(key) .. ":" .. visit(item[key]) end
        end
        seen[item] = nil
        return (array and "[" or "{") .. table.concat(parts, ",") .. (array and "]" or "}")
    end
    local raw = visit(value)
    encodedValues[raw] = copy(value)
    return raw
end
local function decode(raw)
    assert(type(raw) == "string" and encodedValues[raw] ~= nil, "invalid mock JSON")
    return copy(encodedValues[raw])
end
local function newDisk() return { files = {}, writes = {} } end
local function put(disk, name, value) disk.files[BASE .. "/" .. name] = encode(value) end
local function model(revision, body)
    return {version=1, revision=revision, nextId=2, activeId="note-1", notes={
        {id="note-1",title="Fixture",body=body or "",createdAt=EPOCH,updatedAt=EPOCH}
    }, trash={}}
end
local function systemResult()
    return {ok=true,hotspot={available=true,on=false,ssid="Tide-test",desiredSsid="Tide-test",
        iface="mock-wlan",gateway="",desiredBand="bg",busy=false},
        windows={{id="7",title="Fixture window",appId="fixture"}}}
end

local function boot(options)
    options = options or {}
    local h = {now=options.now or EPOCH,disk=options.disk or newDisk(),values={},history={},
        watchers={},requests={},notifications={},mkdirs={},reads={},encodeAttempts=0,
        reject=options.reject or {}}
    local function label(argv) return argv[1] == "chmod" and "chmod" or argv[3] end
    function h:count(kind, pending)
        local count = 0
        for _, request in ipairs(self.requests) do
            if request.kind == kind and (not pending or not request.done) then count = count + 1 end
        end
        return count
    end
    function h:reply(kind, value, overrides)
        local request
        for _, candidate in ipairs(self.requests) do
            if candidate.kind == kind and not candidate.done then request = candidate; break end
        end
        assert(request, "no pending mock request: " .. kind)
        request.done = true
        local result = {exitCode=0,stdout=value ~= nil and encode(value) or "",stderr="",
            timedOut=false,stdoutTruncated=false,stderrTruncated=false}
        for key, item in pairs(overrides or {}) do result[key] = item end
        request.callback(result)
        return request
    end
    function h:initialize(exitCode, finishSnapshot)
        self:reply("chmod", nil, {exitCode=exitCode or 0})
        if finishSnapshot ~= false and self:count("snapshot",true) > 0 then
            self:reply("snapshot", systemResult())
        end
        return self
    end
    function h:send(command) self.host.state.set("command", command) end
    function h:visibility(open) self.host.state.set("visibility", {open=open}) end
    function h:tick(milliseconds) self.now = self.now + milliseconds; self.env.update() end
    function h:notes() return self.values.notes_snapshot end
    function h:timer() return self.values.timer_snapshot end
    function h:writeCount(kind)
        local count = 0
        for _, call in ipairs(self.disk.writes) do
            if not kind or call.path:match("/" .. kind .. "%-%a%.json$") then count = count + 1 end
        end
        return count
    end
    function h:latest(kind)
        local best, slot
        for _, suffix in ipairs({"a", "b"}) do
            local name = kind .. "-" .. suffix .. ".json"
            local ok, value = pcall(decode, self.disk.files[BASE .. "/" .. name])
            if ok and type(value) == "table" and type(value.revision) == "number"
                and (not best or value.revision > best.revision) then best, slot = value, name end
        end
        return best, slot
    end
    local host = {}
    host.pluginDir = function() return "/mock/plugin" end
    host.pluginDataDir = function()
        if options.dataDirUnavailable then return nil, "mock data directory unavailable" end
        return "/mock/plugin-data"
    end
    host.nowMs = function() return h.now end
    -- Declared plugin settings only; the service is expected to read nothing else.
    h.config = copy(options.config or {})
    host.getConfig = function(key) return h.config[key] end
    host.setUpdateInterval = function(value) h.interval = value end
    host.mkdirAll = function(path)
        h.mkdirs[#h.mkdirs + 1] = path
        if options.mkdirMode == "fail" then return false, "mock mkdir failed" end
        if options.mkdirMode == "throw" then error("mock mkdir exception") end
        return true
    end
    host.readFile = function(path)
        h.reads[#h.reads + 1] = path
        -- API 32 returns the SAME generic error for missing and unreadable files.
        -- Tests must not distinguish these by inventing errno-bearing messages.
        if (h.disk.readErrors and h.disk.readErrors[path]) or h.disk.files[path] == nil then
            return nil, "cannot open file"
        end
        return h.disk.files[path]
    end
    host.fileExists = function(path) return h.disk.files[path] ~= nil end
    host.writeFile = function(path, raw)
        assert(type(raw) == "string", "writeFile expects bytes")
        h.disk.writes[#h.disk.writes + 1] = {path=path,raw=raw}
        local mode = (path:match("/notes%-%a%.json$") and h.disk.notesMode)
            or (path:match("/timer%-%a%.json$") and h.disk.timerMode)
            or (path:match("/stopwatch%-%a%.json$") and h.disk.stopwatchMode)
        if mode == "fail" then return false end
        if mode == "throw" then error("mock write failed") end
        h.disk.files[path] = mode == "corrupt" and "{broken" or raw
        return true
    end
    host.json = {
        encode=function(value)
            h.encodeAttempts = h.encodeAttempts + 1
            if h.encodeFailure then error("mock encode failed") end
            if h.encodeNil then return nil, "mock encode failed" end
            return encode(value)
        end,
        decode=decode,
    }
    host.state = {
        watch=function(key, callback)
            h.watchers[key] = h.watchers[key] or {}
            table.insert(h.watchers[key], callback)
        end,
        get=function(key) return h.values[key] end,
        set=function(key, value)
            h.values[key] = copy(value)
            h.history[key] = h.history[key] or {}
            table.insert(h.history[key], copy(value))
            for _, callback in ipairs(h.watchers[key] or {}) do callback(copy(value)) end
        end,
    }
    host.notify = function(title, body)
        local durable = h:latest("timer")
        h.notifications[#h.notifications + 1] = {title=title,body=body,
            durableStatus=durable and durable.timer and durable.timer.status}
    end
    host.runAsync = function(argv, callback, timeout)
        -- This is ONLY a queue: never invoke os.execute, io.popen or any process.
        assert(argv[1] == "chmod" or (argv[1] == "python3"
            and argv[2] == "/mock/plugin/helpers/system.py"), "unexpected external command")
        local kind = label(argv)
        local accepted = not h.reject[kind]
        h.requests[#h.requests + 1] = {kind=kind,argv=copy(argv),callback=callback,
            timeout=timeout,done=not accepted,accepted=accepted}
        return accepted
    end
    h.host = host
    -- Whitelist the Lua basics. The real entry has no access to os/io/debug or
    -- arbitrary require, and every boot gets a fresh module cache and globals.
    local env = {noctalia=host,assert=assert,error=error,ipairs=ipairs,pairs=pairs,next=next,
        pcall=pcall,select=select,type=type,tonumber=tonumber,tostring=tostring,
        math=math,string=string,table=table}
    env._G = env
    local modules = {}
    env.require = function(path)
        assert(path == "./lib/notes.luau" or path == "./lib/countdown.luau" or path == "./lib/calculator.luau" or path == "./lib/frontend.luau" or path == "./lib/stopwatch.luau", "unexpected module " .. tostring(path))
        if modules[path] == nil then
            local chunk, err = loadfile(directory .. "../" .. path:sub(3), "t", env)
            assert(chunk, err)
            modules[path] = chunk()
        end
        return modules[path]
    end
    local entry, err = loadfile(directory .. "../service.luau", "t", env)
    assert(entry, err)
    h.env = env
    entry()
    assert(type(env.update) == "function" and type(env.onExit) == "function"
        and type(env.onIpc) == "function", "real service callbacks were not installed")
    return h
end

local function initialized(options) return boot(options):initialize() end
local function activeBody(h)
    local snapshot = h:notes()
    for _, note in ipairs(snapshot.model.notes) do
        if note.id == snapshot.model.activeId then return note.body end
    end
end

test("real entry installs callbacks and gates writes on initialization", function()
    local h = boot()
    equal(h.interval, 250)
    equal(#h.watchers.command, 1)
    equal(#h.watchers.visibility, 1)
    equal(h:notes().ready, false)
    equal(h:notes().model, nil)
    equal(h:timer().ready, false)
    equal(h:timer().timer.durationMs, 1500000)
    equal(h.values.system_snapshot.loading, true)
    equal(h:writeCount(), 0)
    equal(h.mkdirs[1], BASE)
    local init = h.requests[1]
    equal(table.concat(init.argv, "|"), "chmod|-R|go-rwx|--|" .. BASE)
    equal(init.timeout, 5000)
    h:send({action="note-add",title="Too early"})
    equal(h.values.feedback.ok, false)
    h:send({action="timer-start",durationMs=1000})
    equal(h.values.feedback.ok, false)
    equal(h:writeCount(), 0)
    h:initialize()
    equal(h:notes().ready, true)
    equal(h:notes().model.notes[1].title, "随手记")
    equal(h:timer().ready, true)
    equal(h:count("snapshot"), 1)
end)

test("permission failure blocks persistence and reports both consumers", function()
    local h = boot():initialize(1)
    equal(h:notes().ready, false)
    equal(h:timer().ready, false)
    check(h:notes().error ~= "", "notes permission error missing")
    check(h:timer().error ~= "", "timer permission error missing")
    h:send({action="note-add"})
    h:send({action="timer-start",durationMs=1000})
    h:tick(10000)
    h.env.onExit()
    equal(h:writeCount(), 0)
    equal(h:count("snapshot"), 0)
end)

test("rejected initialization surfaces an error to both consumers", function()
    local h = boot({reject={chmod=true}})
    equal(h:notes().ready, false)
    equal(h:timer().ready, false)
    check(h:notes().error ~= "", "notes initialization failure missing")
    check(h:timer().error ~= "", "timer initialization failure must not remain blank")
    equal(h:writeCount(), 0)
end)

test("initialization chooses latest valid note snapshot", function()
    local disk = newDisk()
    put(disk, "notes-a.json", model(2, "older"))
    put(disk, "notes-b.json", model(3, "latest"))
    local h = initialized({disk=disk})
    equal(activeBody(h), "latest")
    equal(h:notes().model.revision, 3)
    equal(h:writeCount("notes"), 0)
end)

test("corrupt snapshots are never silently overwritten", function()
    local disk = newDisk()
    disk.files[BASE .. "/notes-a.json"] = "{broken"
    disk.files[BASE .. "/notes-b.json"] = ""
    local h = initialized({disk=disk})
    equal(h:notes().model, nil)
    check(h:notes().error ~= "", "corrupt-note error missing")
    h:send({action="note-add",title="Must not overwrite"})
    h:send({action="flush"})
    h.env.onExit()
    equal(h:writeCount("notes"), 0)
    equal(disk.files[BASE .. "/notes-a.json"], "{broken")
    equal(disk.files[BASE .. "/notes-b.json"], "")
end)

test("one corrupt notes slot recovers the other with a warning", function()
    local disk = newDisk()
    put(disk, "notes-a.json", model(4, "recovered"))
    disk.files[BASE .. "/notes-b.json"] = "invalid"
    local h = initialized({disk=disk})
    equal(activeBody(h), "recovered")
    equal(h:notes().error, "")
    check(h:notes().warning ~= "", "recovery warning missing")
    equal(h:writeCount("notes"), 0)
end)

test("note creation is immediately persisted by the service", function()
    local h = initialized()
    h:send({action="note-add",title="Project"})
    equal(#h:notes().model.notes, 2)
    equal(h:notes().model.activeId, "note-2")
    equal(h:notes().saving, false)
    equal(h:notes().error, "")
    equal(h:writeCount("notes"), 1)
    local saved, slot = h:latest("notes")
    equal(slot, "notes-a.json")
    equal(saved.notes[2].title, "Project")
    equal(saved.revision, 1)
end)

test("note edits debounce from the latest edit", function()
    local h = initialized()
    h:send({action="note-edit",body="first"})
    equal(h:notes().saving, true)
    equal(activeBody(h), "first")
    equal(h:writeCount("notes"), 0)
    h:tick(100)
    h:send({action="note-edit",body="latest"})
    h:tick(499)
    equal(h:writeCount("notes"), 0)
    h:tick(1)
    equal(h:writeCount("notes"), 1)
    equal(h:latest("notes").notes[1].body, "latest")
    equal(h:notes().saving, false)
end)

test("closing the panel flushes pending edits immediately", function()
    local h = initialized()
    h:send({action="note-edit",body="saved on close"})
    h:visibility(false)
    equal(h:notes().saving, false)
    equal(h:writeCount("notes"), 1)
    equal(h:latest("notes").notes[1].body, "saved on close")
end)

test("explicit flush and real onExit flush pending notes", function()
    local h = initialized()
    h:send({action="note-edit",body="explicit"})
    h:send({action="flush"})
    equal(h:latest("notes").notes[1].body, "explicit")
    h:send({action="note-edit",body="on exit"})
    h.env.onExit()
    equal(h:latest("notes").notes[1].body, "on exit")
    equal(h:notes().saving, false)
    equal(h:writeCount("notes"), 2)
end)

test("failed note writes stay visibly unsaved and retry after three seconds", function()
    local h = initialized()
    h:send({action="note-edit",body="old durable body"})
    h:send({action="flush"})
    local _, oldSlot = h:latest("notes")
    local oldRaw = h.disk.files[BASE .. "/" .. oldSlot]
    h.disk.notesMode = "fail"
    h:send({action="note-edit",body="pending body"})
    h:tick(500)
    equal(h:notes().saving, true)
    check(h:notes().error ~= "", "failed save must be visible")
    equal(activeBody(h), "pending body")
    equal(h.disk.files[BASE .. "/" .. oldSlot], oldRaw)
    local attempts = h:writeCount("notes")
    h:tick(2999)
    equal(h:writeCount("notes"), attempts)
    h.disk.notesMode = nil
    h:tick(1)
    equal(h:writeCount("notes"), attempts + 1)
    equal(h:notes().saving, false)
    equal(h:notes().error, "")
    equal(h:latest("notes").notes[1].body, "pending body")
end)

test("readback mismatch never marks a note saved", function()
    local h = initialized()
    h:send({action="note-edit",body="good"}); h:send({action="flush"})
    local _, slot = h:latest("notes")
    local goodRaw = h.disk.files[BASE .. "/" .. slot]
    h.disk.notesMode = "corrupt"
    h:send({action="note-edit",body="not durable"}); h:visibility(false)
    equal(h:notes().saving, true)
    check(h:notes().error ~= "", "readback verification error missing")
    equal(h.disk.files[BASE .. "/" .. slot], goodRaw)
    h.disk.notesMode = nil
    local restart = initialized({disk=h.disk,now=h.now+1000})
    equal(activeBody(restart), "good")
    check(restart:notes().warning ~= "", "recovery warning missing after interrupted write")
end)

test("encoding and thrown note-write failures preserve dirty state", function()
    local h = initialized()
    h.encodeFailure = true
    h:send({action="note-edit",body="encoding failed"}); h:send({action="flush"})
    equal(h:notes().saving, true)
    check(h:notes().error ~= "", "encoding failure missing")
    equal(h:writeCount("notes"), 0)
    h.encodeFailure = false
    h.disk.notesMode = "throw"
    h:send({action="flush"})
    equal(h:notes().saving, true)
    check(h:notes().error ~= "", "write exception missing")
    h.disk.notesMode = nil
    h:send({action="flush"})
    equal(h:notes().saving, false)
end)

test("invalid note edits preserve the original model", function()
    local h = initialized()
    h:send({action="note-edit",body=123})
    equal(activeBody(h), "")
    equal(h:notes().model.revision, 0)
    equal(h.values.feedback.ok, false)
    equal(h:writeCount("notes"), 0)
end)

test("delete and restore use recoverable persisted trash", function()
    local h = initialized()
    h:send({action="note-edit",body="recover me"}); h:send({action="flush"})
    h:send({action="note-delete",id="note-1"})
    equal(#h:notes().model.notes, 0)
    equal(h:latest("notes").trash[1].body, "recover me")
    h:send({action="note-restore",id="note-1"})
    equal(activeBody(h), "recover me")
    equal(#h:latest("notes").trash, 0)
end)

test("closed panel still expires the real service timer exactly once", function()
    local h = initialized()
    h:visibility(true)
    h:reply("snapshot", systemResult())
    h:send({action="timer-start",durationMs=1000})
    h:visibility(false)
    local queries = h:count("snapshot")
    h:tick(1000)
    equal(h:timer().timer.status, "finished")
    equal(#h.notifications, 1)
    equal(h:latest("timer").timer.status, "finished")
    for _ = 1, 8 do h:tick(1000) end
    equal(#h.notifications, 1)
    equal(h:count("snapshot"), queries)
end)

test("service IPC pause and resume retain remaining time", function()
    local h = initialized()
    h.env.onIpc("timer-start", "5")
    h:tick(1200)
    h.env.onIpc("timer-pause")
    equal(h:timer().timer.status, "paused")
    equal(h:timer().timer.remainingMs, 3800)
    equal(h:latest("timer").timer.status, "paused")
    h:tick(100000)
    equal(#h.notifications, 0)
    h.env.onIpc("timer-resume")
    h:tick(3800)
    equal(#h.notifications, 1)
    h.env.onIpc("timer-reset")
    equal(h:timer().timer.status, "idle")
    equal(h:timer().timer.remainingMs, 5000)
end)

test("fresh service VM restores an in-flight absolute deadline", function()
    local first = initialized()
    first:send({action="timer-start",durationMs=10000})
    local second = initialized({disk=first.disk,now=EPOCH+3000})
    equal(second:timer().timer.status, "running")
    equal(second:timer().timer.deadlineMs, EPOCH+10000)
    equal(second:timer().timer.remainingMs, 7000)
    equal(#second.notifications, 0)
    second:tick(7000)
    equal(#second.notifications, 1)
    local third = initialized({disk=second.disk,now=EPOCH+30000})
    equal(third:timer().timer.status, "finished")
    equal(#third.notifications, 0)
end)

test("expired restart persists completion before notifying once", function()
    local first = initialized()
    first:send({action="timer-start",durationMs=1000})
    local second = initialized({disk=first.disk,now=EPOCH+2000})
    equal(second:timer().timer.status, "finished")
    equal(#second.notifications, 1)
    equal(second:latest("timer").timer.status, "finished")
    local third = initialized({disk=second.disk,now=EPOCH+3000})
    equal(#third.notifications, 0)
end)

test("paused service snapshot remains paused across a long restart", function()
    local first = initialized()
    first:send({action="timer-start",durationMs=5000})
    first:tick(1000); first:send({action="timer-pause"})
    local second = initialized({disk=first.disk,now=EPOCH+86400000})
    equal(second:timer().timer.status, "paused")
    equal(second:timer().timer.remainingMs, 4000)
    equal(#second.notifications, 0)
end)

test("timer persistence failure is visible without stopping live counting", function()
    local h = initialized()
    h.disk.timerMode = "fail"
    h:send({action="timer-start",durationMs=2000})
    equal(h:timer().timer.status, "running")
    check(h:timer().error ~= "", "timer persistence error missing")
    h:tick(1000)
    equal(h:timer().timer.remainingMs, 1000)
end)

test("failed completion save cannot notify again after restart", function()
    local first = initialized()
    first:send({action="timer-start",durationMs=1000})
    first.disk.timerMode = "fail"
    first:tick(1000)
    equal(first:timer().timer.status, "finished")
    check(first:timer().error ~= "", "failed completion must report persistence error")
    first.disk.timerMode = nil
    local second = initialized({disk=first.disk,now=EPOCH+2000})
    equal(#first.notifications + #second.notifications, 1,
        "same timer notified twice because finished snapshot was not durable")
end)

test("pause at expiry cannot duplicate notification after a failed save", function()
    local first = initialized()
    first:send({action="timer-start",durationMs=1000})
    first.disk.timerMode = "fail"
    first.now = EPOCH + 1000
    first:send({action="timer-pause"})
    equal(first:timer().timer.status, "finished")
    first.disk.timerMode = nil
    local second = initialized({disk=first.disk,now=EPOCH+2000})
    equal(#first.notifications + #second.notifications, 1,
        "pause-at-expiry notified twice across restart")
end)

test("failed expired-restore save suppresses a non-durable notification", function()
    local first = initialized()
    first:send({action="timer-start",durationMs=1000})
    first.disk.timerMode = "fail"
    local second = initialized({disk=first.disk,now=EPOCH+2000})
    equal(second:timer().timer.status, "finished")
    equal(#second.notifications, 0)
    check(second:timer().error ~= "", "restore persistence failure missing")
end)

test("closing before initialization preserves notes and restores an overdue timer", function()
    local disk = newDisk()
    put(disk, "notes-a.json", model(7, "must survive early close"))
    put(disk, "timer-a.json", {version=1,revision=3,timer={version=1,status="running",
        durationMs=1000,remainingMs=1000,deadlineMs=EPOCH+1000}})
    local h = boot({disk=disk})
    h:visibility(true)
    h:visibility(false)
    h:tick(2000)
    equal(h:notes().ready, false)
    equal(h:writeCount(), 0)
    equal(#h.notifications, 0)
    h:initialize()
    equal(activeBody(h), "must survive early close")
    equal(h:notes().saving, false)
    equal(h:writeCount("notes"), 0)
    equal(h:timer().timer.status, "finished")
    equal(#h.notifications, 1)
    equal(h.notifications[1].durableStatus, "finished")
    local queries = h:count("snapshot")
    h:tick(30000)
    equal(h:count("snapshot"), queries)
    equal(#h.notifications, 1)
end)

test("a failed running save retries without shifting its absolute deadline", function()
    local h = initialized()
    h.disk.timerMode = "fail"
    h:send({action="timer-start",durationMs=10000})
    local attempts = h:writeCount("timer")
    h:tick(2999)
    equal(h:writeCount("timer"), attempts)
    check(h:timer().error ~= "", "dirty timer error disappeared before durability")
    h.disk.timerMode = nil
    h:tick(1)
    equal(h:writeCount("timer"), attempts+1)
    equal(h:timer().error, "")
    local saved = h:latest("timer")
    equal(saved.timer.status, "running")
    equal(saved.timer.deadlineMs, EPOCH+10000)
    equal(saved.timer.remainingMs, 7000)
    equal(#h.notifications, 0)
    h:tick(7000)
    equal(#h.notifications, 1)
    equal(h.notifications[1].durableStatus, "finished")
end)

test("failed runtime completion retries and then notifies exactly once", function()
    local h = initialized()
    h:send({action="timer-start",durationMs=1000})
    h.disk.timerMode = "fail"
    h:tick(1000)
    equal(h:timer().timer.status, "finished")
    equal(#h.notifications, 0)
    equal(h:latest("timer").timer.status, "running")
    local attempts = h:writeCount("timer")
    h:tick(2999)
    equal(h:writeCount("timer"), attempts)
    h.disk.timerMode = nil
    h:tick(1)
    equal(h:writeCount("timer"), attempts+1)
    equal(h:timer().error, "")
    equal(#h.notifications, 1)
    equal(h.notifications[1].durableStatus, "finished")
    h:tick(10000)
    equal(#h.notifications, 1)
    local restart = initialized({disk=h.disk,now=h.now+1000})
    equal(#restart.notifications, 0)
end)

test("failed pause-at-expiry retries its pending finish notification", function()
    local h = initialized()
    h:send({action="timer-start",durationMs=1000})
    h.disk.timerMode = "fail"
    h.now = EPOCH + 1000
    h:send({action="timer-pause"})
    equal(#h.notifications, 0)
    h.disk.timerMode = nil
    h:tick(3000)
    equal(#h.notifications, 1)
    equal(h.notifications[1].durableStatus, "finished")
    equal(h:timer().error, "")
    h:tick(3000)
    equal(#h.notifications, 1)
end)

test("failed expired restore retries and delivers its pending notification", function()
    local first = initialized()
    first:send({action="timer-start",durationMs=1000})
    first.disk.timerMode = "fail"
    local h = initialized({disk=first.disk,now=EPOCH+2000})
    equal(h:timer().timer.status, "finished")
    equal(#h.notifications, 0)
    local attempts = h:writeCount("timer")
    h:tick(2999)
    equal(h:writeCount("timer"), attempts)
    h.disk.timerMode = nil
    h:tick(1)
    equal(h:writeCount("timer"), attempts+1)
    equal(#h.notifications, 1)
    equal(h.notifications[1].durableStatus, "finished")
    equal(h:timer().error, "")
    local restart = initialized({disk=h.disk,now=h.now+1000})
    equal(#restart.notifications, 0)
end)

test("persistent timer write failures retry only every three seconds", function()
    local h = initialized()
    h.disk.timerMode = "fail"
    h:send({action="timer-start",durationMs=120000})
    equal(h:writeCount("timer"), 1)
    for _ = 1, 11 do h:tick(250) end
    equal(h:writeCount("timer"), 1)
    h:tick(250)
    equal(h:writeCount("timer"), 2)
    for _ = 1, 11 do h:tick(250) end
    equal(h:writeCount("timer"), 2)
    h:tick(250)
    equal(h:writeCount("timer"), 3)
    equal(#h.notifications, 0)
    h.disk.timerMode = nil
    h:tick(3000)
    equal(h:writeCount("timer"), 4)
    equal(h:timer().error, "")
    equal(h:latest("timer").timer.deadlineMs, EPOCH+120000)
end)

test("onExit saves a pending finished state before sending its notification", function()
    local h = initialized()
    h:send({action="timer-start",durationMs=1000})
    h.disk.timerMode = "fail"
    h:tick(1000)
    equal(#h.notifications, 0)
    h.disk.timerMode = nil
    h.env.onExit()
    equal(#h.notifications, 1)
    equal(h.notifications[1].durableStatus, "finished")
    h.env.onExit()
    equal(#h.notifications, 1)
    local restart = initialized({disk=h.disk,now=h.now+1000})
    equal(#restart.notifications, 0)
end)

test("explicit reset cancels an old pending finish without a stale notification", function()
    local h = initialized()
    h:send({action="timer-start",durationMs=1000})
    h.disk.timerMode = "fail"
    h:tick(1000)
    h:send({action="timer-reset",durationMs=5000})
    equal(h:timer().timer.status, "idle")
    h.disk.timerMode = nil
    h:tick(3000)
    equal(h:latest("timer").timer.status, "idle")
    equal(h:timer().error, "")
    equal(#h.notifications, 0)
    h:tick(10000)
    equal(#h.notifications, 0)
end)

test("automatic snapshot queries are throttled and stop when closed", function()
    local h = initialized()
    equal(h:count("snapshot"), 1)
    h:visibility(true)
    equal(h:count("snapshot"), 2)
    h:visibility(true); h:send({action="refresh"})
    equal(h:count("snapshot"), 2)
    h:reply("snapshot", systemResult())
    h:tick(2999)
    equal(h:count("snapshot"), 2)
    h:tick(1)
    equal(h:count("snapshot"), 3)
    h:reply("snapshot", systemResult())
    h:visibility(false)
    h:tick(3000); h:tick(60000)
    equal(h:count("snapshot"), 3)
end)

test("visibility heartbeat expiry prevents orphan polling", function()
    local h = initialized()
    h:visibility(true); h:reply("snapshot", systemResult())
    local requests = h:count("snapshot")
    h:tick(12000)
    equal(h:count("snapshot"), requests)
end)

test("window IDs are validated before any external command is queued", function()
    local h = initialized()
    for _, id in ipairs({"", "-1", "1.5", "1e3", "1; echo unsafe", "1 2", 123, false}) do
        h:send({action="window-focus",id=id})
        equal(h.values.feedback.ok, false)
    end
    equal(h:count("focus"), 0)
    h:send({action="window-focus",id="123"})
    local focus = h:reply("focus", {ok=true,message="focused"})
    equal(table.concat(focus.argv,"|"), "python3|/mock/plugin/helpers/system.py|focus|123")
    equal(focus.timeout, 5000)
    equal(h.values.feedback.ok, true)
    equal(h.values.feedback.scope, "windows")
    h:reply("snapshot", systemResult())
    h.env.onIpc("close-window", "456")
    local close = h:reply("close", {ok=true,message="closed"})
    equal(close.argv[3], "close")
    equal(close.argv[4], "456")
end)

test("hotspot busy rejects overlapping action and discards its private request", function()
    local h = initialized()
    local path = BASE .. "/hotspot-request-fixture.json"
    h:send({action="hotspot",kind="on"})
    equal(h.values.system_snapshot.hotspot.busy, true)
    h:send({action="hotspot",kind="apply",path=path})
    equal(h:count("hotspot"), 1)
    equal(h:count("discard-request"), 1)
    equal(h.values.feedback.ok, false)
    local discard = h:reply("discard-request", {ok=true})
    equal(discard.argv[4], path)
    local action = h:reply("hotspot", {ok=true,message="fixture complete"})
    equal(action.argv[4], "on")
    equal(action.timeout, 60000)
    equal(h.values.system_snapshot.hotspot.busy, false)
    equal(h.values.feedback.ok, true)
    equal(h:count("snapshot",true), 1)
end)

test("rejected hotspot process releases busy state and reports failure", function()
    local h = initialized()
    h.reject.hotspot = true
    h:send({action="hotspot",kind="off"})
    equal(h.values.system_snapshot.hotspot.busy, false)
    equal(h.values.feedback.ok, false)
    equal(h.values.feedback.scope, "hotspot")
    check(h.values.feedback.message ~= "", "action rejection has no feedback")
end)

test("a pending snapshot cannot clear an active hotspot operation's busy state", function()
    local h = boot():initialize(0, false)
    h:send({action="hotspot",kind="on"})
    h:reply("snapshot", systemResult())
    equal(h.values.system_snapshot.hotspot.busy, true)
    h:send({action="refresh"})
    equal(h:count("snapshot",true), 0)
    h:reply("hotspot", {ok=false,message="fixture failure"})
    equal(h.values.system_snapshot.hotspot.busy, false)
    equal(h.values.feedback.ok, false)
    equal(h:count("snapshot",true), 1)
end)

test("rejected window process reports a boolean failure", function()
    local h = initialized()
    h.reject.focus = true
    h:send({action="window-focus",id="123"})
    equal(h.values.feedback.ok, false)
    equal(h.values.feedback.scope, "windows")
    check(h.values.feedback.message ~= "", "window failure missing")
end)

test("snapshot errors release the refresh guard and expose uncertainty", function()
    local variants = {
        {timedOut=true}, {stdoutTruncated=true}, {stdout="{broken"},
        {stdout=encode("not a table")},
    }
    for _, result in ipairs(variants) do
        local h = boot():initialize(0, false)
        h:reply("snapshot", nil, result)
        equal(h.values.system_snapshot.loading, false)
        equal(h.values.system_snapshot.hotspot.on, nil)
        check(h.values.system_snapshot.windowsError ~= nil, "snapshot error is hidden")
        h:send({action="refresh"})
        equal(h:count("snapshot",true), 1)
        h:reply("snapshot", systemResult())
        equal(h.values.system_snapshot.hotspot.on, false)
    end
end)

test("rejected snapshot process can be retried", function()
    local h = boot({reject={snapshot=true}}):initialize()
    equal(h.values.system_snapshot.loading, false)
    check(h.values.system_snapshot.windowsError ~= nil, "failed refresh is hidden")
    h.reject.snapshot = nil
    h:send({action="refresh"})
    equal(h:count("snapshot",true), 1)
    h:reply("snapshot", systemResult())
    equal(h.values.system_snapshot.hotspot.on, false)
end)

test("preferences restore and persist only supported tab choices", function()
    local disk = newDisk()
    put(disk, "preferences.json", {tab="notes",reducedMotion=true})
    local h = initialized({disk=disk})
    equal(h.values.preferences.tab, "notes")
    equal(h.values.preferences.reducedMotion, true)
    h:send({action="preferences",tab="invalid",reducedMotion=false})
    local preferences = decode(disk.files[BASE .. "/preferences.json"])
    equal(preferences.tab, "notes")
    equal(preferences.reducedMotion, false)
    h:send({action="preferences",tab="timer"})
    -- Legacy aliases are stored canonically: the frontend only knows the four pages.
    equal(h.values.preferences.tab, "tools")
    h:send({action="preferences",tab="windows"})
    equal(h.values.preferences.tab, "windows")
end)

-- Additional regressions exercise the real callbacks while all persistence remains in memory.
local function assertStorageBlocked(h)
    equal(h:notes().ready, false)
    equal(h:notes().model, nil)
    equal(h:timer().ready, false)
    check(h:notes().error ~= "", "storage failure must be visible to notes")
    check(h:timer().error ~= "", "storage failure must be visible to timer")
    h:send({action="note-add",title="must not be persisted"})
    equal(h.values.feedback.ok, false)
    h:send({action="note-edit",body="must not replace saved data"})
    equal(h.values.feedback.ok, false)
    h:send({action="timer-start",durationMs=1000})
    equal(h.values.feedback.ok, false)
    h.env.onIpc("timer-start", "1")
    equal(h.values.feedback.ok, false)
    h:send({action="preferences",tab="timer",reducedMotion=true})
    h:send({action="flush"})
    h:visibility(false)
    h:tick(10000)
    h.env.onExit(0, "reload")
    equal(h:writeCount(), 0, "uninitialized service wrote persistent data")
    equal(#h.reads, 0, "uninitialized service read private data")
    equal(#h.notifications, 0)
    equal(h:notes().ready, false)
    equal(h:timer().ready, false)
end

test("nil pluginDataDir keeps callbacks alive and storage closed", function()
    local h = boot({dataDirUnavailable=true})
    assertStorageBlocked(h)
    equal(#h.mkdirs, 0)
    equal(#h.requests, 0, "nil data directory must not reach chmod or the helper")
end)

for _, mode in ipairs({"fail", "throw"}) do
    test("mkdirAll " .. mode .. " keeps storage closed without scheduling chmod", function()
        local h = boot({mkdirMode=mode})
        assertStorageBlocked(h)
        equal(#h.mkdirs, 1)
        equal(h.mkdirs[1], BASE)
        equal(#h.requests, 0, "failed mkdir must not reach chmod or the helper")
    end)
end

test("rejected initialization cannot alter existing notes or emit an overdue notification", function()
    local disk = newDisk()
    put(disk, "notes-a.json", model(9, "private saved body"))
    put(disk, "timer-a.json", {version=1,revision=3,timer={version=1,status="running",
        durationMs=1000,remainingMs=1000,deadlineMs=EPOCH-1000}})
    local original = encode(disk.files)
    local h = boot({disk=disk,reject={chmod=true}})
    assertStorageBlocked(h)
    equal(encode(disk.files), original)
    equal(h:count("chmod"), 1)
    equal(h.requests[1].accepted, false)
    equal(h:count("snapshot"), 0)
end)

for _, mode in ipairs({"readback", "encode-throw", "encode-nil"}) do
    test("completion " .. mode .. " failure retries after three seconds and notifies only once", function()
        local h = initialized()
        h:send({action="timer-start",durationMs=1000})
        if mode == "readback" then h.disk.timerMode = "corrupt"
        elseif mode == "encode-throw" then h.encodeFailure = true
        else h.encodeNil = true end
        h:tick(1000)
        equal(h:timer().timer.status, "finished")
        check(h:timer().error ~= "", "non-durable finish needs a visible error")
        equal(#h.notifications, 0)
        equal(h:latest("timer").timer.status, "running")
        local writes, attempts = h:writeCount("timer"), h.encodeAttempts
        h:tick(2999)
        equal(h:writeCount("timer"), writes)
        equal(h.encodeAttempts, attempts, "retry ran before the three-second boundary")
        h.disk.timerMode, h.encodeFailure, h.encodeNil = nil, false, false
        h:tick(1)
        equal(h:writeCount("timer"), writes+1)
        equal(h.encodeAttempts, attempts+1)
        equal(h:timer().error, "")
        equal(h:latest("timer").timer.status, "finished")
        equal(#h.notifications, 1)
        equal(h.notifications[1].durableStatus, "finished")
        h:tick(30000)
        h.env.onExit(0, "reload")
        equal(#h.notifications, 1)
        local restart = initialized({disk=h.disk,now=h.now+1000})
        equal(restart:timer().timer.status, "finished")
        equal(#restart.notifications, 0)
    end)
end

test("nil encoder result leaves notes unsaved until the three-second recovery", function()
    local h = initialized()
    h.encodeNil = true
    h:send({action="note-edit",body="codec recovery"})
    h:tick(500)
    equal(h:notes().saving, true)
    check(h:notes().error ~= "", "nil,error encoder result was treated as success")
    equal(h:writeCount("notes"), 0)
    local attempts = h.encodeAttempts
    h:tick(2999)
    equal(h.encodeAttempts, attempts)
    h.encodeNil = false
    h:tick(1)
    equal(h.encodeAttempts, attempts+1)
    equal(h:notes().saving, false)
    equal(h:notes().error, "")
    equal(h:latest("notes").notes[1].body, "codec recovery")
end)

test("onExit samples remaining time without moving a running deadline", function()
    local h = initialized()
    h:send({action="timer-start",durationMs=10000})
    h.now = EPOCH + 1250 -- No update callback before teardown.
    h:send({action="note-edit",body="flushed with the running timer"})
    h.env.onExit(15, "shutdown")
    local saved, slot = h:latest("timer")
    equal(slot, "timer-b.json")
    equal(saved.revision, 2)
    equal(saved.timer.status, "running")
    equal(saved.timer.deadlineMs, EPOCH+10000)
    equal(saved.timer.remainingMs, 8750)
    equal(h:latest("notes").notes[1].body, "flushed with the running timer")
    equal(#h.notifications, 0)
    local restart = initialized({disk=h.disk,now=EPOCH+2250})
    equal(activeBody(restart), "flushed with the running timer")
    equal(restart:timer().timer.deadlineMs, EPOCH+10000)
    equal(restart:timer().timer.remainingMs, 7750)
end)

test("onExit before the final tick preserves overdue work for one restart notification", function()
    local h = initialized()
    h:send({action="timer-start",durationMs=1000})
    h.now = EPOCH + 2000 -- Teardown wins the scheduling race with update().
    h.env.onExit(0, "reload")
    local saved = h:latest("timer")
    equal(saved.timer.status, "running", "snapshot swallowed the pending finish transition")
    equal(saved.timer.remainingMs, 0)
    equal(saved.timer.deadlineMs, EPOCH+1000)
    equal(#h.notifications, 0)
    local restart = initialized({disk=h.disk,now=h.now+1})
    equal(#restart.notifications, 1)
    equal(restart.notifications[1].durableStatus, "finished")
    local again = initialized({disk=h.disk,now=h.now+2000})
    equal(#again.notifications, 0)
end)

test("onExit with storage still unavailable keeps a pending finish silent and recoverable", function()
    local h = initialized()
    h:send({action="timer-start",durationMs=1000})
    local _, slot = h:latest("timer")
    local durable = h.disk.files[BASE .. "/" .. slot]
    h.disk.timerMode = "fail"
    h:tick(1000)
    local attempts = h:writeCount("timer")
    h.env.onExit(0, "reload")
    equal(h:writeCount("timer"), attempts+1, "exit did not attempt its final flush")
    equal(h.disk.files[BASE .. "/" .. slot], durable)
    equal(#h.notifications, 0)
    h.disk.timerMode = nil
    local restart = initialized({disk=h.disk,now=h.now+1000})
    equal(#restart.notifications, 1)
    equal(restart.notifications[1].durableStatus, "finished")
    local again = initialized({disk=h.disk,now=h.now+2000})
    equal(#again.notifications, 0)
end)

test("starting a new timer replaces an old unsaved finish without its stale notification", function()
    local h = initialized()
    h:send({action="timer-start",durationMs=1000})
    h.disk.timerMode = "fail"
    h:tick(1000)
    h:send({action="timer-start",durationMs=5000})
    equal(h:timer().timer.status, "running")
    h.disk.timerMode = nil
    h:tick(3000)
    equal(h:latest("timer").timer.status, "running")
    equal(h:latest("timer").timer.deadlineMs, EPOCH+6000)
    equal(#h.notifications, 0)
    h:tick(2000)
    equal(#h.notifications, 1)
    equal(h:latest("timer").timer.durationMs, 5000)
    equal(h:latest("timer").timer.finishedAtMs, EPOCH+6000)
    h:tick(10000)
    h.env.onExit()
    local restart = initialized({disk=h.disk,now=h.now+1000})
    equal(#h.notifications, 1)
    equal(#restart.notifications, 0)
end)

test("generic read error for missing snapshots still permits first-run notes", function()
    local h = initialized()
    local raw, readError = h.host.readFile(BASE .. "/notes-a.json")
    equal(raw, nil)
    equal(readError, "cannot open file", "mock diverged from the actual SDK error shape")
    equal(h.host.fileExists(BASE .. "/notes-a.json"), false)
    equal(h:notes().error, "")
    equal(h:notes().model.revision, 0)
    equal(h:writeCount("notes"), 0)
    h:send({action="note-edit",body="a real first note"})
    h:send({action="flush"})
    equal(h:notes().saving, false)
    equal(h:latest("notes").notes[1].body, "a real first note")
end)

for _, suffix in ipairs({"a", "b"}) do
    test("known-existing unreadable notes-" .. suffix .. " never becomes a blank model", function()
        local disk = newDisk()
        put(disk, "notes-a.json", model(3, "older private body"))
        put(disk, "notes-b.json", model(9, "latest private body"))
        local originalA = disk.files[BASE .. "/notes-a.json"]
        local originalB = disk.files[BASE .. "/notes-b.json"]
        local unreadable = BASE .. "/notes-" .. suffix .. ".json"
        disk.readErrors = {[unreadable]=true}
        local h = initialized({disk=disk})
        local raw, readError = h.host.readFile(unreadable)
        equal(raw, nil)
        equal(readError, "cannot open file", "unreadable errors must not invent an errno code")
        equal(h.host.fileExists(unreadable), true)
        equal(h:notes().model, nil, "read error was mistaken for an absent initial snapshot")
        check(h:notes().error ~= "", "existing unreadable snapshot needs a visible blocking error")
        equal(h:notes().saving, false)
        h:send({action="note-add",title="must not replace private data"})
        equal(h.values.feedback.ok, false)
        h:send({action="note-edit",body="must not overwrite either slot"})
        equal(h.values.feedback.ok, false)
        h:send({action="flush"})
        h:visibility(false)
        h:tick(10000)
        h.env.onExit(0, "reload")
        equal(h:writeCount("notes"), 0)
        equal(disk.files[BASE .. "/notes-a.json"], originalA)
        equal(disk.files[BASE .. "/notes-b.json"], originalB)
        -- Recovery is a new runtime after the mock permission fault is removed.
        -- Do not pretend fileExists can diagnose inaccessible parent paths.
        disk.readErrors = nil
        local restart = initialized({disk=disk,now=h.now+1000})
        equal(activeBody(restart), "latest private body")
        equal(restart:notes().model.revision, 9)
        equal(restart:notes().error, "")
    end)
end

test("read permission failure during save preserves the previous slot until verified recovery", function()
    local h = initialized()
    h:send({action="note-edit",body="last verified body"})
    h:send({action="flush"})
    local _, slot = h:latest("notes")
    local original = h.disk.files[BASE .. "/" .. slot]
    h.disk.readErrors = {[BASE .. "/notes-b.json"]=true}
    h:send({action="note-edit",body="unverified newer body"})
    h:visibility(false)
    equal(h:notes().saving, true)
    check(h:notes().error ~= "", "readback permission error incorrectly marked the note saved")
    equal(h.disk.files[BASE .. "/" .. slot], original)
    local attempts = h:writeCount("notes")
    h:tick(2999)
    equal(h:writeCount("notes"), attempts)
    h.disk.readErrors = nil
    h:tick(1)
    equal(h:writeCount("notes"), attempts+1)
    equal(h:notes().saving, false)
    equal(h:notes().error, "")
    equal(h:latest("notes").notes[1].body, "unverified newer body")
end)


test("stopwatch initializes independently without writing unused state", function()
    local h=initialized()
    equal(h.values.stopwatch_snapshot.ready,true)
    equal(h.values.stopwatch_snapshot.stopwatch.status,"idle")
    equal(h.values.stopwatch_snapshot.stopwatch.elapsedMs,0)
    equal(h:writeCount("stopwatch"),0)
end)
test("stopwatch start does not alter notes or countdown", function()
    local h=initialized()
    h:send({action="note-edit",id="note-1",body="kept fixture"});h:send({action="flush"})
    h:send({action="timer-start",durationMs=60000})
    local beforeTimer=encode(h:timer().timer)
    local beforeNotes=encode(h:notes().model)
    h:send({action="stopwatch-start"})
    equal(h.values.stopwatch_snapshot.stopwatch.status,"running")
    equal(encode(h:timer().timer),beforeTimer)
    equal(encode(h:notes().model),beforeNotes)
    equal(h:latest("stopwatch").stopwatch.startedAtMs,h.now)
end)
test("stopwatch lap pause continue and reset use only explicit commands", function()
    local h=initialized()
    h:send({action="stopwatch-start"});h:tick(1234)
    h:send({action="stopwatch-lap"})
    equal(h.values.stopwatch_snapshot.stopwatch.laps[1].totalMs,1234)
    h:tick(766);h:send({action="stopwatch-pause"})
    equal(h.values.stopwatch_snapshot.stopwatch.elapsedMs,2000)
    h:tick(10000);equal(h.values.stopwatch_snapshot.stopwatch.elapsedMs,2000)
    h:send({action="stopwatch-start"});h:tick(1500);h:send({action="stopwatch-pause"})
    equal(h.values.stopwatch_snapshot.stopwatch.elapsedMs,3500)
    h:send({action="stopwatch-reset"})
    equal(h.values.stopwatch_snapshot.stopwatch.status,"idle")
    equal(#h.values.stopwatch_snapshot.stopwatch.laps,0)
end)
test("hiding the UI never pauses or periodically writes the stopwatch", function()
    local h=initialized();h:send({action="stopwatch-start"})
    local writes=h:writeCount("stopwatch")
    h:visibility(false);h:tick(65000)
    equal(h.values.stopwatch_snapshot.stopwatch.status,"running")
    equal(h.values.stopwatch_snapshot.stopwatch.startedAtMs,EPOCH)
    equal(h:writeCount("stopwatch"),writes)
end)
test("running stopwatch restores elapsed time across a new service VM", function()
    local h=initialized();h:send({action="stopwatch-start"});h:tick(2000);h.env.onExit()
    local next=initialized({disk=h.disk,now=h.now+5000})
    equal(next.values.stopwatch_snapshot.stopwatch.status,"running")
    equal(next.values.stopwatch_snapshot.stopwatch.elapsedMs,7000)
    equal(next.values.stopwatch_snapshot.stopwatch.startedAtMs,next.now)
end)
test("paused stopwatch stays paused across restart", function()
    local h=initialized();h:send({action="stopwatch-start"});h:tick(2450);h:send({action="stopwatch-pause"})
    local next=initialized({disk=h.disk,now=h.now+60000})
    equal(next.values.stopwatch_snapshot.stopwatch.status,"paused")
    equal(next.values.stopwatch_snapshot.stopwatch.elapsedMs,2450)
end)
test("stopwatch write failure retries after three seconds without false saved state", function()
    local h=initialized();h.disk.stopwatchMode="fail";h:send({action="stopwatch-start"})
    check(h.values.stopwatch_snapshot.error~="")
    equal(h:writeCount("stopwatch"),1)
    h:tick(2999);equal(h:writeCount("stopwatch"),1)
    h.disk.stopwatchMode=nil;h:tick(1)
    equal(h:writeCount("stopwatch"),2)
    equal(h.values.stopwatch_snapshot.error,"")
    equal(h:latest("stopwatch").stopwatch.elapsedMs,3000)
end)
test("one valid stopwatch snapshot recovers a corrupt newer copy", function()
    local disk=newDisk()
    put(disk,"stopwatch-a.json",{version=1,revision=1,stopwatch={version=1,status="paused",elapsedMs=5000,laps={}}})
    disk.files[BASE.."/stopwatch-b.json"]="{broken"
    local h=initialized({disk=disk})
    equal(h.values.stopwatch_snapshot.ready,true)
    equal(h.values.stopwatch_snapshot.stopwatch.elapsedMs,5000)
    equal(h:writeCount("stopwatch"),0)
end)
test("unreadable stopwatch state is not silently overwritten", function()
    local disk=newDisk();disk.files[BASE.."/stopwatch-a.json"]="{broken"
    local h=initialized({disk=disk})
    equal(h.values.stopwatch_snapshot.ready,false)
    check(h.values.stopwatch_snapshot.error~="")
    h:send({action="stopwatch-start"});h:send({action="stopwatch-reset"});h.env.onExit()
    equal(h:writeCount("stopwatch"),0)
    equal(disk.files[BASE.."/stopwatch-a.json"],"{broken")
end)
test("unreadable timer archive starts clean but reports it instead of silently overwriting", function()
    local disk = newDisk()
    disk.files[BASE .. "/timer-a.json"] = "{broken"
    local h = initialized({disk=disk})
    equal(h:timer().ready, true)
    equal(h:timer().timer.status, "idle")
    equal(h:timer().timer.durationMs, 1500000)
    check(h:timer().error ~= "", "an unreadable countdown archive must be reported")
    equal(h:writeCount("timer"), 0)
    equal(disk.files[BASE .. "/timer-a.json"], "{broken")
end)
test("a readable countdown archive still wins over a corrupt sibling", function()
    local disk = newDisk()
    put(disk, "timer-a.json", {version=1,revision=4,timer={version=1,status="paused",durationMs=60000,remainingMs=42000}})
    disk.files[BASE .. "/timer-b.json"] = "{broken"
    local h = initialized({disk=disk})
    equal(h:timer().timer.status, "paused")
    equal(h:timer().timer.remainingMs, 42000)
    equal(h:timer().error, "")
end)
test("initialization and exit both tighten the private tree", function()
    local h = initialized()
    equal(table.concat(h.requests[1].argv, "|"), "chmod|-R|go-rwx|--|" .. BASE)
    h.env.onExit()
    local last = h.requests[#h.requests]
    equal(last.kind, "chmod")
    equal(table.concat(last.argv, "|"), "chmod|-R|go-rwx|--|" .. BASE)
    equal(last.accepted, true)
end)
test("a blocked initialization never schedules a permission sweep", function()
    local h = boot({reject={chmod=true}})
    h.env.onExit()
    equal(h:count("chmod"), 1)
end)
test("failed initialization also disables stopwatch persistence", function()
    local h=boot():initialize(1,false)
    equal(h.values.stopwatch_snapshot.ready,false)
    check(h.values.stopwatch_snapshot.error~="")
    h:send({action="stopwatch-start"})
    equal(h:writeCount("stopwatch"),0)
end)
test("plugin settings fall back to the declared defaults", function()
    local h = initialized()
    local c = h.values.config
    equal(c.panelWidth, 450)
    equal(c.defaultTab, "notes")
    equal(c.rememberLastTab, true)
    equal(c.timerDefaultMinutes, 25)
    equal(table.concat(c.timerPresets, ","), "5,15,25,60")
    equal(c.confirmWindowClose, true)
    equal(c.hotspotDefaultSsid, "")
    equal(c.hotspotDefaultBand, "bg")
    equal(c.refreshSeconds, 3)
    equal(h:timer().timer.durationMs, 1500000)
end)
test("settings are clamped and normalised before the frontend sees them", function()
    local h = initialized({config={panel_width=100, timer_default_minutes=0, system_refresh_seconds=99,
        hotspot_default_band="a", confirm_window_close=false, hotspot_default_ssid="Tide 热点", default_tab="nonsense"}})
    local c = h.values.config
    equal(c.panelWidth, 380, "panel width must clamp low")
    equal(c.timerDefaultMinutes, 1, "a zero default must clamp up")
    equal(c.refreshSeconds, 30, "the refresh interval must clamp high")
    equal(c.hotspotDefaultBand, "a")
    equal(c.confirmWindowClose, false)
    equal(c.hotspotDefaultSsid, "Tide 热点")
    equal(c.defaultTab, "notes", "an unknown tab must fall back")
    equal(h:timer().timer.durationMs, 60000, "an untouched idle countdown follows the default")
end)
test("countdown presets are filtered, capped and never left empty", function()
    local h = initialized({config={timer_presets={"5","bad","0","9","70","3","4","8","11"}}})
    equal(table.concat(h.values.config.timerPresets, ","), "5,9,70,3,4,8")
    local empty = initialized({config={timer_presets={"nope","99999"}}})
    equal(table.concat(empty.values.config.timerPresets, ","), "5,15,25,60")
end)
test("a session that does not remember the tab always opens on the configured one", function()
    local disk = newDisk()
    put(disk, "preferences.json", {tab="tools", reducedMotion=false})
    local h = initialized({disk=disk, config={default_tab="hotspot", remember_last_tab=false}})
    equal(h.values.preferences.tab, "hotspot", "the stored tab must not win while remembering is off")
    h:send({action="preferences",tab="windows"})
    equal(h.values.preferences.tab, "windows", "switching tabs inside the session still works")
    equal(decode(disk.files[BASE .. "/preferences.json"]).tab, "tools", "the tab must not be persisted")
end)
test("the status refresh interval follows the setting", function()
    local h = initialized({config={system_refresh_seconds=5}})
    local baseline = h:count("snapshot")
    h:send({action="visibility",open=true,tab="windows"})
    equal(h:count("snapshot"), baseline + 1, "opening a system page refreshes once")
    if h:count("snapshot", true) > 0 then h:reply("snapshot", systemResult()) end
    h:tick(4999)
    equal(h:count("snapshot"), baseline + 1, "the refresh must wait for the configured interval")
    h:tick(1)
    equal(h:count("snapshot"), baseline + 2, "the configured interval must be honoured")
end)
test("changing a setting applies live instead of restarting the runtime", function()
    local h = initialized()
    h.config.timer_default_minutes = 7
    h.config.timer_presets = {"3","9"}
    h.config.panel_width = 512
    h.config.hotspot_default_ssid = "Tide Live"
    h.env.onConfigChanged()
    equal(h.values.config.timerDefaultMinutes, 7)
    equal(h.values.config.panelWidth, 512)
    equal(table.concat(h.values.config.timerPresets, ","), "3,9")
    equal(h.values.config.hotspotDefaultSsid, "Tide Live")
    equal(h:timer().timer.durationMs, 420000, "an untouched idle countdown follows the new default")
end)
test("a setting change never rewrites a countdown that was already used", function()
    local h = initialized()
    h:send({action="timer-start",durationMs=60000})
    h:send({action="timer-pause"})
    h.config.timer_default_minutes = 7
    h.env.onConfigChanged()
    equal(h:timer().timer.durationMs, 60000, "a used countdown keeps its own length")
end)

print(string.format("service_spec: %d passed, %d failed, %d assertions", passed, failed, assertions))
if failed > 0 then error("service_spec failed", 0) end
