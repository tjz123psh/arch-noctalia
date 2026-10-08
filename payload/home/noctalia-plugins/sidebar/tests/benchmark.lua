-- Offline description-tree workload, NOT compositor FPS or native layout time.
local source = arg[1] or "sidebar/panel.luau"
local env = setmetatable({ arg = { source, "--harness" } }, { __index = _G })
local H = assert(loadfile("sidebar/tests/sidebar_spec.lua", "t", env))()
for _, motion in ipairs({ "light", "soft", "off" }) do
  local h = H.harness(motion)
  local cpu = os.clock() h.env.onOpen()
  local first = h.built h:settle()
  local openRenders, openNodes = h.renders, h.nodes
  h.env.onIpc("toggle", "wins") h:settle()
  h.env.onIpc("toggle", "wins") h:settle()
  local r, n, b = h.renders, h.nodes, h.built
  h.env.onIpc("toggle", "wins") h:settle()
  local foldR, foldN, foldB = h.renders-r, h.nodes-n, h.built-b
  h.env.onClose() b = h.built h.env.onOpen()
  print(string.format("%s first_built=%d reopen_built=%d boot_renders=%d boot_nodes=%d warm_fold_renders=%d warm_fold_nodes=%d warm_fold_built=%d offline_cpu_ms=%.2f", motion, first, h.built-b, openRenders, openNodes, foldR, foldN, foldB, 1000*(os.clock()-cpu)))
end
