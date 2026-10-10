-- Memory-only regression harness: no screenshot, process, desktop or user-file operation is executed.
local panelPath = arg[1] or "magnifier/panel.luau"
local count, assertions = 0, 0
local function check(v, msg) assertions = assertions + 1; assert(v, msg or "assertion failed") end
local function equal(a,b,msg) check(a==b,(msg or "mismatch")..": "..tostring(a).." ~= "..tostring(b)) end
local function clone(v)
  if type(v)~="table" then return v end
  local r={} for k,x in pairs(v) do r[k]=clone(x) end return r
end
local function visit(n,fn)
  if type(n)~="table" then return end
  fn(n); for _,child in ipairs(n.children or {}) do visit(child,fn) end
end
local function harness(runtime)
  local h={now=1000,files={},removed={},commands={},pending={},renders=0,subscriptions=0,runtime=runtime or "/memory/runtime"}
  local ui=setmetatable({}, {__index=function(_,kind) return function(props,children) return {kind=kind,props=props or {},children=children or {}} end end})
  local function encode(v) return string.format('{"zoom":%.12g,"cx":%.12g,"cy":%.12g}',v.zoom,v.cx,v.cy) end
  local function decode(s)
    local z,x,y=s:match('"zoom":([%d.e+-]+),"cx":([%d.e+-]+),"cy":([%d.e+-]+)')
    return z and {zoom=tonumber(z),cx=tonumber(x),cy=tonumber(y)} or nil
  end
  local n={
    nowMs=function()return h.now end,
    outputs=function()return {{focused=true,x=0,y=0,width=1920,height=1080}}end,
    getenv=function(key)if key=="XDG_RUNTIME_DIR" then return h.runtime end end,
    expandPath=function(path)return (path:gsub("^~","/memory/home"))end,
    pluginDataDir=function()return "/memory/data"end,
    json={encode=encode,decode=decode},mkdirAll=function()return true end,
    readFile=function(path)return h.files[path]end,
    writeFile=function(path,value)h.files[path]=value; return true end,
    removeFile=function(path)h.removed[#h.removed+1]=path; h.files[path]=nil; return true end,
    notify=function()end,
    runAsync=function(command,callback,timeout)
      h.commands[#h.commands+1]=clone(command)
      if h.reject then return false end
      if callback then h.pending[#h.pending+1]={command=clone(command),callback=callback,timeout=timeout} end
      return true
    end,
  }
  local p={render=function(tree)h.tree=clone(tree);h.renders=h.renders+1 end,
    setNeedsFrameTick=function(v)h.frame=v;h.subscriptions=h.subscriptions+1 end,
    close=function()h.env.onClose()end}
  h.env=setmetatable({noctalia=n,panel=p,ui=ui},{__index=_G})
  assert(loadfile(panelPath,"t",h.env))()
  function h:step(ms)self.now=self.now+ms;self.env.onFrameTick(ms)end
  function h:take()
    for i,r in ipairs(self.pending)do if type(r.command)=="table" and r.command[1]=="grim" then table.remove(self.pending,i);return r end end
    error("no pending screenshot")
  end
  function h:deliver(r,code)
    local path=r.command[#r.command];self.files[path]="fixture PNG";r.callback({exitCode=code or 0,stdout=""});return path
  end
  function h:complete(code)return self:deliver(self:take(),code)end
  function h:image()local found;visit(self.tree,function(n)if n.kind=="image"then found=n end end);return found end
  function h:zoom()local value;visit(self.tree,function(n)if n.kind=="label" and n.props.text:find("视口",1,true)then value=tonumber(n.props.text:match("(%d+)%%"))end end);return value end
  function h:saved()return decode(self.files["/memory/data/view.json"])end
  function h:tracker()for path in pairs(self.files)do if path:match("/cursor%-.+%.pos$")then return path end end end
  function h:heartbeat()for path in pairs(self.files)do if path:match("/heartbeat%-.+%.txt$")then return path end end end
  function h:cleanErrors()for path,value in pairs(self.files)do if path:match("/errors%.txt$")then check(value=="","guard swallowed error: "..tostring(value))end end end
  h.env.onOpen({});return h
end
local function test(name,fn)fn();count=count+1;print("ok "..count.." - "..name)end

test("closed capture callbacks cannot render or wake the panel",function()
  local h=harness();local r=h:take();local path=r.command[#r.command];h.env.onClose()
  local renders,subscriptions=h.renders,h.subscriptions;h:deliver(r)
  equal(h.files[path],nil);equal(h.renders,renders);equal(h.subscriptions,subscriptions);equal(h.frame,false);h:cleanErrors()
end)
test("rapid reopen isolates frames and tracker leases even in the same millisecond",function()
  local h=harness();local old=h:take();local oldHeartbeat=h:heartbeat();h.env.onClose();h.env.onOpen({})
  local fresh=h:take();check(old.command[#old.command]~=fresh.command[#fresh.command]);check(oldHeartbeat~=h:heartbeat())
  local newPath=h:deliver(fresh);local renders=h.renders;h:deliver(old)
  equal(h:image().props.path,newPath);equal(h.files[newPath],"fixture PNG");equal(h.renders,renders);h:cleanErrors()
end)
test("only the most recent three completed frames are retained",function()
  local h=harness();local paths={}
  for i=1,7 do paths[i]=h:complete();if i<7 then h:step(34)end end
  for i=1,4 do equal(h.files[paths[i]],nil)end
  for i=5,7 do equal(h.files[paths[i]],"fixture PNG")end
  h.env.onClose();for _,path in ipairs(paths)do equal(h.files[path],nil)end;h:cleanErrors()
end)
test("capture failure retains the last good image and removes partial output",function()
  local h=harness();local good=h:complete();h:step(34);local bad=h:complete(1)
  equal(h:image().props.path,good);equal(h.files[bad],nil);h:cleanErrors()
end)
test("watchdog and late completion cannot clear the new in-flight capture",function()
  local h=harness();local old=h:take();h:step(2101);local fresh=h:take()
  h:deliver(old);h:step(34);equal(#h.pending,0,"old callback restarted capture over active request")
  h:deliver(fresh);equal(#h.pending,1,"latest coalesced viewport should be requested once");h:cleanErrors()
end)
test("keyboard zoom visibly interpolates and reaches the exact requested endpoint",function()
  local h=harness();h:complete();h.env.onKey("plus",true);h:step(16);h:complete()
  check(h:zoom()>200 and h:zoom()<250,"zoom jumped to endpoint")
  h:step(150);h:complete();equal(h:zoom(),250);h.env.onClose();equal(h:saved().zoom,2.5);h:cleanErrors()
end)
test("repeated zoom keys accumulate against the requested target",function()
  local h=harness();h:complete();h.env.onKey("plus",true);h.env.onKey("plus",true);h.env.onClose()
  equal(h:saved().zoom,3.125,"close should save the last user target, not an intermediate frame");h:cleanErrors()
end)
test("zoom reversal starts from the current view rather than jumping",function()
  local h=harness();h:complete();h.env.onKey("plus",true);h:step(70);h:complete();local mid=h:zoom()
  h.env.onKey("minus",true);h:step(16);h:complete();check(h:zoom()<mid and h:zoom()>200)
  h:step(150);h:complete();equal(h:zoom(),200);h:cleanErrors()
end)
test("repeated keyboard pans preserve target and close commits it",function()
  local h=harness();h:complete();h.env.onKey("Left",true);h.env.onKey("Left",true);h.env.onClose()
  equal(h:saved().cx,806);equal(h:saved().cy,540); -- 每次77.5px移动都按原有规则对齐到整数视口原点。
  h:cleanErrors()
end)
test("mouse follow remains immediate during a keyboard zoom",function()
  local h=harness();h:complete();h.env.onKey("plus",true)
  h.files[h:tracker()]="seq=1 type=move x=300 y=700";h:step(16)
  local r=h:take();local x,y,w,hh=r.command[6]:match("(%-?%d+),(%-?%d+) (%d+)x(%d+)")
  check(math.abs(tonumber(x)+tonumber(w)/2-300)<=.5);check(math.abs(tonumber(y)+tonumber(hh)/2-700)<=.5)
  h:deliver(r);h:step(160);h:complete();h.env.onClose();equal(h:saved().cx,300);equal(h:saved().cy,700.5);h:cleanErrors()
end)
test("closing removes only owned paths and does not enqueue pkill or wildcard cleanup",function()
  local h=harness();h:complete();local heartbeat=h:heartbeat();local countBefore=#h.commands;h.env.onClose()
  equal(h.files[heartbeat],nil);equal(#h.commands,countBefore)
  for _,command in ipairs(h.commands)do if type(command)=="string"then check(not command:find("pkill",1,true));check(not command:find("rm ",1,true));check(not command:find("*.png",1,true))end end
  h:cleanErrors()
end)
test("rejected screenshot start does not leave a stuck pending request",function()
  local h=harness();h:complete();h.reject=true;h:step(40);equal(#h.pending,0);h.reject=false;h:step(40);equal(#h.pending,1);h:cleanErrors()
end)
test("odd-sized viewports do not drift across repeated close and open",function()
  local h=harness();h:complete();h.env.onKey("plus",true);h:step(160);h:complete();h.env.onClose()
  local saved=h:saved()
  for _=1,4 do h.env.onOpen({});h:complete();h.env.onClose();equal(h:saved().cx,saved.cx);equal(h:saved().cy,saved.cy)end
  h:cleanErrors()
end)
test("zoom targets remain within bounds during fast repeated input",function()
  local h=harness();h:complete();for _=1,100 do h.env.onKey("plus",true)end;h.env.onClose();equal(h:saved().zoom,8)
  h.env.onOpen({});h:complete();for _=1,100 do h.env.onKey("minus",true)end;h.env.onClose();equal(h:saved().zoom,1);h:cleanErrors()
end)
if arg[2]=="--emit-tracker-command" then
  local h=harness("/memory/user's runtime")
  for _,command in ipairs(h.commands)do if type(command)=="string"then print("TRACKER_COMMAND="..command)end end
end
print(string.format("PASS: magnifier %d scenarios, %d assertions (memory mocks only)",count,assertions))
