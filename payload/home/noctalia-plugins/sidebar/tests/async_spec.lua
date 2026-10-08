-- Offline only: all commands remain inert in the harness queue.
-- Run from repository root: lua sidebar/tests/async_spec.lua
local env=setmetatable({arg={"sidebar/panel.luau","--harness"}},{__index=_G})
local H=assert(loadfile("sidebar/tests/sidebar_spec.lua","t",env))()
local count, assertions=0,0
local function eq(a,b,msg) assertions=assertions+1; assert(a==b,(msg or "mismatch")..": expected "..tostring(b)..", got "..tostring(a)) end
local function ok(v,msg) assertions=assertions+1; assert(v,msg or "assertion failed") end
local function frames(h) for _=1,100 do h:step(16) end end
local function new(record)
  local h=H.harness("off"); h.allowRemove=true
  if record then h.files["/data/timer.pid"]=record end
  h.deliver=function() error("automatic delivery forbidden during async regression") end
  h.env.onOpen(); frames(h); return h
end
local function match(r,k)
  local c=r.command
  if k=="start" or k=="stop" or k=="probe" then return type(c)=="string" and c:find("action='"..k.."'",1,true)~=nil end
  return type(c)=="table" and c[1]==k
end
local function pending(h,k) local n=0 for _,r in ipairs(h.async) do if match(r,k) then n=n+1 end end return n end
local function take(h,k) for i,r in ipairs(h.async) do if match(r,k) then table.remove(h.async,i); return r end end error("missing request: "..k) end
local function deliver(h,r,s,code) r.callback({exitCode=code or 0,stdout=s or ""}); frames(h) end
local function reply(h,k,s,code) local r=take(h,k); deliver(h,r,s,code); return r end
local function node(h,fn) local result; H.visit(h.tree,function(n) if fn(n) then result=n end end); return result end
local function text(h,s) return node(h,function(n) return n.props.text==s end)~=nil end
local function test(name,fn) fn(); count=count+1; print("ok "..count.." - "..name) end

local raw="v2 4242 8888 mock-round"
local live="LIVE 4242 8888 mock-round"
test("LIVE adoption survives close open with unknown duration",function()
  local h=new(raw); reply(h,"probe",live); ok(text(h,"后台计时中"))
  h.env.onClose(); h.env.onOpen(); frames(h); reply(h,"probe",live); ok(text(h,"后台计时中")); eq(pending(h,"start"),0)
end)
test("GONE marks adopted timer finished",function()
  local h=new(raw); reply(h,"probe","GONE\n"); ok(text(h,"已到点")); eq(pending(h,"stop"),0)
end)
test("invalid probe response does not mean completion",function()
  local h=new(raw); reply(h,"probe","LIVE 4242"); ok(text(h,"后台核验未返回有效结果，请重试")); ok(not text(h,"已到点"))
end)
test("stop carries full identity and accepts STOPPED",function()
  local h=new(raw); reply(h,"probe",live); h.env.onTimerToggle(); local stop=take(h,"stop")
  ok(stop.command:find(raw,1,true)); ok(stop.command:find("8888",1,true)); deliver(h,stop,"STOPPED"); ok(text(h,"待机"))
end)
test("start stop start queue retains correct old round",function()
  local h=new(); h.env.onTimerToggle(); h.env.onTimerToggle(); h.env.onTimerToggle()
  eq(pending(h,"start"),1); eq(pending(h,"stop"),0)
  reply(h,"start",live); eq(pending(h,"start"),0); local stop=take(h,"stop"); ok(stop.command:find(raw,1,true))
  deliver(h,stop,"STOPPED"); eq(pending(h,"start"),1); reply(h,"start","LIVE 4343 9999 mock-new"); ok(node(h,function(n) return type(n.props.text)=="string" and n.props.text:match("^运行中") end))
end)
test("control callbacks drain queued stop while closed",function()
  local h=new(); h.env.onTimerToggle(); h.env.onTimerToggle(); h.env.onClose(); local renders=h.renders
  reply(h,"start",live); eq(pending(h,"stop"),1); reply(h,"stop","STOPPED"); eq(h.renders,renders)
  h.env.onOpen(); frames(h); ok(text(h,"待机")); eq(pending(h,"start"),0)
end)
test("start acknowledgement across close preserves running state",function()
  local h=new(); h.env.onTimerToggle(); h.env.onClose(); reply(h,"start",live)
  h.env.onOpen(); frames(h); ok(node(h,function(n) return type(n.props.text)=="string" and n.props.text:match("^运行中") end)); eq(pending(h,"start"),0)
end)
test("synchronous start rejection clears pending and permits retry",function()
  local h=new(); h.rejectAsync=true; h.env.onTimerToggle(); ok(text(h,"启动失败，请检查计时器命令或后台记录"))
  h.rejectAsync=false; h.env.onTimerToggle(); eq(pending(h,"start"),1); reply(h,"start",live); ok(node(h,function(n) return type(n.props.text)=="string" and n.props.text:match("^运行中") end))
end)
test("stop failure retains identity for explicit retry",function()
  local h=new(raw); reply(h,"probe",live); h.env.onTimerToggle(); reply(h,"stop","",1)
  ok(text(h,"停止失败，后台记录未改动；请重试")); h.env.onTimerToggle(); local stop=take(h,"stop"); ok(stop.command:find(raw,1,true)); deliver(h,stop,"GONE"); ok(text(h,"待机"))
end)
test("BUSY start adopts existing timer instead of success",function()
  local h=new(); h.env.onTimerToggle(); reply(h,"start","BUSY 4242 8888 mock-round",1)
  ok(text(h,"后台已有计时，请先停止")); h.env.onTimerToggle(); ok(take(h,"stop").command:find(raw,1,true))
end)
test("probe queued stop receives birth identity after close",function()
  local h=new("4242"); h.env.onTimerToggle(); eq(pending(h,"stop"),0); h.env.onClose()
  reply(h,"probe","LIVE 4242 8888 legacy"); local stop=take(h,"stop"); ok(stop.command:find("8888",1,true)); deliver(h,stop,"STOPPED")
  h.files["/data/timer.pid"]=""; h.env.onOpen(); frames(h); ok(text(h,"待机"))
end)
print(string.format("async regression: %d scenarios, %d assertions passed (memory mocks only)",count,assertions))
