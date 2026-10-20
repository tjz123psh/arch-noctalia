-- The old panel ID is only a compatibility adapter; no old visual tree may be rebuilt.
local root="tide-sidebar/"
local f=io.open(root.."panel.luau","r");if f then f:close() else root="" end
local commands,closed={},0
local env=setmetatable({noctalia={state={set=function(key,value)assert(key=="command");table.insert(commands,value)end}},
    panel={close=function()closed=closed+1 end}}, {__index=_G})
assert(loadfile(root.."panel.luau","t",env))()
env.onOpen(nil)
assert(commands[#commands].action=="frontend-toggle" and closed==1)
env.onOpen("timer")
assert(commands[#commands].action=="frontend-show" and commands[#commands].page=="tools" and closed==2)
env.onOpen("notes")
assert(commands[#commands].page=="notes")
env.onIpc("page","calculator")
assert(commands[#commands].page=="tools")
env.onIpc("close")
assert(commands[#commands].action=="frontend-hide")
local count=#commands
env.onIpc("page","untrusted-unknown-page")
assert(#commands==count)
assert(env.render==nil and env.onFrameTick==nil)
print("panel_spec: 7 legacy-adapter checks passed; old UI is not rendered")
