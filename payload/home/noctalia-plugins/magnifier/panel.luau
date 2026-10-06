--!nonstrict
-- pang/magnifier — 屏幕放大镜（Noctalia v5 插件） v0.5
-- 方案与边界：/home/pang/noctalia-work/experiments/2026-10-04-magnifier-plugin-spec.md
--
-- 形态（用户定稿）：按快捷键 → 面板开在鼠标处 → 鼠标移动，画面实时跟着移动。
-- 光标来源：本地小工具 cursor-track（~/bin，源码 ~/dev/cursor-track）——它铺一层全屏透明
--   layer surface 直接收 wl_pointer 事件，把位置写进 $XDG_RUNTIME_DIR/pang-magnifier/cursor.pos。
--   （niri 没有任何光标查询接口；XWayland 的 xdotool 查询在指针位于 Wayland 原生表面时是死值。）
--   代价：cursor-track 在 overlay 层、输入区全屏 → 放大镜打开期间桌面点击被它接走（点击=退出）。
-- 放大倍率 = 显示框(640×414) / 视口；视口一变就重抓（ui.image 无裁剪/偏移）。
-- 视口矩形避让面板矩形（防"镜中镜"）→ 面板覆盖区（右上 660×500）放大不到。
--
-- 操作：Alt+A 开/关 · 鼠标移动=移动画面 · `+`/`-`/`0` 缩放(100–800%)
--       `p` 回到鼠标 · `r` 重拍 · `l`/空格 跟随⇄定格 · 方向键（定格下平移）· 点击/`Esc` 退出
-- IPC：noctalia msg plugin pang/magnifier:panel all <follow on|off|recenter|retake|zoom 4|center x,y|status|close>

local render -- forward declaration

-- ============ 几何与常量 ============
-- 注意：窗口尺寸在 plugin.toml（660x500），这里是"树"的尺寸——noctalia 会再往里加
-- 自己的内边距（实测约 14/26），树跟窗口一样大会被裁掉右下角。
-- 取 (窗口 - 内边距 - 10) ≈ 640x470：内容贴住内沿、不裁切，也不留大黑边。
local PANEL_W, PANEL_H = 640, 470
local PAD = 10
local HEAD_H, FOOT_H, GAP = 28, 42, 6
local IMG_W = PANEL_W - PAD * 2                              -- 620
local IMG_H = PANEL_H - PAD * 2 - HEAD_H - FOOT_H - GAP * 2  -- 368
local ZOOM_MIN, ZOOM_MAX, ZOOM_STEP = 1.0, 8.0, 1.25
local TICK_MS = 16         -- 每个显示帧读取最新光标位置
local IDLE_MS = 33         -- 跟随模式下持续刷新动态内容；抓帧串行，不积压任务
local PANEL_TOP = 44
local MARGIN = 24

-- ============ 状态 ============
local alive, gen = false, 0
local follow = true
local zoom = 2.0
local seq = 0
local curPath = nil
local dir = nil
local ox, oy, ow, oh = 0, 0, 1920, 1080
local px0, py0, px1, py1 = 0, 0, 0, 0
local vx, vy, vw, vh = 0, 0, 0, 0
local lastNote = ""
local lastKey = ""
local keyCount = 0
local clicks = 0
local lastCursor = "-"
local cursorSrc = "无"
local lastStart = 0
local lastQuery = 0
local inflight = false
local pendingShot = false
local inflightSince = 0
local capfail = 0
local lastRecordMs = 0
local ticks = 0
local lastPoll = 0
local trackerPath = nil
local trackerSeq = 0
local trackerStart = 0
local heartbeatPath = nil
local lastHeartbeat = 0
local lastStateWrite = 0
local lastViewSave = 0

-- ============ 小工具 ============
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function rnd(v) return math.floor(v + 0.5) end

local function pick_output()
  local outs = noctalia.outputs() or {}
  for _, o in ipairs(outs) do
    if o.focused then return o end
  end
  return outs[1]
end

local function size_for(z)
  vw = clamp(rnd(IMG_W / z), 32, ow)
  vh = clamp(rnd(IMG_H / z), 32, oh)
end

-- 夹到屏幕内；与面板矩形相交时沿代价更小的轴推出去（防"镜中镜"）
local function place(cx, cy)
  local hw, hh = vw / 2, vh / 2
  local minx, maxx = ox + hw, ox + ow - hw
  local miny, maxy = oy + hh, oy + oh - hh
  cx = clamp(cx, minx, maxx)
  cy = clamp(cy, miny, maxy)
  if cx + hw > px0 and cx - hw < px1 and cy + hh > py0 and cy - hh < py1 then
    local cand = {
      { (px0 - hw) - cx, 0 },
      { (px1 + hw) - cx, 0 },
      { 0, (py0 - hh) - cy },
      { 0, (py1 + hh) - cy },
    }
    local best, bestd = nil, nil
    for _, c in ipairs(cand) do
      local nx, ny = cx + c[1], cy + c[2]
      if nx >= minx - 0.5 and nx <= maxx + 0.5 and ny >= miny - 0.5 and ny <= maxy + 0.5 then
        local d = math.abs(c[1]) + math.abs(c[2])
        if not bestd or d < bestd then best, bestd = c, d end
      end
    end
    if best then cx, cy = cx + best[1], cy + best[2] end
  end
  vx = rnd(cx - hw)
  vy = rnd(cy - hh)
  return cx, cy
end

local function center() return vx + vw / 2, vy + vh / 2 end

local function status_text()
  local cx, cy = center()
  return string.format("%s · %d%% · 视口 %d×%d",
    follow and "跟随鼠标" or "已定格", rnd(zoom * 100), vw, vh)
end

-- 键位提示（两行；每一项都与 onKey 里的分支逐条对应，改键位时一起改）
local function hint_text()
  if follow then
    return "移动鼠标 = 移动画面　·　= / - 缩放　·　0 = 100%",
           "p = 拉回鼠标　·　r = 重拍　·　l = 定格　·　点击 / Esc = 退出"
  end
  return "已定格　·　方向键 = 平移　·　p = 回到鼠标",
         "l = 恢复跟随　·　r = 重拍　·　点击 / Esc = 退出"
end

local function write_state()
  if not dir then return end
  local now = noctalia.nowMs()
  if now - lastStateWrite < 1000 then return end
  lastStateWrite = now
  local cx, cy = center()
  noctalia.writeFile(dir .. "/state.txt", string.format(
    "mode=%s\nzoom=%.2f\nview=%d,%d %dx%d\ncenter=%d,%d\npanel=%d,%d %dx%d\nout=%d,%d %dx%d\nseq=%d\nnote=%s\ncursor=%s\nsrc=%s\nclicks=%d\npath=%s\n",
    follow and "follow" or "freeze", zoom, vx, vy, vw, vh, rnd(cx), rnd(cy),
    px0, py0, px1 - px0, py1 - py0, ox, oy, ow, oh, seq, lastNote,
    lastCursor, cursorSrc, clicks, curPath or ""))
  noctalia.writeFile(dir .. "/diag.txt", string.format(
    "inflight=%s ms=%d ticks=%d capfail=%d lastrec=%d\n",
    tostring(inflight), inflight and (rnd(noctalia.nowMs()) - inflightSince) or 0, ticks, capfail,
    lastRecordMs > 0 and (rnd(noctalia.nowMs()) - lastRecordMs) or -1))
  noctalia.writeFile(dir .. "/keys.txt", string.format("lastkey=%s\nkeycount=%d\nclicks=%d\n", lastKey, keyCount, clicks))
end

local function note(msg) lastNote = msg end

-- 全量守卫：回调里任何错误都记进 errors.txt，并且不让它打断运行时
local function guard(what, fn)
  local ok, err = pcall(fn)
  if not ok then
    local base = dir or "/tmp"
    local lg = noctalia.readFile(base .. "/errors.txt") or ""
    if #lg > 8192 then lg = "" end
    noctalia.writeFile(base .. "/errors.txt",
      lg .. string.format("%d %s: %s\n", rnd(noctalia.nowMs()), what, tostring(err)))
    lastNote = "内部错误（见 errors.txt）"
  end
  return ok
end

local function save_view()
  local cx, cy = center()
  local enc = noctalia.json.encode({ zoom = zoom, cx = rnd(cx), cy = rnd(cy) })
  if enc then noctalia.writeFile((noctalia.pluginDataDir() or "/tmp") .. "/view.json", enc) end
end

local function load_view()
  local raw = noctalia.readFile((noctalia.pluginDataDir() or "/tmp") .. "/view.json")
  if not raw or raw == "" then return nil end
  local dec = noctalia.json.decode(raw)
  if type(dec) ~= "table" then return nil end
  local z, cx, cy = tonumber(dec.zoom), tonumber(dec.cx), tonumber(dec.cy)
  if not z or not cx or not cy then return nil end
  return z, cx, cy
end

-- ============ 光标：cursor-track 优先，X 查询兜底 ============
local function start_tracker()
  trackerPath = dir .. "/cursor.pos"
  heartbeatPath = dir .. "/heartbeat.txt"
  trackerSeq = 0
  trackerStart = noctalia.nowMs()
  lastHeartbeat = 0
  noctalia.writeFile(heartbeatPath, tostring(rnd(noctalia.nowMs())))
  -- 同步清空（不能用 runAsync("rm")：它和下面的 spawn 是竞争关系，
  -- 曾经 rm 后到、把追踪器的第一条记录删掉，追踪器随即因"文件消失"自我保护退出）
  noctalia.writeFile(trackerPath, "")
  -- 杀旧 + 清文件 + 起新，放在同一条命令里按顺序执行（避免自愈重启时越积越多）
  local bin = noctalia.expandPath("~/bin/cursor-track")
  noctalia.runAsync("pkill -x cursor-track; rm -f '" .. trackerPath .. "'; ("
    .. bin .. " '" .. trackerPath .. "' '" .. heartbeatPath .. "' || cursor-track '" .. trackerPath .. "' '" .. heartbeatPath .. "') &")
end

local function stop_tracker()
  if heartbeatPath then
    -- 同步删心跳：追踪器对"心跳消失"是立即退出的（onClose 里的 runAsync spawn 会被丢弃，
    -- 只有同步的 writeFile/removeFile 可靠），这样点击被接走的窗口从 ~3s 缩到 ~1s
    noctalia.removeFile(heartbeatPath)
  end
  if trackerPath then
    noctalia.runAsync("rm -f '" .. trackerPath .. "' ; pkill -x cursor-track")
  end
end

-- 读追踪器文件：有新事件则返回 type,x,y
local function tracker_poll()
  if not trackerPath then return nil end
  local raw = noctalia.readFile(trackerPath)
  if not raw or raw == "" then return nil end
  local sn = tonumber(raw:match("seq=(%d+)"))
  if not sn or sn == trackerSeq then return nil end   -- 用 != ：追踪器重启后序号会回到 1
  trackerSeq = sn
  lastRecordMs = rnd(noctalia.nowMs())
  local typ = raw:match("type=([%a%-]+)") or "move"
  local x = tonumber(raw:match("x=(%-?%d+)"))
  local y = tonumber(raw:match("y=(%-?%d+)"))
  if not x or not y then return nil end
  lastCursor = string.format("%d,%d", rnd(x), rnd(y))
  cursorSrc = "tracker"
  return typ, x, y
end

-- 只看最后位置（不要求 seq 变化；p 键用）
local function tracker_peek()
  if not trackerPath then return nil end
  local raw = noctalia.readFile(trackerPath)
  if not raw then return nil end
  local x = tonumber(raw:match("x=(%-?%d+)"))
  local y = tonumber(raw:match("y=(%-?%d+)"))
  if x and y then return x, y end
  return nil
end

local function over_panel(x, y)
  return x >= px0 and x <= px1 and y >= py0 and y <= py1
end

-- ============ 抓帧 ============
local function capture()
  if not alive or vw <= 0 or vh <= 0 then return end
  -- 看门狗：任何回调丢失都别让管道卡死（用户反馈"乱按后画面冻住"的兜底）
  if inflight and noctalia.nowMs() - inflightSince > 2000 then
    inflight = false
    capfail = capfail + 1
    note("抓帧超时重试")
  end
  if inflight then pendingShot = true return end
  inflight = true
  inflightSince = noctalia.nowMs()
  lastStart = noctalia.nowMs()
  seq = seq + 1
  local path = string.format("%s/frame-%d.png", dir, seq)
  local g, mine = gen, seq
  -- argv 直启 + 无损 PNG 不压缩，减少每帧编码耗时
  local geo = string.format("%d,%d %dx%d", vx, vy, vw, vh)
  local ok = noctalia.runAsync({ "grim", "-c", "-l", "0", "-g", geo, path }, function(res)
    guard("capture", function()
    if alive then panel.setNeedsFrameTick(true) end   -- 重申订阅（重启运行时后订阅会丢）
    if not alive or g ~= gen or mine ~= seq then return end
    inflight = false
    if res.exitCode == 0 then
      curPath = path
      note(follow and "跟随" or "定格")
      -- 仅回收本轮已过时的截图，保留最近三帧给图片加载；不再启动清理进程。
      -- 旧方案每八帧只清两张，持续刷新时会不断占用内存盘。
      if mine > 3 then
        noctalia.removeFile(string.format("%s/frame-%d.png", dir, mine - 3))
      end
    else
      note("抓帧失败")
    end
    local now = noctalia.nowMs()
    if now - lastViewSave >= 1000 then
      lastViewSave = now
      save_view()
    end
    render()
    if pendingShot and alive then
      pendingShot = false
      capture()
    end
    end)
  end, 3000)
  if ok == false then
    inflight = false
    capfail = capfail + 1
    note("抓帧启动失败")
    render()
  end
end

local function set_center(cx, cy, shot)
  place(cx, cy)
  if shot then capture() else render() end
end

local function set_zoom(z)
  zoom = clamp(z, ZOOM_MIN, ZOOM_MAX)
  local cx, cy = center()
  size_for(zoom)
  place(cx, cy)
  capture()
end

local function bump_zoom(factor) set_zoom(zoom * factor) end

local function freeze(reason)
  if follow then
    follow = false
    note(reason or "定格")
  end
end

local function recenter()
  local x, y = tracker_peek()
  if x and y then
    place(x, y)
    note("回到鼠标")
    capture()
    return
  end
  note("无光标数据（cursor-track 未运行？）")
  capture()
end

-- ============ 渲染 ============
render = function()
  local hint1, hint2 = hint_text()
  local body = curPath
    and ui.image({ path = curPath, width = IMG_W, height = IMG_H, fit = "stretch", radius = 8, border = "outline", borderWidth = 1 })
    or ui.box({ width = IMG_W, height = IMG_H, radius = 8, fill = "surface_variant" })
  panel.render(ui.column({ width = PANEL_W, height = PANEL_H, padding = PAD, gap = GAP }, {
    ui.row({ height = HEAD_H, justify = "space_between", align = "center" }, {
      ui.label({ text = status_text(), fontSize = 13, color = "on_surface", maxLines = 1 }),
      ui.label({ text = "Alt+A 关闭", fontSize = 10, color = "on_surface_variant", maxLines = 1 }),
    }),
    body,
    ui.column({ height = FOOT_H, gap = 2, justify = "center" }, {
      ui.label({ text = hint1, fontSize = 10, color = "on_surface_variant", maxLines = 1 }),
      ui.label({ text = hint2, fontSize = 10, color = "on_surface_variant", maxLines = 1 }),
    }),
  }))
  write_state()
end
do
  local rawRender = render
  render = function() guard("render", function() rawRender() end) end
end

-- ============ 生命周期 ============
function onOpen(context)
  alive = true
  gen = gen + 1
  follow = true
  seq = 0
  inflight = false
  pendingShot = false
  lastPoll = 0
  lastStateWrite = 0
  lastViewSave = 0
  curPath = nil
  lastNote = ""
  clicks = 0
  dir = (noctalia.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/pang-magnifier"
  noctalia.mkdirAll(dir)
  noctalia.runAsync("rm -f " .. dir .. "/frame-*.png")
  local o = pick_output()
  if o then
    ox, oy, ow, oh = o.x or 0, o.y or 0, o.width or 1920, o.height or 1080
  end
  px0 = ox + ow - PANEL_W - MARGIN
  py0 = oy + PANEL_TOP - MARGIN
  px1 = ox + ow + MARGIN
  py1 = oy + PANEL_TOP + PANEL_H + MARGIN
  local pz, pcx, pcy = load_view()
  zoom = pz and clamp(pz, ZOOM_MIN, ZOOM_MAX) or 2.0
  size_for(zoom)
  place(pcx or (ox + ow / 2), pcy or (oy + oh / 2))
  panel.setNeedsFrameTick(true)
  render()
  capture()
  start_tracker()          -- 追踪器一起来就会发 enter，下一拍视野就到位
end

function onClose()
  alive = false
  panel.setNeedsFrameTick(false)
  save_view()
  noctalia.runAsync("rm -f " .. dir .. "/frame-*.png")
  stop_tracker()   -- 尽力而为：这里发出的 spawn 可能被丢弃，兜底靠心跳超时
end

-- 心跳：面板开着就一直发；停发会让追踪器（拿不到心跳）自我保护退出
local function beat()
  local now = noctalia.nowMs()
  if heartbeatPath and now - lastHeartbeat >= 1000 then
    lastHeartbeat = now
    -- 心跳里带上 tick 计数：随时能判断帧回调是否还活着
    noctalia.writeFile(heartbeatPath, string.format("%d ticks=%d", rnd(now), ticks))
  end
end

function onFrameTick(deltaMs)
  if not alive then return end
  ticks = ticks + 1
  beat()
  local now = noctalia.nowMs()
  if now - lastPoll < TICK_MS then return end -- 只读取最新位置，不排队处理历史移动
  lastPoll = now
  -- 追踪器失联（>5s 没任何记录，含 2s 一次的 alive）→ 自动重启，免得"画面冻住"要手动重开面板
  if now - trackerStart > 8000 and (lastRecordMs == 0 or now - lastRecordMs > 8000) then
    note("追踪器失联，已重启")
    start_tracker()
    render()
    return
  end
  local typ, x, y = tracker_poll()
  if typ then
    if typ == "click" then panel.close() return end
    if follow and not over_panel(x, y) then
      local cx, cy = center()
      if math.abs(x - cx) > 2 or math.abs(y - cy) > 2 then
        place(x, y)
        capture()
        return
      end
    end
    if follow and now - lastStart >= IDLE_MS then capture() end
    return
  end
  if follow and now - lastStart >= IDLE_MS then capture() end
end

-- ============ 按键（键盘是主控；光标被追踪器接走，不设可点按钮） ============
function onKey(chord, pressed)
  lastKey = tostring(chord) .. "|" .. tostring(pressed)
  keyCount = keyCount + 1
  if dir then
    local lg = noctalia.readFile(dir .. "/keylog.txt") or ""
    if #lg > 4096 then lg = "" end
    noctalia.writeFile(dir .. "/keylog.txt", lg .. tostring(chord) .. "|" .. tostring(pressed) .. "|" .. type(pressed) .. "\n")
  end
  write_state()
  if pressed == false or pressed == "false" then return end
  local c = (chord or ""):lower()
  c = c:match("([^+]+)$") or c
  if c == "escape" then panel.close()
  elseif c == "equal" or c == "plus" or c == "kp_add" then bump_zoom(ZOOM_STEP)
  elseif c == "minus" or c == "kp_subtract" then bump_zoom(1 / ZOOM_STEP)
  elseif c == "0" then set_zoom(ZOOM_MIN)
  elseif c == "r" then capture()
  elseif c == "p" then recenter()
  elseif c == "l" or c == "space" then
    follow = not follow
    if follow then recenter() else note("定格"); capture() end
  elseif c == "up" then freeze("手动平移"); local cx, cy = center(); set_center(cx, cy - vh * 0.25, true)
  elseif c == "down" then freeze("手动平移"); local cx, cy = center(); set_center(cx, cy + vh * 0.25, true)
  elseif c == "left" then freeze("手动平移"); local cx, cy = center(); set_center(cx - vw * 0.25, cy, true)
  elseif c == "right" then freeze("手动平移"); local cx, cy = center(); set_center(cx + vw * 0.25, cy, true)
  end
end

-- ============ IPC ============
function onIpc(event, payload)
  if event == "follow" or event == "live" then
    if payload == "on" then follow = true elseif payload == "off" then follow = false else follow = not follow end
    if follow then recenter() else note("定格"); capture() end
  elseif event == "recenter" or event == "pick" then recenter()
  elseif event == "zoom-in" then bump_zoom(ZOOM_STEP)
  elseif event == "zoom-out" then bump_zoom(1 / ZOOM_STEP)
  elseif event == "zoom-reset" then set_zoom(ZOOM_MIN)
  elseif event == "zoom" then
    local z = tonumber(payload)
    if z then set_zoom(z) end
  elseif event == "retake" or event == "capture" then capture()
  elseif event == "center" then
    if not payload or payload == "" or payload == "reset" then
      freeze("手动平移")
      set_center(ox + ow / 2, oy + oh / 2, true)
    else
      local a, b = tostring(payload):match("^(%-?%d+),%s*(%-?%d+)$")
      if a and b then
        freeze("手动平移")
        set_center(ox + tonumber(a), oy + tonumber(b), true)
      end
    end
  elseif event == "status" then
    noctalia.notify("放大镜", status_text() .. " · 光标源 " .. cursorSrc)
  elseif event == "close" then
    panel.close()
  end
end


-- ============ 对外回调的守卫包装（noctalia 调这些全局函数） ============
local _rawOnOpen, _rawOnClose, _rawOnTick, _rawOnKey, _rawOnIpc = onOpen, onClose, onFrameTick, onKey, onIpc
function onOpen(ctx) guard("onOpen", function() _rawOnOpen(ctx) end) end
function onClose() guard("onClose", function() _rawOnClose() end) end
function onFrameTick(dt) guard("onFrameTick", function() _rawOnTick(dt) end) end
function onKey(chord, pressed) guard("onKey", function() _rawOnKey(chord, pressed) end) end
function onIpc(event, payload) guard("onIpc", function() _rawOnIpc(event, payload) end) end
