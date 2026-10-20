-- Run from the repository root: lua tide-sidebar/tests/tools_spec.lua
-- Or from the plugin directory: lua tests/tools_spec.lua
-- Tests use only the local Lua interpreter; modules do not depend on the host.
local source = debug.getinfo(1, "S").source
local directory = string.match(source, "^@(.*/)") or "./"
local Calculator = dofile(directory .. "../lib/calculator.luau")
local Countdown = dofile(directory .. "../lib/countdown.luau")

local passed, failed, assertions = 0, 0, 0

local function check(condition, message)
    assertions = assertions + 1
    if not condition then error(message or "assertion failed", 2) end
end

local function equal(actual, expected, message)
    check(actual == expected, (message or "values differ")
        .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function near(actual, expected)
    check(type(actual) == "number", "expected a number, got " .. tostring(actual))
    check(math.abs(actual - expected) <= 1e-12 * math.max(1, math.abs(expected)),
        "expected approximately " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name, run)
    local ok, err = pcall(run)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end

local function calculates(expression, expected, answer)
    local value, err = Calculator.evaluate(expression, answer)
    equal(err, nil, expression)
    near(value, expected)
end

local function rejects(run, code)
    local value, err = run()
    equal(value, nil)
    equal(type(err), "table")
    equal(err.code, code)
    check(type(err.message) == "string" and #err.message > 0, "expected a readable error")
    return err
end

local function stateIs(state, status, duration, remaining, deadline)
    equal(state.version, 1)
    equal(state.status, status)
    equal(state.durationMs, duration)
    equal(state.remainingMs, remaining)
    equal(state.deadlineMs, deadline)
end

local arithmetic = {
    { "1 + 2 * 3", 7 }, { "(1 + 2) * 3", 9 }, { "10-3-2", 5 },
    { "24/4/2", 3 }, { "2^3^2", 512 }, { "-2^2", -4 },
    { "(-2)^2", 4 }, { "2^-2", 0.25 }, { "-2^-2", -0.25 },
    { "2^(-2^2)", 0.0625 }, { "--2 + +-3", -1 }, { "2*-3", -6 },
    { ".5 + 1. + 0.25", 1.75 }, { "1e3 + 2.5E-2", 1000.025 },
    { "0.1 + 0.2", 0.3 }, { "0^0", 1 }, { "(2^3)^2", 64 },
    { "50%", 0.5 }, { "200+10%", 200.1 }, { "200*(1+10%)", 220 },
    { "(200+10)%", 2.1 }, { "50%%", 0.005 }, { "-50%", -0.5 },
    { "2^50%", math.sqrt(2) }, { "pi*2", math.pi * 2 },
    { "π/2", math.pi / 2 }, { "e^2", math.exp(2) }, { "PI + E", math.pi + math.exp(1) },
    { "sqrt(9)", 3 }, { "abs(-2)", 2 }, { "sqrt(abs(-9))+abs(-2^2)", 7 },
    { "SQRT(16)+ABS(-1)", 5 }, { "2×3÷4", 1.5 }, { "−2^2", -4 },
    { string.char(9) .. " 1 +" .. string.char(10) .. " 2 " .. string.char(13), 3 }, { "9223372036854775807+1", 9223372036854775808.0 },
}
for _, case in ipairs(arithmetic) do
    test("arithmetic " .. case[1], function() calculates(case[1], case[2]) end)
end

test("last answer remains caller owned", function()
    calculates("ans + 1", 1)
    calculates("ANS*2", 14, 7)
    calculates("ans^2", 9, -3)
    calculates("ans+1", 1) -- no implicit module-global previous answer
    rejects(function() return Calculator.evaluate("ans", math.huge) end, "invalid_answer")
    rejects(function() return Calculator.evaluate("ans", 0/0) end, "invalid_answer")
    rejects(function() return Calculator.evaluate("ans", "2") end, "invalid_answer")
end)

local invalidArithmetic = {
    { "", "empty_expression" }, { "   ", "empty_expression" },
    { ".", "invalid_number" }, { "1e", "invalid_number" }, { "2e+", "invalid_number" },
    { "1e999", "invalid_number" }, { "1+", "unexpected_token" },
    { "(1+2", "unmatched_parenthesis" }, { "1+2)", "unexpected_token" },
    { "()", "unexpected_token" }, { "2(3)", "unexpected_token" },
    { "2pi", "unexpected_token" }, { "2..3", "unexpected_token" },
    { "2 3", "unexpected_token" }, { "2**3", "unexpected_token" },
    { "2//3", "unexpected_token" }, { "50%2", "unexpected_token" },
    { "sqrt 9", "expected_parenthesis" }, { "abs()", "unexpected_token" },
    { "sqrt(9,4)", "invalid_character" }, { "unknown(2)", "unknown_identifier" },
    { "os", "unknown_identifier" }, { "load(2)", "unknown_identifier" },
    { "1;return 2", "invalid_character" }, { "'2'", "invalid_character" },
    { "{2}", "invalid_character" }, { "0x10", "unexpected_token" },
    { "1/0", "division_by_zero" }, { "1/-0", "division_by_zero" },
    { "2/(1-1)", "division_by_zero" }, { "0^-1", "division_by_zero" },
    { "sqrt(-1)", "domain_error" }, { "(-2)^.5", "domain_error" },
    { "1e308*1e308", "non_finite_result" }, { "1e308+1e308", "non_finite_result" },
    { "2^1024", "non_finite_result" }, { "1e308/1e-308", "non_finite_result" },
}
for _, case in ipairs(invalidArithmetic) do
    test("reject arithmetic " .. case[1], function()
        local err = rejects(function() return Calculator.evaluate(case[1]) end, case[2])
        check(type(err.position) == "number" and err.position >= 1, "expected an input position")
    end)
end

test("calculator input limits and exact error positions", function()
    rejects(function() return Calculator.evaluate(nil) end, "invalid_expression")
    rejects(function() return Calculator.evaluate({}) end, "invalid_expression")
    rejects(function() return Calculator.evaluate(string.rep("1", 1025)) end, "expression_too_long")
    rejects(function() return Calculator.evaluate(string.rep("(", 80) .. "1" .. string.rep(")", 80)) end,
        "expression_too_complex")
    rejects(function() return Calculator.evaluate(string.rep("-", 80) .. "1") end, "expression_too_complex")
    rejects(function() return Calculator.evaluate(string.rep("1^", 80) .. "1") end, "expression_too_complex")
    rejects(function() return Calculator.evaluate(string.rep("1+", 256) .. "1") end, "expression_too_complex")
    local err = rejects(function() return Calculator.evaluate("1 / 0") end, "division_by_zero")
    equal(err.position, 3)
    local character = rejects(function() return Calculator.evaluate("π + @") end, "invalid_character")
    equal(character.position, 6) -- byte offset, not Unicode character index
end)

test("calculator result formatting", function()
    equal(Calculator.format(Calculator.evaluate("0.1+0.2")), "0.3")
    equal(Calculator.format(-0.0), "0")
    equal(Calculator.format(42), "42")
    equal(Calculator.format(math.huge), "—")
    equal(Calculator.format(0/0), "—")
    equal(Calculator.format(nil), "—")
end)

test("calculator generated precedence cases", function()
    for a = -12, 12 do
        for b = -5, 5 do
            calculates("(" .. a .. ")+(" .. b .. ")*2", a + b * 2)
            if b ~= 0 then
                calculates("(" .. a .. ")/(" .. b .. ")", a / b)
            end
        end
    end
end)

test("malformed calculator input never escapes as an exception", function()
    local symbols = { "0", "2", "(", ")", "+", "-", "*", "/", "^", "%",
        "sqrt", "ans", ".", ";", string.char(0), "π", "÷", "a", "'", "{", "}" }
    local seed = 73
    for attempt = 1, 500 do
        local parts = {}
        for index = 1, attempt % 37 do
            seed = (seed * 48271) % 2147483647
            parts[index] = symbols[seed % #symbols + 1]
        end
        local ok, result, err = pcall(Calculator.evaluate, table.concat(parts))
        check(ok, "evaluate threw on malformed input")
        if result == nil then
            check(type(err) == "table" and type(err.code) == "string", "missing structured error")
        else
            equal(err, nil)
            check(result == result and math.abs(result) < math.huge, "non-finite successful result")
        end
    end
end)

test("duration fields and inclusive limits", function()
    equal(Countdown.duration(0, 0, 1), 1000)
    equal(Countdown.duration(1, 2, 3), 3723000)
    equal(Countdown.duration(99, 59, 59), 359999000)
    equal(Countdown.duration(nil, 1, nil), 60000)
    equal(Countdown.MIN_DURATION_MS, 1000)
    equal(Countdown.MAX_DURATION_MS, 359999000)
    rejects(function() return Countdown.duration(0, 0, 0) end, "invalid_duration")
    rejects(function() return Countdown.duration() end, "invalid_duration")
    for _, fields in ipairs({ {100,0,0}, {-1,0,0}, {0,60,0}, {0,0,60},
        {0,0,-1}, {0,0,1.5}, {0,0,"1"}, {true,0,0}, {math.huge,0,0} }) do
        rejects(function() return Countdown.duration(fields[1], fields[2], fields[3]) end,
            "invalid_duration_fields")
    end
end)

test("new state validates durations and is independent", function()
    stateIs(Countdown.new(), "idle", 300000, 300000, nil)
    stateIs(Countdown.new(1000), "idle", 1000, 1000, nil)
    stateIs(Countdown.new(359999000), "idle", 359999000, 359999000, nil)
    for _, value in ipairs({ 0, 999, 359999001, -1000, 1000.5, "1000", false, math.huge, 0/0 }) do
        rejects(function() return Countdown.new(value) end, "invalid_duration")
    end
    local a, b = Countdown.new(), Countdown.new()
    check(a ~= b, "new state aliases another instance")
    a.remainingMs = 1
    equal(b.remainingMs, 300000)
end)

test("start, pause, resume and exact deadline", function()
    local idle = Countdown.new(65000)
    local started, err = Countdown.start(idle, 100000)
    equal(err, nil)
    stateIs(started, "running", 65000, 65000, 165000)
    stateIs(idle, "idle", 65000, 65000, nil)
    equal(Countdown.remaining(started, 101000), 64000)
    local advanced, didFinish = Countdown.tick(started, 120100)
    equal(didFinish, false)
    stateIs(advanced, "running", 65000, 44900, 165000)
    equal(started.remainingMs, 65000)
    local paused, pauseError, pauseFinished = Countdown.pause(advanced, 120100)
    equal(pauseError, nil)
    equal(pauseFinished, false)
    stateIs(paused, "paused", 65000, 44900, nil)
    equal(Countdown.remaining(paused, 999999), 44900)
    local resumed = Countdown.resume(paused, 200000)
    stateIs(resumed, "running", 65000, 44900, 244900)
    local almost, almostFinished = Countdown.tick(resumed, 244899)
    equal(almostFinished, false)
    equal(almost.remainingMs, 1)
    equal(Countdown.format(almost.remainingMs), "00:00:01")
    local finished, justFinished = Countdown.tick(almost, 244900)
    equal(justFinished, true)
    stateIs(finished, "finished", 65000, 0, nil)
    equal(finished.finishedAtMs, 244900)
    local finishedAgain, repeated = Countdown.tick(finished, 999999)
    equal(repeated, false)
    equal(finishedAgain.finishedAtMs, 244900)
    check(finishedAgain ~= finished, "tick must return a new table")
end)

test("service catches expiry after all panel ticks stop", function()
    local state = Countdown.start(Countdown.new(1000), 10000)
    local finished, didFinish = Countdown.tick(state, 900000)
    equal(didFinish, true)
    equal(finished.finishedAtMs, 11000)
    for index = 1, 5 do
        finished, didFinish = Countdown.tick(finished, 900000 + index * 1000)
        equal(didFinish, false)
    end
end)

test("reset and start with a replacement duration", function()
    local original = Countdown.start(Countdown.new(5000), 100)
    local restarted = Countdown.start(original, 1000, 3000)
    stateIs(restarted, "running", 3000, 3000, 4000)
    equal(original.deadlineMs, 5100)
    local reset = Countdown.reset(restarted, 1100)
    stateIs(reset, "idle", 3000, 3000, nil)
    equal(reset.finishedAtMs, nil)
    stateIs(Countdown.reset(restarted, 1100, 10000), "idle", 10000, 10000, nil)
    local finished = Countdown.tick(restarted, 4000)
    stateIs(Countdown.reset(finished, 5000), "idle", 3000, 3000, nil)
    rejects(function() return Countdown.start(original, 1000, 0) end, "invalid_duration")
    rejects(function() return Countdown.reset(original, 1000, 999) end, "invalid_duration")
end)

test("pause at deadline reports finish, not a zero-length pause", function()
    local running = Countdown.start(Countdown.new(1000), 500)
    local finished, err, didFinish = Countdown.pause(running, 1500)
    equal(err, nil)
    equal(didFinish, true)
    equal(finished.status, "finished")
    local _, again = Countdown.tick(finished, 1600)
    equal(again, false)
end)

test("resume can preserve less than one second", function()
    local running = Countdown.start(Countdown.new(1000), 100)
    local paused = Countdown.pause(running, 1099)
    equal(paused.remainingMs, 1)
    local resumed = Countdown.resume(paused, 10000)
    equal(resumed.deadlineMs, 10001)
    local done, didFinish = Countdown.tick(resumed, 10001)
    equal(done.status, "finished")
    equal(didFinish, true)
end)

test("invalid transitions do not alter state", function()
    local idle = Countdown.new(1000)
    rejects(function() return Countdown.pause(idle, 0) end, "invalid_transition")
    rejects(function() return Countdown.resume(idle, 0) end, "invalid_transition")
    local running = Countdown.start(idle, 0)
    rejects(function() return Countdown.resume(running, 1) end, "invalid_transition")
    local paused = Countdown.pause(running, 1)
    rejects(function() return Countdown.pause(paused, 2) end, "invalid_transition")
    local finished = Countdown.tick(running, 1000)
    rejects(function() return Countdown.resume(finished, 1000) end, "invalid_transition")
    equal(idle.status, "idle")
    equal(running.status, "running")
    equal(paused.status, "paused")
end)

test("running snapshots recover from absolute deadlines", function()
    local running = Countdown.start(Countdown.new(10000), 100000)
    local snapshot, err = Countdown.snapshot(running, 103000)
    equal(err, nil)
    stateIs(snapshot, "running", 10000, 7000, 110000)
    equal(running.remainingMs, 10000)
    local restored, restoreError, didFinish = Countdown.restore(snapshot, 109000)
    equal(restoreError, nil)
    equal(didFinish, false)
    stateIs(restored, "running", 10000, 1000, 110000)
    equal(snapshot.remainingMs, 7000)
    local finished, finishError, expired = Countdown.restore(snapshot, 115000)
    equal(finishError, nil)
    equal(expired, true)
    equal(finished.finishedAtMs, 110000)
    local savedFinish = Countdown.snapshot(finished, 115000)
    local restarted, restartError, again = Countdown.restore(savedFinish, 200000)
    equal(restartError, nil)
    equal(again, false)
    stateIs(restarted, "finished", 10000, 0, nil)
end)

test("snapshot does not swallow an unreported expired transition", function()
    local running = Countdown.start(Countdown.new(1000), 1000)
    local expiredSnapshot = Countdown.snapshot(running, 3000)
    stateIs(expiredSnapshot, "running", 1000, 0, 2000)
    local finished, err, didFinish = Countdown.restore(expiredSnapshot, 4000)
    equal(err, nil)
    equal(didFinish, true)
    equal(finished.status, "finished")
    local _, again = Countdown.tick(finished, 4001)
    equal(again, false)
end)

test("paused and idle snapshots survive long restarts", function()
    local idle = Countdown.new(10000)
    local savedIdle = Countdown.snapshot(idle, 1)
    local restoredIdle, idleError, idleFinish = Countdown.restore(savedIdle, 999999)
    equal(idleError, nil)
    equal(idleFinish, false)
    stateIs(restoredIdle, "idle", 10000, 10000, nil)
    local paused = Countdown.pause(Countdown.start(idle, 1000), 3500)
    local snapshot = Countdown.snapshot(paused, 999999)
    local restored, err, didFinish = Countdown.restore(snapshot, 999999999)
    equal(err, nil)
    equal(didFinish, false)
    stateIs(restored, "paused", 10000, 7500, nil)
    equal(Countdown.resume(restored, 999999999).deadlineMs, 1000007499)
end)

test("snapshot contains independent JSON-safe data only", function()
    local running = Countdown.start(Countdown.new(5000), 0)
    running.transient = function() error("must not be serialized") end
    local snapshot = Countdown.snapshot(running, 1)
    equal(snapshot.transient, nil)
    for key, value in pairs(snapshot) do
        equal(type(key), "string")
        check(type(value) == "string" or type(value) == "number", "non-JSON snapshot value")
    end
    snapshot.remainingMs = 1
    equal(running.remainingMs, 5000)
end)

test("invalid clocks and integer overflow are rejected", function()
    local idle = Countdown.new(1000)
    for _, now in ipairs({ -1, 0.5, "1000", false, math.huge, 0/0, 9007199254740992 }) do
        rejects(function() return Countdown.start(idle, now) end, "invalid_time")
    end
    rejects(function() return Countdown.start(idle, nil) end, "invalid_time")
    rejects(function() return Countdown.start(idle, 9007199254740991) end, "invalid_time")
    rejects(function() return Countdown.remaining(idle, -1) end, "invalid_time")
    rejects(function() return Countdown.snapshot(idle, -1) end, "invalid_time")
    local value, didFinish, err = Countdown.tick(idle, -1)
    equal(value, nil)
    equal(didFinish, false)
    equal(err.code, "invalid_time")
    local paused = Countdown.pause(Countdown.start(idle, 0), 1)
    rejects(function() return Countdown.resume(paused, 9007199254740991) end, "invalid_time")
end)

test("corrupt or unsupported snapshots fail explicitly", function()
    rejects(function() return Countdown.restore(nil, 0) end, "invalid_state")
    rejects(function() return Countdown.restore({}, 0) end, "unsupported_version")
    local badVersion = Countdown.new(1000)
    badVersion.version = 2
    rejects(function() return Countdown.restore(badVersion, 0) end, "unsupported_version")
    local corruptions = {
        { "durationMs", -1 }, { "durationMs", math.huge }, { "remainingMs", -1 },
        { "remainingMs", 1001 }, { "remainingMs", 0.5 }, { "remainingMs", "1000" },
        { "status", "missing" }, { "status", "paused" }, { "deadlineMs", false },
    }
    for _, change in ipairs(corruptions) do
        local snapshot = Countdown.start(Countdown.new(1000), 0)
        snapshot[change[1]] = change[2]
        rejects(function() return Countdown.restore(snapshot, 500) end, "invalid_state")
    end
    local noDeadline = Countdown.start(Countdown.new(1000), 0)
    noDeadline.deadlineMs = nil
    rejects(function() return Countdown.restore(noDeadline, 0) end, "invalid_state")
    local badIdle = Countdown.new(1000)
    badIdle.remainingMs = 500
    rejects(function() return Countdown.restore(badIdle, 0) end, "invalid_state")
    local badPaused = Countdown.pause(Countdown.start(Countdown.new(1000), 0), 1)
    badPaused.remainingMs = 0
    rejects(function() return Countdown.restore(badPaused, 0) end, "invalid_state")
    local badFinished = Countdown.tick(Countdown.start(Countdown.new(1000), 0), 1000)
    badFinished.finishedAtMs = nil
    rejects(function() return Countdown.restore(badFinished, 0) end, "invalid_state")
end)

test("large Unix milliseconds and maximum duration never accumulate tick drift", function()
    local epoch = 1700000000000
    local duration = Countdown.MAX_DURATION_MS
    local state = Countdown.start(Countdown.new(duration), epoch)
    for _, elapsed in ipairs({ 1, 15234, 60000, duration - 1 }) do
        local didFinish
        state, didFinish = Countdown.tick(state, epoch + elapsed)
        equal(didFinish, false)
        equal(state.deadlineMs, epoch + duration)
        equal(state.remainingMs, duration - elapsed)
    end
    local saved = Countdown.snapshot(state, epoch + duration - 1)
    local restored, err, didFinish = Countdown.restore(saved, epoch + duration)
    equal(err, nil)
    equal(didFinish, true)
    equal(restored.finishedAtMs, epoch + duration)
end)

test("clock rollback is bounded without rewriting the deadline", function()
    local running = Countdown.start(Countdown.new(1000), 2000)
    local state, didFinish = Countdown.tick(running, 500)
    equal(didFinish, false)
    equal(state.remainingMs, 1000)
    equal(state.deadlineMs, 3000)
    equal(Countdown.remaining(state, 2999), 1)
    local finished = Countdown.tick(state, 3000)
    local persisted, again = Countdown.tick(finished, 0)
    equal(persisted.status, "finished")
    equal(again, false)
end)

test("countdown formatting uses ceiling seconds and full hours", function()
    equal(Countdown.format(0), "00:00:00")
    equal(Countdown.format(1), "00:00:01")
    equal(Countdown.format(999), "00:00:01")
    equal(Countdown.format(1000), "00:00:01")
    equal(Countdown.format(1001), "00:00:02")
    equal(Countdown.format(59999), "00:01:00")
    equal(Countdown.format(3723000), "01:02:03")
    equal(Countdown.format(359999000), "99:59:59")
    equal(Countdown.format(-1), "--:--:--")
    equal(Countdown.format(math.huge), "--:--:--")
    equal(Countdown.format(nil), "--:--:--")
end)

print(string.format("tools_spec: %d passed, %d failed, %d assertions", passed, failed, assertions))
if failed > 0 then error("tools_spec failed", 0) end
