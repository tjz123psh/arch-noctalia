--!nonstrict
-- Pure stopwatch state. No timer/notes state is read or changed here.
local M = { MAX_LAPS = 100, MAX_ELAPSED_MS = 315576000000 }
local validStatus={idle=true,running=true,paused=true}
local function finite(value) return type(value)=="number" and value==value and value<math.huge and value>-math.huge end
local function number(value) return finite(value) and value>=0 and value%1==0 end
local function errorValue(code,message) return {code=code,message=message} end
local function clone(state)
  local out={version=1,status=state.status,elapsedMs=state.elapsedMs,startedAtMs=state.startedAtMs,laps={}}
  for _,lap in ipairs(state.laps or {}) do table.insert(out.laps,{index=lap.index,totalMs=lap.totalMs,splitMs=lap.splitMs}) end
  return out
end
function M.new() return {version=1,status="idle",elapsedMs=0,laps={}} end
function M.validate(state)
  if type(state)~="table" or state.version~=1 or not validStatus[state.status]
    or not number(state.elapsedMs) or state.elapsedMs>M.MAX_ELAPSED_MS or type(state.laps)~="table" then
    return nil,errorValue("invalid_state","秒表状态格式不正确")
  end
  if state.status=="running" and not number(state.startedAtMs) then return nil,errorValue("invalid_anchor","秒表开始时间不正确") end
  if state.status~="running" and state.startedAtMs~=nil then return nil,errorValue("invalid_anchor","暂停秒表不应保留运行时间锚点") end
  if #state.laps>M.MAX_LAPS then return nil,errorValue("too_many_laps","计次数量超出上限") end
  local previous=0
  for key in pairs(state.laps) do
    if type(key)~="number" or key%1~=0 or key<1 or key>#state.laps then return nil,errorValue("invalid_laps","计次列表格式不正确") end
  end
  for index,lap in ipairs(state.laps) do
    if type(lap)~="table" or lap.index~=index or not number(lap.totalMs) or not number(lap.splitMs)
      or lap.totalMs<previous or lap.totalMs>M.MAX_ELAPSED_MS or lap.splitMs~=lap.totalMs-previous then
      return nil,errorValue("invalid_laps","计次记录格式不正确")
    end
    previous=lap.totalMs
  end
  if state.status=="idle" and (state.elapsedMs~=0 or #state.laps~=0) then return nil,errorValue("invalid_idle","未开始的秒表应为零") end
  if state.status~="running" and previous>state.elapsedMs then return nil,errorValue("invalid_laps","计次超出了累计时间") end
  return clone(state)
end
function M.elapsed(state,nowMs)
  local value=state.elapsedMs or 0
  if state.status=="running" and finite(nowMs) and finite(state.startedAtMs) then value=value+math.max(0,nowMs-state.startedAtMs) end
  local last=state.laps and state.laps[#state.laps]
  if last then value=math.max(value,last.totalMs) end
  return math.floor(math.min(M.MAX_ELAPSED_MS,math.max(0,value)))
end
local function prepare(state,nowMs)
  local copy,err=M.validate(state)
  if not copy then return nil,err end
  if not number(nowMs) then return nil,errorValue("invalid_time","时间值无效") end
  return copy
end
function M.start(state,nowMs)
  local copy,err=prepare(state,nowMs);if not copy then return nil,err end
  if copy.status=="running" then return copy end
  copy.status="running";copy.startedAtMs=nowMs
  return copy
end
function M.pause(state,nowMs)
  local copy,err=prepare(state,nowMs);if not copy then return nil,err end
  if copy.status~="running" then return copy end
  copy.elapsedMs=M.elapsed(copy,nowMs);copy.startedAtMs=nil;copy.status="paused"
  return copy
end
function M.reset(state,nowMs)
  local copy,err=prepare(state,nowMs);if not copy then return nil,err end
  return M.new()
end
function M.lap(state,nowMs)
  local copy,err=prepare(state,nowMs);if not copy then return nil,err end
  if copy.status~="running" then return nil,errorValue("not_running","请先开始秒表") end
  if #copy.laps>=M.MAX_LAPS then return nil,errorValue("lap_limit","最多保留 100 次计次，未丢弃旧记录") end
  local total=M.elapsed(copy,nowMs)
  local previous=copy.laps[#copy.laps]
  table.insert(copy.laps,{index=#copy.laps+1,totalMs=total,splitMs=total-(previous and previous.totalMs or 0)})
  return copy
end
function M.snapshot(state,nowMs)
  local copy,err=prepare(state,nowMs);if not copy then return nil,err end
  if copy.status=="running" then copy.elapsedMs=M.elapsed(copy,nowMs);copy.startedAtMs=nowMs end
  return copy
end
function M.restore(value,nowMs)
  local copy,err=prepare(value,nowMs);if not copy then return nil,err end
  return M.snapshot(copy,nowMs)
end
function M.format(ms)
  ms=finite(ms) and math.max(0,math.floor(ms)) or 0
  local total=math.floor(ms/1000)
  local hours=math.floor(total/3600)
  local minutes=math.floor(total/60)%60
  local seconds=total%60
  local hundredths=math.floor(ms%1000/10)
  if hours>0 then return string.format("%02d:%02d:%02d.%02d",hours,minutes,seconds,hundredths) end
  return string.format("%02d:%02d.%02d",minutes,seconds,hundredths)
end
return M
