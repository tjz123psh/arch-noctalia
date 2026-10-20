--!nonstrict
-- Legacy panel ID adapter. All visible UI now lives in the persistent native frontend.
local aliases={home="notes",notes="notes",calculator="tools",timer="tools",tools="tools",hotspot="hotspot",windows="windows"}
function onOpen(context)
  local page=type(context)=="string" and aliases[context] or nil
  noctalia.state.set("command",{action=page and "frontend-show" or "frontend-toggle",page=page})
  panel.close()
end
function onIpc(event,payload)
  if event=="page" and aliases[payload] then
    noctalia.state.set("command",{action="frontend-show",page=aliases[payload]})
  elseif event=="close" then noctalia.state.set("command",{action="frontend-hide"}) end
end
