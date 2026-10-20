--!nonstrict
-- One GTK child and private, atomic view snapshots. Data ownership stays in service.luau.
local M = {}
local names={notes=true,timer=true,stopwatch=true,system=true,calc=true,preferences=true,feedback=true,control=true,geometry=true,config=true}
function M.new(api,base,onCommand,onError)
  local self={api=api,dir=base and (base.."/frontend") or nil,started=false,ready=false,dead=false,
    instance=tostring(math.floor(api.nowMs())).."-"..tostring(math.random(100000,999999)),
    latest={},pending={},encoded={},chunks={},serial=0,visible=false,page="notes",reducedMotion=false,
    lastSeen=0,startedAt=0,failed=false,capable=base~=nil and type(api.runStream)=="function" and type(api.renameFile)=="function"}
  local function errorMessage(message)
    if onError then onError(message) end
  end
  function self:publish(name,value)
    if not names[name] then return false end
    self.latest[name]=value
    if not self.capable then return false end
    local ok,raw=pcall(api.json.encode,value)
    if not ok or type(raw)~="string" then return false end
    if self.encoded[name]==raw then return false end
    self.encoded[name]=raw
    self.pending[name]=value
    return true
  end
  function self:flush()
    if not self.ready or self.dead then return end
    for name,value in pairs(self.pending) do
      local ok,raw=pcall(api.json.encode,{instance=self.instance,data=value})
      if ok and type(raw)=="string" then
        local temporary=self.dir.."/"..name..".pending"
        local target=self.dir.."/"..name..".json"
        if api.writeFile(temporary,raw) and api.renameFile(temporary,target) then self.pending[name]=nil end
      end
    end
  end
  function self:control(action,page,reduced)
    if page then self.page=page end
    if type(reduced)=="boolean" then self.reducedMotion=reduced end
    if action=="toggle" then self.visible=not self.visible elseif action=="show" then self.visible=true elseif action=="hide" then self.visible=false end
    self.serial=self.serial+1
    self:publish("control",{serial=self.serial,visible=self.visible,page=self.page,reducedMotion=self.reducedMotion,quit=action=="quit"})
    self:flush()
  end
  function self:receive(line)
    if self.dead or type(line)~="string" or #line>65536 then return end
    local ok,packet=pcall(api.json.decode,line)
    if not ok or type(packet)~="table" or packet.protocol~=1 or packet.instance~=self.instance then return end
    local now=api.nowMs()
    for id,chunk in pairs(self.chunks) do if now-chunk.at>10000 then self.chunks[id]=nil end end
    if packet.chunk then
      local id,part,parts,text=packet.chunk,packet.part,packet.parts,packet.text
      if type(id)~="string" or #id>64 or not id:match("^[%w_-]+$") or type(part)~="number" or type(parts)~="number"
        or part%1~=0 or parts%1~=0 or parts<1 or parts>128 or part<1 or part>parts or type(text)~="string" or #text>40000 then return end
      local chunk=self.chunks[id]
      if not chunk then
        local count=0;for _ in pairs(self.chunks) do count=count+1 end
        if count>=4 then errorMessage("界面请求过多，尚未保存，请重试");return end
        chunk={parts=parts,items={},count=0,bytes=0,at=now};self.chunks[id]=chunk
      end
      if chunk.parts~=parts then self.chunks[id]=nil;return end
      if not chunk.items[part] then chunk.items[part]=text;chunk.count=chunk.count+1;chunk.bytes=chunk.bytes+#text end
      if chunk.bytes>1048576 then self.chunks[id]=nil;errorMessage("界面请求过大，尚未保存");return end
      if chunk.count<parts then return end
      self.chunks[id]=nil
      local joined=table.concat(chunk.items)
      ok,packet=pcall(api.json.decode,joined)
      if not ok or type(packet)~="table" or packet.protocol~=1 or packet.instance~=self.instance then return end
    end
    if type(packet.action)=="string" and #packet.action<80 then
      onCommand(packet)
      self:flush()
    end
  end
  function self:start()
    if self.started or self.dead or not self.capable then return false end
    local assets={"main.js","ui.js","style.css","views/notes.js","views/tools.js","views/system.js"}
    for _,name in ipairs(assets) do
      if type(api.fileExists)=="function" and not api.fileExists(api.pluginDir().."/native/"..name) then self.failed=true;return false end
    end
    if not api.mkdirAll(self.dir) then errorMessage("无法创建界面私有通信目录");return false end
    self.started=true;self.startedAt=api.nowMs();self.failed=false
    local accepted=api.runAsync({"chmod","700","--",self.dir},function(result)
      if self.dead then return end
      if result.exitCode~=0 then self.started=false;errorMessage("无法保护界面通信目录");return end
      self.ready=true
      self:control(nil,self.page,self.reducedMotion)
      for name,value in pairs(self.latest) do self.pending[name]=value end
      self:flush()
      -- API32 runStream accepts a shell string, unlike runAsync's argv overload.
      -- Every argument is a quoted, owned path/constant; no note/password text enters it.
      local arguments={"env","LD_PRELOAD=/usr/lib/libgtk4-layer-shell.so","GDK_BACKEND=wayland","gjs","-m",api.pluginDir().."/native/main.js","--bridge-dir",self.dir,"--instance",self.instance}
      local quoted={"exec"}
      for _,argument in ipairs(arguments) do table.insert(quoted,"'"..tostring(argument):gsub("'","'\\''").."'") end
      local callOK,launched=pcall(api.runStream,table.concat(quoted," "),function(line) self:receive(line) end)
      if not callOK or not launched then self.started=false;self.failed=true;errorMessage("原生侧栏无法启动，请检查 GJS / GTK4");end
    end,5000)
    if not accepted then self.started=false;errorMessage("无法初始化界面通信目录") end
    return accepted
  end
  function self:ensure()
    local t=api.nowMs()
    if self.started and ((self.lastSeen==0 and t-self.startedAt>15000) or (self.lastSeen>0 and t-self.lastSeen>24000)) then self.started=false;self.failed=true end
    if self.failed then self.visible=false;self.failed=false end
    if self.started then return true end
    return self:start()
  end
  function self:restart()
    self.relaunchVisible=self.visible
    self:control("quit")
    self.relaunchAt=api.nowMs()+600
  end
  function self:pulse()
    if self.relaunchAt and api.nowMs()>=self.relaunchAt then
      self.relaunchAt=nil;self.started=false;self.ready=false;self.lastSeen=0
      self.instance=tostring(math.floor(api.nowMs())).."-"..tostring(math.random(100000,999999))
      self.visible=self.relaunchVisible==true
      self:start()
    end
  end
  function self:shutdown()
    if self.dead then return end
    self:control("quit")
    self.dead=true
  end
  return self
end
return M
