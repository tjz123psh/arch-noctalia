-- UX transitions against real panel code; every process and file is a memory mock.
local H=assert(loadfile("sidebar/tests/sidebar_spec.lua","t",setmetatable({arg={"sidebar/panel.luau","--harness"}},{__index=_G})))()
local N=assert(loadfile("sidebar/tests/notes_spec.lua","t",setmetatable({arg={"--harness"}},{__index=_G})))()
local passed=0
local function test(name,fn) fn();passed=passed+1;print("PASS "..name) end
local function opens(h)
  local n=0;for _,r in ipairs(h.async)do if type(r.command)=="table" and r.command[1]=="xdg-open" then n=n+1 end end;return n
end
local function firstOpen(h)
  for _,r in ipairs(h.async)do if type(r.command)=="table" and r.command[1]=="xdg-open" then return r end end
end
local function replaceOnce(text,from,to)
  local a,b=assert(text:find(from,1,true));return text:sub(1,a-1)..to..text:sub(b+1)
end

test("reopening during save seeds the editor from the newest draft",function()
  local h=N.new();N.input(h).props.onChange("draft");N.frames(h);local save=N.take(h,"save")
  local latest="draft + newest suffix";N.input(h).props.onChange(latest);h:step(16)
  h.env.onClose();h.env.onOpen();assert(N.input(h).props.value==latest)
  N.input(h).props.onChange(latest.."!")
  N.deliver(h,save,{ok=true,note=N.document("draft","saved-a")})
  assert(N.take(h,"save").command[7]==latest.."!")
end)
test("reopening during read preserves multiple later input events",function()
  local h=N.new();h.env.onIpc("notes","refresh");local read=N.take(h,"read")
  N.input(h).props.onChange("first draft");h:step(16)
  N.input(h).props.onChange("latest draft");h:step(16)
  h.env.onClose();h.env.onOpen();assert(N.input(h).props.value=="latest draft")
  N.input(h).props.onChange("latest draft!")
  N.deliver(h,read,{ok=true,note=N.note()})
  assert(N.take(h,"save").command[7]=="latest draft!")
end)
test("reopening a conflict preserves later typing and the recovery copy",function()
  local h=N.new();N.input(h).props.onChange("conflicted draft");N.frames(h)
  N.reply(h,"save",{ok=false,error="conflict",message="synthetic external change"},1)
  local latest="conflicted draft + newest suffix";N.input(h).props.onChange(latest);h:step(16)
  h.env.onClose();h.env.onOpen();assert(N.input(h).props.value==latest)
  N.input(h).props.onChange(latest.."!");h.env.onNoteNew(true)
  assert(N.take(h,"create").command[5]==latest.."!")
end)
test("post-commit conflict keeps newer input without automatic overwrite",function()
  local h=N.new();N.input(h).props.onChange("draft");N.frames(h)
  local save=N.take(h,"save");N.input(h).props.onChange("draft plus later typing")
  N.deliver(h,save,{ok=false,error="conflict",message="external change after commit"},1)
  assert(N.count(h,"save")==0 and N.input(h).props.value=="draft plus later typing")
  assert(H.find(h.tree,"notes-save-copy"))
end)
test("external editor waits through all queued saves",function()
  local h=N.new();N.input(h).props.onChange("first draft")
  H.find(h.tree,"notes-open").props.onClick()
  assert(opens(h)==0 and N.count(h,"save")==1)
  local first=N.take(h,"save");N.input(h).props.onChange("latest draft")
  N.deliver(h,first,{ok=true,note=N.document("first draft","saved-a")})
  assert(opens(h)==0)
  local last=N.take(h,"save");assert(last.command[7]=="latest draft")
  N.deliver(h,last,{ok=true,note=N.document("latest draft","saved-b")})
  assert(opens(h)==1 and firstOpen(h).command[2]:sub(-#N.name)==N.name)
end)
test("external editor never opens after a failed or conflicting save",function()
  for _,code in ipairs({"io_error","conflict"})do
    local h=N.new();N.input(h).props.onChange("keep this input")
    H.find(h.tree,"notes-open").props.onClick()
    N.reply(h,"save",{ok=false,error=code,message="synthetic failure"},1)
    assert(opens(h)==0 and N.input(h).props.value=="keep this input")
  end
end)
test("external editor waits for an outstanding read and a clean note opens directly",function()
  local h=N.new();H.find(h.tree,"notes-open").props.onClick();assert(opens(h)==1)
  h=N.new();h.env.onIpc("notes","refresh")
  H.find(h.tree,"notes-open").props.onClick();assert(opens(h)==0)
  N.reply(h,"read",{ok=true,note=N.note()});assert(opens(h)==1)
end)
test("undo-to-clean during a read still drains return and new-note actions",function()
  for _,action in ipairs({"notes-back","notes-new"})do
    local h=N.new();h.env.onIpc("notes","refresh");local read=N.take(h,"read")
    local original=N.note().text
    N.input(h).props.onChange(original.."x");N.input(h).props.onChange(original)
    H.find(h.tree,action).props.onClick()
    N.deliver(h,read,{ok=true,note=N.note()})
    assert(N.count(h,action=="notes-back" and "list" or "create")==1)
    assert(N.count(h,"save")==0)
  end
end)
test("CR LF CRLF and mixed task lines change only the selected checkbox",function()
  for _,seps in ipairs({{"\n","\n"},{"\r","\r"},{"\r\n","\r\n"},{"\r","\n"},{"\n","\r\n"}})do
    for _,target in ipairs({2,3})do
      local h=N.new();h.env.onIpc("notes","refresh")
      local raw="标题"..seps[1].."- [ ] first"..seps[2].."- [ ] second"
      local n=N.document(raw:gsub("\r\n","\n"),"line-endings")
      n.tasks={{line=2,text="first",done=false},{line=3,text="second",done=false}};n.taskCount=2;n.doneCount=0
      N.reply(h,"read",{ok=true,note=n});h.env.onNoteToggle(target)
      local request=N.take(h,"toggle")
      local label=target==2 and "first" or "second"
      local expected=replaceOnce(n.text,"- [ ] "..label,"- [x] "..label)
      assert(N.input(h).props.value==expected)
      local after=H.copy(n);after.text=expected;after.revision="toggled";after.tasks[target-1].done=true;after.doneCount=1
      N.deliver(h,request,{ok=true,note=after})
      assert(N.count(h,"save")==0 and N.input(h).props.value==expected)
    end
  end
end)
test("timer shortcuts work before first open without losing the remembered note",function()
  local h=H.harness("off",{notesFile=N.name,timerSec=90})
  h.env.onIpc("timer","start:60s")
  assert(N.count(h,"start")==1 and h.renders==0)
  assert(h:layout().timerSec==60 and h:layout().notesFile==N.name)
  N.reply(h,"start","LIVE 4242 8888 mock-round")
  h.env.onIpc("notes","new");assert(N.count(h,"create")==0 and h.renders==0)
end)
test("hidden stop adopts and verifies an existing worker before stopping it",function()
  local h=H.harness("off");h.files["/data/timer.pid"]="v2 4242 8888 mock-round"
  h.env.onIpc("timer","stop")
  assert(N.count(h,"probe")==1 and N.count(h,"stop")==0)
  N.reply(h,"probe","LIVE 4242 8888 mock-round")
  local stop=N.take(h,"stop");assert(stop.command:find("v2 4242 8888 mock-round",1,true))
  N.deliver(h,stop,"STOPPED");assert(h.renders==0)
end)
test("hidden start accepts another round after the worker cleared its record",function()
  local h=H.harness("off");h.env.onOpen();h:settle();h.env.onIpc("timer","start:1s")
  h.files["/data/timer.pid"]="v2 4242 8888 mock-round";N.reply(h,"start","LIVE 4242 8888 mock-round")
  h.env.onClose();local renders=h.renders;h.now=h.now+2000;h.files["/data/timer.pid"]=""
  h.env.onIpc("timer","start:60s")
  assert(N.count(h,"start")==1 and h.renders==renders)
end)
test("hidden start neither replaces a live timer nor treats read failure as completion",function()
  for _,failRead in ipairs({false,true})do
    local h=H.harness("off");h.env.onIpc("timer","start:60s")
    h.files["/data/timer.pid"]="v2 4242 8888 mock-round";N.reply(h,"start","LIVE 4242 8888 mock-round")
    if failRead then h.failRead={["/data/timer.pid"]=true} end
    h.env.onIpc("timer","start:2m");assert(N.count(h,"start")==0 and h.renders==0)
  end
end)
print(passed.." UX boundary regressions passed (memory mocks only)")
