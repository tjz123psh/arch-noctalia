-- Offline only: all UI commands and file writes remain in memory.
local env = setmetatable({arg={"sidebar/panel.luau","--harness"}}, {__index=_G})
local H = assert(loadfile("sidebar/tests/sidebar_spec.lua","t",env))()
local function frames(h) for _=1,85 do h:step(16) end end
local function matches(req, action)
  local c=req.command
  if action=="start" or action=="stop" or action=="probe" then return type(c)=="string" and c:find("action='"..action.."'",1,true) end
  return type(c)=="table" and c[1]=="python3" and c[3]==action
end
local function take(h,action)
  for i,r in ipairs(h.async) do if matches(r,action) then return table.remove(h.async,i) end end
  error("missing request: "..action)
end
local function count(h,action) local n=0 for _,r in ipairs(h.async) do if matches(r,action) then n=n+1 end end return n end
local serial=0
local function deliver(h,req,value,code)
  local stdout=value
  if type(value)=="table" then serial=serial+1; stdout="notes-reply-"..serial; h.encoded[stdout]=value end
  req.callback({exitCode=code or 0,stdout=stdout or ""}); frames(h)
end
local function reply(h,action,value,code) local r=take(h,action); deliver(h,r,value,code); return r end
local name="今日 '计划'.md"
local label="完成 '示例' <b> & $(echo noop)"
local function note(revision,done)
  return {name=name,title="今日计划",revision=revision or "revision-a",editable=true,
    text="# 便签\n- ["..(done and "x" or " ").."] "..label.."\n- [x] 已完成\n",
    tasks={{line=2,text=label,done=done or false},{line=3,text="已完成",done=true}},taskCount=2,doneCount=done and 2 or 1,truncated=false}
end
local function document(text,revision,filename)
  local n=note(revision);n.text=text;n.tasks={};n.taskCount=0;n.doneCount=0
  if filename then n.name=filename;n.title=filename end
  return n
end
local function new()
  local h=H.harness("off"); h.env.onOpen(); h:settle(); h.deliver=function() end
  h.env.onIpc("toggle","notes"); frames(h)
  reply(h,"list",{ok=true,notes={{name=name,title="今日计划",taskCount=2,doneCount=1},{name="另一份.md",title="另一份",taskCount=0,doneCount=0}},truncated=false})
  h.env.onIpc("notes","select:"..name); frames(h)
  reply(h,"read",{ok=true,note=note()})
  return h
end
local function text(h,s)
  local found=false; H.visit(h.tree,function(n) if n.props.text==s then found=true end end); return found
end
local function input(h)
  local found; H.visit(h.tree,function(n) if n.props.key and n.props.key:match("^notes%-editor%-%d+$") then found=n end end); return found
end
if arg[1]=="--harness" then return {new=new,take=take,reply=reply,note=note,label=label,name=name,frames=frames,
  input=input,count=count,deliver=deliver,document=document,text=text} end
local passed=0
local function test(name,fn) fn(); passed=passed+1; print("PASS "..name) end

test("normal multiline editor and new button replace preview and task input",function()
  local h=H.harness(); h.env.onOpen(); h:settle(); assert(count(h,"list")==0)
  h=new(); local editor=input(h)
  assert(editor.props.multiline and editor.props.submitOnEnter==false and editor.props.onSubmit==nil)
  assert(editor.props.value==note().text and H.find(h.tree,"notes-new"))
  assert(not H.find(h.tree,"notes-preview") and not H.find(h.tree,"notes-add"))
end)
test("typing is debounced and saving never clears or remounts the editor",function()
  local h=new(); local editor=input(h); local key=editor.props.key
  editor.props.onChange("第一行\n第二行\n")
  h:step(300); assert(count(h,"save")==0)
  editor.props.onChange("第一行\n第二行继续写\n")
  h:step(600); assert(count(h,"save")==0)
  h:step(250); assert(count(h,"save")==1)
  local req=take(h,"save"); assert(req.command[6]=="revision-a" and req.command[7]=="第一行\n第二行继续写\n")
  deliver(h,req,{ok=true,note=document(req.command[7],"revision-b")})
  assert(input(h).props.value==req.command[7] and input(h).props.key==key)
  assert(text(h,"已保存") and count(h,"save")==0)
end)
test("typing during a save queues the latest text rather than dropping it",function()
  local h=new(); input(h).props.onChange("first\n"); frames(h); local req=take(h,"save")
  input(h).props.onChange("first\ncontinued typing\n")
  deliver(h,req,{ok=true,note=document("first\n","revision-b")})
  local nextSave=take(h,"save")
  assert(nextSave.command[6]=="revision-b" and nextSave.command[7]=="first\ncontinued typing\n")
  deliver(h,nextSave,{ok=true,note=document(nextSave.command[7],"revision-c")})
  assert(input(h).props.value==nextSave.command[7])
end)
test("closing flushes the last keystroke and completes without hidden rendering",function()
  local h=new(); input(h).props.onChange("last keystroke\n"); h.env.onClose()
  local req=take(h,"save"); local renders=h.renders
  deliver(h,req,{ok=true,note=document("last keystroke\n","revision-b")})
  assert(h.renders==renders and count(h,"save")==0)
  h.env.onOpen(); frames(h); reply(h,"read",{ok=true,note=document("last keystroke\n","revision-b")})
  assert(input(h).props.value=="last keystroke\n")
end)
test("close drains newer input after the in-flight save",function()
  local h=new(); input(h).props.onChange("first"); frames(h); local first=take(h,"save")
  input(h).props.onChange("latest before close"); h.env.onClose()
  deliver(h,first,{ok=true,note=document("first","revision-b")})
  local nextSave=take(h,"save"); assert(nextSave.command[7]=="latest before close")
  deliver(h,nextSave,{ok=true,note=document("latest before close","revision-c")})
  assert(count(h,"save")==0)
end)
test("new note is created once and opens an empty editable box",function()
  local h=new(); h.env.onNoteNew(false); h.env.onNoteNew(false); assert(count(h,"create")==1)
  local req=take(h,"create"); assert(req.command[5]=="")
  deliver(h,req,{ok=true,note=document("","created-revision","便签-3.md")})
  assert(input(h).props.value=="" and input(h).props.multiline and h:layout().notesFile=="便签-3.md")
end)
test("new waits for the current dirty note to save",function()
  local h=new(); input(h).props.onChange("save this first"); h.env.onNoteNew(false)
  assert(count(h,"create")==0 and count(h,"save")==1)
  reply(h,"save",{ok=true,note=document("save this first","revision-b")}); assert(count(h,"create")==1)
end)
test("switching files saves first instead of losing the draft",function()
  local h=new(); input(h).props.onChange("unsaved draft")
  h.env.onIpc("notes","select:另一份.md"); assert(count(h,"save")==1 and count(h,"read")==0)
  reply(h,"save",{ok=true,note=document("unsaved draft","revision-b")})
  local req=take(h,"read"); assert(req.command[5]=="另一份.md")
  deliver(h,req,{ok=true,note=document("other content","other-revision","另一份.md")})
  assert(input(h).props.value=="other content")
end)
test("conflict preserves editor text and allows save as a new note",function()
  local h=new(); input(h).props.onChange("keep\nmy draft"); frames(h)
  reply(h,"save",{ok=false,error="conflict",message="外部已修改，保留输入"},1)
  assert(input(h).props.value=="keep\nmy draft" and count(h,"read")==0 and count(h,"save")==0)
  assert(H.find(h.tree,"notes-save-copy")); h.env.onNoteNew(true)
  local req=take(h,"create"); assert(req.command[5]=="keep\nmy draft")
  deliver(h,req,{ok=true,note=document("keep\nmy draft","copy-revision","便签-3.md")})
  assert(input(h).props.value=="keep\nmy draft" and text(h,"已保存"))
end)
test("a stale read cannot replace text typed since the request started",function()
  local h=new(); h.env.onIpc("notes","refresh"); local req=take(h,"read")
  input(h).props.onChange("keep this typing")
  deliver(h,req,{ok=true,note=document("external text","external-revision")})
  assert(input(h).props.value=="keep this typing")
  local save=take(h,"save"); assert(save.command[6]=="revision-a")
end)
test("toggle writes the exact revision and updates the main text box",function()
  local h=new(); h.env.onNoteToggle(2); h.env.onNoteToggle(2)
  assert(count(h,"toggle")==1); local req=take(h,"toggle")
  assert(req.command[6]=="revision-a" and req.command[7]=="2" and req.command[8]=="1")
  deliver(h,req,{ok=true,note=note("revision-b",true)})
  assert(H.find(h.tree,"task-check-2").props.glyph=="square-check" and input(h).props.value==note("revision-b",true).text)
end)
test("old task callbacks cannot operate on a refreshed note",function()
  local h=new(); local oldCheck=H.find(h.tree,"task-check-2").props.onClick; local oldFocus=H.find(h.tree,"task-focus-2").props.onClick
  h.env.onIpc("notes","refresh"); reply(h,"read",{ok=true,note=note("new-revision")})
  oldCheck(); oldFocus(); assert(count(h,"toggle")==0 and count(h,"start")==0)
end)
test("collapsed editor is detached and ignores stale input events",function()
  local h=new(); local old=input(h); h.env.onIpc("toggle","notes"); assert(not input(h))
  old.props.onChange("invisible"); assert(count(h,"save")==0)
  h.env.onIpc("toggle","notes"); reply(h,"read",{ok=true,note=note()}); assert(input(h).props.value==note().text)
end)
test("failed creation preserves the existing note",function()
  local h=new(); h.rejectAsync=true; h.env.onNoteNew(false); frames(h)
  assert(input(h).props.value==note().text); h.rejectAsync=false; h.env.onNoteNew(false); assert(count(h,"create")==1)
end)

test("last selected note is restored after a new runtime",function()
  local h=H.harness("off",{open={notes=true},notesFile=name}); h.deliver=function() end
  h.env.onOpen(); frames(h)
  reply(h,"list",{ok=true,notes={{name=name,title="今日计划",taskCount=2,doneCount=1}},truncated=false})
  reply(h,"read",{ok=true,note=note()}); assert(input(h).props.value==note().text)
end)
test("typing during checkbox save preserves both the check and new text",function()
  local h=new(); h.env.onNoteToggle(2); local toggle=take(h,"toggle")
  local latest=note("revision-b",true).text.."continued typing\n"
  input(h).props.onChange(latest)
  deliver(h,toggle,{ok=true,note=note("revision-b",true)})
  local save=take(h,"save"); assert(save.command[6]=="revision-b" and save.command[7]==latest)
end)
test("closing during an in-flight read still saves subsequent typing",function()
  local h=new(); h.env.onIpc("notes","refresh"); local read=take(h,"read")
  input(h).props.onChange("do not lose this"); h.env.onClose()
  deliver(h,read,{ok=true,note=note()}); local save=take(h,"save")
  assert(save.command[7]=="do not lose this")
end)

test("task focus starts 25 minutes with escaped notification and visible label",function()
  local h=new(); h.env.onNoteFocus(2); local start=take(h,"start")
  assert(start.command:find("secs='1500'",1,true) and start.command:find("专注计时",1,true))
  assert(start.command:find("&lt;b&gt; &amp;",1,true) and not start.command:find("<b>",1,true))
  assert(H.find(h.tree,"timer-task").props.text==label)
  assert(not H.find(h.tree,"task-focus-2").props.enabled)
  h.env.onNoteFocus(2); assert(count(h,"start")==0)
end)
test("completed tasks cannot start focus",function()
  local h=new(); h.env.onNoteFocus(3); assert(count(h,"start")==0)
end)
test("task label survives pause and extension; manual preset detaches it",function()
  local h=new(); h.env.onNoteFocus(2); reply(h,"start","LIVE 4242 8888 mock-round")
  h.env.onTimerExtend(60); reply(h,"stop","STOPPED"); local restart=take(h,"start")
  assert(restart.command:find("专注计时",1,true)); deliver(h,restart,"LIVE 4343 9999 mock-next")
  h.env.onTimerToggle(); reply(h,"stop","STOPPED"); assert(H.find(h.tree,"timer-task").props.text==label)
  h.env.onTimerSetSec(90); assert(not H.find(h.tree,"timer-task")); h.env.onTimerToggle()
  local generic=take(h,"start").command; assert(generic:find("title='计时器'",1,true) and not generic:find("&lt;b&gt;",1,true))
end)
test("metadata restores only the matching active timer",function()
  for _,matches in ipairs({true,false}) do
    local h=H.harness("off",{open={timer=true}})
    local raw="v2 4242 8888 mock-round"
    h.files["/data/timer.pid"]=raw
    h.files["/data/timer.pid.task"]=(matches and raw or "different-round").."\nmetadata\n"
    h.encoded.metadata={label=label,note=name,line=2}; h.deliver=function() end
    h.env.onOpen(); frames(h); reply(h,"probe","LIVE 4242 8888 mock-round")
    assert((H.find(h.tree,"timer-task")~=nil)==matches)
  end
end)
test("BUSY adopts actual task instead of the attempted task",function()
  local h=new(); h.files["/data/timer.pid.task"]="v2 4242 8888 mock-round\nactual-task\n"
  h.encoded["actual-task"]={label="another task",note=name,line=20}
  h.env.onNoteFocus(2); reply(h,"start","BUSY 4242 8888 mock-round",4)
  assert(H.find(h.tree,"timer-task").props.text=="another task")
end)
test("completion never automatically marks task done",function()
  local h=new(); h.env.onNoteFocus(2); reply(h,"start","LIVE 4242 8888 mock-round")
  h.now=h.now+1501000; h.env.update(); frames(h)
  if count(h,"read")>0 then reply(h,"read",{ok=true,note=note()}) end
  assert(count(h,"toggle")==0 and H.find(h.tree,"task-check-2").props.glyph=="square")
  assert(H.find(h.tree,"task-focus-2").props.enabled)
end)
test("extension requires a valid successful stop acknowledgement",function()
  local h=new(); h.env.onNoteFocus(2); reply(h,"start","LIVE 4242 8888 mock-round")
  h.env.onTimerExtend(60); reply(h,"stop","INVALID",0); assert(count(h,"start")==0)
end)
print(passed.." notes UI/timer regressions passed (memory mocks only)")
