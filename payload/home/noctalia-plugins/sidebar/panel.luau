--!nonstrict
-- pang/sidebar v2.2 — 布局稳定优先 / 数据安全 / 自由时长计时器（媒体卡已按用户要求移除）
-- 卡片：搜索 / 窗口 / 计时器 / 系统 / 最近文件。
-- 默认正文即时收展，只淡入箭头；柔和模式短高度过渡。输入收起时卸载以解除焦点。
-- 卡片头部/列表行/空状态共用构件；搜索支持 Alt+↑↓ 选择、
--       Enter 打开选中项；窗口/最近加右键菜单；曲线可悬停读数；
--       修正异步竞态与错误路径（应用列表、计时器 pid、xbel 解析）。
-- plugin_api 32：容器 tooltip / panel.openContextMenu / ui.graph 指针回调。

-- ============ 通用小工具 ============
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function fmtSec(sec)
  sec = math.max(0, math.floor(sec + 0.999))
  if sec >= 3600 then
    return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor((sec % 3600) / 60), sec % 60)
  end
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
local function trunc(s, n)
  if utf8 and utf8.offset then
    local ok, pos = pcall(utf8.offset, s, n + 1)
    if ok then return pos and (s:sub(1, utf8.offset(s, n) - 1) .. "…") or s end
  end
  return s -- 无法确认 UTF-8 边界时不截断，避免中文乱码。
end
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
local SEARCH_LIMIT = tonumber(noctalia.getConfig("search_limit")) or 10
local RECENT_COUNT = tonumber(noctalia.getConfig("recent_count")) or 8

local MOTION = noctalia.getConfig("motion") or "light"
local render -- forward declaration
local updateToolbarStatus
local timer -- forward declaration：计时器状态（布局文件持久化 durSec，见 flushLayout）

-- 折叠状态 + 卡片顺序（可拖拽排序）：默认展开 搜索；顺序与折叠持久化到 panel_layout.json
local open = { search = true, wins = false, timer = false, sysmon = false, recent = false }
local order = { "search", "wins", "timer", "sysmon", "recent" }
local CARD_KEYS = { search = true, wins = true, timer = true, sysmon = true, recent = true }
local stateDirty = false    -- 性能：只在可见数据变化时重绘（空闲秒不重绘）
local winsTick = 0
local updateTick = 0

-- 宿主负责面板开场；插件不叠加整树透明度，软模式的高度仍会触发布局。
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
local motionMs = MOTION == "soft" and 220 or 0
local feedback = {} -- 轻量模式只淡入箭头；正文一次布局。
-- ease-out 首帧即可看到响应；不使用先慢后快的长缓入。
local function ease(x) return 1 - (1 - x) ^ 3 end
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
  -- 宿主仅在创建 Input 时读取 focus/value；缓存不保留过时的创建请求。
  for _, props in ipairs(focusEdges) do props.focus = nil end
  focusEdges = {}
end
local function foldValue(key)
  local m = folds[key]
  if not m then return open[key] and 1 or 0 end
  local x = math.min(1, math.max(0, (noctalia.nowMs() - m.t0) / m.duration))
  return m.from + (m.to - m.from) * ease(x)
end
local function bodyVisible(key)
  -- 隐藏不会 blur；收起输入卡片时真正移除输入框。
  if key == "search" or key == "timer" then return open[key] end
  return retainedBodies[key] or warmVisible[key] or open[key] or folds[key] ~= nil
end
local function setCardOpen(key, value)
  if not CARD_KEYS[key] or open[key] == value then return end
  local from = foldValue(key)
  open[key] = value
  if key == "search" or key == "timer" then markDirty(key) end
  local target = value and 1 or 0
  if MOTION == "light" then feedback[key] = noctalia.nowMs() wake() end
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
    -- 冷卡片也先从当前高度开始：只标记构造，不在 setLayout 循环里提交多次。
    warmVisible[key] = true
    markDirty(key)
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
      duration = math.max(80, motionMs * (value and 1 or 0.85) * math.sqrt(math.abs(target - from))) }
    lastMotionSubmit = 0
    wake()
  end
end

local function layoutPath() return noctalia.pluginDataDir() .. "/panel_layout.json" end
local layoutWarned = false
local function flushLayout()
  layoutSaveAt = nil
  local enc = noctalia.json.encode({ version = 2, order = order, open = open, pinned = pinned, focusMode = focusMode, focusRestore = focusRestore, activeCard = activeCard, timerSec = timer and timer.durSec or nil })
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
  if type(payload) ~= "string" or type(value) ~= "string" then return end
  if value ~= "end" and not value:match("^before|[^|]+$") then return end
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
    pinned[payload] = false
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
  if not motionNodes[key] or next(dirtyCards) ~= nil then
    render("layout")
  else
    if updateToolbarStatus then updateToolbarStatus() end
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
# XDG 优先级：用户应用可隐藏/覆盖系统同 ID；不以显示名称去重。
home=${XDG_DATA_HOME:-$HOME/.local/share}
dirs=${XDG_DATA_DIRS:-/usr/local/share:/usr/share}
oldIFS=$IFS
IFS=:
set -f
set -- "$home" $dirs
IFS=$oldIFS
for root do
  d="$root/applications"
  [ -d "$d" ] || continue
  find "$d" -type f -name '*.desktop' -exec awk -v root="$d/" -F'=' '
    function flush() {
      if (fname == "") return
      id=substr(fname,length(root)+1); gsub(/\//,"-",id)
      visible=(!hidden && !nd && type=="Application" && (exec!="" || dbus))
      if (localname!="") name=localname
      printf "%s\t%s\t%s\t%d\t%s\t%s\t%d\n", name,exec,icon,term,fname,id,visible
    }
    function reset() { name=""; localname=""; exec=""; icon=""; term=0; nd=0; hidden=0; dbus=0; type=""; s=0; fname=FILENAME }
    BEGIN { locale=ENVIRON["LC_ALL"]; if(locale=="") locale=ENVIRON["LC_MESSAGES"]; if(locale=="") locale=ENVIRON["LANG"]; sub(/\..*/,"",locale); sub(/@.*/,"",locale) }
    FNR==1 { flush(); reset() }
    END { flush() }
    { sub(/\r$/, "") }
    $0=="[Desktop Entry]" { s=1; next }
    /^\[/ { s=0; next }
    !s { next }
    $1=="Name" { name=substr($0,6) }
    $1=="Name[" locale "]" { localname=substr($0,index($0,"=")+1) }
    $1=="Exec" { exec=substr($0,6) }
    $1=="Icon" { icon=substr($0,6) }
    $1=="Terminal" && $2=="true" { term=1 }
    $1=="NoDisplay" && $2=="true" { nd=1 }
    $1=="Hidden" && $2=="true" { hidden=1 }
    $1=="DBusActivatable" && $2=="true" { dbus=1 }
    $1=="Type" { type=substr($0,6) }
  ' {} +
done
]]
  local started = query("apps", cmd, function(res)
    local seen = {}
    local list = {}
    for line in ((res.stdout or "") .. "\n"):gmatch("([^\n]*)\n") do
      if line ~= "" then
        local name, exec, icon, term, path, id, visible = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([01])$")
        if id and not seen[id] then
          seen[id] = true
          if visible == "1" and name ~= "" then
            list[#list + 1] = { name = name, exec = exec, icon = icon or "", terminal = term == "1",
              path = path, id = id:gsub("%.desktop$", "") }
          end
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
  -- GIO 正确处理 Desktop Entry 的转义、占位符、Terminal 与 D-Bus 激活。
  local started = noctalia.runAsync({ "gio", "launch", a.path }, function(res)
    if res.exitCode ~= 0 then noctalia.notifyError("搜索", "应用启动失败：" .. a.name) end
  end)
  if started then panel.close() else noctalia.notifyError("搜索", "无法启动应用") end
end

function onSearchChanged(value)
  if not panelVisible or not open.search then return end
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

-- Alt+↑↓ 选择结果；普通方向键留给输入框（宿主全局捕获不能按焦点放行）。
function onKey(chord, pressed)
  if pressed == false or pressed == "false" then return end
  if not panelVisible or not open.search or activeCard ~= "search" or search.cmdMode or #search.results == 0 then return end
  local c = tostring(chord or ""):lower()
  if c == "alt+down" then
    search.sel = math.min(#search.results, search.sel + 1)
    render("search")
  elseif c == "alt+up" then
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
      table.insert(children, ui.label({ text = "Alt+↑↓ 选择 · Enter 打开", fontSize = FS.small, color = CL.muted, textAlign = "end" }))
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

-- URI 的 + 是文件名本身，不是空格；只解码一次，拒绝坏转义和 NUL。
local function artDecode(value)
  if not value:find("%", 1, true) then
    if value:find("%z") then return nil end
    return value
  end
  if value:gsub("%%[%x][%x]", ""):find("%%") then return nil end
  local decoded = value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
  if decoded:find("%z") then return nil end
  return decoded
end

-- ============ 卡 2：窗口列表 ============
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

-- ============ 卡 3：计时器（独立进程发通知，面板关着也能提醒） ============
timer = {
  durSec = 1500, roundSec = 1500, remain = 1500, deadlineMs = 0, running = false, done = false, adopted = false,
  rev = 0, round = nil, pending = nil, error = nil,
}
local timerInput = { text = "", sec = nil, rev = 0 } -- 自由时长输入框的文案、解析结果与重键计数
local timerQueue, timerActive, timerProbeFlight = {}, nil, nil
local function timerPidPath() return noctalia.pluginDataDir() .. "/timer.pid" end

-- 自由时长解析：90 / 90s / 25m / 1h30m / 1:30（分:秒）/ 1:30:00（时:分:秒）；范围 1 秒～24 小时。
local function clampDur(v)
  if not v or v < 1 then return nil end
  return math.min(86400, math.floor(v))
end
local function parseDuration(text)
  local s = trim(text or ""):lower():gsub("%s+", "")
  if s == "" then return nil end
  s = s:gsub("小时", "h"):gsub("时", "h"):gsub("分钟", "m"):gsub("分", "m"):gsub("秒", "s")
  local h, m, sec = s:match("^(%d+):(%d+):(%d+)$")
  if h then
    h, m, sec = tonumber(h), tonumber(m), tonumber(sec)
    if m >= 60 or sec >= 60 then return nil end
    return clampDur(h * 3600 + m * 60 + sec)
  end
  local mm, ss = s:match("^(%d+):(%d+)$")
  if mm then
    mm, ss = tonumber(mm), tonumber(ss)
    if ss >= 60 then return nil end
    return clampDur(mm * 60 + ss)
  end
  if s:match("^%d+$") then return clampDur(tonumber(s) * 60) end
  local total, pos, matched = 0, 1, false
  while pos <= #s do
    local st, en, num, unit = s:find("(%d+)([hms])", pos)
    if not st or st ~= pos then return nil end
    local n = tonumber(num)
    if unit == "h" then total = total + n * 3600
    elseif unit == "m" then total = total + n * 60
    else total = total + n end
    pos, matched = en + 1, true
  end
  if not matched then return nil end
  return clampDur(total)
end

local function durationLabel(sec)
  sec = math.max(1, math.floor(tonumber(sec) or 0))
  local h, m, s = math.floor(sec / 3600), math.floor((sec % 3600) / 60), sec % 60
  local parts = {}
  if h > 0 then parts[#parts + 1] = h .. " 小时" end
  if m > 0 then parts[#parts + 1] = m .. " 分钟" end
  if s > 0 then parts[#parts + 1] = s .. " 秒" end
  return table.concat(parts, " ")
end

-- 控制队列不使用 query：关闭面板只能停止重绘，不能丢弃启停回调或放行第二条命令。
local function timerPump()
  if timerActive or #timerQueue == 0 then return end
  local job = table.remove(timerQueue, 1)
  timerActive = job
  local function finish(res)
    if timerActive ~= job then return end -- 同步失败/重复回调只结算一次
    timerActive = nil
    job.callback(res)
    timerPump()
  end
  local command = job.build()
  if not command then finish({ exitCode = 0, stdout = "STOPPED" }) return end
  local started = noctalia.runAsync(command, finish)
  if not started then finish({ exitCode = -1, stdout = "" }) end
end
local function timerSubmit(build, callback)
  timerQueue[#timerQueue + 1] = { build = build, callback = callback }
  timerPump()
end

-- v2 worker 不接收外部 kill：停止只撤销本轮记录，最多一秒后自行退出。
-- 每次检查/到期清理均持同一把锁且核对完整身份；旧轮次绝不清掉新记录。
local TIMER_WORKER = [=[
pf=$1; token=$2; secs=$3; msg=$4
stat=$(cat "/proc/$$/stat") || exit 1
rest=${stat##*) }; set -- $rest; shift 19; birth=$1
owned="v2 $$ $birth $token"
[ ! -L "$pf.lock" ] && [ ! -L "$pf" ] || exit 1
exec 9>>"$pf.lock" || exit 1
# /proc/uptime 为两位小数的单调时间；不能累减 sleep 次数，否则长计时会累积漂移。
clock_ticks() {
  read -r uptime unused < /proc/uptime || return 1
  whole=${uptime%.*}; fraction=${uptime#*.}
  ticks=$((whole * 100 + 1$fraction - 100))
}
deadline=''
while :; do
  flock -x 9 || exit 1
  current=$(cat "$pf" 2>/dev/null)
  [ "$current" = "$owned" ] || exit 0
  clock_ticks || exit 1
  [ -n "$deadline" ] || deadline=$((ticks + secs * 100))
  if [ "$ticks" -ge "$deadline" ]; then
    : > "$pf" || exit 1
    flock -u 9; exec 9>&-
    notify-send -a sidebar-panel 计时器 "$msg"
    exit
  fi
  flock -u 9
  sleep 1 || exit 1
done
]=]

-- shell 返回 LIVE/BUSY + pid/birth/token，GONE、CHANGED 或明确失败。
-- 旧纯数字记录只在完整匹配本插件旧命令后可接管，绝不凭 kill -0 杀任意 PID。
local function timerCommand(action, raw, birth, secs, request)
  local pf = timerPidPath()
  local legacyPrefix = "sh\n-c\necho $$ > " .. shq(pf) .. "; sleep "
  local legacyMiddle = '; notify-send -a sidebar-panel 计时器 "'
  local legacySuffix = ' 分钟到了"; rm -f ' .. shq(pf)
  local command = "pf=" .. shq(pf) .. "; action=" .. shq(action)
    .. "; expected=" .. shq(raw or "") .. "; expected_birth=" .. shq(birth or "")
    .. "; secs=" .. shq(tostring(secs or 0)) .. "; request=" .. shq(request or "")
    .. "; msg=" .. shq(durationLabel(tonumber(secs) or timer.durSec) .. "到了")
    .. "; legacy_prefix=" .. shq(legacyPrefix) .. "; legacy_middle=" .. shq(legacyMiddle)
    .. "; legacy_suffix=" .. shq(legacySuffix) .. "; worker=" .. shq(TIMER_WORKER) .. "\n"
  return command .. [=[
number() { case "$1" in ''|*[!0-9]*) return 1;; esac; }
proc_info() {
  [ "$pid" -gt 1 ] 2>/dev/null || return 1
  stat=$(cat "/proc/$pid/stat" 2>/dev/null) || return 1
  rest=${stat##*) }; set -- $rest
  [ "$#" -ge 20 ] || return 1
  case "$1" in Z|X) return 1;; esac
  group=$3; session=$4; shift 19; actual_birth=$1
}
load_record() {
  set -- $record
  if [ "$#" -eq 4 ] && [ "$1" = v2 ]; then
    pid=$2; birth=$3; token=$4
    number "$pid" && number "$birth" || return 2
    case "$token" in ''|*[!0-9-]*) return 2;; esac
    proc_info || return 1
    [ "$birth" = "$actual_birth" ] || return 1
    [ "$group" = "$pid" ] && [ "$session" = "$pid" ] || return 2
    cmd=$(tr '\000' '\n' < "/proc/$pid/cmdline" 2>/dev/null) || return 1
    marker=$(printf '\nsidebar-timer-v2\n%s\n%s' "$pf" "$token")
    nl='
'
    case "$cmd" in *"$marker$nl"*) return 0;; *) return 2;; esac
  fi
  [ "$#" -eq 1 ] && number "$1" || return 2
  pid=$1; token=legacy
  proc_info || return 1
  birth=$actual_birth
  [ "$group" = "$pid" ] && [ "$session" = "$pid" ] || return 2
  cmd=$(tr '\000' '\n' < "/proc/$pid/cmdline" 2>/dev/null) || return 1
  tail=${cmd#"$legacy_prefix"}; old_secs=${tail%%;*}
  tail=${tail#"$old_secs$legacy_middle"}; old_minutes=${tail%% *}
  number "$old_secs" && number "$old_minutes" || return 2
  [ "$cmd" = "$legacy_prefix$old_secs$legacy_middle$old_minutes$legacy_suffix" ] || return 2
}
report() { printf '%s %s %s %s\n' "$1" "$pid" "$birth" "$token"; }
[ ! -L "$pf" ] && [ ! -L "$pf.lock" ] || exit 3
exec 9>>"$pf.lock" || exit 3
flock -x -w 3 9 || exit 3
record=''
if [ -e "$pf" ]; then record=$(cat "$pf") || exit 3; fi
if [ "$action" != start ] && [ "$record" != "$expected" ]; then
  if [ -z "$record" ]; then printf 'GONE\n'; else printf 'CHANGED\n'; fi
  exit 0
fi
if [ -n "$record" ]; then load_record; state=$?; else state=1; fi
if [ "$state" -eq 2 ]; then printf 'UNSAFE\n'; exit 3; fi
if [ "$action" = probe ]; then
  if [ "$state" -eq 0 ]; then report LIVE; else printf 'GONE\n'; fi
  exit 0
fi
if [ "$action" = stop ]; then
  if [ "$state" -eq 0 ] && [ "$token" = legacy ]; then
    [ -z "$expected_birth" ] || [ "$birth" = "$expected_birth" ] || exit 3
    # 只杀已验证的旧 shell，不向负 PID/进程组发信号；再核对出生时间并等待退出。
    proc_info && [ "$actual_birth" = "$birth" ] || exit 3
    kill -TERM "$pid" 2>/dev/null || { proc_info && exit 3; }
    tries=0
    while proc_info && [ "$actual_birth" = "$birth" ]; do
      tries=$((tries + 1)); [ "$tries" -lt 40 ] || exit 3
      sleep 0.05
    done
  fi
  # v2 撤销授权即可，完全不使用 PID 信号。缺失/已结束也可安全停止。
  current=$(cat "$pf" 2>/dev/null)
  if [ "$current" = "$expected" ]; then : > "$pf" || exit 3; fi
  printf 'STOPPED\n'; exit 0
fi
if [ "$state" -eq 0 ]; then report BUSY; exit 4; fi
for tool in setsid flock sleep notify-send; do command -v "$tool" >/dev/null 2>&1 || exit 3; done
token="$request-$$"
# 子进程不能继承回调管道或锁；它取得独立锁后才开始倒计时。
setsid sh -c "$worker" sidebar-timer-v2 "$pf" "$token" "$secs" "$msg" 9>&- </dev/null >/dev/null 2>&1 &
pid=$!; tries=0
while :; do
  if proc_info && [ "$group" = "$pid" ] && [ "$session" = "$pid" ]; then break; fi
  tries=$((tries + 1)); [ "$tries" -lt 40 ] || exit 3
  sleep 0.025
done
birth=$actual_birth
printf 'v2 %s %s %s\n' "$pid" "$birth" "$token" > "$pf" || exit 3
report LIVE
]=]
end

local function timerIdentity(res)
  local kind, pid, birth, token = trim(res.stdout or ""):match("^(%u+) (%d+) (%d+) ([%w%-]+)$")
  if kind ~= "LIVE" and kind ~= "BUSY" then return nil end
  local raw = token == "legacy" and pid or ("v2 " .. pid .. " " .. birth .. " " .. token)
  return { raw = raw, birth = birth }, kind
end
local function timerChanged(rev)
  if rev ~= timer.rev then return false end
  timer.pending = nil
  markDirty("timer")
  return true
end
local function timerNewIntent(pending)
  timer.rev = timer.rev + 1
  timer.pending, timer.error = pending, nil
  return timer.rev
end

local function timerKill(rev)
  -- 捕获轮次对象，不在排队命令执行时读取“当前轮次”；启动完成后会填入该对象的身份。
  local round = timer.round
  if not round then round = { raw = trim(noctalia.readFile(timerPidPath()) or "") } end
  timerSubmit(function()
    if not round.raw or round.raw == "" then return nil end
    return timerCommand("stop", round.raw, round.birth)
  end, function(res)
    if not timerChanged(rev) then return end
    local status = trim(res.stdout or "")
    if res.exitCode ~= 0 or (status ~= "STOPPED" and status ~= "GONE") then
      timer.error = "停止失败，后台记录未改动；请重试"
      timer.round, timer.running, timer.adopted = round, true, true
    else
      timer.round = nil
    end
  end)
end
local function timerStart()
  if timer.running then return end
  if timer.remain <= 0 then timer.remain = timer.durSec end
  local secs = math.max(1, math.ceil(timer.remain))
  local rev = timerNewIntent("启动中…")
  local round = {}
  timer.round = round
  timer.roundSec = secs
  timer.running, timer.done, timer.adopted = true, false, false
  timer.deadlineMs = noctalia.nowMs() + secs * 1000
  local command = timerCommand("start", nil, nil, secs, tostring(math.floor(noctalia.nowMs())) .. "-" .. rev)
  timerSubmit(function()
    round.startedAt = noctalia.nowMs()
    return command
  end, function(res)
    local identity, kind = timerIdentity(res)
    if identity then round.raw, round.birth = identity.raw, identity.birth end
    if not timerChanged(rev) then return end
    if identity and kind == "LIVE" and res.exitCode == 0 then
      timer.deadlineMs = round.startedAt + secs * 1000
      timer.remain = math.max(0, (timer.deadlineMs - noctalia.nowMs()) / 1000)
      timer.running, timer.adopted = true, false
    else
      timer.running, timer.adopted = identity ~= nil, identity ~= nil
      timer.error = kind == "BUSY" and "后台已有计时，请先停止" or "启动失败，请检查计时器命令或后台记录"
    end
  end)
end
local function timerPause()
  if not timer.running then return end
  local rev = timerNewIntent("停止中…")
  timer.remain = timer.adopted and timer.durSec or math.max(0, (timer.deadlineMs - noctalia.nowMs()) / 1000)
  timer.running, timer.adopted, timer.done = false, false, false
  timerKill(rev)
end
local function timerReset()
  local rev = timerNewIntent("停止中…")
  timer.running, timer.done, timer.adopted = false, false, false
  timer.remain = timer.durSec
  timerKill(rev)
end

local function timerProbe()
  if not timer.adopted or timerProbeFlight then return end
  local round, rev = timer.round, timer.rev
  if not round then return end
  local flight = {}
  timerProbeFlight = flight
  local raw = round.raw
  timerSubmit(function() return timerCommand("probe", raw) end, function(res)
    if timerProbeFlight == flight then timerProbeFlight = nil end
    local identity = timerIdentity(res)
    -- 即使用户已经点停止，仍给被捕获的旧轮次补齐出生时间；只禁止它修改新界面。
    if identity and identity.raw == raw then round.birth = identity.birth end
    if timer.round ~= round or timer.rev ~= rev or not timer.adopted then return end
    if res.exitCode ~= 0 then
      timer.error = "无法核验后台计时；未停止任何进程"
    elseif identity then
      round.raw, round.birth = identity.raw, identity.birth
      timer.error = nil
    elseif trim(res.stdout or "") == "CHANGED" then
      -- 外部重载换了记录：下次只核对新快照，当前回调不能宣告新计时已结束。
      timer.round = { raw = trim(noctalia.readFile(timerPidPath()) or "") }
      timer.error = "后台记录已变化，正在重新核对"
    elseif trim(res.stdout or "") == "GONE" then
      timer.adopted, timer.running, timer.done = false, false, true
      timer.remain, timer.round, timer.error = 0, nil, nil
    else
      timer.error = "后台核验未返回有效结果，请重试"
    end
    markDirty("timer")
  end)
end
-- 关开面板不清 adopted；只有身份核验或明确的用户操作才改变接管状态。
local function timerAdopt()
  if timer.running or timer.pending then
    if timer.adopted then timerProbe() end
    return
  end
  local raw = trim(noctalia.readFile(timerPidPath()) or "")
  if raw == "" then return end
  timer.rev = timer.rev + 1
  timer.round = { raw = raw }
  timer.adopted, timer.running, timer.done, timer.error = true, true, false, nil
  markDirty("timer")
  timerProbe()
end

function onTimerSetSec(value) -- 预设与自由输入共用：只在未计时时修改时长
  if timer.running or timer.pending then return end
  local v = tonumber(value)
  if not v or v ~= v or v == math.huge or v == -math.huge or v < 1 then return end
  timer.durSec = math.min(86400, math.floor(v))
  timer.remain, timer.roundSec, timer.done, timer.error = timer.durSec, timer.durSec, false, nil
  render("timer")
  persistLayout()
end
function onTimerToggle()
  if timer.running then timerPause() else timerStart() end
  render("timer")
end
function onTimerReset() timerReset() render("timer") end
function onTimerDurInput(text)
  timerInput.text = tostring(text or "")
  timerInput.sec = parseDuration(timerInput.text)
  if timerInput.sec and not timer.running and not timer.pending then
    timer.durSec = timerInput.sec
    timer.remain, timer.roundSec, timer.done, timer.error = timer.durSec, timer.durSec, false, nil
    persistLayout()
  end
  render("timer")
end
function onTimerDurSubmit(text) -- Enter：按输入的时长直接开始
  onTimerDurInput(text)
  if timerInput.sec and not timer.running and not timer.pending then
    timerStart()
    render("timer")
  end
end
-- 运行中延长：安全停止当前轮后以「剩余 + 加时」重开一轮；接管中的后台计时剩余未知，不支持。
function onTimerExtend(addSec)
  addSec = tonumber(addSec) or 0
  if addSec < 1 or not timer.running or timer.pending or timer.adopted then return end
  local total = math.min(86400, math.floor(math.max(0, (timer.deadlineMs - noctalia.nowMs()) / 1000) + addSec))
  local rev = timerNewIntent("延长中…")
  local round = timer.round
  if not round then round = { raw = trim(noctalia.readFile(timerPidPath()) or "") } end
  timer.round = round
  timer.running = false
  timerSubmit(function()
    if not round.raw or round.raw == "" then return nil end
    return timerCommand("stop", round.raw, round.birth)
  end, function(res)
    if not timerChanged(rev) then return end
    local status = trim(res.stdout or "")
    if res.exitCode ~= 0 and status ~= "STOPPED" and status ~= "GONE" then
      -- 旧轮未停止：恢复运行态，剩余按原截止时刻重算，不宣称已延长
      timer.round, timer.running = round, true
      timer.remain = math.max(0, (timer.deadlineMs - noctalia.nowMs()) / 1000)
      timer.error = "延长失败：旧计时未停止，请重试"
      markDirty("timer")
      return
    end
    timer.round, timer.error = nil, nil
    timer.durSec, timer.remain, timer.roundSec = total, total, total
    timerStart()
    render("timer")
  end)
end
function timerIpc(payload) -- 无鼠标回归/快捷键通道：start:<时长> / stop / reset / extend:<秒>
  if type(payload) ~= "string" then return end
  local verb, arg = payload:match("^(%a+):?(.*)$")
  if verb == "start" then
    local sec = parseDuration(arg)
    if sec and not timer.running and not timer.pending then
      timer.durSec, timer.remain, timer.roundSec = sec, sec, sec
      timer.error = nil
      timerStart()
    end
  elseif verb == "stop" then
    timerPause()
  elseif verb == "reset" then
    timerReset()
  elseif verb == "extend" then
    onTimerExtend(tonumber(arg) or 0)
  end
  render("timer")
end

local function timerCard()
  local status, summary
  if timer.pending or timer.error then
    status = timer.pending or timer.error
    summary = status
  elseif timer.adopted then
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
    if timer.error then table.insert(children, emptyState("alert-triangle", timer.error)) end
    table.insert(children, ui.row({ align = "center", gap = SP.block }, {
      ui.label({ text = timer.adopted and "—:—" or fmtSec(timer.remain), fontSize = FS.hero, fontWeight = "bold", flexGrow = 1 }),
      ui.button({
        text = timer.adopted and "停止" or (timer.running and "暂停" or "开始"),
        variant = "primary", controlSize = "sm", onClick = "onTimerToggle",
      }),
      ui.button({ text = "重置", variant = "ghost", controlSize = "sm", enabled = not timer.adopted, onClick = "onTimerReset" }),
    }))
    if timer.running and not timer.adopted and timer.roundSec and timer.roundSec > 0 then
      local ratio = 1 - math.min(1, math.max(0, timer.remain / timer.roundSec))
      table.insert(children, ui.progress({ progress = ratio, fill = "primary", height = 4, radius = 2 }))
    end
    if timer.running and not timer.adopted then
      -- 运行中：快速加时（安全重启本轮，剩余时间 + 加时）
      table.insert(children, ui.row({ align = "center", gap = SP.block }, {
        ui.button({ text = "+1 分", variant = "ghost", controlSize = "sm", flexGrow = 1, onClick = function() onTimerExtend(60) end }),
        ui.button({ text = "+5 分", variant = "ghost", controlSize = "sm", flexGrow = 1, onClick = function() onTimerExtend(300) end }),
      }))
    elseif not timer.running then
      local function presetChip(sec, label)
        return ui.button({
          text = label, variant = (timer.durSec == sec) and "secondary" or "ghost", controlSize = "sm", flexGrow = 1,
          onClick = function() timerInput.text, timerInput.sec, timerInput.rev = "", nil, timerInput.rev + 1 onTimerSetSec(sec) end,
        })
      end
      table.insert(children, ui.row({ align = "center", gap = SP.block }, {
        presetChip(60, "1 分"), presetChip(180, "3 分"), presetChip(300, "5 分"), presetChip(600, "10 分"),
      }))
      table.insert(children, ui.row({ align = "center", gap = SP.block }, {
        presetChip(900, "15 分"), presetChip(1500, "25 分"), presetChip(2700, "45 分"), presetChip(3600, "1 时"),
      }))
      table.insert(children, ui.input({
        key = "timer-input-" .. timerInput.rev, value = timerInput.text,
        placeholder = "自由时长：90s · 25m · 1h30m · 1:30",
        onChange = "onTimerDurInput", onSubmit = "onTimerDurSubmit", submitOnEnter = true,
      }))
      local hint
      if timerInput.text == "" then
        hint = "当前 " .. fmtSec(timer.durSec)
      elseif timerInput.sec then
        hint = "= " .. fmtSec(timerInput.sec) .. " · 按 Enter 直接开始"
      else
        hint = "无法识别的时长，示例：90s / 25m / 1h30m / 1:30"
      end
      table.insert(children, ui.label({ text = hint, fontSize = FS.small, color = CL.muted }))
    end
  end
  local bodyH = timer.error and 288 or (timer.running and (timer.adopted and 60 or 112) or 218)
  return cardShell("timer", children, bodyH)
end

-- ============ 卡 4：系统一览 ============
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

-- ============ 卡 5：最近文件（GTK recently-used.xbel） ============
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
  if not s:find("&", 1, true) then return s end
  local function cp(n, base)
    local c = tonumber(n, base)
    if c and c > 0 and c < 0x110000 and not (c >= 0xD800 and c <= 0xDFFF) and utf8 and utf8.char then return utf8.char(c) end
    return "?"
  end
  s = s:gsub("&#x(%x+);", function(n) return cp(n, 16) end)
  s = s:gsub("&#(%d+);", function(n) return cp(n, 10) end)
  return (s:gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"))
end

local function refreshRecent()
  -- grep -o 逐条取出 bookmark 标签，Lua 侧再按属性名取值（不依赖属性顺序）
  query("recent", [[f="${XDG_DATA_HOME:-$HOME/.local/share}/recently-used.xbel"; [ -f "$f" ] || exit 0; grep -o '<bookmark [^>]*>' "$f" || true]], function(res)
    local prevSig = recentSig(recent.list) .. tostring(recent.ok) .. tostring(recent.loaded)
    local list = {}
    if res.exitCode == 0 then
      for line in ((res.stdout or "") .. "\n"):gmatch("([^\n]*)\n") do
        local href = line:match('href="([^"]*)"')
        if href and href:sub(1, 7) == "file://" then
          local visited = line:match('visited="([^"]*)"') or ""
          local uri = xmlUnescape(href)
          local host, escaped = uri:match("^file://([^/]*)(/.*)$")
          if host and (host == "" or host:lower() == "localhost") then
            local path = artDecode(escaped:match("^[^?#]*"))
            if path and not path:find("%z") then list[#list + 1] = { ts = visited, path = path } end
          end
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

-- ============ 生命周期 ============
local cardBuilders = {
  search = searchCard,
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
    setCardOpen(key, mode == "all" or (mode == "daily" and key == "search"))
  end
  render("layout")
  persistLayout()
end

local toolbarStatusProps
local function toolbarStatus()
  local count = 0
  for _, key in ipairs(order) do if open[key] then count = count + 1 end end
  local status = timer.running and (timer.adopted and "后台计时中" or ("计时 " .. fmtSec(timer.remain)))
    or (count .. " 项展开")
  return status
end
updateToolbarStatus = function()
  if toolbarStatusProps then toolbarStatusProps.text = toolbarStatus() end
end
local function toolbar()
  local subtitle = focusMode and "一次只做一件事" or "把常用的事，放在手边"
  toolbarStatusProps = { key = "toolbar-status", text = toolbarStatus(), fontSize = FS.small, color = "primary" }
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
        variant = "secondary", tooltip = "展开搜索", onClick = function() setLayout("daily") end }),
      ui.button({ key = "focus", text = "专注", glyph = "focus-2", controlSize = "sm", flexGrow = 1,
        variant = focusMode and "primary" or "ghost", tooltip = focusMode and "退出并恢复原布局" or "只展开当前卡片，切换时自动收起其他卡片",
        onClick = function() setFocusMode(not focusMode) end }),
      ui.button({ key = "collapse", text = "收起", glyph = "chevrons-up", controlSize = "sm", flexGrow = 1,
        variant = "ghost", tooltip = "全部收起，只看摘要", onClick = function() setLayout("none") end }),
    }),
    ui.row({ align = "center", justify = "space_between" }, {
      ui.label({ text = noctalia.formatTime("%m / %d  ·  %H:%M"), fontSize = FS.small, color = CL.muted }),
      ui.label(toolbarStatusProps),
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
          if not cardCache[k] or (dirtyCards[k] and (next(folds) == nil or motionNodes[k] == nil or k == "search" or k == "timer")) then
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
  if timer and type(st.timerSec) == "number" and st.timerSec >= 1 and st.timerSec <= 86400 then
    local sec = math.floor(st.timerSec)
    timer.durSec, timer.roundSec, timer.remain = sec, sec, sec
  end
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
  if (next(folds) ~= nil or next(feedback) ~= nil) and now - lastMotionSubmit < 16 then return end
  for key, t0 in pairs(feedback) do
    local header = headerNodes[key]
    local x = math.min(1, (now - t0) / 120)
    if header then header.arrow.props.opacity = 0.45 + 0.55 * ease(x) changed = true end
    if x >= 1 then feedback[key] = nil end
  end
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
    if #bootQueue > 0 and now >= bootAt and next(feedback) == nil then
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
  panel.setNeedsFrameTick(next(folds) ~= nil or next(feedback) ~= nil or stateDirty or #bootQueue > 0 or layoutSaveAt ~= nil)
end

noctalia.setUpdateInterval(1000)

function onOpen(_context)
  generation = generation + 1
  restoreLayout()
  panelVisible = true
  clockMinute = noctalia.formatTime("%H:%M")
  focusEdges = {}
  folds, feedback = {}, {}
  lastMotionSubmit, settleAt = 0, 0
  if customizing then for key in pairs(CARD_KEYS) do dirtyCards[key] = true end end
  customizing = false
  dirtyCards.search = true
  -- 面板关闭会销毁原生树；首屏不带收起的大列表，避免重新打开时集中创建。
  for key in pairs(CARD_KEYS) do
    if not open[key] then
      retainedBodies[key], warmVisible[key] = nil, nil
      dirtyCards[key] = true
    end
  end
  search.text, search.results, search.cmdText, search.cmdMode = "", {}, nil, false
  search.rev, search.wantFocus = search.rev + 1, open.search
  bootReady = false
  -- 先交付首帧，再错峰加载。缓存内容立即可用，不等进程读取。
  bootAt = noctalia.nowMs() + 280
  bootQueue = {
    function() if not apps.loaded or noctalia.nowMs() - apps.loadedAt > 600000 then refreshApps() end end,
    function() timerAdopt() end,
    refreshWins,
    refreshRecent,
  }
  for _, key in ipairs({ "wins" }) do
    if not retainedBodies[key] then
      bootQueue[#bootQueue + 1] = function() warmVisible[key] = true markDirty(key) end
    end
  end
  render("pending")
  panel.setWantsSecondTicks(true)
  wake()
end

function onClose()
  panelVisible = false
  generation = generation + 1
  focusEdges = {}
  folds, feedback = {}, {}
  for key, node in pairs(motionNodes) do
    node.viewport.props.height = open[key] and node.height or 0.1
    node.viewport.props.visible = open[key]
    node.shell.props.gap = open[key] and SP.block or 0
    if headerNodes[key] then headerNodes[key].arrow.props.opacity = 1 end
  end
  bootQueue = {}
  bootReady = false
  panel.setNeedsFrameTick(false)
  panel.setWantsSecondTicks(false)
  if layoutSaveAt then flushLayout() end
end

function onExit(_signal, _reason)
  if layoutSaveAt then flushLayout() end
end

-- IPC 也用于快捷键绑定与无鼠标回归；不暴露任意执行或文件路径。
function onIpc(event, payload)
  if not panelVisible then return end
  if event == "toggle" and CARD_KEYS[payload] then toggleCard(payload)
  elseif event == "layout" and (payload == "daily" or payload == "all" or payload == "none") then setLayout(payload)
  elseif event == "focus" then setFocusMode(not focusMode)
  elseif event == "customize" then customizing = not customizing render()
  elseif event == "timer" then timerIpc(payload)
  elseif event == "pin" and CARD_KEYS[payload] then pinned[payload] = not pinned[payload] render() persistLayout()
  end
end

function update()
  if not panelVisible or not bootReady or next(folds) ~= nil then return end
  updateTick = updateTick + 1
  winsTick = winsTick + 1
  -- 窗口列表：展开时每秒，收起时 3 秒一次（收起态只需要数量）
  if open.wins or winsTick % 3 == 1 then refreshWins() end
  recent.tick = recent.tick + 1
  if recent.tick % 30 == 1 then refreshRecent() end
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
  -- 分钟变化才更新时钟；其余由数据回调按需提交。
  local minute = noctalia.formatTime("%H:%M")
  if minute ~= clockMinute then clockMinute = minute stateDirty = true end
  if stateDirty then wake() end
end
