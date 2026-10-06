--!nonstrict
-- pang/sidebar v2.0 — 轻量工作台：分层布局 / 专注与置顶 / 裁切动效 / 按需刷新
-- 卡片：搜索 / 媒体 / 随手记 / 窗口 / 计时器 / 系统 / 最近文件。
-- 数据更新与画卷式展开分离；折叠内容预建并保留，点击不再重新创建控件。
-- v0.3：卡片头部/列表行/空状态抽成共用构件与设计 token；搜索支持 ↑↓ 选择、
--       Enter 打开选中项；窗口/最近/笔记加右键菜单；媒体可拖拽跳转、曲线可悬停读数；
--       修正异步竞态与错误路径（应用列表、封面、计时器 pid、笔记目录、xbel 解析）。
-- plugin_api 32：容器 tooltip / panel.openContextMenu / ui.graph 指针回调。

-- ============ 通用小工具 ============
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function fmtUs(us)
  local s = math.floor((tonumber(us) or 0) / 1000000)
  return string.format("%d:%02d", math.floor(s / 60), s % 60)
end
local function fmtSec(sec)
  sec = math.max(0, math.floor(sec + 0.999))
  return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end
local function fmtBps(b)
  b = tonumber(b) or 0
  if b < 1024 then return string.format("%d B/s", b) end
  if b < 1048576 then return string.format("%.1f KB/s", b / 1024) end
  return string.format("%.1f MB/s", b / 1048576)
end
local function basename(p) return (p:match("[^/]+$")) or p end
local function dirname(p) return (p:match("^(.*)/[^/]*$")) or "" end
local function trunc(s, n) if #s > n then return s:sub(1, n - 1) .. "…" end return s end
local function endsWith(s, suffix) return s:sub(-#suffix) == suffix end
local function shq(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

-- ============ 设计 token（一处定义，各卡统一引用） ============
local FS = { hero = 30, list = 13, body = 12, caption = 11, small = 10 } -- 字号阶梯
local SP = { stack = 10, card = 12, block = 8, row = 7, tight = 4 }      -- 间距阶梯
local RD = { card = 16, row = 9 }                                        -- 圆角
local CL = {                                                             -- 颜色角色
  card = "surface_variant/0.24",
  row = "surface_variant/0.35",
  rowActive = "primary/0.20",
  muted = "on_surface_variant",
}

-- 插件设置（Settings → Plugins 修改；声明见 plugin.toml 的 [[setting]]）
local NOTES_DIR = noctalia.getConfig("notes_dir") or "~/Documents/notes"
local SEARCH_LIMIT = tonumber(noctalia.getConfig("search_limit")) or 10
local RECENT_COUNT = tonumber(noctalia.getConfig("recent_count")) or 8

local MOTION = noctalia.getConfig("motion") or "light"
local render -- forward declaration

-- 折叠状态 + 卡片顺序（可拖拽排序）：默认展开 搜索/媒体/笔记；顺序与折叠持久化到 panel_layout.json
local open = { search = true, media = true, note = true, wins = false, timer = false, sysmon = false, recent = false }
local order = { "search", "media", "note", "wins", "timer", "sysmon", "recent" }
local CARD_KEYS = { search = true, media = true, note = true, wins = true, timer = true, sysmon = true, recent = true }
local stateDirty = false    -- 性能：只在可见数据变化时重绘（空闲秒不重绘）
local lastMediaSig = ""     -- 性能：封面只在曲目变化时才查
local winsTick = 0
local mediaTick = 0
local updateTick = 0

-- 宿主负责开场，插件只动画裁切高度，避免整树叠加透明度。
local folds, motionNodes, cardCache, dirtyCards = {}, {}, {}, {}
local retainedBodies, headerNodes, warmVisible = {}, {}, {}
local lastMotionSubmit, settleAt = 0, 0
local cachedTree
local panelVisible = false
local generation, inFlight = 0, {}
local clockMinute = ""
local focusEdges = {}
local pinned = {}
local focusMode, focusRestore, activeCard = false, nil, "search"
local customizing, layoutLoaded = false, false
local layoutSaveAt = nil
local bootQueue, bootAt, bootReady = {}, 0, false
local motionMs = MOTION == "off" and 0 or (MOTION == "soft" and 440 or 300)
-- 画卷式：开头立刻起速（不吃掉首帧延迟），中段平稳，收尾自然减速。
-- 纯余弦/缓入曲线在起点速度为 0，视觉上就是"顿一下才开始动"。
local function ease(x) return 0.18 * x + 0.82 * (0.5 - 0.5 * math.cos(x * math.pi)) end
local function wake() if panelVisible then panel.setNeedsFrameTick(true) end end
local function markDirty(key) dirtyCards[key] = true stateDirty = true wake() end
-- 每个数据源最多一个在途请求；关闭/重开后旧回调不能污染新状态。
local function query(key, command, callback)
  if inFlight[key] == generation then return true end
  local gen = generation
  inFlight[key] = gen
  local started = noctalia.runAsync(command, function(result)
    if inFlight[key] == gen then inFlight[key] = nil end
    if gen ~= generation or not panelVisible then return end
    callback(result)
  end)
  if not started then
    inFlight[key] = nil
    callback({ exitCode = -1, stdout = "" })
  end
  return started
end
local function focusOnce(props)
  if props.focus then focusEdges[#focusEdges + 1] = props end
  return props
end
local function submitTree()
  panel.render(cachedTree)
  -- focus 是一次性请求，不能留在缓存中每个动画帧重复抢焦点。
  for _, props in ipairs(focusEdges) do props.focus = nil end
  focusEdges = {}
end
local function foldValue(key)
  local m = folds[key]
  if not m then return open[key] and 1 or 0 end
  local x = math.min(1, math.max(0, (noctalia.nowMs() - m.t0) / m.duration))
  return m.from + (m.to - m.from) * ease(x)
end
local function bodyVisible(key) return retainedBodies[key] or open[key] or folds[key] ~= nil end
local function setCardOpen(key, value)
  if not CARD_KEYS[key] or open[key] == value then return end
  local from = foldValue(key)
  open[key] = value
  local target = value and 1 or 0
  local node, header = motionNodes[key], headerNodes[key]
  if node then
    -- 常态路径只改已有节点；不在点击时构造列表、输入框或图片。
    node.viewport.props.visible = value or motionMs > 0
    node.shell.props.border = value and "primary/0.18" or "on_surface/0.05"
    if header then
      header.icon.props.fill = value and "primary/0.12" or "surface_variant/0.30"
      header.icon.children[1].props.color = value and "primary" or CL.muted
      header.arrow.props.name = value and "chevron-down" or "chevron-right"
      header.row.props.tooltip = value and "点击收起" or "点击展开"
    end
  else
    -- 没有可动画的节点（卡片没有正文，或刚被重建）：直接重建，让状态和画面立刻一致，
    -- 不要开一个什么都不会动的折叠、拖到最后再整块跳过去。
    markDirty(key)
    if panelVisible then render("pending") end
    return
  end
  if motionMs == 0 then
    folds[key] = nil
    if node then
      node.viewport.props.height = math.max(0.1, node.height * target)
      node.viewport.props.visible = value
      node.shell.props.gap = SP.block * target
    end
  else
    folds[key] = { from = from, to = target, t0 = noctalia.nowMs(),
      duration = math.max(120, motionMs * (value and 1 or 0.85) * math.sqrt(math.abs(target - from))) }
    lastMotionSubmit = 0
    wake()
  end
end

local function layoutPath() return noctalia.pluginDataDir() .. "/panel_layout.json" end
local layoutWarned = false
local function flushLayout()
  layoutSaveAt = nil
  local enc = noctalia.json.encode({ version = 2, order = order, open = open, pinned = pinned, focusMode = focusMode, focusRestore = focusRestore, activeCard = activeCard })
  if not enc then return end
  local ok, err = noctalia.writeFile(layoutPath(), enc)
  if not ok and not layoutWarned then
    layoutWarned = true -- 只提示一次，避免拖拽时反复弹错
    noctalia.notifyError("Sidebar", err or "布局保存失败")
  end
end

local function persistLayout()
  layoutSaveAt = noctalia.nowMs() + 350 -- 连点/拖拽合并落盘，避开动画
  wake()
end

-- 拖拽落下：payload = 被拖的卡片 key；value = "before|<key>" 或 "end"
function onCardDrop(payload, value)
  local anchor = nil
  if value ~= "end" then
    local _, a = value:match("^([^|]+)|(.+)$")
    anchor = a
  end
  if not CARD_KEYS[payload] or (anchor and not CARD_KEYS[anchor]) then return end
  if anchor then pinned[payload] = pinned[anchor] == true end
  local src = nil
  for i, k in ipairs(order) do
    if k == payload then src = i break end
  end
  if not src then return end
  if value == "end" then
    table.remove(order, src)
    table.insert(order, payload)
  elseif anchor and anchor ~= payload then
    table.remove(order, src)
    local dst = nil
    for i, k in ipairs(order) do
      if k == anchor then dst = i break end
    end
    if dst then
      table.insert(order, dst, payload)
    else
      table.insert(order, 1, payload)
    end
  end
  render()
  persistLayout()
end

local function chevron(key)
  return ui.glyph({ name = open[key] and "chevron-down" or "chevron-right", size = 12, color = CL.muted })
end

local function toggleCard(key)
  local value = not open[key]
  if value then
    activeCard = key
    if focusMode then
      for k in pairs(CARD_KEYS) do if k ~= key then setCardOpen(k, false) end end
    end
  end
  setCardOpen(key, value)
  if not motionNodes[key] then
    render("layout")
  else
    submitTree()
  end
  persistLayout()
end

-- 卡片头部：拖拽把手 + 标题 + 附加节点（摘要/按钮）+ 折叠箭头；整行可点击折叠
local function cardHeader(key, glyphName, title, extras, onToggle)
  local icon = ui.row({ width = 28, height = 28, radius = 8,
    fill = open[key] and "primary/0.12" or "surface_variant/0.30", align = "center", justify = "center" }, {
    ui.glyph({ name = glyphName, size = 16, color = open[key] and "primary" or CL.muted }),
  })
  local iconBody = icon
  if customizing then
    icon = ui.dragSource({ key = "drag-" .. key, dragType = "card", payload = key,
      previewAncestor = 2, tooltip = "拖动图标排序", width = 28, height = 28 }, { icon })
  end
  local kids = { icon, ui.label({ text = title, fontSize = FS.body, fontWeight = "bold", flexGrow = 1 }) }
  if extras then for _, node in ipairs(extras) do
    if node.type == "label" then node.props.maxWidth = customizing and 80 or 150 node.props.maxLines = 1 end
    kids[#kids + 1] = node
  end end
  if customizing then
    kids[#kids + 1] = ui.button({ glyph = "pin", height = 26, width = 26,
      variant = pinned[key] and "secondary" or "ghost", tooltip = pinned[key] and "取消置顶" or "置顶这张卡片",
      onClick = function() pinned[key] = not pinned[key] render() persistLayout() end })
  elseif pinned[key] then
    kids[#kids + 1] = ui.glyph({ name = "pin", size = 10, color = "primary" })
  end
  local arrow = chevron(key)
  kids[#kids + 1] = arrow
  local row = ui.row({ key = "header-" .. key, align = "center", gap = SP.row,
    onClick = onToggle or function() toggleCard(key) end,
    tooltip = open[key] and "点击收起" or "点击展开" }, kids)
  headerNodes[key] = { icon = iconBody, arrow = arrow, row = row }
  return row
end

-- 列表行：统一圆角/内距/选中面色
local function listRow(key, active, onClick, children, tooltip)
  return ui.row({
    key = key,
    radius = RD.row,
    padding = SP.row,
    gap = SP.block,
    fill = active and CL.rowActive or CL.row,
    onClick = onClick,
    tooltip = tooltip,
    align = "center",
  }, children)
end

-- 空态/错误态：图标 + 一句说明
local function emptyState(glyphName, text)
  return ui.row({ align = "center", justify = "center", gap = SP.block, paddingV = 12 }, {
    ui.glyph({ name = glyphName, size = 18, color = CL.muted }),
    ui.label({ text = text, fontSize = FS.body, color = CL.muted }),
  })
end

-- 卡片外壳：统一面色/圆角/内距/块间距
-- 固定上限的内容视口：长列表在卡内滚动，折叠时只推进裁切高度。
local function cardShell(key, children, bodyHeight)
  local kids = { children[1] }
  local shell = ui.column({ key = "card-" .. key, fill = CL.card, radius = RD.card,
    border = open[key] and "primary/0.18" or "on_surface/0.05", borderWidth = 1,
    padding = SP.card, gap = 0, align = "stretch" }, kids)
  motionNodes[key] = nil -- 同一张卡重建后旧节点立即作废，避免动画作用在已不在树里的节点上
  if #children > 1 then
    retainedBodies[key] = true
    local body = {}
    for i = 2, #children do body[#body + 1] = children[i] end
    local progress = foldValue(key)
    local curH = math.max(0.1, bodyHeight * progress)
    local isVis = open[key] or folds[key] ~= nil or progress > 0.005
    local viewport = ui.scroll({ key = "body-" .. key, height = curH,
      visible = isVis,
      paddingH = 0, paddingV = 0 }, { ui.column({ key = "content-" .. key, gap = SP.block, align = "stretch" }, body) })
    kids[2] = viewport
    shell.props.gap = SP.block * progress
    motionNodes[key] = { shell = shell, viewport = viewport, height = bodyHeight }
  end
  return shell
end

-- ============ 卡 1：搜索（应用 + 命令前缀） ============
local apps = { loaded = false, list = {}, error = false, loadedAt = 0 }
local search = { text = "", rev = 0, results = {}, cmdText = nil, cmdMode = false, wantFocus = false, sel = 1 }

local function refreshSearchResults()
  local q = search.text
  search.cmdMode = (q:sub(1, 1) == ">")
  search.cmdText = nil
  search.results = {}
  search.sel = 1
  if q == "" then return end
  if search.cmdMode then
    local c = trim(q:sub(2))
    search.cmdText = (c ~= "") and c or nil
    return
  end
  local scored = {}
  for _, a in ipairs(apps.list) do
    local s = noctalia.fuzzyScore(q, a.name)
    if s then table.insert(scored, { s = s, a = a }) end
  end
  table.sort(scored, function(x, y)
    if x.s ~= y.s then return x.s > y.s end
    return x.a.name < y.a.name
  end)
  local out = {}
  for i = 1, math.min(#scored, SEARCH_LIMIT) do out[i] = scored[i].a end
  search.results = out
end

local frequentCache = nil
local function refreshApps()
  local cmd = [[
for d in "$HOME/.local/share/applications" /usr/share/applications; do
  [ -d "$d" ] || continue
  set -- "$d"/*.desktop
  [ -e "$1" ] || continue
  awk -F'=' '
    function flush() {
      if (name != "" && !nd && type == "Application" && exec != "") {
        gsub(/ ?%[fFuUdDnNickvm]/, "", exec)
        printf "%s\t%s\t%s\t%d\t%s\n", name, exec, icon, term, fname
      }
    }
    function reset() { name=""; exec=""; icon=""; term=0; nd=0; type=""; s=0; fname=FILENAME }
    FNR==1 { flush(); reset() }
    END { flush() }
    $0=="[Desktop Entry]" { s=1; next }
    /^\[/ { s=0; next }
    !s { next }
    $1=="Name" && name=="" { name=substr($0,6) }
    $1=="Exec" && exec=="" { exec=substr($0,6) }
    $1=="Icon" && icon=="" { icon=substr($0,6) }
    $1=="Terminal" && $2=="true" { term=1 }
    $1=="NoDisplay" && $2=="true" { nd=1 }
    $1=="Type" && type=="" { type=substr($0,6) }
  ' "$@"
done
]]
  local started = query("apps", cmd, function(res)
    local seen = {}
    local list = {}
    for line in ((res.stdout or "") .. "\n"):gmatch("([^\n]*)\n") do
      if line ~= "" then
        local name, exec, icon, term, path = line:match("^(.-)\t(.-)\t(.-)\t(.-)\t(.*)$")
        if name and not seen[name] then
          seen[name] = true
          table.insert(list, {
            name = name,
            exec = exec,
            icon = icon or "",
            terminal = (term == "1"),
            id = (path:match("([^/]+)%.desktop$") or ""),
          })
        end
      end
    end
    apps.list = list
    frequentCache = nil
    apps.loaded = true
    apps.loadedAt = noctalia.nowMs()
    apps.error = (res.exitCode ~= 0)
    -- 列表到达后立刻重算结果并重绘：加载完成前输入的查询也要出结果
    refreshSearchResults()
    markDirty("search")
  end)
  if not started then
    apps.loaded = true
    apps.error = true
    markDirty("search")
  end
end

-- 常用应用（frecency）：记录启动次数与时间，查询为空时给出快捷入口
local usage = {}
local function usagePath() return noctalia.pluginDataDir() .. "/app_usage.json" end
local function loadUsage()
  local raw = noctalia.readFile(usagePath())
  if not raw then return end
  local d = noctalia.json.decode(raw)
  if type(d) == "table" then usage = d end
end
local function recordUsage(a)
  local key = (a.id ~= "") and a.id or a.name
  local e = usage[key]
  if type(e) ~= "table" then e = { c = 0, t = 0, name = a.name } end
  e.c = (e.c or 0) + 1
  e.t = noctalia.nowMs()
  e.name = a.name
  usage[key] = e
  -- 只保留最近使用的 40 条，避免文件无限增长
  local keys = {}
  for k in pairs(usage) do keys[#keys + 1] = k end
  if #keys > 40 then
    table.sort(keys, function(x, y) return (usage[x].t or 0) > (usage[y].t or 0) end)
    for i = 41, #keys do usage[keys[i]] = nil end
  end
  local enc = noctalia.json.encode(usage)
  if enc then noctalia.writeFile(usagePath(), enc) end
end
local function frequentApps(limit)
  if frequentCache then return frequentCache end
  local now = noctalia.nowMs()
  local scored = {}
  for _, e in pairs(usage) do
    if type(e) == "table" and e.c and e.t and e.name then
      local ageDays = (now - e.t) / 86400000
      if ageDays < 21 then scored[#scored + 1] = { score = e.c / (1 + ageDays), name = e.name } end
    end
  end
  table.sort(scored, function(x, y) return x.score > y.score end)
  local out = {}
  for _, s in ipairs(scored) do
    if #out >= limit then break end
    for _, a in ipairs(apps.list) do
      if a.name == s.name then
        out[#out + 1] = a
        break
      end
    end
  end
  frequentCache = out
  return out
end
loadUsage()

local function launchApp(a)
  if not a then return end
  recordUsage(a)
  frequentCache = nil
  if a.terminal then
    noctalia.runInTerminal(a.exec)
  else
    noctalia.runAsync(a.exec)
  end
  panel.close()
end

function onSearchChanged(value)
  activeCard = "search"
  search.text = value or ""
  refreshSearchResults()
  render("search")
end

function onSearchSubmit(_)
  if search.cmdMode and search.cmdText then
    noctalia.runInTerminal(search.cmdText)
    panel.close()
  else
    local a = search.results[search.sel] or search.results[1]
    if a then launchApp(a) end
  end
end

-- ↑↓ 在结果间移动选择（chord 与 plugin.toml 的 capture_keys 逐条对应）
function onKey(chord, pressed)
  if pressed == false or pressed == "false" then return end
  if not open.search or search.cmdMode or #search.results == 0 then return end
  local c = tostring(chord or ""):lower()
  if c == "down" then
    search.sel = math.min(#search.results, search.sel + 1)
    render("search")
  elseif c == "up" then
    search.sel = math.max(1, search.sel - 1)
    render("search")
  end
end

function onRunCmd()
  if search.cmdText then
    noctalia.runInTerminal(search.cmdText)
    panel.close()
  end
end

local function appIconNode(a, size)
  if a.iconPath == nil then
    local p = nil
    if a.icon ~= "" then p = noctalia.appIconPath(a.icon, size) end
    if p == nil and a.id ~= "" then p = noctalia.appIconPath(a.id, size) end
    a.iconPath = p or false
  end
  if a.iconPath then
    return ui.image({ path = a.iconPath, width = size, height = size, fit = "contain" })
  end
  return ui.row({ width = size, height = size, fill = "surface_variant/0.5", radius = 6, align = "center", justify = "center" }, {
    ui.glyph({ name = "app-window", size = math.floor(size * 0.6), color = "on_surface_variant" }),
  })
end

local function searchCard()
  local summary
  if apps.error then
    summary = "应用列表不可用"
  elseif not apps.loaded then
    summary = "载入中…"
  elseif #search.results > 0 then
    summary = #search.results .. " / " .. #apps.list
  else
    summary = #apps.list .. " 个应用"
  end
  local children = {
    cardHeader("search", "search", "搜索", {
      ui.label({ text = summary, fontSize = FS.small, color = CL.muted }),
    }, function()
      if not open.search then search.wantFocus = true end
      toggleCard("search")
    end),
  }
  if bodyVisible("search") then
    local iprops = {
      key = "search-" .. search.rev,
      value = search.text,
      placeholder = "搜应用…（以 > 开头执行命令）",
      submitOnEnter = true,
      onChange = "onSearchChanged",
      onSubmit = "onSearchSubmit",
    }
    if search.wantFocus then
      iprops.focus = true
      search.wantFocus = false
    end
    table.insert(children, ui.input(focusOnce(iprops)))
    if search.cmdMode and search.cmdText then
      table.insert(children, ui.row({
        key = "cmdrow", radius = RD.row, padding = SP.block, fill = "surface_variant/0.6",
        onClick = "onRunCmd", align = "center", gap = SP.block, tooltip = "在终端运行（Enter）",
      }, {
        ui.glyph({ name = "terminal", size = 14 }),
        ui.label({ text = "运行：" .. search.cmdText, fontSize = FS.body, maxLines = 1, flexGrow = 1 }),
        ui.label({ text = "Enter", fontSize = FS.small, color = CL.muted }),
      }))
    elseif #search.results > 0 then
      for i, a in ipairs(search.results) do
        local rowKids = {
          appIconNode(a, 22),
          ui.label({ text = a.name, fontSize = FS.list, maxLines = 1, flexGrow = 1 }),
        }
        if i == search.sel then
          rowKids[#rowKids + 1] = ui.glyph({ name = "corner-down-left", size = 12, color = CL.muted })
        end
        table.insert(children, listRow("res-" .. (a.id ~= "" and a.id or a.name), i == search.sel, function() launchApp(a) end, rowKids))
      end
      table.insert(children, ui.label({ text = "↑↓ 选择 · Enter 打开", fontSize = FS.small, color = CL.muted, textAlign = "end" }))
    elseif apps.error then
      table.insert(children, emptyState("alert-triangle", "应用列表读取失败"))
    elseif not apps.loaded then
      table.insert(children, emptyState("loader", "正在读取应用列表…"))
    elseif search.text == "" then
      -- 空查询：常用应用快捷入口（按启动次数与新鲜度排序）
      local fav = frequentApps(5)
      if #fav > 0 then
        table.insert(children, ui.label({ text = "常用", fontSize = FS.small, color = CL.muted }))
        for _, a in ipairs(fav) do
          table.insert(children, listRow("fav-" .. (a.id ~= "" and a.id or a.name), false, function() launchApp(a) end, {
            appIconNode(a, 22),
            ui.label({ text = a.name, fontSize = FS.list, maxLines = 1, flexGrow = 1 }),
            ui.glyph({ name = "arrow-up-right", size = 12, color = CL.muted }),
          }))
        end
      end
    else
      table.insert(children, emptyState("search-off", "没有匹配的应用"))
    end
  end
  return cardShell("search", children, math.min(280, 74 + math.max(#search.results, search.text == "" and #frequentApps(5) or 0) * 46))
end

-- ============ 卡 2：媒体 ============
local media = { ok = false, status = "Stopped", artist = "", title = "", lengthUs = 0, posUs = 0, seeking = nil }
local artPath = nil
local artHash = ""
local artSlot = 0
local artGen = 0          -- 封面异步代次：过期回调直接丢弃
local artLastTryMs = 0

local refreshArt -- 前向声明（refreshMedia 回调里在曲目变化时调用）

local function refreshMedia()
  query("media",
    "playerctl metadata --format '{{status}}|||{{artist}}|||{{title}}|||{{mpris:length}}|||{{position}}'",
    function(res)
      local prevSig = media.status .. "|" .. media.artist .. "|" .. media.title .. "|" .. media.lengthUs .. "|" .. media.posUs .. "|" .. tostring(media.ok) .. "|" .. tostring(artPath)
      if res.exitCode ~= 0 or res.stdout == "" then
        media.ok = false
        media.seeking = nil
        if artPath ~= nil or artHash ~= "" then
          artGen = artGen + 1 -- 使在途的封面提取失效
          artHash = ""
          artPath = nil
        end
      else
        local line = res.stdout:gsub("%s+$", "")
        local status, artist, title, len, pos = line:match("^(.-)|||(.-)|||(.-)|||(.-)|||(.-)$")
        if status == nil then
          media.ok = false
          media.seeking = nil
        else
          media.ok = true
          media.status = status
          media.artist = artist
          media.title = title
          media.lengthUs = tonumber(len) or 0
          -- playerctl format 里的 position 已是微秒
          media.posUs = tonumber(pos) or 0
          -- 性能：封面哈希只在曲目变化时跑（空闲秒不再起进程）；status 变化不触发
          local msig = artist .. "|" .. title
          if msig ~= lastMediaSig then
            lastMediaSig = msig
            media.seeking = nil
            refreshArt()
          elseif artPath == nil and (noctalia.nowMs() - artLastTryMs) > 30000 then
            refreshArt() -- 上轮提取失败：每 30 秒重试一次
          end
        end
      end
      local newSig = media.status .. "|" .. media.artist .. "|" .. media.title .. "|" .. media.lengthUs .. "|" .. media.posUs .. "|" .. tostring(media.ok) .. "|" .. tostring(artPath)
      if newSig ~= prevSig then markDirty("media") end
    end)
end

-- 封面：全部交给 shell 处理（data:/file:/http: 三种来源），Lua 侧只比较短哈希；
-- 哈希在提取成功后才提交，代次不匹配的回调直接丢弃（快速切歌不再串封面）
refreshArt = function()
  local gen = artGen + 1
  artGen = gen
  artLastTryMs = noctalia.nowMs()
  noctalia.runAsync(
    "playerctl metadata mpris:artUrl 2>/dev/null | md5sum | cut -c1-12",
    function(res)
      if gen ~= artGen then return end
      local h = (res.stdout or ""):gsub("%s+$", "")
      if res.exitCode ~= 0 or h == "" or h == "d41d8cd98f00" then
        if artPath ~= nil then
          artPath = nil
          markDirty("media")
        end
        artHash = ""
        return
      end
      if h == artHash and artPath ~= nil then return end
      local slot = 1 - artSlot
      local dest = noctalia.pluginDataDir() .. "/art_" .. tostring(slot) .. ".jpg"
      local extract = "u=$(playerctl metadata mpris:artUrl); case \"$u\" in\n"
        .. "file://*) cp -- \"${u#file://}\" " .. shq(dest) .. ";;\n"
        .. "http*) curl -sL --max-time 20 -o " .. shq(dest) .. " \"$u\";;\n"
        .. "data:*) printf '%s' \"$u\" | sed 's/^data:[^,]*,//' | base64 -d > " .. shq(dest) .. ";;\nesac"
      noctalia.runAsync(extract, function(eres)
        if gen ~= artGen then return end
        if eres.exitCode ~= 0 or not noctalia.fileExists(dest) then return end -- 失败保留旧封面，由重试路径再试
        artHash = h
        artSlot = slot
        artPath = dest
        markDirty("media")
      end)
    end)
end

function onMediaPrev() noctalia.runAsync("playerctl previous") end
function onMediaNext() noctalia.runAsync("playerctl next") end
function onMediaToggle() noctalia.runAsync("playerctl play-pause") end

-- 拖动进度条：拖动期间用预览值渲染，松手后用 argv 形式定位，避免 shell 解析
function onSeekChange(value)
  local v = tonumber(value)
  if v == nil or media.lengthUs <= 0 then return end
  media.seeking = math.min(1, math.max(0, v / 1000))
  render("media")
end

function onSeekEnd(value)
  local v = tonumber(value)
  if v == nil or media.lengthUs <= 0 then return end
  local ratio = math.min(1, math.max(0, v / 1000))
  local targetUs = math.floor(ratio * media.lengthUs)
  noctalia.runAsync({ "playerctl", "position", string.format("%.3f", targetUs / 1000000) })
  media.posUs = targetUs -- 乐观更新，下一次轮询回来前先按目标显示
  media.seeking = nil
  markDirty("media")
end

local function mediaCard()
  local extras = {}
  if media.ok and media.title ~= "" then
    extras[1] = ui.label({ text = media.title, fontSize = FS.small, color = CL.muted, maxLines = 1 })
  end
  local children = { cardHeader("media", "music", "媒体", extras) }
  if bodyVisible("media") then
    if not media.ok then
      table.insert(children, emptyState("music-off", "暂无播放内容"))
    else
      local cover = artPath and ui.image({ path = artPath, width = 64, height = 64, radius = 12, fit = "cover" })
        or ui.row({ width = 64, height = 64, fill = "primary/0.10", radius = 12, align = "center", justify = "center" }, {
          ui.glyph({ name = "music", size = 26, color = "primary" }),
        })
      table.insert(children, ui.row({ gap = 12, align = "center" }, {
        cover, ui.column({ gap = 5, flexGrow = 1 }, {
          ui.label({ text = media.status == "Playing" and "正在播放" or "已暂停", fontSize = FS.small, color = "primary" }),
          ui.label({ text = media.title ~= "" and media.title or "未知曲目", fontSize = FS.list, fontWeight = "bold", maxLines = 1 }),
          ui.label({ text = media.artist ~= "" and media.artist or "未知艺术家", fontSize = FS.caption, color = CL.muted, maxLines = 1 }),
        }),
      }))
      if media.lengthUs > 0 then
        -- 进度条即跳转条：拖动给出预览，松手定位；长度未知（直播流）时不显示
        local ratio = media.seeking or math.min(1, math.max(0, media.posUs / media.lengthUs))
        table.insert(children, ui.slider({
          min = 0, max = 1000, step = 1,
          value = math.floor(ratio * 1000 + 0.5),
          controlSize = "sm", height = 20,
          onChange = "onSeekChange", onDragEnd = "onSeekEnd",
        }))
        table.insert(children, ui.row({ align = "center", justify = "space_between" }, {
          ui.label({ text = fmtUs(media.seeking and (media.seeking * media.lengthUs) or media.posUs), fontSize = FS.caption, color = CL.muted }),
          ui.label({ text = fmtUs(media.lengthUs), fontSize = FS.caption, color = CL.muted }),
        }))
      end
      table.insert(children, ui.row({ align = "center", justify = "center", gap = 10 }, {
        ui.button({ glyph = "player-skip-back", variant = "ghost", tooltip = "上一首", onClick = "onMediaPrev" }),
        ui.button({ glyph = (media.status == "Playing") and "player-pause" or "player-play", variant = "primary", tooltip = "播放 / 暂停", onClick = "onMediaToggle" }),
        ui.button({ glyph = "player-skip-forward", variant = "ghost", tooltip = "下一首", onClick = "onMediaNext" }),
      }))
    end
  end
  return cardShell("media", children, media.ok and (media.lengthUs > 0 and 170 or 112) or 48)
end

-- ============ 卡 3：窗口列表 ============
local wins = { list = {}, ok = false }
local winIconCache = {}

local function winsSig(list, ok)
  local s = ok and "1" or "0"
  for _, w in ipairs(list) do
    s = s .. "|" .. tostring(w.id) .. (w.focused and "F" or "") .. tostring(w.wsIdx or "") .. w.title
  end
  return s
end

local function refreshWins()
  -- 一次取窗口 + 工作区：id → 显示序号（用户看到的是序号，不是内部 id）
  query("wins", "niri msg -j windows; printf '\\n###\\n'; niri msg -j workspaces", function(res)
    local prevSig = winsSig(wins.list, wins.ok)
    local winJson, wsJson = (res.stdout or ""):match("^(.-)\n###\n(.*)$")
    local data = nil
    if res.exitCode == 0 and winJson then data = noctalia.json.decode(winJson) end
    if type(data) ~= "table" then
      wins.ok = false
    else
      local wsIdx = {}
      local wsData = wsJson and noctalia.json.decode(wsJson)
      if type(wsData) == "table" then
        for _, ws in ipairs(wsData) do
          if type(ws) == "table" and ws.id then wsIdx[ws.id] = ws.idx end
        end
      end
      local list = {}
      for _, w in ipairs(data) do
        if type(w) == "table" then
          local wsid = w.workspace_id or 0
          table.insert(list, {
            id = w.id,
            title = w.title or "",
            app_id = w.app_id or "",
            focused = (w.is_focused == true),
            ws = wsid,
            wsIdx = wsIdx[wsid] or wsid,
          })
        end
      end
      table.sort(list, function(x, y)
        if x.wsIdx ~= y.wsIdx then return x.wsIdx < y.wsIdx end
        if x.ws ~= y.ws then return x.ws < y.ws end
        return x.id < y.id
      end)
      wins.list = list
      wins.ok = true
    end
    if winsSig(wins.list, wins.ok) ~= prevSig then markDirty("wins") end
  end)
end

local function focusWin(id)
  noctalia.runAsync("niri msg action focus-window --id " .. id)
  panel.close()
end
local function closeWin(id)
  noctalia.runAsync("niri msg action close-window --id " .. id)
end

-- 窗口右键菜单（openContextMenu 必须在 button 的 onRightClick 回调里直接调用）
local winMenu = { id = 0, title = "", app_id = "" }

function openWinMenu(w)
  winMenu.id = w.id
  winMenu.title = w.title or ""
  winMenu.app_id = w.app_id or ""
  panel.openContextMenu({
    items = {
      { kind = "header", label = winMenu.title ~= "" and trunc(winMenu.title, 60) or ("窗口 " .. tostring(w.id)) },
      { id = "focus", label = "聚焦窗口" },
      { id = "close", label = "关闭窗口" },
      { kind = "separator" },
      { id = "copy-title", label = "复制标题", enabled = winMenu.title ~= "" },
      { id = "copy-app", label = "复制应用 ID", enabled = winMenu.app_id ~= "" },
    },
    onActivate = "onWinMenuAction",
    context = w.id,
  })
end

function onWinMenuAction(actionId, _winId)
  if actionId == "focus" then
    focusWin(winMenu.id)
  elseif actionId == "close" then
    closeWin(winMenu.id)
  elseif actionId == "copy-title" then
    noctalia.copyToClipboard(winMenu.title, "text/plain")
  elseif actionId == "copy-app" then
    noctalia.copyToClipboard(winMenu.app_id, "text/plain")
  end
end

local function winIconNode(appId, size)
  if appId ~= "" then
    if winIconCache[appId] == nil then
      winIconCache[appId] = noctalia.appIconPath(appId, size) or false
    end
    if winIconCache[appId] then
      return ui.image({ path = winIconCache[appId], width = size, height = size, fit = "contain" })
    end
  end
  return ui.glyph({ name = "app-window", size = size, color = "on_surface_variant" })
end

local function winsCard()
  local children = {
    cardHeader("wins", "layout-grid", "窗口", {
      ui.label({ text = (#wins.list) .. " 个", fontSize = FS.small, color = CL.muted }),
    }),
  }
  if bodyVisible("wins") then
    if not wins.ok then
      table.insert(children, emptyState("alert-triangle", "niri 不可达"))
    elseif #wins.list == 0 then
      table.insert(children, emptyState("app-window", "当前没有打开的窗口"))
    else
      -- 按工作区分组：同组连续排列（refreshWins 已按 wsIdx, id 排序）
      local wsCounts = {}
      for _, w in ipairs(wins.list) do wsCounts[w.wsIdx] = (wsCounts[w.wsIdx] or 0) + 1 end
      local lastWs = nil
      for _, w in ipairs(wins.list) do
        if w.wsIdx ~= lastWs then
          lastWs = w.wsIdx
          local wsLabel = (w.wsIdx and w.wsIdx > 0) and ("工作区 " .. w.wsIdx) or "其他"
          table.insert(children, ui.row({ paddingH = SP.row, paddingV = SP.tight }, {
            ui.label({ text = wsLabel .. " · " .. (wsCounts[w.wsIdx] or 0) .. " 个", fontSize = FS.small, color = CL.muted }),
          }))
        end
        local sub = (w.app_id ~= "") and w.app_id or ("窗口 " .. tostring(w.id))
        local texts = { ui.label({ text = (w.title ~= "") and w.title or sub, fontSize = FS.body, maxLines = 1 }) }
        if w.title ~= "" then
          table.insert(texts, ui.label({ text = sub, fontSize = FS.small, color = CL.muted, maxLines = 1 }))
        end
        table.insert(children, listRow("win-" .. w.id, w.focused, function() focusWin(w.id) end, {
          winIconNode(w.app_id, 20),
          ui.column({ gap = 1, flexGrow = 1 }, texts),
          ui.button({
            glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "关闭窗口（右键更多）",
            onClick = function() closeWin(w.id) end,
            onRightClick = function() openWinMenu(w) end,
          }),
        }))
      end
    end
  end
  return cardShell("wins", children, wins.ok and #wins.list > 0 and math.min(290, #wins.list * 68 + 28) or 48)
end

-- ============ 卡 4：计时器（独立进程发通知，面板关着也能提醒） ============
local timer = { durMin = 25, remain = 1500, deadlineMs = 0, running = false, done = false, adopted = false }

local function timerPidPath() return noctalia.pluginDataDir() .. "/timer.pid" end
local function timerKill()
  local pf = timerPidPath()
  noctalia.runAsync("if [ -f " .. shq(pf) .. " ]; then PID=$(cat " .. shq(pf) .. "); kill -TERM -$PID 2>/dev/null; kill -TERM $PID 2>/dev/null; rm -f " .. shq(pf) .. "; fi")
end
local function timerStart()
  if timer.running then return end
  if timer.remain <= 0 then timer.remain = timer.durMin * 60 end -- 到点后再点“开始”= 用当前时长重新计时
  timer.deadlineMs = noctalia.nowMs() + timer.remain * 1000
  timer.running = true
  timer.done = false
  local pf = timerPidPath()
  local secs = math.floor(timer.remain + 0.999)
  local msg = string.format("%d 分钟到了", timer.durMin)
  local inner = "echo $$ > " .. shq(pf) .. "; sleep " .. secs .. "; notify-send -a sidebar-panel 计时器 \"" .. msg .. "\"; rm -f " .. shq(pf)
  noctalia.runAsync("setsid sh -c " .. shq(inner))
end
local function timerPause()
  if not timer.running then return end
  timerKill()
  timer.remain = math.max(0, (timer.deadlineMs - noctalia.nowMs()) / 1000)
  timer.running = false
end
local function timerReset()
  timerKill()
  timer.running = false
  timer.done = false
  timer.adopted = false
  timer.remain = timer.durMin * 60
end

-- 与磁盘对账：热重载/重启后若后台进程还活着，接管显示（剩余时间不可知）
local function timerAdopt()
  timer.adopted = false
  if not timer.running and noctalia.fileExists(timerPidPath()) then
    timer.adopted = true
    timer.running = true
    timer.done = false
  end
end

-- 接管期间轮询后台进程是否还活着；进程消失即视为到点/被终止
local function timerProbe()
  local pf = timerPidPath()
  noctalia.runAsync("[ -f " .. shq(pf) .. " ] && kill -0 $(cat " .. shq(pf) .. ") 2>/dev/null", function(res)
    if res.exitCode == 0 then return end
    if timer.adopted and timer.running then
      timer.adopted = false
      timer.running = false
      timer.done = true
      timer.remain = 0
      markDirty("timer")
    end
  end)
end

local function timerPreset(m)
  timerKill()
  timer.durMin = m
  timer.running = false
  timer.done = false
  timer.adopted = false
  timer.remain = m * 60
end

function onTimerToggle()
  if timer.adopted then
    -- 接管中的后台计时：停止并复位
    timerKill()
    timer.adopted = false
    timer.running = false
    timer.done = false
    timer.remain = timer.durMin * 60
  elseif timer.running then
    timerPause()
  else
    timerStart()
  end
  render("timer")
end
function onTimerReset()
  timerReset()
  render("timer")
end
-- 拖动自定义时长：仅待机时生效，松手前就同步显示
function onTimerDurChange(value)
  if timer.running then return end
  local v = tonumber(value)
  if v == nil then return end
  timer.durMin = math.floor(v)
  timer.remain = timer.durMin * 60
  timer.done = false
  render("timer")
end
function onTimerPreset5() timerPreset(5) render("timer") end
function onTimerPreset15() timerPreset(15) render("timer") end
function onTimerPreset25() timerPreset(25) render("timer") end

local function timerCard()
  local status, summary
  if timer.adopted then
    status = "后台计时中"
    summary = status
  elseif timer.running then
    status = "运行中"
    summary = status .. "  " .. fmtSec(timer.remain)
  elseif timer.remain <= 0 then
    status = "已到点"
    summary = status
  else
    status = "待机"
    summary = status
  end
  local children = {
    cardHeader("timer", "clock-hour-4", "计时器", {
      ui.label({ text = summary, fontSize = FS.small, color = CL.muted }),
    }),
  }
  if bodyVisible("timer") then
    local function presetBtn(m)
      return ui.button({
        text = m .. " 分",
        variant = (not timer.running and timer.durMin == m) and "secondary" or "ghost",
        controlSize = "sm",
        onClick = "onTimerPreset" .. m,
      })
    end
    table.insert(children, ui.row({ align = "center", gap = SP.block }, {
      ui.label({ text = timer.adopted and "—:—" or fmtSec(timer.remain), fontSize = FS.hero, fontWeight = "bold", flexGrow = 1 }),
      presetBtn(5), presetBtn(15), presetBtn(25),
    }))
    if timer.running and not timer.adopted and timer.durMin > 0 then
      local ratio = 1 - math.min(1, math.max(0, timer.remain / (timer.durMin * 60)))
      table.insert(children, ui.progress({ progress = ratio, fill = "primary", height = 4, radius = 2 }))
    end
    if not timer.running then
      table.insert(children, ui.slider({
        min = 1, max = 120, step = 1, value = timer.durMin, controlSize = "sm", height = 20,
        onChange = "onTimerDurChange",
      }))
      table.insert(children, ui.row({ align = "center", justify = "space_between" }, {
        ui.label({ text = "自定义时长", fontSize = FS.small, color = CL.muted }),
        ui.label({ text = tostring(timer.durMin) .. " 分", fontSize = FS.small, color = CL.muted }),
      }))
    end
    table.insert(children, ui.row({ align = "center", gap = SP.block }, {
      ui.button({
        text = timer.adopted and "停止" or (timer.running and "暂停" or "开始"),
        variant = "primary", controlSize = "sm", flexGrow = 1, onClick = "onTimerToggle",
      }),
      ui.button({ text = "重置", variant = "ghost", controlSize = "sm", flexGrow = 1, enabled = not timer.adopted, onClick = "onTimerReset" }),
    }))
  end
  return cardShell("timer", children, 190)
end

-- ============ 卡 5：系统一览 ============
local sysmon = { disk = nil, stats = nil, cpuHist = {}, procs = {}, tick = 0, hover = nil, lastSampleMs = 0 }

local function pushHist(t, v)
  table.insert(t, v)
  if #t > 60 then table.remove(t, 1) end
end

local function refreshProcs()
  query("procs", "ps -eo pcpu=,pmem=,comm= --sort=-pcpu | head -6", function(res)
    local list = {}
    for line in ((res.stdout or "") .. "\n"):gmatch("([^\n]*)\n") do
      local cpu, _mem, comm = line:match("^%s*([%d%.]+)%s+([%d%.]+)%s+(.+)$")
      if cpu and comm then
        table.insert(list, { cpu = tonumber(cpu), name = trim(comm) })
      end
    end
    sysmon.procs = list
    markDirty("sysmon")
  end)
end

-- 曲线悬停读数：只有索引变化才重绘（宿主已对指针事件做合并）
function onGraphMove(normX)
  local n = #sysmon.cpuHist
  if n == 0 then return end
  local idx = math.floor((tonumber(normX) or 0) * n) + 1
  idx = math.min(n, math.max(1, idx))
  if sysmon.hover ~= idx then
    sysmon.hover = idx
    render("sysmon")
  end
end

function onGraphLeave()
  if sysmon.hover ~= nil then
    sysmon.hover = nil
    render("sysmon")
  end
end

local function sysCard()
  local st = sysmon.stats
  local summary = ""
  if st then
    summary = string.format("CPU %.0f%%", (st.cpu and st.cpu.usagePercent) or 0)
    if st.ram then summary = summary .. string.format(" · 内存 %.0f%%", st.ram.usagePercent or 0) end
  end
  local children = {
    cardHeader("sysmon", "cpu", "系统", {
      ui.label({ text = summary, fontSize = FS.small, color = CL.muted }),
    }),
  }
  if bodyVisible("sysmon") then
    if not st then
      table.insert(children, emptyState("alert-triangle", "系统监控不可用"))
    else
      if #sysmon.cpuHist > 1 then
        table.insert(children, ui.graph({
          values = sysmon.cpuHist, height = 36, color = "primary", fillOpacity = 0.18,
          onPointerMove = "onGraphMove", onPointerLeave = "onGraphLeave",
        }))
      end
      local line1
      if sysmon.hover and sysmon.cpuHist[sysmon.hover] then
        local ago = #sysmon.cpuHist - sysmon.hover
        line1 = string.format("CPU %.0f%%（%d 秒前）", sysmon.cpuHist[sysmon.hover] * 100, ago)
      else
        line1 = string.format("CPU %.0f%%", (st.cpu and st.cpu.usagePercent) or 0)
        if st.cpu and st.cpu.tempC then line1 = line1 .. string.format("  %.0f°C", st.cpu.tempC) end
        if st.ram then line1 = line1 .. string.format("  内存 %.0f%%", st.ram.usagePercent or 0) end
      end
      table.insert(children, ui.label({ text = line1, fontSize = FS.body }))
      if st.ram and st.ram.totalMb and st.ram.totalMb > 0 then
        table.insert(children, ui.progress({ progress = (st.ram.usedMb or 0) / st.ram.totalMb, fill = "primary", height = 4, radius = 2 }))
      end
      if st.gpu and st.gpu.usagePercent then
        local g = string.format("GPU %.0f%%", st.gpu.usagePercent)
        if st.gpu.tempC then g = g .. string.format("  %.0f°C", st.gpu.tempC) end
        if st.gpu.vramUsedBytes and st.gpu.vramTotalBytes and st.gpu.vramTotalBytes > 0 then
          g = g .. string.format("  显存 %.0f%%", 100 * st.gpu.vramUsedBytes / st.gpu.vramTotalBytes)
        end
        table.insert(children, ui.label({ text = g, fontSize = FS.caption, color = CL.muted }))
      end
      if st.net then
        table.insert(children, ui.label({
          text = string.format("网络 ↓%s ↑%s", fmtBps(st.net.rxBytesPerSec), fmtBps(st.net.txBytesPerSec)),
          fontSize = FS.caption, color = CL.muted,
        }))
      end
      if st.loadAvg then
        table.insert(children, ui.label({
          text = string.format("负载 %.2f  %.2f  %.2f", st.loadAvg[1] or 0, st.loadAvg[2] or 0, st.loadAvg[3] or 0),
          fontSize = FS.small, color = CL.muted,
        }))
      end
      if noctalia.diskStats then
        local dsk = sysmon.disk
        if dsk and dsk.usagePercent then
          table.insert(children, ui.label({ text = string.format("磁盘 %.0f%%", dsk.usagePercent), fontSize = FS.caption, color = CL.muted }))
        end
      end
    end
    if #sysmon.procs > 0 then
      for _, p in ipairs(sysmon.procs) do
        table.insert(children, ui.row({ gap = SP.row }, {
          ui.label({ text = p.name, fontSize = FS.caption, flexGrow = 1, maxLines = 1 }),
          ui.label({ text = string.format("%.0f%%", p.cpu), fontSize = FS.caption, color = CL.muted }),
        }))
      end
    end
  end
  return cardShell("sysmon", children, 310)
end

-- ============ 卡 6：最近文件（GTK recently-used.xbel） ============
local recent = { list = {}, ok = false, loaded = false, tick = 0 }

local function recentSig(list)
  local s = tostring(#list)
  for _, r in ipairs(list) do
    s = s .. "|" .. r.path
  end
  return s
end

-- XML 实体解码：href 里的路径可能含 &amp; 等（&amp; 必须最后解，避免二次解码）
local function xmlUnescape(s)
  local function cp(n, base)
    local c = tonumber(n, base)
    if c and c > 0 and c < 0x110000 and utf8 and utf8.char then return utf8.char(c) end
    return "?"
  end
  s = s:gsub("&#x(%x+);", function(n) return cp(n, 16) end)
  s = s:gsub("&#(%d+);", function(n) return cp(n, 10) end)
  return (s:gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"))
end

local function refreshRecent()
  -- grep -o 逐条取出 bookmark 标签，Lua 侧再按属性名取值（不依赖属性顺序）
  query("recent", [[f="$HOME/.local/share/recently-used.xbel"; [ -f "$f" ] || exit 0; grep -o '<bookmark [^>]*>' "$f" || true]], function(res)
    local prevSig = recentSig(recent.list) .. tostring(recent.ok) .. tostring(recent.loaded)
    local list = {}
    if res.exitCode == 0 then
      for line in ((res.stdout or "") .. "\n"):gmatch("([^\n]*)\n") do
        local href = line:match('href="([^"]*)"')
        if href and href:sub(1, 7) == "file://" then
          local visited = line:match('visited="([^"]*)"') or ""
          local path = noctalia.string.urlDecode(xmlUnescape(href:sub(8)))
          table.insert(list, { ts = visited, path = path })
        end
      end
      table.sort(list, function(x, y) return x.ts > y.ts end)
      local out = {}
      for i = 1, math.min(#list, RECENT_COUNT) do out[i] = list[i] end
      recent.list = out
      recent.ok = true
    else
      recent.ok = false
    end
    recent.loaded = true
    if recentSig(recent.list) .. tostring(recent.ok) .. tostring(recent.loaded) ~= prevSig then markDirty("recent") end
  end)
end

local function openRecent(path)
  noctalia.runAsync("xdg-open " .. shq(path))
  panel.close()
end

local function openRecentDir(path)
  local dir = dirname(path)
  if dir ~= "" then noctalia.runAsync("xdg-open " .. shq(dir)) end
end

-- 最近文件右键菜单（只能从 button 的 onRightClick 打开）
local recentMenu = { path = "" }

function openRecentMenu(r)
  recentMenu.path = r.path
  panel.openContextMenu({
    items = {
      { kind = "header", label = trunc(basename(r.path), 60) },
      { id = "open", label = "打开" },
      { id = "reveal", label = "打开所在目录" },
      { kind = "separator" },
      { id = "copy", label = "复制路径" },
    },
    onActivate = "onRecentMenuAction",
  })
end

function onRecentMenuAction(actionId, _ctx)
  local path = recentMenu.path
  if path == "" then return end
  if actionId == "open" then
    openRecent(path)
  elseif actionId == "reveal" then
    openRecentDir(path)
  elseif actionId == "copy" then
    noctalia.copyToClipboard(path, "text/plain")
  end
end

local function recentCard()
  local children = {
    cardHeader("recent", "file-text", "最近文件", {
      ui.label({ text = (#recent.list > 0) and (#recent.list .. " 条") or "", fontSize = FS.small, color = CL.muted }),
    }),
  }
  if bodyVisible("recent") then
    if recent.loaded and not recent.ok then
      table.insert(children, emptyState("alert-triangle", "读取最近文件失败"))
    elseif #recent.list == 0 then
      table.insert(children, emptyState("file-text", recent.loaded and "暂无记录" or "载入中…"))
    else
      for i, r in ipairs(recent.list) do
        table.insert(children, listRow("rec-" .. i, false, function() openRecent(r.path) end, {
          ui.glyph({ name = "file-text", size = 16, color = CL.muted }),
          ui.column({ gap = 1, flexGrow = 1 }, {
            ui.label({ text = basename(r.path), fontSize = FS.body, maxLines = 1 }),
            ui.label({ text = dirname(r.path), fontSize = FS.small, color = CL.muted, maxLines = 1 }),
          }),
          ui.button({
            glyph = "folder", variant = "ghost", controlSize = "sm", tooltip = "打开所在目录（右键更多）",
            onClick = function() openRecentDir(r.path) end,
            onRightClick = function() openRecentMenu(r) end,
          }),
        }, trunc(r.path, 120)))
      end
    end
  end
  return cardShell("recent", children, math.min(280, math.max(48, #recent.list * 58)))
end

-- ============ 卡 7：临时笔记（多便签 + 预览） ============
local note = {
  dir = "", path = "", buffer = "", rev = 0, dirty = false, idle = 0,
  stamp = "", pendingClear = false, pendingDelete = false, preview = false,
  files = {}, sel = 0, failures = 0, retryAt = 0, broken = false, editFocus = false, loaded = false,
}

local function noteStatePath() return noctalia.pluginDataDir() .. "/note_state.json" end

local function saveNote()
  if not note.dirty or note.path == "" then
    note.idle = 0
    return
  end
  local ok, err = noctalia.writeFile(note.path, note.buffer)
  note.idle = 0
  if ok then
    note.dirty = false
    note.failures = 0
    note.stamp = noctalia.formatTime("%H:%M:%S")
    markDirty("note")
  else
    -- 退避重试：首次失败提示一次，之后 2^n 秒拉长间隔，避免每 2 秒弹错
    note.failures = note.failures + 1
    note.retryAt = noctalia.nowMs() + 2 ^ math.min(note.failures, 5) * 1000
    if note.failures == 1 then
      noctalia.notifyError("临时笔记", err or "写入失败")
    end
  end
end

-- 自动保存节拍：编辑停止 ~2 秒后落盘，失败按退避间隔重试
local function noteTick()
  if not note.dirty then return end
  note.idle = note.idle + 1
  if note.idle >= 2 and noctalia.nowMs() >= note.retryAt then
    saveNote()
  end
end

local function persistNoteState()
  if note.path ~= "" then
    local enc = noctalia.json.encode({ file = basename(note.path) })
    if enc then noctalia.writeFile(noteStatePath(), enc) end
  end
end

local function scanNotes()
  local out = {}
  local names = noctalia.listDir(note.dir) or {}
  for _, n in ipairs(names) do
    if endsWith(n, ".md") then table.insert(out, n) end
  end
  table.sort(out)
  return out
end

local function openNoteFile(name)
  if not name or name == "" then return end
  note.path = note.dir .. "/" .. name
  local content = noctalia.readFile(note.path)
  note.buffer = content or ""
  note.dirty = false
  note.rev = note.rev + 1
  note.pendingClear = false
  note.pendingDelete = false
  note.failures = 0
  note.retryAt = 0
  note.editFocus = false
  note.stamp = ""
end

local function createNewNote()
  local n = 2
  local existing = {}
  for _, f in ipairs(note.files) do existing[f] = true end
  local name = "便签-2.md"
  while existing[name] do
    n = n + 1
    name = "便签-" .. n .. ".md"
  end
  local ok, err = noctalia.writeFile(note.dir .. "/" .. name, "")
  if not ok then
    noctalia.notifyError("临时笔记", err or "无法新建便签")
    return nil
  end
  return name
end

function onNoteSwitch(value)
  local idx = tonumber(value)
  if idx == nil then return end
  saveNote()
  if note.dirty then return end -- 保存失败时保留缓冲，不切走
  persistNoteState()
  -- selectedIndex 假定 0 基；最后一项是"＋ 新建便签"
  if idx >= #note.files then
    local name = createNewNote()
    if name then
      note.files = scanNotes()
      for i, f in ipairs(note.files) do
        if f == name then note.sel = i - 1 end
      end
      openNoteFile(name)
    end
  else
    local name = note.files[idx + 1]
    if name then
      note.sel = idx
      openNoteFile(name)
    end
  end
  persistNoteState()
  render("note")
end

function onNoteEdited(value)
  activeCard = "note"
  note.buffer = value or ""
  note.dirty = true
  note.idle = 0
end

function onTogglePreview()
  note.preview = not note.preview
  render("note")
end

function onClearClick() note.pendingClear = true render("note") end
function onClearConfirm()
  note.buffer = ""
  note.dirty = true
  note.rev = note.rev + 1
  note.pendingClear = false
  saveNote()
  render("note")
end
function onClearCancel() note.pendingClear = false render("note") end

-- 右键垃圾桶：删除当前便签（保留至少一份）
function openNoteMenu()
  panel.openContextMenu({
    items = {
      { id = "clear", label = "清空内容" },
      { kind = "separator" },
      { id = "delete", label = "删除这份便签", enabled = #note.files > 1 },
    },
    onActivate = "onNoteMenuAction",
  })
end

function onNoteMenuAction(actionId, _ctx)
  if actionId == "clear" then
    note.pendingDelete = false
    note.pendingClear = true
  elseif actionId == "delete" then
    note.pendingClear = false
    note.pendingDelete = true
  end
  render("note")
end

function onDeleteConfirm()
  note.pendingDelete = false
  local path = note.path
  if path == "" then return end
  local ok, err = noctalia.removeFile(path)
  if not ok then
    noctalia.notifyError("临时笔记", err or "删除失败")
    render("note")
    return
  end
  note.files = scanNotes()
  local target = note.files[1]
  if target then
    note.sel = 0
    openNoteFile(target)
  else
    local name = createNewNote()
    if name then
      note.files = scanNotes()
      for i, f in ipairs(note.files) do
        if f == name then note.sel = i - 1 end
      end
      openNoteFile(name)
    end
  end
  persistNoteState()
  render("note")
end
function onDeleteCancel() note.pendingDelete = false render("note") end

local function noteCard()
  if not note.loaded then
    return cardShell("note", { cardHeader("note", "note", "随手记"), emptyState("pencil", "准备笔记…") }, 48)
  end
  local statusText
  if note.broken then
    return cardShell("note", {
      cardHeader("note", "note", "临时笔记", {
        ui.label({ text = "目录不可用", fontSize = FS.small, color = CL.muted }),
      }),
      emptyState("alert-triangle", "笔记目录不可用"),
    }, 48)
  end
  if note.dirty then
    statusText = "输入中…"
  elseif note.stamp ~= "" then
    statusText = "已保存 " .. note.stamp
  else
    statusText = "就绪"
  end
  local extras = {
    ui.label({ text = statusText, fontSize = FS.small, color = CL.muted }),
  }
  if note.pendingClear then
    extras[#extras + 1] = ui.button({ text = "确认清空", variant = "destructive", controlSize = "sm", onClick = "onClearConfirm" })
    extras[#extras + 1] = ui.button({ glyph = "close", variant = "ghost", controlSize = "sm", onClick = "onClearCancel" })
  elseif note.pendingDelete then
    extras[#extras + 1] = ui.button({ text = "确认删除", variant = "destructive", controlSize = "sm", onClick = "onDeleteConfirm" })
    extras[#extras + 1] = ui.button({ glyph = "close", variant = "ghost", controlSize = "sm", onClick = "onDeleteCancel" })
  else
    extras[#extras + 1] = ui.button({ glyph = note.preview and "pencil" or "eye", variant = "ghost", controlSize = "sm", tooltip = note.preview and "编辑" or "预览", onClick = "onTogglePreview" })
    extras[#extras + 1] = ui.button({
      glyph = "trash", variant = "ghost", controlSize = "sm",
      tooltip = "清空内容（右键删除整份）", onClick = "onClearClick", onRightClick = "openNoteMenu",
    })
  end
  local block = { cardHeader("note", "note", "随手记", extras) }
  if bodyVisible("note") then
    local opts = {}
    for _, f in ipairs(note.files) do table.insert(opts, f) end
    table.insert(opts, "＋ 新建便签")
    local body
    if note.preview then
      body = ui.column({ fill = "surface_variant/0.22", radius = 8, padding = 8 }, {
        ui.markdown({ text = note.buffer ~= "" and note.buffer or "_（空）_", width = 340 }),
      })
    elseif note.buffer:match("^%s*$") and not note.editFocus then
      -- 空便签：先显示可点击的提示（输入框在 frameVisible=false 时不渲染自己的 placeholder）
      body = ui.row({
        fill = "surface_variant/0.35", radius = RD.row, padding = SP.block, height = 200, align = "start",
        onClick = function() activeCard = "note" note.editFocus = true note.wantFocus = true render("note") end, tooltip = "点击开始输入",
      }, {
        ui.label({ text = "随手记点什么…", fontSize = FS.body, color = CL.muted }),
      })
    else
      -- frameVisible=false：不用输入框自带的高亮边框（圆角不受控、偏圆），
      -- 外框与预览模式保持同一规格（fill/radius 8/padding 8/height 240）
      body = ui.row({ fill = "surface_variant/0.35", radius = 8, padding = 8, height = 200, align = "stretch" }, {
        ui.input(focusOnce({
          key = "note-" .. note.rev,
          value = note.buffer,
          multiline = true,
          flexGrow = 1,
          frameVisible = false,
          focus = note.wantFocus or nil,
          placeholder = "随手记点什么…",
          onChange = "onNoteEdited",
        })),
      })
    end
    table.insert(block, ui.select({ options = opts, selectedIndex = note.sel, controlSize = "sm", onChange = "onNoteSwitch" }))
    table.insert(block, body)
  end
  note.wantFocus = false
  return cardShell("note", block, 240)
end

-- ============ 生命周期 ============
local cardBuilders = {
  search = searchCard,
  media = mediaCard,
  note = noteCard,
  wins = winsCard,
  timer = timerCard,
  sysmon = sysCard,
  recent = recentCard,
}

-- 专注是临时工作状态；退出时恢复之前展开的卡片，不破坏布局。
local function setFocusMode(value)
  if value == focusMode then return end
  if value then
    focusRestore = {}
    for key in pairs(CARD_KEYS) do focusRestore[key] = open[key] end
    if not open[activeCard] then
      for _, key in ipairs(order) do if open[key] then activeCard = key break end end
    end
    for key in pairs(CARD_KEYS) do setCardOpen(key, key == activeCard) end
  else
    for key in pairs(CARD_KEYS) do setCardOpen(key, focusRestore and focusRestore[key] == true) end
    focusRestore = nil
  end
  focusMode = value
  render("layout")
  persistLayout()
end

local function setLayout(mode)
  focusMode, focusRestore = false, nil
  for key in pairs(CARD_KEYS) do
    setCardOpen(key, mode == "all" or (mode == "daily" and (key == "search" or key == "media" or key == "note")))
  end
  render("layout")
  persistLayout()
end

local function toolbar()
  local count = 0
  for _, key in ipairs(order) do if open[key] then count = count + 1 end end
  local subtitle = focusMode and "一次只做一件事" or "把常用的事，放在手边"
  local status = timer.running and (timer.adopted and "后台计时中" or ("计时 " .. fmtSec(timer.remain)))
    or (media.ok and media.status == "Playing" and "音乐播放中" or (count .. " 项展开"))
  local children = {
    ui.row({ align = "center", gap = 10 }, {
      ui.row({ width = 38, height = 38, fill = "primary/0.14", radius = 12, align = "center", justify = "center" }, {
        ui.glyph({ name = "layout-grid", size = 22, color = "primary" }),
      }),
      ui.column({ gap = 3, flexGrow = 1 }, {
        ui.label({ text = "随手工作台", fontSize = 19, fontWeight = "bold" }),
        ui.label({ text = subtitle, fontSize = FS.caption, color = CL.muted }),
      }),
      ui.button({ key = "customize", glyph = customizing and "check" or "adjustments-horizontal", controlSize = "sm",
        variant = customizing and "secondary" or "ghost", tooltip = customizing and "完成整理" or "整理卡片：置顶、排序、动效",
        onClick = function() customizing = not customizing render() end }),
    }),
    ui.row({ gap = 6, align = "center" }, {
      ui.button({ key = "daily", text = "常用", glyph = "layout-grid", controlSize = "sm", flexGrow = 1,
        variant = "secondary", tooltip = "展开搜索、媒体和笔记", onClick = function() setLayout("daily") end }),
      ui.button({ key = "focus", text = "专注", glyph = "focus-2", controlSize = "sm", flexGrow = 1,
        variant = focusMode and "primary" or "ghost", tooltip = focusMode and "退出并恢复原布局" or "只展开当前卡片，切换时自动收起其他卡片",
        onClick = function() setFocusMode(not focusMode) end }),
      ui.button({ key = "collapse", text = "收起", glyph = "chevrons-up", controlSize = "sm", flexGrow = 1,
        variant = "ghost", tooltip = "全部收起，只看摘要", onClick = function() setLayout("none") end }),
    }),
    ui.row({ align = "center", justify = "space_between" }, {
      ui.label({ text = noctalia.formatTime("%m / %d  ·  %H:%M"), fontSize = FS.small, color = CL.muted }),
      ui.label({ text = status, fontSize = FS.small, color = "primary" }),
    }),
  }
  if customizing then
    children[#children + 1] = ui.row({ gap = 6, align = "center" }, {
      ui.label({ text = "拖动图标排序 · 图钉置顶", fontSize = FS.small, flexGrow = 1, color = CL.muted }),
      ui.button({ text = "全展开", variant = "ghost", controlSize = "sm", onClick = function() setLayout("all") end }),
      ui.button({ glyph = "settings", variant = "ghost", controlSize = "sm", tooltip = "动效及插件设置",
        onClick = function() noctalia.openSettings() end }),
    })
  end
  return ui.column({ key = "toolbar", padding = 14, gap = 12, radius = 18,
    fill = "primary/0.06", border = "primary/0.15", borderWidth = 1 }, children)
end

render = function(key)
  if not panelVisible then return end
  if key == nil then
    for k in pairs(CARD_KEYS) do dirtyCards[k] = true end
  elseif CARD_KEYS[key] then
    dirtyCards[key] = true
  end
  local blocks = {}
  local pinCount = 0
  for _, k in ipairs(order) do if pinned[k] then pinCount = pinCount + 1 end end
  -- 单一滚动轴里的两个分区；跨组拖放时跟随目标组。
  for _, pinGroup in ipairs({ true, false }) do
    local count = pinGroup and pinCount or (#order - pinCount)
    if count > 0 then
      blocks[#blocks + 1] = ui.row({ key = pinGroup and "pinned-label" or "tools-label", paddingH = 3, align = "center", gap = 6 }, {
        ui.glyph({ name = pinGroup and "pin" or "layout-grid", size = 12, color = CL.muted }),
        ui.label({ text = pinGroup and "置顶" or "工具", fontSize = FS.small, color = CL.muted, flexGrow = 1 }),
        ui.label({ text = tostring(count), fontSize = FS.small, color = CL.muted }),
      })
      for _, k in ipairs(order) do
        if (pinned[k] == true) == pinGroup then
          if not cardCache[k] or (dirtyCards[k] and (next(folds) == nil or motionNodes[k] == nil)) then
            cardCache[k] = cardBuilders[k]()
            dirtyCards[k] = nil
          end
          local card = cardCache[k]
          if customizing then
            card = ui.dropZone({ key = "dz-" .. k, accepts = { "card" }, value = "before|" .. k,
              onDrop = "onCardDrop", direction = "column" }, { card })
          end
          blocks[#blocks + 1] = card
        end
      end
    end
  end
  if customizing then
    blocks[#blocks + 1] = ui.dropZone({ key = "dz-end", accepts = { "card" }, value = "end",
      onDrop = "onCardDrop", height = 6, expandOnDrag = true, hitSlop = 30 })
  end
  cachedTree = ui.column({ key = "sidebar", flexGrow = 1, gap = SP.stack }, {
    toolbar(),
    ui.scroll({ key = "cards", flexGrow = 1 }, { ui.column({ gap = SP.stack, align = "stretch" }, blocks) }),
    ui.label({ text = focusMode and "专注模式 · 点击另一张卡片即可切换" or "点击标题收展 · 右上角整理卡片", fontSize = FS.small, color = CL.muted, textAlign = "center" }),
  })
  stateDirty = next(dirtyCards) ~= nil
  submitTree()
end

local function initializeNotes()
  -- 保存失败后的未落盘缓冲优先，绝不在重开时被磁盘旧内容覆盖。
  if note.dirty then note.loaded = true markDirty("note") return end
  -- 笔记目录与迁移（目录不可用时标记 broken，卡片显示错误态而不是让 onOpen 崩溃）
  note.dir = noctalia.expandPath(NOTES_DIR)
  note.broken = false
  local dirOk, dirErr = noctalia.mkdirAll(note.dir)
  if dirOk then
    note.files = scanNotes()
    if #note.files == 0 then
      local old = noctalia.expandPath("~/Documents/scratchpad.md")
      if noctalia.fileExists(old) then
        noctalia.renameFile(old, note.dir .. "/便签.md")
      end
      note.files = scanNotes()
    end
    if #note.files == 0 then
      local wOk, wErr = noctalia.writeFile(note.dir .. "/便签.md", "")
      if wOk then
        note.files = scanNotes()
      else
        note.broken = true
        noctalia.notifyError("临时笔记", wErr or "无法写入笔记目录")
      end
    end
  else
    note.broken = true
    noctalia.notifyError("临时笔记", dirErr or "无法创建笔记目录")
  end
  if not note.broken then
    local target = note.files[1]
    local saved = noctalia.readFile(noteStatePath())
    if saved then
      local state = noctalia.json.decode(saved)
      if type(state) == "table" and state.file then
        for _, f in ipairs(note.files) do
          if f == state.file then target = f end
        end
      end
    end
    note.sel = 0
    for i, f in ipairs(note.files) do
      if f == target then note.sel = i - 1 end
    end
    openNoteFile(target)
  end
  note.loaded = true
  markDirty("note")
end

local function restoreLayout()
  if layoutLoaded then return end
  layoutLoaded = true
  local raw = noctalia.readFile(layoutPath())
  local st = raw and noctalia.json.decode(raw)
  if type(st) ~= "table" then return end
  for k in pairs(CARD_KEYS) do
    if type(st.open) == "table" and type(st.open[k]) == "boolean" then open[k] = st.open[k] end
    pinned[k] = type(st.pinned) == "table" and st.pinned[k] == true or false
  end
  if type(st.order) == "table" then
    local seen, revived = {}, {}
    for _, k in ipairs(st.order) do
      if type(k) == "string" and CARD_KEYS[k] and not seen[k] then seen[k] = true revived[#revived + 1] = k end
    end
    for _, k in ipairs(order) do if not seen[k] then revived[#revived + 1] = k end end
    order = revived
  end
  if type(st.activeCard) == "string" and CARD_KEYS[st.activeCard] then activeCard = st.activeCard end
  focusMode = st.focusMode == true
  if focusMode then
    focusRestore = {}
    for k in pairs(CARD_KEYS) do
      focusRestore[k] = type(st.focusRestore) == "table" and st.focusRestore[k] == true or false
      open[k] = k == activeCard
    end
  end
end

-- 数据回调只标记对应卡片；动效中不重排列表，结束后合并成一次提交。
function onFrameTick(_deltaMs)
  if not panelVisible or not cachedTree then panel.setNeedsFrameTick(false) return end
  local now, changed = noctalia.nowMs(), false
  for key, m in pairs(folds) do
    local progress, node = foldValue(key), motionNodes[key]
    if node == nil then
      -- 卡片被重建过、已经没有可动画的节点：立刻结束这次折叠并重建，绝不动画一棵不在画面里的树。
      folds[key] = nil
      markDirty(key)
      changed = true
    else
      local height = math.max(0.1, node.height * progress)
      local gap = SP.block * progress
      local isVis = progress > 0.005
      if node.viewport.props.height ~= height or node.viewport.props.visible ~= isVis or node.shell.props.gap ~= gap then
        node.viewport.props.height, node.viewport.props.visible, node.shell.props.gap = height, isVis, gap
        changed = true
      end
      if now - m.t0 >= m.duration then
        folds[key] = nil
        node.viewport.props.height = open[key] and node.height or 0.1
        node.viewport.props.visible = open[key]
        node.shell.props.gap = open[key] and SP.block or 0
        changed = true
      end
    end
  end
  if next(folds) == nil then
    if next(dirtyCards) ~= nil then stateDirty = true end
    if #bootQueue > 0 and now >= bootAt then
      local task = table.remove(bootQueue, 1)
      task()
      bootAt = now + 16
      if #bootQueue == 0 then bootReady = true end
    end
    -- 折叠结束的那一帧：先把最终画面平滑送出去，整卡重建留到下一帧。
    -- 否则收尾会在同一帧里连带一次全量重建，看起来就是"最后一下跳过去"。
    if changed then
      submitTree()
      settleAt = now + 24 -- 之后再把攒下的数据更新并进一次重建，别和动画终点抢同一帧
    elseif stateDirty and now >= settleAt then
      render("pending")
    end
    if layoutSaveAt and now >= layoutSaveAt then flushLayout() end
  elseif changed then
    submitTree()
  end
  if changed then lastMotionSubmit = now end
  panel.setNeedsFrameTick(next(folds) ~= nil or stateDirty or #bootQueue > 0 or layoutSaveAt ~= nil)
end

noctalia.setUpdateInterval(1000)

function onOpen(_context)
  generation = generation + 1
  restoreLayout()
  panelVisible = true
  clockMinute = noctalia.formatTime("%H:%M")
  focusEdges = {}
  folds, motionNodes, cardCache, dirtyCards = {}, {}, {}, {}
  customizing = false
  search.text, search.results, search.cmdText, search.cmdMode = "", {}, nil, false
  search.rev, search.wantFocus = search.rev + 1, open.search
  bootReady = false
  -- 先交付首帧，再错峰加载。缓存内容立即可用，不等笔记/进程读取。
  bootAt = noctalia.nowMs() + 280
  bootQueue = {
    initializeNotes,
    function() if not apps.loaded or noctalia.nowMs() - apps.loadedAt > 600000 then refreshApps() end end,
    function() timerAdopt() refreshMedia() end,
    refreshWins,
    refreshRecent,
  }
  render()
  panel.setWantsSecondTicks(true)
  wake()
end

function onClose()
  panelVisible = false
  generation = generation + 1
  artGen = artGen + 1
  focusEdges = {}
  folds = {}
  bootQueue = {}
  bootReady = false
  panel.setNeedsFrameTick(false)
  panel.setWantsSecondTicks(false)
  if layoutSaveAt then flushLayout() end
  saveNote()
  persistNoteState()
end

function onExit(_signal, _reason)
  if layoutSaveAt then flushLayout() end
  saveNote()
  persistNoteState()
end

-- IPC 也用于快捷键绑定与无鼠标回归；不暴露任意执行或文件路径。
function onIpc(event, payload)
  if not panelVisible then return end
  if event == "toggle" and CARD_KEYS[payload] then toggleCard(payload)
  elseif event == "layout" and (payload == "daily" or payload == "all" or payload == "none") then setLayout(payload)
  elseif event == "focus" then setFocusMode(not focusMode)
  elseif event == "customize" then customizing = not customizing render()
  elseif event == "pin" and CARD_KEYS[payload] then pinned[payload] = not pinned[payload] render() persistLayout()
  end
end

function update()
  if not panelVisible or not bootReady or next(folds) ~= nil then return end
  updateTick = updateTick + 1
  winsTick = winsTick + 1
  mediaTick = mediaTick + 1
  -- 媒体：有内容时每秒查询；完全空闲时 3 秒一次（回调只在实际变化时标脏）
  if media.ok or mediaTick % 3 == 1 then refreshMedia() end
  -- 窗口列表：展开时每秒，收起时 3 秒一次（收起态只需要数量）
  if open.wins or winsTick % 3 == 1 then refreshWins() end
  recent.tick = recent.tick + 1
  if recent.tick % 10 == 1 then refreshRecent() end
  -- 计时器推进；接管中的后台计时每 3 秒探测一次是否已结束
  if timer.running and not timer.adopted then
    local rem = (timer.deadlineMs - noctalia.nowMs()) / 1000
    if rem <= 0 then
      timer.running = false
      timer.done = true
      timer.remain = 0
      markDirty("timer")
    else
      timer.remain = rem
      markDirty("timer") -- 收起时顶部计时摘要也持续更新
    end
  elseif timer.adopted and updateTick % 3 == 1 then
    timerProbe()
  end
  -- 系统采样：宿主按自己的轮询周期刷新，只在新样本到达时入曲线
  sysmon.tick = sysmon.tick + 1
  local st = noctalia.systemStats()
  if st then
    local prevCpu = sysmon.stats and sysmon.stats.cpu and sysmon.stats.cpu.usagePercent
    local prevRam = sysmon.stats and sysmon.stats.ram and sysmon.stats.ram.usagePercent
    sysmon.stats = st
    if st.sampledAtMs == nil or st.sampledAtMs ~= sysmon.lastSampleMs then
      sysmon.lastSampleMs = st.sampledAtMs or sysmon.lastSampleMs
      pushHist(sysmon.cpuHist, ((st.cpu and st.cpu.usagePercent) or 0) / 100)
    end
    if open.sysmon then
      markDirty("sysmon") -- 曲线每秒移动
    else
      -- 收起态只有一行摘要：取整有变化才重绘
      local cpuNow = math.floor((st.cpu and st.cpu.usagePercent) or 0)
      local ramNow = math.floor((st.ram and st.ram.usagePercent) or 0)
      if cpuNow ~= math.floor(prevCpu or -1) or ramNow ~= math.floor(prevRam or -1) then
        markDirty("sysmon")
      end
    end
  end
  if open.sysmon and sysmon.tick % 5 == 1 then refreshProcs() end
  if open.sysmon and (sysmon.disk == nil or sysmon.tick % 30 == 1) and noctalia.diskStats then
    sysmon.disk = noctalia.diskStats(noctalia.expandPath("~/"))
    markDirty("sysmon")
  end
  -- 笔记自动保存（编辑停顿后的落盘 + 失败退避重试）
  noteTick()
  -- 分钟变化才更新时钟；其余由数据回调按需提交。
  local minute = noctalia.formatTime("%H:%M")
  if minute ~= clockMinute then clockMinute = minute stateDirty = true end
  if stateDirty then wake() end
end
