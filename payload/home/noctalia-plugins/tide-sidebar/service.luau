--!nonstrict
-- The only writer of notes/timer files. Runs even while the panel is closed.
local Notes = require("./lib/notes.luau")
local Countdown = require("./lib/countdown.luau")
local Stopwatch = require("./lib/stopwatch.luau")
local Calculator = require("./lib/calculator.luau")
local Frontend = require("./lib/frontend.luau")
local frontend, command
local helper = noctalia.pluginDir() .. "/helpers/system.py"
local dataRoot = noctalia.pluginDataDir()
local base = type(dataRoot)=="string" and dataRoot~="" and (dataRoot .. "/private") or nil
local ready, noteModel, noteSlot, noteDirty, noteDue = false, nil, nil, false, 0
local noteError, noteWarning = "", ""
local timer, timerRevision, timerSlot = Countdown.new(1500000), 0, nil
local timerError, timerLastSecond = "", -1
local timerDirty, timerRetryAt, pendingFinish = false, 0, false
local stopwatch, stopwatchRevision, stopwatchSlot = Stopwatch.new(), 0, nil
local stopwatchError, stopwatchBlocked = "", false
local stopwatchDirty, stopwatchRetryAt = false, 0
local preferences = { tab = "notes", reducedMotion = false }
local calculation={expression="",result="0",error="",history={},requestId=""}
local lastAnswer=0
local function normalizePage(page)
  if page=="tools" or page=="calculator" or page=="timer" then return "tools" end
  if page=="hotspot" or page=="windows" then return page end
  return "notes"
end
local function reducedMotion()
  return preferences.reducedMotion or (type(noctalia.getConfig)=="function" and noctalia.getConfig("reduced_motion")==true)
end
-- Plugin settings are declared in plugin.toml; undeclared keys must never be read
-- (the host logs a loud warning and returns nil for those).
local function setting(key,fallback)
  if type(noctalia.getConfig)~="function" then return fallback end
  local value=noctalia.getConfig(key)
  if value==nil then return fallback end
  return value
end
local function clampInt(value,fallback,low,high)
  local number=tonumber(value)
  if not number then return fallback end
  number=math.floor(number)
  if number<low then return low elseif number>high then return high end
  return number
end
local function presetList()
  local raw=setting("timer_presets",nil)
  local result={}
  if type(raw)=="table" then
    for _,item in ipairs(raw) do
      local minutes=tonumber(item)
      if minutes and minutes>=1 and minutes<=5999 then
        table.insert(result,math.floor(minutes))
        if #result>=6 then break end
      end
    end
  end
  if #result==0 then result={5,15,25,60} end
  return result
end
local function readConfig()
  local tab=setting("default_tab","notes")
  if tab~="tools" and tab~="hotspot" and tab~="windows" then tab="notes" end
  return {
    panelWidth=clampInt(setting("panel_width",450),450,380,640),
    rememberLastTab=setting("remember_last_tab",true)==true,
    defaultTab=tab,
    timerDefaultMinutes=clampInt(setting("timer_default_minutes",25),25,1,5999),
    timerPresets=presetList(),
    confirmWindowClose=setting("confirm_window_close",true)==true,
    hotspotDefaultSsid=tostring(setting("hotspot_default_ssid","") or ""),
    hotspotDefaultBand=setting("hotspot_default_band","bg")=="a" and "a" or "bg",
    refreshSeconds=clampInt(setting("system_refresh_seconds",3),3,1,30),
  }
end
local config=readConfig()
local function refreshIntervalMs() return config.refreshSeconds*1000 end
local function visibleHoldMs() return config.refreshSeconds*4000 end
-- The countdown starts from the configured default; a saved archive still wins.
timer=Countdown.new(config.timerDefaultMinutes*60000)
local visibleUntil, nextRefresh, refreshBusy, actionBusy = 0, 0, false, false
local systemGeneration, hotspotOperationWarning = 0, nil
local system = {hotspot={available=false,on=nil,ssid="",desiredSsid="",iface="",gateway="",desiredBand="bg",busy=false},windows={},windowsError=nil,loading=true}
local actionSequence = 0
local function now() return noctalia.nowMs() end
local function readJson(name)
  local raw = noctalia.readFile(base .. "/" .. name)
  if not raw or raw == "" then return nil end
  local ok, value = pcall(noctalia.json.decode,raw)
  return ok and type(value)=="table" and value or nil
end
local function writeJson(name,value)
  local ok, raw = pcall(noctalia.json.encode,value)
  if not ok or type(raw)~="string" then return false end
  local written = noctalia.writeFile(base .. "/" .. name,raw)
  return written and noctalia.readFile(base .. "/" .. name)==raw
end
local noteIO={
  read=function(name)
    local path=base.."/"..name
    local raw=noctalia.readFile(path)
    if raw==nil and type(noctalia.fileExists)=="function" and noctalia.fileExists(path) then
      return nil,"existing_unreadable"
    end
    return raw
  end,
  write=function(name,raw) return noctalia.writeFile(base.."/"..name,raw) end,
  decode=function(raw) return noctalia.json.decode(raw) end,
  encode=function(value) return noctalia.json.encode(value) end,
}
local function publishNotes()
  local value={model=noteModel,ready=ready,saving=noteDirty,error=noteError,warning=noteWarning}
  noctalia.state.set("notes_snapshot",value)
  if frontend then frontend:publish("notes",value) end
end
local function publishTimer()
  local value={timer=timer,ready=ready,error=timerError}
  noctalia.state.set("timer_snapshot",value)
  if frontend then frontend:publish("timer",value) end
end
local function publishStopwatch()
  local value={stopwatch=stopwatch,ready=ready and not stopwatchBlocked,error=stopwatchError}
  noctalia.state.set("stopwatch_snapshot",value)
  if frontend then frontend:publish("stopwatch",value) end
end
local function publishPreferences()
  noctalia.state.set("preferences",preferences)
  if frontend then frontend:publish("preferences",preferences) end
end
local function configSnapshot()
  return {
    panelWidth=config.panelWidth,
    defaultTab=config.defaultTab,
    rememberLastTab=config.rememberLastTab,
    timerDefaultMinutes=config.timerDefaultMinutes,
    timerPresets=config.timerPresets,
    confirmWindowClose=config.confirmWindowClose,
    hotspotDefaultSsid=config.hotspotDefaultSsid,
    hotspotDefaultBand=config.hotspotDefaultBand,
    refreshSeconds=config.refreshSeconds,
    reducedMotion=reducedMotion(),
  }
end
local function publishConfig()
  local value=configSnapshot()
  noctalia.state.set("config",value)
  if frontend then frontend:publish("config",value) end
end
local function saveStopwatch()
  if not ready or stopwatchBlocked then return false end
  local snapshot,err=Stopwatch.snapshot(stopwatch,now())
  if not snapshot then stopwatchError=err and err.message or "秒表状态无效";return false end
  local slot=stopwatchSlot=="stopwatch-a.json" and "stopwatch-b.json" or "stopwatch-a.json"
  local revision=stopwatchRevision+1
  if writeJson(slot,{version=1,revision=revision,stopwatch=snapshot}) then
    stopwatchSlot=slot;stopwatchRevision=revision;stopwatchDirty=false;stopwatchError="";return true
  end
  stopwatchDirty=true;stopwatchRetryAt=now()+3000
  stopwatchError="秒表状态尚未保存，将自动重试；请先不要重启 Shell"
  return false
end
local function loadStopwatch()
  local best,found=nil,false
  for _,slot in ipairs({"stopwatch-a.json","stopwatch-b.json"}) do
    local raw=readJson(slot)
    if raw or (type(noctalia.fileExists)=="function" and noctalia.fileExists(base.."/"..slot)) then found=true end
    if raw and raw.version==1 and type(raw.revision)=="number" and raw.revision>=0 and raw.revision%1==0 then
      local restored=Stopwatch.restore(raw.stopwatch,now())
      if restored and (not best or raw.revision>best.revision) then best={value=restored,revision=raw.revision,slot=slot} end
    end
  end
  if best then stopwatch=best.value;stopwatchRevision=best.revision;stopwatchSlot=best.slot
  elseif found then stopwatchBlocked=true;stopwatchError="秒表存档无法安全读取，原文件已保留，未覆盖" end
end
local function publishSystem()
  system.hotspot.busy=actionBusy
  system.hotspot.operationWarning=hotspotOperationWarning
  noctalia.state.set("system_snapshot",system)
  if frontend then frontend:publish("system",system) end
end
local function feedback(ok,message,scope,extra)
  actionSequence=actionSequence+1
  local value={sequence=actionSequence,ok=ok==true,message=message or "",scope=scope or "",at=now()}
  for key,item in pairs(extra or {}) do value[key]=item end
  noctalia.state.set("feedback",value)
  if frontend then frontend:publish("feedback",value) end
end
local function flushNotes()
  if not ready or not noteDirty or not noteModel then return end
  local slot,err=Notes.save(noteIO,noteModel,noteSlot)
  if slot then noteSlot=slot; noteDirty=false; noteError="" else noteError=err or "便签未保存"; noteDue=now()+3000 end
  publishNotes()
end
local function saveTimer()
  if not ready then return false end
  local nextSlot=timerSlot=="timer-a.json" and "timer-b.json" or "timer-a.json"
  local revision=timerRevision+1
  if writeJson(nextSlot,{version=1,revision=revision,timer=Countdown.snapshot(timer,now())}) then
    timerSlot=nextSlot; timerRevision=revision; timerError=""; timerDirty=false; return true
  end
  timerDirty=true; timerRetryAt=now()+3000
  timerError="倒计时状态暂未保存；会自动重试，请先不要重启 Shell"
  return false
end
-- 5.4 起插件可以弹系统 OSD（plugin_api 39+）；旧版本没有这个表，静默跳过。
local function osdShow(icon,value,opts)
  local osd=noctalia.osd
  if type(osd)~="table" or type(osd.show)~="function" then return end
  pcall(osd.show,icon,value,opts)
end
local function finishNotification()
  noctalia.notify("倒计时结束","设定的时间已到。")
  osdShow("clock","倒计时结束")
end
local function finishSafely()
  pendingFinish=true
  if saveTimer() then pendingFinish=false; finishNotification() end
end
local function loadTimer()
  local best,found=nil,false
  for _,slot in ipairs({"timer-a.json","timer-b.json"}) do
    local raw=readJson(slot)
    if raw or (type(noctalia.fileExists)=="function" and noctalia.fileExists(base.."/"..slot)) then found=true end
    if raw and raw.version==1 and type(raw.revision)=="number" and raw.revision>=0 then
      local restored,err,didFinish=Countdown.restore(raw.timer,now())
      if restored and (not best or raw.revision>best.revision) then
        best={timer=restored,revision=raw.revision,slot=slot,didFinish=didFinish}
      end
    end
  end
  if best then
    timer=best.timer; timerRevision=best.revision; timerSlot=best.slot
    if best.didFinish then
      -- Save the completed state before notifying, so subsequent starts do not repeat it.
      finishSafely()
    end
  elseif found then
    -- A countdown is short-lived, so start clean but say so instead of silently
    -- overwriting the file that could not be read.
    timerError="倒计时存档无法读取，已从默认时长开始；旧文件将在下次保存时被覆盖"
  end
end

local function decodeResult(result)
  if result.timedOut then return nil,"查询超时，请重试" end
  if result.stdoutTruncated then return nil,"返回内容过大，未使用不完整结果" end
  local ok,value=pcall(noctalia.json.decode,result.stdout or "")
  if not ok or type(value)~="table" then return nil,"系统工具返回无效结果" end
  return value
end
local function run(args,callback,timeout)
  local cmd={"python3",helper}
  for _,arg in ipairs(args) do table.insert(cmd,tostring(arg)) end
  local accepted=noctalia.runAsync(cmd,function(result)
    local value,err=decodeResult(result)
    callback(value,err)
  end,timeout or 15000)
  if not accepted then callback(nil,"无法启动系统查询工具") end
end
local refresh
refresh=function()
  if refreshBusy or actionBusy then return end
  refreshBusy=true
  local generation=systemGeneration
  run({"snapshot"},function(value,err)
    refreshBusy=false
    if generation~=systemGeneration then
      if not actionBusy then refresh() end
      return
    end
    if value and value.ok and type(value.hotspot)=="table" and type(value.windows)=="table" then
      system=value
      system.loading=false
      system.hotspot.busy=actionBusy
    else
      system.loading=false
      system.hotspot.on=nil
      system.hotspot.error=err or (value and value.message) or "无法获取热点状态"
      system.windowsError=err or "无法获取窗口列表"
    end
    publishSystem()
  end,15000)
end
local function windowAction(kind,id)
  if type(id)~="string" or not id:match("^%d+$") then feedback(false,"无效窗口编号","windows"); return end
  run({kind,id},function(value,err)
    feedback(value and value.ok==true,(value and value.message) or err or "窗口操作已完成","windows",{windowAction=kind,windowId=id})
    refresh()
  end,5000)
end
local function hotspotAction(kind,path)
  if actionBusy then
    if type(path)=="string" and path~="" then run({"discard-request",path},function() end,5000) end
    feedback(false,"上一次热点操作还在进行，请稍候","hotspot"); return
  end
  if kind~="on" and kind~="off" and kind~="apply" then return end
  local args={"hotspot",kind}
  if type(path)=="string" and path~="" then table.insert(args,path) end
  actionBusy=true
  systemGeneration=systemGeneration+1
  hotspotOperationWarning=nil
  publishSystem()
  run(args,function(value,err)
    actionBusy=false
    if value and type(value.hotspot)=="table" then system.hotspot=value.hotspot end
    hotspotOperationWarning=value and type(value.warning)=="string" and value.warning or nil
    local message=(value and value.message) or err or "热点操作结束；请核对当前状态"
    if hotspotOperationWarning and hotspotOperationWarning~="" then message=message.." "..hotspotOperationWarning end
    feedback(value and value.ok==true,message,"hotspot")
    if value and value.ok==true then osdShow(system.hotspot.on and "wifi" or "wifi-off",message) end
    publishSystem()
    refresh()
  end,60000)
end
local function applyTimer(action,duration)
  if not ready then feedback(false,"后台服务正在初始化","timer"); return end
  local next,err,didFinish
  if action=="start" then next,err=Countdown.start(timer,now(),duration)
  elseif action=="pause" then next,err,didFinish=Countdown.pause(timer,now())
  elseif action=="resume" then next,err=Countdown.resume(timer,now())
  elseif action=="reset" then next,err=Countdown.reset(timer,now(),duration)
  else return end
  if not next then feedback(false,type(err)=="table" and err.message or tostring(err or "时长不正确"),"timer"); return end
  timer=next
  if didFinish then finishSafely() else pendingFinish=false; saveTimer() end
  publishTimer()
end
local function applyStopwatch(action)
  if not ready or stopwatchBlocked then feedback(false,stopwatchError~="" and stopwatchError or "秒表正在初始化","stopwatch");return end
  local operation=action=="start" and Stopwatch.start or action=="pause" and Stopwatch.pause or action=="reset" and Stopwatch.reset or action=="lap" and Stopwatch.lap
  if not operation then return end
  local value,err=operation(stopwatch,now())
  if not value then feedback(false,err and err.message or "秒表操作失败","stopwatch");return end
  stopwatch=value
  saveStopwatch();publishStopwatch()
end
command=function(c)
  if type(c)~="table" or type(c.action)~="string" then return end
  local action=c.action
  if action=="frontend-ready" then
    frontend.lastSeen=now()
    publishNotes(); publishTimer(); publishStopwatch(); publishSystem()
    frontend:publish("preferences",preferences); frontend:publish("calc",calculation)
    publishConfig()
    frontend:control(nil,frontend.page,reducedMotion())
  elseif action=="frontend-heartbeat" then
    frontend.lastSeen=now()
  elseif action=="frontend-geometry" then
    local values={page=normalizePage(c.page)}
    for _,key in ipairs({"windowWidth","windowHeight","stackHeight","editorViewportHeight","editorTop","editorBottom"}) do
      local value=tonumber(c[key]);if value and value==value and value>=0 and value<=20000 then values[key]=value end
    end
    frontend:publish("geometry",values)
  elseif action=="visibility" then
    local current=not c.controlSerial or c.controlSerial>=frontend.serial
    if current then frontend.visible=c.open==true;frontend.page=normalizePage(c.tab or frontend.page) end
    noctalia.state.set("visibility",{open=current and c.open==true or frontend.visible,tab=normalizePage(c.tab or frontend.page),at=now()})
  elseif action=="frontend-toggle" or action=="frontend-show" or action=="frontend-hide" then
    local kind=action:sub(10)
    if ready then frontend:ensure() end
    frontend:control(kind,c.page and normalizePage(c.page) or nil,reducedMotion())
  elseif action=="calc-evaluate" then
    local expression=type(c.expression)=="string" and c.expression or ""
    calculation.expression=expression;calculation.requestId=tostring(c.requestId or "")
    if expression=="" then calculation.result="0";calculation.error=""
    else
      local result,err=Calculator.evaluate(expression,lastAnswer)
      if result==nil then calculation.error=err and err.message or "表达式不正确"
      else
        calculation.result=Calculator.format(result);calculation.error=""
        if c.commit==true then
          lastAnswer=result
          table.insert(calculation.history,1,{expression=expression,result=calculation.result})
          if #calculation.history>8 then table.remove(calculation.history) end
        end
      end
    end
    frontend:publish("calc",calculation)
  elseif action:sub(1,5)=="note-" then
    if not ready or not noteModel then feedback(false,noteError~="" and noteError or "便签正在加载","notes"); return end
    local next,err=Notes.apply(noteModel,action:sub(6),c,now())
    if not next then noteError=err or "便签操作失败"; publishNotes(); feedback(false,noteError,"notes"); return end
    noteModel=next; noteDirty=true; noteError=""; noteDue=now()+500
    publishNotes()
    if action~="note-edit" then flushNotes() end
  elseif action=="flush" then flushNotes()
  elseif action=="refresh" then refresh()
  elseif action=="window-focus" then windowAction("focus",c.id)
  elseif action=="window-close" then windowAction("close",c.id)
  elseif action=="hotspot" then hotspotAction(c.kind,c.path)
  elseif action:sub(1,6)=="timer-" then applyTimer(action:sub(7),tonumber(c.durationMs))
  elseif action:sub(1,10)=="stopwatch-" then applyStopwatch(action:sub(11))
  elseif action=="preferences" then
    local tabs={home=true,notes=true,tools=true,calculator=true,timer=true,hotspot=true,windows=true}
    if tabs[c.tab] then preferences.tab=normalizePage(c.tab) end
    if type(c.reducedMotion)=="boolean" then preferences.reducedMotion=c.reducedMotion end
    -- Only a session that is allowed to remember the tab writes it back.
    if ready and config.rememberLastTab then writeJson("preferences.json",preferences) end
    publishPreferences()
    frontend:control(nil,normalizePage(preferences.tab),reducedMotion())
  end
end
frontend=Frontend.new(noctalia,base,function(value) command(value) end,function(message) feedback(false,message,"") end)
noctalia.state.watch("command",function(value) command(value);frontend:flush() end)
noctalia.state.watch("visibility",function(value)
  if type(value)~="table" then return end
  local needsSystem=value.tab==nil or value.tab=="hotspot" or value.tab=="windows" or value.tab=="home"
  visibleUntil=value.open==true and needsSystem and now()+visibleHoldMs() or 0
  if value.open==true and needsSystem and now()>=nextRefresh then nextRefresh=now()+refreshIntervalMs(); refresh() end
  if value.open~=true then flushNotes() end
end)
noctalia.setUpdateInterval(250)
publishNotes(); publishTimer(); publishStopwatch(); publishSystem()
local directoryOK, directoryResult = false, false
if base then directoryOK, directoryResult = pcall(noctalia.mkdirAll,base) end
if not base or not directoryOK or directoryResult==false then
  noteError="无法创建插件私有数据目录，未写入任何便签"; timerError=noteError; stopwatchError=noteError
  publishNotes(); publishTimer(); publishStopwatch()
else
local accepted=noctalia.runAsync({"chmod","-R","go-rwx","--",base},function(result)
  if result.exitCode~=0 then
    noteError="无法保护便签目录的访问权限，未写入任何便签"; timerError=noteError; stopwatchError=noteError
    publishNotes(); publishTimer(); publishStopwatch(); return
  end
  ready=true
  noteModel,noteSlot,noteWarning=Notes.load(noteIO,now())
  noteWarning=noteWarning or ""
  if not noteModel then noteError=noteWarning; noteWarning="" end
  local loaded=readJson("preferences.json")
  if loaded then
    local tabs={home=true,notes=true,tools=true,calculator=true,timer=true,hotspot=true,windows=true}
    if tabs[loaded.tab] then preferences.tab=normalizePage(loaded.tab) end
    preferences.reducedMotion=loaded.reducedMotion==true
  end
  if not config.rememberLastTab then preferences.tab=config.defaultTab end
  loadTimer();loadStopwatch()
  publishNotes(); publishTimer(); publishStopwatch()
  noctalia.state.set("preferences",preferences)
  publishPreferences();frontend:publish("calc",calculation);publishConfig()
  if frontend.serial==0 then frontend.page=normalizePage(preferences.tab) end;frontend.reducedMotion=reducedMotion()
  frontend:start()
  refresh()
end,5000)
if not accepted then noteError="无法启动后台存储初始化"; timerError=noteError; stopwatchError=noteError; publishNotes(); publishTimer(); publishStopwatch() end
end
function update()
  local t=now()
  if noteDirty and t>=noteDue then flushNotes() end
  if ready and timer.status=="running" then
    local next,didFinish,err=Countdown.tick(timer,t)
    if next then
      timer=next
      if didFinish then finishSafely() end
      local second=math.ceil(Countdown.remaining(timer,t)/1000)
      if second~=timerLastSecond or didFinish then timerLastSecond=second; publishTimer() end
    end
  end
  if ready and timerDirty and t>=timerRetryAt then
    if saveTimer() and pendingFinish then pendingFinish=false; finishNotification() end
    publishTimer()
  end
  if ready and stopwatchDirty and t>=stopwatchRetryAt then saveStopwatch();publishStopwatch() end
  if t<visibleUntil and t>=nextRefresh then nextRefresh=t+refreshIntervalMs(); refresh() end
  frontend:pulse()
  frontend:flush()
end
function onExit()
  frontend:shutdown()
  flushNotes()
  if ready and stopwatchDirty then saveStopwatch() end
  if ready and saveTimer() and pendingFinish then pendingFinish=false; finishNotification() end
  -- Files written during this session were created 0644; tighten them again.
  if ready then noctalia.runAsync({"chmod","-R","go-rwx","--",base},function() end,5000) end
end
function onIpc(event,payload)
  if event=="toggle" or event=="show" or event=="hide" then
    if ready then frontend:ensure() end
    frontend:control(event,payload and payload~="" and normalizePage(payload) or nil,reducedMotion())
  elseif event=="reload-ui" then frontend:restart()
  elseif event=="motion" and (payload=="on" or payload=="off") then command({action="preferences",reducedMotion=payload=="off"})
  elseif event=="refresh" then refresh()
  elseif event=="timer-start" then applyTimer("start",tonumber(payload) and tonumber(payload)*1000)
  elseif event=="timer-pause" then applyTimer("pause")
  elseif event=="timer-resume" then applyTimer("resume")
  elseif event=="timer-reset" then applyTimer("reset",tonumber(payload) and tonumber(payload)*1000)
  elseif event:sub(1,10)=="stopwatch-" then applyStopwatch(event:sub(11))
  elseif event=="hotspot" and (payload=="on" or payload=="off") then hotspotAction(payload)
  elseif event=="focus-window" then windowAction("focus",payload)
  elseif event=="close-window" then windowAction("close",payload)
  end
  frontend:flush()
end

function onConfigChanged()
  config=readConfig()
  -- A running or paused countdown is never touched: only an untouched idle one
  -- follows the new default length.
  if ready and timer.status=="idle" and timerRevision==0 then
    timer=Countdown.new(config.timerDefaultMinutes*60000)
    publishTimer()
  end
  if not config.rememberLastTab then preferences.tab=config.defaultTab end
  publishPreferences();publishConfig()
  frontend:control(nil,normalizePage(preferences.tab),reducedMotion())
end
