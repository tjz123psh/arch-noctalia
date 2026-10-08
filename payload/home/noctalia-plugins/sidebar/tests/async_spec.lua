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
  if k=="poll" then return type(c)=="table" and c[1]=="playerctl" and c[2]=="metadata" end
  if k=="seek" then return type(c)=="table" and c[1]=="playerctl" and c[3]=="position" end
  if k=="start" or k=="stop" or k=="probe" then return type(c)=="string" and c:find("action='"..k.."'",1,true)~=nil end
  return type(c)=="table" and c[1]==k
end
local function pending(h,k) local n=0 for _,r in ipairs(h.async) do if match(r,k) then n=n+1 end end return n end
local function take(h,k) for i,r in ipairs(h.async) do if match(r,k) then table.remove(h.async,i); return r end end error("missing request: "..k) end
local function deliver(h,r,s,code) r.callback({exitCode=code or 0,stdout=s or ""}); frames(h) end
local function reply(h,k,s,code) local r=take(h,k); deliver(h,r,s,code); return r end
local function node(h,fn) local result; H.visit(h.tree,function(n) if fn(n) then result=n end end); return result end
local function text(h,s) return node(h,function(n) return n.props.text==s end)~=nil end
local function slider(h) local n=node(h,function(n) return n.props.onDragEnd=="onSeekEnd" end); return n and n.props.value end
local function image(h) local n=node(h,function(n) return n.type=="image" end); return n and n.props.path end
local function metadata(o)
  local f={"mock.instance","Playing","Artist","Title","100000000","10000000","/track/1","file:///music/one",""}
  for k,v in pairs(o or {}) do f[k]=v end
  return table.concat(f,string.char(31)).."\n"
end
local function media(o) local h=new(); reply(h,"poll",metadata(o)); return h end
local function poll(h,o) h:step(3100); h.env.update(); reply(h,"poll",metadata(o)) end
local function allocate(h,id) local p="/data/sidebar-art-"..string.format("%010d",id); h.files[p]="mock bytes"; reply(h,"mktemp",p.."\n"); return p end
local function cover(h,id) local p=allocate(h,id); reply(h,"curl"); reply(h,"file","image/png\n"); eq(image(h),p); return p end
local function test(name,fn) fn(); count=count+1; print("ok "..count.." - "..name) end

test("nine ASCII31 fields preserve empty artist and multiline title",function()
  local h=new(); local r=take(h,"poll"); local _,seps=r.command[4]:gsub(string.char(31),""); eq(seps,8)
  deliver(h,r,metadata({[3]="",[4]="a\nb\t' quoted"})); ok(text(h,"a\nb\t' quoted")); ok(text(h,"未知艺术家")); eq(slider(h),100)
end)
test("malformed metadata and invalid status fail closed",function()
  local h=new(); reply(h,"poll","mock"..string.char(31).."Playing"); ok(text(h,"暂无播放内容"))
  poll(h,{[2]="Invalid"}); ok(text(h,"暂无播放内容")); eq(slider(h),nil)
end)
test("nonfinite length hides seek and position clamps",function()
  local h=media({[5]="inf"}); eq(slider(h),nil); poll(h,{[6]="200000000"}); eq(slider(h),1000)
  poll(h,{[6]="-10"}); eq(slider(h),0)
end)
test("old poll cannot rewind after seek completion",function()
  local h=media(); h:step(3100); h.env.update(); local old=take(h,"poll")
  h.env.onSeekEnd("800"); reply(h,"seek"); deliver(h,old,metadata()); eq(slider(h),800)
end)
test("old poll cannot rewind pending seek",function()
  local h=media(); h:step(3100); h.env.update(); local old=take(h,"poll")
  h.env.onSeekEnd("700"); deliver(h,old,metadata()); eq(slider(h),700); reply(h,"seek"); eq(pending(h,"poll"),1)
end)
test("seek serializes and keeps only latest target",function()
  local h=media(); h.env.onSeekEnd("200"); h.env.onSeekEnd("500"); h.env.onSeekEnd("900")
  eq(pending(h,"seek"),1); eq(reply(h,"seek").command[4],"20.000"); eq(pending(h,"seek"),1)
  local last=reply(h,"seek"); eq(last.command[4],"90.000"); eq(last.command[2],"--player=mock.instance")
  reply(h,"poll",metadata({[6]="90000000"})); eq(slider(h),900)
end)
test("seek rejects invalid input and clamps valid input",function()
  local h=media(); for _,v in ipairs({"nan","inf","bad"}) do h.env.onSeekEnd(v) end; eq(pending(h,"seek"),0)
  h.env.onSeekEnd("2000"); eq(take(h,"seek").command[4],"100.000")
end)
test("old lifecycle metadata cannot overwrite reopened panel",function()
  local h=new(); local old=take(h,"poll"); h.env.onClose(); h.env.onOpen(); frames(h)
  reply(h,"poll",metadata({[4]="New"})); deliver(h,old,metadata({[4]="Old"})); ok(text(h,"New")); ok(not text(h,"Old"))
end)
test("stale cover cleans only its unique owned path",function()
  local h=media({[9]="https://example.invalid/a"}); local old=allocate(h,1); local download=take(h,"curl")
  poll(h,{[4]="New",[9]="https://example.invalid/b"}); eq(pending(h,"mktemp"),0)
  h.files["/data/user-image"]="keep"; deliver(h,download); eq(h.files[old],nil); eq(h.files["/data/user-image"],"keep")
  local fresh=cover(h,2); ok(fresh~=old); eq(pending(h,"curl"),0)
end)
test("new track failure removes old image and retries after cooldown",function()
  local h=media({[9]="https://example.invalid/a"}); cover(h,3)
  poll(h,{[4]="New",[9]="https://example.invalid/b"}); eq(image(h),nil)
  local failed=allocate(h,4); reply(h,"curl","",22); eq(h.files[failed],nil); eq(image(h),nil)
  poll(h,{[4]="New",[9]="https://example.invalid/b"}); eq(pending(h,"mktemp"),0)
  h:step(30000); h.env.update(); reply(h,"poll",metadata({[4]="New",[9]="https://example.invalid/b"})); cover(h,5)
end)
test("non-image MIME rejects and removes temporary path",function()
  local h=media({[9]="https://example.invalid/error"}); local p=allocate(h,6); reply(h,"curl"); reply(h,"file","text/html\n"); eq(image(h),nil); eq(h.files[p],nil)
end)
test("file URI decodes once preserves plus and strips query",function()
  local h=media({[9]="file://localhost/tmp/a+b%20%2520%23%3F.png?ignored#fragment"}); local p=allocate(h,7)
  local cp=reply(h,"cp"); eq(cp.command[2],"--"); eq(cp.command[3],"/tmp/a+b %20#?.png"); eq(cp.command[4],p)
  reply(h,"file","image/jpeg"); eq(image(h),p)
end)
test("unsafe file URI authorities escapes and relative paths rejected",function()
  for i,url in ipairs({"file://remote/tmp/a","file:relative","file:///tmp/%00","file:///tmp/%xx"}) do
    local h=media({[9]=url}); local p=allocate(h,10+i); eq(pending(h,"cp"),0); eq(h.files[p],nil); eq(image(h),nil)
  end
end)
test("close during allocation cleans stale path without download",function()
  local h=media({[9]="https://example.invalid/a"}); h.env.onClose(); local p=allocate(h,20)
  eq(h.files[p],nil); eq(pending(h,"curl"),0)
end)
test("paused media polls every three seconds without overlap",function()
  local h=media({[2]="Paused"}); h.env.update(); eq(pending(h,"poll"),0)
  h:step(3000); h.env.update(); eq(pending(h,"poll"),1); h:step(9000); h.env.update(); eq(pending(h,"poll"),1)
end)
test("collapsed playing media polls every three seconds",function()
  local h=media(); h.env.onIpc("toggle","media"); frames(h); h.env.update(); reply(h,"poll",metadata())
  h.env.update(); eq(pending(h,"poll"),0); h:step(3000); h.env.update(); eq(pending(h,"poll"),1)
end)
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
