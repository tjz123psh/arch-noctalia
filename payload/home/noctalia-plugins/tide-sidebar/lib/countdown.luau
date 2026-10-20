-- Pure, immutable countdown state for a service (not a panel-owned timer).
-- All clock values are caller-supplied Unix milliseconds, never os.clock().
-- Keep the returned state after every operation. tick returns didFinish only
-- on the running -> finished transition; persist finished before notifying.
-- start/pause/resume/reset/new -> state | nil, error | nil
-- pause additionally returns didFinish as its third result if already due.
-- tick(state, nowMs) -> state | nil, didFinish, error | nil
-- restore(snapshot, nowMs) -> state | nil, error | nil, didFinish
-- snapshot preserves a pending running transition, even if its deadline passed.
local Countdown = {}

Countdown.VERSION = 1
Countdown.MIN_DURATION_MS = 1000
Countdown.MAX_DURATION_MS = (99 * 3600 + 59 * 60 + 59) * 1000
Countdown.DEFAULT_DURATION_MS = 5 * 60 * 1000
local MAX_SAFE_INTEGER = 9007199254740991

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function integer(value)
    return finite(value) and value == math.floor(value)
end

local function failure(code, message)
    return { code = code, message = message }
end

local function validDuration(value)
    return integer(value) and value >= Countdown.MIN_DURATION_MS
        and value <= Countdown.MAX_DURATION_MS
end

local function durationError()
    return failure("invalid_duration", "倒计时时长须为 1 秒至 99 小时 59 分 59 秒的整数毫秒")
end

local function validClock(value)
    return integer(value) and value >= 0 and value <= MAX_SAFE_INTEGER
end

local function clockError()
    return failure("invalid_time", "当前时间须为有效的 Unix 毫秒时间戳")
end

local function clone(state)
    return {
        version = Countdown.VERSION,
        status = state.status,
        durationMs = state.durationMs,
        remainingMs = state.remainingMs,
        deadlineMs = state.deadlineMs,
        finishedAtMs = state.finishedAtMs,
    }
end

local function stateError(state)
    if type(state) ~= "table" then
        return failure("invalid_state", "倒计时状态无效")
    end
    if state.version ~= Countdown.VERSION then
        return failure("unsupported_version", "倒计时快照版本不受支持")
    end
    if not validDuration(state.durationMs) or not integer(state.remainingMs)
        or state.remainingMs < 0 or state.remainingMs > state.durationMs then
        return failure("invalid_state", "倒计时时长或剩余时间无效")
    end
    if state.status == "running" then
        if not validClock(state.deadlineMs) or state.finishedAtMs ~= nil then
            return failure("invalid_state", "运行中的倒计时缺少有效截止时间")
        end
    elseif state.status == "finished" then
        if state.remainingMs ~= 0 or state.deadlineMs ~= nil
            or not validClock(state.finishedAtMs) then
            return failure("invalid_state", "已结束的倒计时状态无效")
        end
    elseif state.status == "paused" or state.status == "idle" then
        if state.deadlineMs ~= nil or state.finishedAtMs ~= nil
            or state.remainingMs <= 0
            or (state.status == "idle" and state.remainingMs ~= state.durationMs) then
            return failure("invalid_state", "未运行的倒计时状态无效")
        end
    else
        return failure("invalid_state", "倒计时状态名称无效")
    end
    return nil
end

local function validate(state, nowMs)
    local err = stateError(state)
    if err then
        return err
    end
    if not validClock(nowMs) then
        return clockError()
    end
    return nil
end

local function remainingUnchecked(state, nowMs)
    if state.status == "running" then
        -- The absolute deadline is authoritative. Bound a wall-clock rollback
        -- so the displayed remainder can never exceed the configured duration.
        return math.max(0, math.min(state.durationMs, state.deadlineMs - nowMs))
    end
    return state.remainingMs
end

-- Hour/minute/second fields are independent integers, not silently normalized.
-- Omitted fields mean zero; a completely empty/zero duration is invalid.
function Countdown.duration(hours, minutes, seconds)
    if hours == nil then hours = 0 end
    if minutes == nil then minutes = 0 end
    if seconds == nil then seconds = 0 end
    if not integer(hours) or hours < 0 or hours > 99
        or not integer(minutes) or minutes < 0 or minutes > 59
        or not integer(seconds) or seconds < 0 or seconds > 59 then
        return nil, failure("invalid_duration_fields", "小时须为 0–99，分钟和秒须为 0–59 的整数")
    end
    local value = (hours * 3600 + minutes * 60 + seconds) * 1000
    if not validDuration(value) then
        return nil, durationError()
    end
    return value, nil
end

function Countdown.new(durationMs)
    if durationMs == nil then durationMs = Countdown.DEFAULT_DURATION_MS end
    if not validDuration(durationMs) then
        return nil, durationError()
    end
    return {
        version = Countdown.VERSION,
        status = "idle",
        durationMs = durationMs,
        remainingMs = durationMs,
    }, nil
end

-- Starting always begins a fresh interval; use resume to keep paused progress.
function Countdown.start(state, nowMs, durationMs)
    local err = validate(state, nowMs)
    if err then return nil, err end
    if durationMs == nil then durationMs = state.durationMs end
    if not validDuration(durationMs) then return nil, durationError() end
    if nowMs > MAX_SAFE_INTEGER - durationMs then return nil, clockError() end
    return {
        version = Countdown.VERSION,
        status = "running",
        durationMs = durationMs,
        remainingMs = durationMs,
        deadlineMs = nowMs + durationMs,
    }, nil
end

function Countdown.remaining(state, nowMs)
    local err = validate(state, nowMs)
    if err then return nil, err end
    return remainingUnchecked(state, nowMs), nil
end

function Countdown.tick(state, nowMs)
    local err = validate(state, nowMs)
    if err then return nil, false, err end
    local nextState = clone(state)
    if state.status ~= "running" then
        return nextState, false, nil
    end
    nextState.remainingMs = remainingUnchecked(state, nowMs)
    if nextState.remainingMs <= 0 then
        nextState.status = "finished"
        nextState.finishedAtMs = state.deadlineMs
        nextState.deadlineMs = nil
        return nextState, true, nil
    end
    return nextState, false, nil
end

function Countdown.pause(state, nowMs)
    local err = validate(state, nowMs)
    if err then return nil, err, false end
    if state.status ~= "running" then
        return nil, failure("invalid_transition", "只有运行中的倒计时可以暂停"), false
    end
    local nextState, didFinish = Countdown.tick(state, nowMs)
    if didFinish then
        return nextState, nil, true
    end
    nextState.status = "paused"
    nextState.deadlineMs = nil
    return nextState, nil, false
end

function Countdown.resume(state, nowMs)
    local err = validate(state, nowMs)
    if err then return nil, err end
    if state.status ~= "paused" then
        return nil, failure("invalid_transition", "只有暂停中的倒计时可以继续")
    end
    if nowMs > MAX_SAFE_INTEGER - state.remainingMs then return nil, clockError() end
    local nextState = clone(state)
    nextState.status = "running"
    nextState.deadlineMs = nowMs + state.remainingMs
    return nextState, nil
end

function Countdown.reset(state, nowMs, durationMs)
    local err = validate(state, nowMs)
    if err then return nil, err end
    if durationMs == nil then durationMs = state.durationMs end
    return Countdown.new(durationMs)
end

-- JSON-safe data only. A running snapshot retains its deadline and status so
-- a missed finish is still reported by restore rather than silently consumed.
function Countdown.snapshot(state, nowMs)
    local err = validate(state, nowMs)
    if err then return nil, err end
    local result = clone(state)
    result.remainingMs = remainingUnchecked(state, nowMs)
    return result, nil
end

-- Paused snapshots stay paused across restarts. Running snapshots use their
-- absolute deadline, not the saved remainder, and may finish immediately.
function Countdown.restore(snapshot, nowMs)
    local err = validate(snapshot, nowMs)
    if err then return nil, err, false end
    local nextState, didFinish = Countdown.tick(snapshot, nowMs)
    return nextState, nil, didFinish
end

-- Ceiling seconds avoids displaying 00:00:00 before the actual deadline.
function Countdown.format(milliseconds)
    if not finite(milliseconds) or milliseconds < 0
        or milliseconds > Countdown.MAX_DURATION_MS then
        return "--:--:--"
    end
    local totalSeconds = math.ceil(milliseconds / 1000)
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor(totalSeconds / 60) % 60
    local seconds = totalSeconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

return Countdown
