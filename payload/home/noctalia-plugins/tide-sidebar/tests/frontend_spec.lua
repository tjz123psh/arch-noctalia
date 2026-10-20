local Frontend=dofile("tide-sidebar/lib/frontend.luau")
local checks=0
local function check(value,message) assert(value,message);checks=checks+1 end
local function copy(value) if type(value)~="table" then return value end local result={} for k,v in pairs(value) do result[k]=copy(v) end return result end
local counter,clock,storage,encoded,received,errors=0,1000,{},{},{},{}
local stream,spawned
local api={
 nowMs=function()return clock end, pluginDir=function()return "/mock/plugin" end,
 json={encode=function(value)counter=counter+1;local key="json-"..counter;encoded[key]=copy(value);return key end,
       decode=function(raw)return copy(encoded[raw]) end},
 mkdirAll=function()return true end,fileExists=function()return true end,
 writeFile=function(path,raw)storage[path]=raw;return true end,
 renameFile=function(a,b)storage[b]=storage[a];storage[a]=nil;return true end,
 runAsync=function(args,callback)callback({exitCode=0});return true end,
 runStream=function(args,callback)spawned=args;stream=callback;return true end,
}
local f=Frontend.new(api,"/private",function(value)table.insert(received,value)end,function(message)table.insert(errors,message)end)
f:publish("notes",{ready=true,model={notes={{id="note-1",body="private note"}}}})
f:control("show","tools")
check(f:start(),"native child starts")
check(type(spawned)=="string" and spawned:match("^exec ") and spawned:find("'gjs' '-m'",1,true),"API32 stream receives a safely quoted command string")
check(f.visible and f.page=="tools","start preserves an earlier show request")
local wire=encoded[storage["/private/frontend/control.json"]]
check(wire.instance==f.instance and wire.data.visible,"control is private and scoped to runtime instance")
check(storage["/private/frontend/notes.pending"]==nil,"temporary snapshot is renamed after write")
local function line(value) return api.json.encode(value) end
stream(line({protocol=1,instance="wrong",action="note-delete",id="note-1"}))
check(#received==0,"foreign instance cannot issue commands")
stream(line({protocol=1,instance=f.instance,action="note-select",id="note-1"}))
check(#received==1 and received[1].id=="note-1","small command reaches existing service")
local large={protocol=1,instance=f.instance,action="note-edit",id="note-1",body=string.rep("x",65536)}
local joined="joined-large-message"
encoded[joined]=large
for index=3,1,-1 do
 local pieces={"joined-","large-","message"}
 stream(line({protocol=1,instance=f.instance,chunk="packet1",part=index,parts=3,text=pieces[index]}))
 if index>1 then check(#received==1,"partial note is not dispatched") end
end
check(#received==2 and #received[2].body==65536,"large message reassembles without losing note text")
stream(line({protocol=1,instance=f.instance,chunk="packet2",part=1,parts=2,text="bad"}))
clock=clock+10001
stream(line({protocol=1,instance=f.instance,action="flush"}))
check(f.chunks.packet2==nil,"abandoned fragments expire")
stream(line({protocol=1,instance=f.instance,chunk="packet3",part=0,parts=2,text="bad"}))
check(f.chunks.packet3==nil,"invalid fragment is rejected")
stream(line({protocol=1,instance=f.instance,chunk="packet4",part=1,parts=129,text="bad"}))
check(f.chunks.packet4==nil,"fragment count is bounded")
f:control("hide")
check(encoded[storage["/private/frontend/control.json"]].data.visible==false,"hide does not touch persisted timer state")
f:shutdown()
local before=#received
stream(line({protocol=1,instance=f.instance,action="note-delete",id="note-1"}))
check(#received==before,"unloaded runtime cannot accept late commands")
print("frontend_spec: "..checks.." checks passed")
