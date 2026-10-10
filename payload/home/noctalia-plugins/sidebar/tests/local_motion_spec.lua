-- Pure memory tests: no native UI, commands, clipboard, or user note files are touched.
local env=setmetatable({arg={"sidebar/panel.luau","--harness"}},{__index=_G})
local H=assert(loadfile("sidebar/tests/sidebar_spec.lua","t",env))()
local noteEnv=setmetatable({arg={"--harness"}},{__index=_G})
local N=assert(loadfile("sidebar/tests/notes_spec.lua","t",noteEnv))()
local total,checks,serial=0,0,0
local function ok(v,msg)checks=checks+1;assert(v,msg or "assertion failed")end
local function eq(a,b,msg)ok(a==b,(msg or "mismatch")..": "..tostring(a).." ~= "..tostring(b))end
local function find(h,key)return H.find(h.tree,key)end
local function editorCount(h)local n=0;H.visit(h.tree,function(v)if v.props.key and v.props.key:match("^notes%-editor%-")then n=n+1 end end);return n end
local function alpha(h,key)local node=find(h,key);assert(node,"missing node "..key);return node.props.opacity or 1 end
local function frame(h,ms)h:step(ms or 16);ok(editorCount(h)<=1,"two editors in one frame");eq(h.tree.props.opacity,nil,"root opacity changed")end
local function frames(h,n,ms)for _=1,n do frame(h,ms)end end
local function deliver(h,request,value,code)
  serial=serial+1;local token="local-motion-reply-"..serial;h.encoded[token]=value
  request.callback({exitCode=code or 0,stdout=token});frame(h,16)
end
local function toList(h)
  find(h,"notes-back").props.onClick()
  N.reply(h,"list",{ok=true,notes={{name=N.name,title="今日计划"},{name="另一份.md",title="另一份"}},truncated=false})
end
local function test(name,fn)fn();total=total+1;print("PASS "..name)end

for _,mode in ipairs({"light","soft","off"})do
  test(mode..": return switches input immediately and fades only the current page",function()
    local h=N.new(mode);local old=N.input(h);find(h,"notes-back").props.onClick()
    eq(editorCount(h),0);old.props.onChange("OLD INPUT MUST BE IGNORED");eq(N.count(h,"save"),0)
    if mode=="off"then eq(alpha(h,"notes-page"),1)else ok(alpha(h,"notes-page")<1)end
    frames(h,18);eq(alpha(h,"notes-page"),1);eq(editorCount(h),0)
    for _,key in ipairs({"search","wins","timer","sysmon","recent"})do local node=find(h,"card-"..key);if node then eq(node.props.opacity,nil,"unrelated card alpha changed")end end
  end)
end

test("editor transition waits for data and never re-focuses or remounts during paint",function()
  local h=N.new("light");toList(h);h.env.onIpc("notes","select:另一份.md")
  eq(editorCount(h),0);eq(alpha(h,"notes-page"),1,"loading placeholder should not fade")
  local req=N.take(h,"read");deliver(h,req,{ok=true,note=N.document("新页面正文\n","b","另一份.md")})
  local editor=N.input(h);local key=editor.props.key
  -- 原版异步加载不保证自动聚焦；本测试只要求动效不新增或重放焦点请求。
  ok(editor.props.focus==nil or editor.props.focus==true,"invalid focus request")
  ok(alpha(h,"notes-page")<1,"new page did not animate")
  frame(h,16);eq(N.input(h).props.key,key);eq(N.input(h).props.focus,nil,"paint replayed focus")
  local previousAlpha=alpha(h,"notes-page");N.input(h).props.onChange("输入不能被动效挡住\n");frame(h,16)
  eq(N.input(h).props.key,key);eq(N.input(h).props.value,"输入不能被动效挡住\n");eq(N.input(h).props.focus,nil)
  ok(alpha(h,"notes-page")>=previousAlpha,"typing restarted page animation")
  frames(h,12);eq(alpha(h,"notes-page"),1)
end)

test("pending save completes before return animation and latest input is preserved",function()
  local h=N.new("light");local key=N.input(h).props.key
  N.input(h).props.onChange("第一笔\n");find(h,"notes-back").props.onClick();local first=N.take(h,"save")
  eq(editorCount(h),1);eq(alpha(h,"notes-page"),1,"navigation animated before saving")
  N.input(h).props.onChange("第一笔\n第二笔\n")
  deliver(h,first,{ok=true,note=N.document("第一笔\n","saved-a")})
  eq(editorCount(h),1);eq(N.input(h).props.key,key);eq(N.input(h).props.value,"第一笔\n第二笔\n")
  eq(N.count(h,"save"),0,"queued draft keeps the existing debounce")
  frame(h,500) -- 2.3.2 intentionally coalesces edits made during an in-flight save.
  local second=N.take(h,"save");eq(second.command[#second.command],"第一笔\n第二笔\n")
  deliver(h,second,{ok=true,note=N.document("第一笔\n第二笔\n","saved-b")})
  eq(editorCount(h),0);ok(alpha(h,"notes-page")<1);frames(h,12);eq(alpha(h,"notes-page"),1)
end)

test("conflict during local feedback keeps draft and does not navigate",function()
  local h=N.new("light");N.input(h).props.onChange("必须保留的草稿\n");local key=N.input(h).props.key
  h.env.onIpc("pin","notes");find(h,"notes-back").props.onClick();local req=N.take(h,"save")
  deliver(h,req,{ok=false,error="conflict",message="外部版本已更新"},1)
  eq(editorCount(h),1);eq(N.input(h).props.key,key);eq(N.input(h).props.value,"必须保留的草稿\n")
  ok(find(h,"notes-save-copy"),"conflict controls starved behind decoration")
  eq(alpha(h,"notes-page"),1);frames(h,16);eq(N.input(h).props.key,key)
end)

test("UI and IPC organization feedback share behavior without touching editor identity",function()
  for _,viaUi in ipairs({true,false})do
    local h=N.new("light");local key=N.input(h).props.key;local value=N.input(h).props.value
    if viaUi then find(h,"customize").props.onClick()else h.env.onIpc("customize","")end
    ok(alpha(h,"customize")<1);eq(N.input(h).props.key,key)
    if viaUi then
      local pin;H.visit(find(h,"header-notes"),function(n)if n.type=="button" and n.props.glyph=="pin"then pin=n end end);assert(pin);pin.props.onClick()
    else h.env.onIpc("pin","notes")end
    ok(alpha(h,"header-icon-notes")<1);eq(N.input(h).props.key,key);eq(N.input(h).props.value,value)
    frames(h,26);eq(alpha(h,"header-icon-notes"),1);eq(alpha(h,"customize"),1);ok(h:layout().pinned.notes)
  end
end)

test("repeated pin feedback continues from current opacity and valid drop preserves rules",function()
  local h=N.new("light");h.env.onIpc("pin","notes");frames(h,3);local prior=alpha(h,"header-icon-notes")
  h.env.onIpc("pin","notes");eq(alpha(h,"header-icon-notes"),prior,"feedback flashed backwards")
  h.env.onCardDrop("notes","before|search");ok(alpha(h,"header-icon-notes")<=1)
  local renders=h.renders;h.env.onCardDrop("invalid","end");eq(h.renders,renders)
  frames(h,26);eq(h:layout().order[1],"notes");eq(h:layout().pinned.notes,false)
end)

test("pure local animation uses cached nodes, no IO and 16ms paint throttling",function()
  local h=N.new("light");find(h,"notes-back").props.onClick();local built,renders=h.built,h.renders;local fs=H.copy(h.fs)
  frames(h,50,4);eq(h.built,built,"pure paint rebuilt controls");ok(h.renders-renders<=14,"paint exceeded frame throttle")
  for name,value in pairs(h.fs)do eq(value,fs[name],"pure animation performed "..name)end
  eq(alpha(h,"notes-page"),1);frame(h,400);eq(h.frame,false,"finished decoration kept frame ticks awake")
end)

test("close settles decorative props and stale drop cannot mutate hidden layout",function()
  local h=N.new("soft");h.env.onIpc("pin","notes");frames(h,2);h.env.onClose();eq(h.frame,false)
  local renders=h.renders;h.env.onCardDrop("notes","end");eq(h.renders,renders)
  h.env.onOpen();N.frames(h);eq(alpha(h,"header-icon-notes"),1);eq(alpha(h,"notes-page"),1)
end)
print(string.format("PASS: sidebar local motion %d scenarios, %d assertions (memory mocks only)",total,checks))
