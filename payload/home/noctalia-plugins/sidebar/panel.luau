--!nonstrict
-- pang/sidebar v0.2 — 左侧全高面板卡片全家桶（2026-10-03）
-- 卡片顺序：搜索 / 媒体 / 窗口 / 计时器 / 系统 / 最近文件 / 笔记
-- 评审版：每张卡一块代码，可独立删减；删卡时同时删 render() 里的对应行。

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
local function endsWith(s, suffix) return s:sub(-#suffix) == suffix end
local function shq(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

local render -- forward declaration

-- 折叠状态 + 卡片顺序（可拖拽排序）：默认展开 搜索/媒体/笔记；顺序与折叠持久化到 panel_layout.json
local open = { search = true, media = true, note = true, wins = false, timer = false, sysmon = false, recent = false }
local order = { "search", "media", "note", "wins", "timer", "sysmon", "recent" }
local CARD_KEYS = { search = true, media = true, note = true, wins = true, timer = true, sysmon = true, recent = true }
local stateDirty = false    -- 性能：只在可见数据变化时重绘（空闲秒不重绘）
local lastMediaSig = ""     -- 性能：封面只在曲目变化时才查
local winsTick = 0
local mediaTick = 0

local function layoutPath() return noctalia.pluginDataDir() .. "/panel_layout.json" end
local function persistLayout()
  local enc = noctalia.json.encode({ order = order, open = open })
  if enc then noctalia.writeFile(layoutPath(), enc) end
end

-- 拖拽落下：payload = 被拖的卡片 key；value = "before|<key>" 或 "end"
function onCardDrop(payload, value)
  local anchor = nil
  if value ~= "end" then
    local _, a = value:match("^([^|]+)|(.+)$")
    anchor = a
  end
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
  persistLayout()
  render()
end

local function chevron(key)
  return ui.glyph({ name = open[key] and "chevron-down" or "chevron-right", size = 12, color = "on_surface_variant" })
end

-- ============ 卡 1：搜索（应用 + 命令前缀） ============
local apps = { loaded = false, list = {} }
local search = { text = "", rev = 0, results = {}, cmdText = nil, cmdMode = false, wantFocus = false }

local function refreshSearchResults()
  local q = search.text
  search.cmdMode = (q:sub(1, 1) == ">")
  search.cmdText = nil
  search.results = {}
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
  for i = 1, math.min(#scored, 10) do out[i] = scored[i].a end
  search.results = out
end

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
  noctalia.runAsync(cmd, function(res)
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
    apps.loaded = true
  end)
end

local function launchApp(a)
  if not a then return end
  if a.terminal then
    noctalia.runInTerminal(a.exec)
  else
    noctalia.runAsync(a.exec)
  end
  panel.close()
end

function onSearchChanged(value)
  search.text = value or ""
  refreshSearchResults()
  render()
end

function onSearchSubmit(_)
  if search.cmdMode and search.cmdText then
    noctalia.runInTerminal(search.cmdText)
    panel.close()
  elseif search.results[1] then
    launchApp(search.results[1])
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
  local children = {
    ui.row({ align = "center", gap = 6, onClick = function() open.search = not open.search persistLayout() render() end }, {
      ui.dragSource({ key = "drag-search", dragType = "card", payload = "search", previewAncestor = 2, tooltip = "拖动排序", width = 24, height = 24, align = "center", justify = "center" }, {
        ui.glyph({ name = "search", size = 14, color = "on_surface_variant" }),
      }),
      ui.label({ text = "搜索", fontSize = 11, color = "on_surface_variant", flexGrow = 1 }),
      ui.label({ text = apps.loaded and (#apps.list .. " 个应用") or "载入中…", fontSize = 10, color = "on_surface_variant" }),
      chevron("search"),
    }),
  }
  if open.search then
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
    table.insert(children, ui.input(iprops))
    if search.cmdMode and search.cmdText then
      table.insert(children, ui.row({
        key = "cmdrow", radius = 8, padding = 8, fill = "surface_variant/0.6",
        onClick = "onRunCmd", align = "center", gap = 8,
      }, {
        ui.glyph({ name = "terminal", size = 14 }),
        ui.label({ text = "运行：" .. search.cmdText, fontSize = 12, maxLines = 1, flexGrow = 1 }),
        ui.label({ text = "Enter", fontSize = 10, color = "on_surface_variant" }),
      }))
    else
      for i, a in ipairs(search.results) do
        table.insert(children, ui.row({
          key = "res-" .. (a.id ~= "" and a.id or a.name),
          radius = 8,
          padding = 6,
          fill = (i == 1) and "primary/0.18" or "surface_variant/0.35",
          onClick = function() launchApp(a) end,
          align = "center",
          gap = 8,
        }, {
          appIconNode(a, 22),
          ui.label({ text = a.name, fontSize = 13, maxLines = 1, flexGrow = 1 }),
        }))
      end
    end
  end
  return ui.column({ fill = "surface_variant/0.55", radius = 14, padding = 12, gap = 8, align = "stretch" }, children)
end

-- ============ 卡 2：媒体 ============
local media = { ok = false, status = "Stopped", artist = "", title = "", lengthUs = 0, posUs = 0 }
local artPath = nil
local artHash = ""
local artSlot = 0

local refreshArt -- 前向声明（refreshMedia 回调里在曲目变化时调用）

local function refreshMedia()
  noctalia.runAsync(
    "playerctl metadata --format '{{status}}|||{{artist}}|||{{title}}|||{{mpris:length}}|||{{position}}'",
    function(res)
      local prevSig = media.status .. "|" .. media.artist .. "|" .. media.title .. "|" .. media.lengthUs .. "|" .. media.posUs .. "|" .. tostring(media.ok) .. "|" .. tostring(artPath)
      if res.exitCode ~= 0 or res.stdout == "" then
        media.ok = false
        artHash = ""
        artPath = nil
      else
        local line = res.stdout:gsub("%s+$", "")
        local status, artist, title, len, pos = line:match("^(.-)|||(.-)|||(.-)|||(.-)|||(.-)$")
        if status == nil then
          media.ok = false
        else
          media.ok = true
          media.status = status
          media.artist = artist
          media.title = title
          media.lengthUs = tonumber(len) or 0
          -- playerctl format 里的 position 已是微秒
          media.posUs = tonumber(pos) or 0
          -- 性能：封面哈希只在曲目变化时跑（空闲秒不再起进程）；status 变化不触发
          local msig = artist .. "|" .. title .. "|" .. tostring(media.ok)
          if msig ~= lastMediaSig then
            lastMediaSig = msig
            refreshArt()
          end
        end
      end
      local newSig = media.status .. "|" .. media.artist .. "|" .. media.title .. "|" .. media.lengthUs .. "|" .. media.posUs .. "|" .. tostring(media.ok) .. "|" .. tostring(artPath)
      if newSig ~= prevSig then stateDirty = true end
    end)
end

-- 封面：全部交给 shell 处理（data:/file:/http: 三种来源），Lua 侧只比较短哈希
refreshArt = function()
  noctalia.runAsync(
    "playerctl metadata mpris:artUrl 2>/dev/null | md5sum | cut -c1-12",
    function(res)
      local h = (res.stdout or ""):gsub("%s+$", "")
      if h == "" or h == "d41d8cd98f00" then
        if artHash ~= "" then
          artHash = ""
          artPath = nil
        end
        return
      end
      if h == artHash then return end
      artHash = h
      artSlot = 1 - artSlot
      local dest = noctalia.pluginDataDir() .. "/art_" .. tostring(artSlot) .. ".jpg"
      local extract = [[u=$(playerctl metadata mpris:artUrl); case "$u" in
file://*) cp -- "${u#file://}" 'DEST';;
http*) curl -sL --max-time 20 -o 'DEST' "$u";;
data:*) printf '%s' "$u" | sed 's/^data:[^,]*,//' | base64 -d > 'DEST';;
esac]]
      extract = extract:gsub("DEST", dest)
      noctalia.runAsync(extract, function(_)
        artPath = dest
        stateDirty = true
      end)
    end)
end

function onMediaPrev() noctalia.runAsync("playerctl previous") end
function onMediaNext() noctalia.runAsync("playerctl next") end
function onMediaToggle() noctalia.runAsync("playerctl play-pause") end

local function mediaCard()
  local header = {
    ui.dragSource({ key = "drag-media", dragType = "card", payload = "media", previewAncestor = 2, tooltip = "拖动排序", width = 24, height = 24, align = "center", justify = "center" }, {
      ui.glyph({ name = "music", size = 14, color = "on_surface_variant" }),
    }),
    ui.label({ text = "媒体", fontSize = 11, color = "on_surface_variant", flexGrow = 1 }),
  }
  if not open.media and media.ok and media.title ~= "" then
    header[#header + 1] = ui.label({ text = media.title, fontSize = 10, color = "on_surface_variant", maxLines = 1 })
  end
  header[#header + 1] = chevron("media")
  local children = {
    ui.row({ align = "center", gap = 6, onClick = function() open.media = not open.media persistLayout() render() end }, header),
  }
  if open.media then
    if not media.ok then
      table.insert(children, ui.row({ align = "center", justify = "center", paddingV = 10 }, {
        ui.label({ text = "暂无播放内容", fontSize = 13, color = "on_surface_variant" }),
      }))
    else
      if artPath ~= nil and noctalia.fileExists(artPath) then
        table.insert(children, ui.image({ path = artPath, width = 280, height = 190, radius = 10, fit = "cover" }))
      else
        table.insert(children, ui.row({ height = 110, fill = "surface_variant/0.5", radius = 10, align = "center", justify = "center" }, {
          ui.glyph({ name = "music", size = 34, color = "on_surface_variant" }),
        }))
      end
      table.insert(children, ui.label({ text = media.title ~= "" and media.title or "未知曲目", fontWeight = "bold", maxLines = 1 }))
      table.insert(children, ui.label({ text = media.artist ~= "" and media.artist or "未知艺术家", fontSize = 12, color = "on_surface_variant", maxLines = 1 }))
      local ratio = 0
      if media.lengthUs > 0 then
        ratio = math.min(1, math.max(0, media.posUs / media.lengthUs))
      end
      table.insert(children, ui.progress({ progress = ratio, fill = "primary", height = 4, radius = 2 }))
      table.insert(children, ui.row({ align = "center", justify = "space_between" }, {
        ui.label({ text = fmtUs(media.posUs), fontSize = 11, color = "on_surface_variant" }),
        ui.label({ text = fmtUs(media.lengthUs), fontSize = 11, color = "on_surface_variant" }),
      }))
      table.insert(children, ui.row({ align = "center", justify = "center", gap = 10 }, {
        ui.button({ glyph = "player-skip-back", variant = "ghost", onClick = "onMediaPrev" }),
        ui.button({ glyph = (media.status == "Playing") and "player-pause" or "player-play", variant = "primary", onClick = "onMediaToggle" }),
        ui.button({ glyph = "player-skip-forward", variant = "ghost", onClick = "onMediaNext" }),
      }))
    end
  end
  return ui.column({ fill = "surface_variant/0.55", radius = 14, padding = 12, gap = 10, align = "stretch" }, children)
end

-- ============ 卡 3：窗口列表 ============
local wins = { list = {}, ok = false }
local winIconCache = {}

local function winsSig(list, ok)
  local s = ok and "1" or "0"
  for _, w in ipairs(list) do
    s = s .. "|" .. tostring(w.id) .. (w.focused and "F" or "") .. w.title
  end
  return s
end

local function refreshWins()
  noctalia.runAsync("niri msg -j windows", function(res)
    local prevSig = winsSig(wins.list, wins.ok)
    local data = nil
    if res.exitCode == 0 then data = noctalia.json.decode(res.stdout or "") end
    if type(data) ~= "table" then
      wins.ok = false
    else
      local list = {}
      for _, w in ipairs(data) do
        if type(w) == "table" then
          table.insert(list, {
            id = w.id,
            title = w.title or "",
            app_id = w.app_id or "",
            focused = (w.is_focused == true),
            ws = w.workspace_id or 0,
          })
        end
      end
      table.sort(list, function(x, y)
        if x.ws ~= y.ws then return x.ws < y.ws end
        return x.id < y.id
      end)
      wins.list = list
      wins.ok = true
    end
    if winsSig(wins.list, wins.ok) ~= prevSig then stateDirty = true end
  end)
end

local function focusWin(id)
  noctalia.runAsync("niri msg action focus-window --id " .. id)
  panel.close()
end
local function closeWin(id)
  noctalia.runAsync("niri msg action close-window --id " .. id)
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
    ui.row({ align = "center", gap = 6, onClick = function() open.wins = not open.wins persistLayout() render() end }, {
      ui.dragSource({ key = "drag-wins", dragType = "card", payload = "wins", previewAncestor = 2, tooltip = "拖动排序", width = 24, height = 24, align = "center", justify = "center" }, {
        ui.glyph({ name = "layout-grid", size = 14, color = "on_surface_variant" }),
      }),
      ui.label({ text = "窗口", fontSize = 11, color = "on_surface_variant", flexGrow = 1 }),
      ui.label({ text = (#wins.list) .. " 个", fontSize = 10, color = "on_surface_variant" }),
      chevron("wins"),
    }),
  }
  if open.wins then
    if not wins.ok then
      table.insert(children, ui.label({ text = "niri 不可达", fontSize = 12, color = "on_surface_variant" }))
    elseif #wins.list == 0 then
      table.insert(children, ui.label({ text = "当前没有打开的窗口", fontSize = 12, color = "on_surface_variant" }))
    else
      for _, w in ipairs(wins.list) do
        local sub = (w.app_id ~= "") and w.app_id or ("窗口 " .. tostring(w.id))
        local texts = { ui.label({ text = (w.title ~= "") and w.title or sub, fontSize = 12, maxLines = 1 }) }
        if w.title ~= "" then
          table.insert(texts, ui.label({ text = sub, fontSize = 10, color = "on_surface_variant", maxLines = 1 }))
        end
        table.insert(children, ui.row({
          key = "win-" .. w.id,
          radius = 8,
          padding = 6,
          fill = w.focused and "primary/0.22" or "surface_variant/0.35",
          onClick = function() focusWin(w.id) end,
          align = "center",
          gap = 8,
        }, {
          winIconNode(w.app_id, 20),
          ui.column({ gap = 1, flexGrow = 1 }, texts),
          ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "关闭窗口", onClick = function() closeWin(w.id) end }),
        }))
      end
    end
  end
  return ui.column({ fill = "surface_variant/0.55", radius = 14, padding = 12, gap = 6, align = "stretch" }, children)
end

-- ============ 卡 4：计时器（独立进程发通知，面板关着也能提醒） ============
local timer = { durMin = 25, remain = 1500, deadlineMs = 0, running = false, done = false }

local function timerPidPath() return noctalia.pluginDataDir() .. "/timer.pid" end
local function timerKill()
  local pf = timerPidPath()
  noctalia.runAsync("if [ -f " .. shq(pf) .. " ]; then PID=$(cat " .. shq(pf) .. "); kill -TERM -$PID 2>/dev/null; kill -TERM $PID 2>/dev/null; rm -f " .. shq(pf) .. "; fi")
end
local function timerStart()
  if timer.running or timer.remain <= 0 then return end
  timer.deadlineMs = noctalia.nowMs() + timer.remain * 1000
  timer.running = true
  timer.done = false
  local pf = timerPidPath()
  local secs = math.floor(timer.remain + 0.999)
  local msg = string.format("%d 分钟到了", timer.durMin)
  local inner = "echo $$ > " .. pf .. "; sleep " .. secs .. "; notify-send -a sidebar-panel 计时器 \"" .. msg .. "\"; rm -f " .. pf
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
  timer.remain = timer.durMin * 60
end
local function timerPreset(m)
  timerKill()
  timer.durMin = m
  timer.running = false
  timer.done = false
  timer.remain = m * 60
end

function onTimerToggle()
  if timer.running then timerPause() else timerStart() end
  render()
end
function onTimerReset()
  timerReset()
  render()
end
function onTimerPreset5() timerPreset(5) render() end
function onTimerPreset15() timerPreset(15) render() end
function onTimerPreset25() timerPreset(25) render() end

local function timerCard()
  local status = timer.running and "运行中" or (timer.remain <= 0 and "已到点" or "待机")
  local children = {
    ui.row({ align = "center", gap = 6, onClick = function() open.timer = not open.timer persistLayout() render() end }, {
      ui.dragSource({ key = "drag-timer", dragType = "card", payload = "timer", previewAncestor = 2, tooltip = "拖动排序", width = 24, height = 24, align = "center", justify = "center" }, {
        ui.glyph({ name = "clock-hour-4", size = 14, color = "on_surface_variant" }),
      }),
      ui.label({ text = "计时器", fontSize = 11, color = "on_surface_variant", flexGrow = 1 }),
      ui.label({ text = status .. (not open.timer and ("  " .. fmtSec(timer.remain)) or ""), fontSize = 10, color = "on_surface_variant" }),
      chevron("timer"),
    }),
  }
  if open.timer then
    local function presetBtn(m)
      return ui.button({
        text = m .. " 分",
        variant = (not timer.running and timer.durMin == m) and "secondary" or "ghost",
        controlSize = "sm",
        onClick = "onTimerPreset" .. m,
      })
    end
    table.insert(children, ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = fmtSec(timer.remain), fontSize = 30, fontWeight = "bold", flexGrow = 1 }),
      presetBtn(5), presetBtn(15), presetBtn(25),
    }))
    table.insert(children, ui.row({ align = "center", gap = 8 }, {
      ui.button({ text = timer.running and "暂停" or "开始", variant = "primary", controlSize = "sm", flexGrow = 1, onClick = "onTimerToggle" }),
      ui.button({ text = "重置", variant = "ghost", controlSize = "sm", flexGrow = 1, onClick = "onTimerReset" }),
    }))
  end
  return ui.column({ fill = "surface_variant/0.55", radius = 14, padding = 12, gap = 8, align = "stretch" }, children)
end

-- ============ 卡 5：系统一览 ============
local sysmon = { stats = nil, cpuHist = {}, procs = {}, tick = 0 }

local function pushHist(t, v)
  table.insert(t, v)
  if #t > 60 then table.remove(t, 1) end
end

local function refreshProcs()
  noctalia.runAsync("ps -eo pcpu=,pmem=,comm= --sort=-pcpu | head -6", function(res)
    local list = {}
    for line in ((res.stdout or "") .. "\n"):gmatch("([^\n]*)\n") do
      local cpu, _mem, comm = line:match("^%s*([%d%.]+)%s+([%d%.]+)%s+(.+)$")
      if cpu and comm then
        table.insert(list, { cpu = tonumber(cpu), name = trim(comm) })
      end
    end
    sysmon.procs = list
    stateDirty = true
  end)
end

local function sysCard()
  local st = sysmon.stats
  local summary = ""
  if st then
    summary = string.format("CPU %.0f%%", (st.cpu and st.cpu.usagePercent) or 0)
    if st.ram then summary = summary .. string.format(" · 内存 %.0f%%", st.ram.usagePercent or 0) end
  end
  local children = {
    ui.row({ align = "center", gap = 6, onClick = function() open.sysmon = not open.sysmon persistLayout() render() end }, {
      ui.dragSource({ key = "drag-sysmon", dragType = "card", payload = "sysmon", previewAncestor = 2, tooltip = "拖动排序", width = 24, height = 24, align = "center", justify = "center" }, {
        ui.glyph({ name = "cpu", size = 14, color = "on_surface_variant" }),
      }),
      ui.label({ text = "系统", fontSize = 11, color = "on_surface_variant", flexGrow = 1 }),
      ui.label({ text = (not open.sysmon) and summary or "", fontSize = 10, color = "on_surface_variant" }),
      chevron("sysmon"),
    }),
  }
  if open.sysmon then
    if not st then
      table.insert(children, ui.label({ text = "系统监控不可用", fontSize = 12, color = "on_surface_variant" }))
    else
      if #sysmon.cpuHist > 1 then
        table.insert(children, ui.graph({ values = sysmon.cpuHist, height = 36, color = "primary", fillOpacity = 0.18 }))
      end
      local line1 = string.format("CPU %.0f%%", (st.cpu and st.cpu.usagePercent) or 0)
      if st.cpu and st.cpu.tempC then line1 = line1 .. string.format("  %.0f°C", st.cpu.tempC) end
      if st.ram then line1 = line1 .. string.format("  内存 %.0f%%", st.ram.usagePercent or 0) end
      table.insert(children, ui.label({ text = line1, fontSize = 12 }))
      if st.ram and st.ram.totalMb and st.ram.totalMb > 0 then
        table.insert(children, ui.progress({ progress = (st.ram.usedMb or 0) / st.ram.totalMb, fill = "primary", height = 4, radius = 2 }))
      end
      if st.net then
        table.insert(children, ui.label({
          text = string.format("网络 ↓%s ↑%s", fmtBps(st.net.rxBytesPerSec), fmtBps(st.net.txBytesPerSec)),
          fontSize = 11, color = "on_surface_variant",
        }))
      end
      if st.loadAvg then
        table.insert(children, ui.label({
          text = string.format("负载 %.2f  %.2f  %.2f", st.loadAvg[1] or 0, st.loadAvg[2] or 0, st.loadAvg[3] or 0),
          fontSize = 10, color = "on_surface_variant",
        }))
      end
      if noctalia.diskStats then
        local dsk = noctalia.diskStats(noctalia.expandPath("~/"))
        if dsk and dsk.usagePercent then
          table.insert(children, ui.label({ text = string.format("磁盘 %.0f%%", dsk.usagePercent), fontSize = 11, color = "on_surface_variant" }))
        end
      end
    end
    if #sysmon.procs > 0 then
      for _, p in ipairs(sysmon.procs) do
        table.insert(children, ui.row({ gap = 6 }, {
          ui.label({ text = p.name, fontSize = 11, flexGrow = 1, maxLines = 1 }),
          ui.label({ text = string.format("%.0f%%", p.cpu), fontSize = 11, color = "on_surface_variant" }),
        }))
      end
    end
  end
  return ui.column({ fill = "surface_variant/0.55", radius = 14, padding = 12, gap = 6, align = "stretch" }, children)
end

-- ============ 卡 6：最近文件（GTK recently-used.xbel） ============
local recent = { list = {}, ok = false, tick = 0 }

local function recentSig(list)
  local s = tostring(#list)
  for _, r in ipairs(list) do
    s = s .. "|" .. r.path
  end
  return s
end

local function refreshRecent()
  noctalia.runAsync([[f="$HOME/.local/share/recently-used.xbel"; [ -f "$f" ] || exit 0; grep '<bookmark ' "$f" | sed -E 's/.*href="([^"]*)".*visited="([^"]*)"[^>]*>.*/\2\t\1/' | grep "file://"]], function(res)
    local prevSig = recentSig(recent.list)
    local list = {}
    for line in ((res.stdout or "") .. "\n"):gmatch("([^\n]*)\n") do
      if line ~= "" then
        local ts, href = line:match("^(.-)\t(.*)$")
        if href and href:sub(1, 7) == "file://" then
          local path = noctalia.string.urlDecode(href:sub(8))
          table.insert(list, { ts = ts or "", path = path })
        end
      end
    end
    table.sort(list, function(x, y) return x.ts > y.ts end)
    local out = {}
    for i = 1, math.min(#list, 8) do out[i] = list[i] end
    recent.list = out
    recent.ok = true
    if recentSig(out) ~= prevSig then stateDirty = true end
  end)
end

local function openRecent(path)
  noctalia.runAsync("xdg-open " .. shq(path))
  panel.close()
end

local function recentCard()
  local children = {
    ui.row({ align = "center", gap = 6, onClick = function() open.recent = not open.recent persistLayout() render() end }, {
      ui.dragSource({ key = "drag-recent", dragType = "card", payload = "recent", previewAncestor = 2, tooltip = "拖动排序", width = 24, height = 24, align = "center", justify = "center" }, {
        ui.glyph({ name = "file-text", size = 14, color = "on_surface_variant" }),
      }),
      ui.label({ text = "最近文件", fontSize = 11, color = "on_surface_variant", flexGrow = 1 }),
      ui.label({ text = (#recent.list > 0) and ((#recent.list) .. " 条") or "", fontSize = 10, color = "on_surface_variant" }),
      chevron("recent"),
    }),
  }
  if open.recent then
    if #recent.list == 0 then
      table.insert(children, ui.label({ text = recent.ok and "暂无记录" or "载入中…", fontSize = 12, color = "on_surface_variant" }))
    else
      for i, r in ipairs(recent.list) do
        table.insert(children, ui.row({
          key = "rec-" .. i,
          radius = 8,
          padding = 6,
          fill = "surface_variant/0.35",
          onClick = function() openRecent(r.path) end,
          align = "center",
          gap = 8,
        }, {
          ui.glyph({ name = "file-text", size = 16, color = "on_surface_variant" }),
          ui.column({ gap = 1, flexGrow = 1 }, {
            ui.label({ text = basename(r.path), fontSize = 12, maxLines = 1 }),
            ui.label({ text = dirname(r.path), fontSize = 10, color = "on_surface_variant", maxLines = 1 }),
          }),
        }))
      end
    end
  end
  return ui.column({ fill = "surface_variant/0.55", radius = 14, padding = 12, gap = 6, align = "stretch" }, children)
end

-- ============ 卡 7：临时笔记（多便签 + 预览） ============
local note = {
  dir = "", path = "", buffer = "", rev = 0, dirty = false, idle = 0,
  stamp = "", pendingClear = false, preview = false, files = {}, sel = 0,
}

local function noteStatePath() return noctalia.pluginDataDir() .. "/note_state.json" end

local function saveNote()
  if note.dirty and note.path ~= "" then
    local ok, err = noctalia.writeFile(note.path, note.buffer)
    if ok then
      note.dirty = false
      note.stamp = noctalia.formatTime("%H:%M:%S")
      stateDirty = true
    else
      noctalia.notifyError("临时笔记", err or "写入失败")
    end
  end
  note.idle = 0
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
  note.path = note.dir .. "/" .. name
  local content = noctalia.readFile(note.path)
  note.buffer = content or ""
  note.dirty = false
  note.rev = note.rev + 1
  note.pendingClear = false
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
  noctalia.writeFile(note.dir .. "/" .. name, "")
  return name
end

function onNoteSwitch(value)
  local idx = tonumber(value)
  if idx == nil then return end
  saveNote()
  persistNoteState()
  -- selectedIndex 假定 0 基；最后一项是"＋ 新建便签"
  if idx >= #note.files then
    local name = createNewNote()
    note.files = scanNotes()
    for i, f in ipairs(note.files) do
      if f == name then note.sel = i - 1 end
    end
    openNoteFile(name)
  else
    local name = note.files[idx + 1]
    if name then
      note.sel = idx
      openNoteFile(name)
    end
  end
  persistNoteState()
  render()
end

function onNoteEdited(value)
  note.buffer = value or ""
  note.dirty = true
  note.idle = 0
end

function onTogglePreview()
  note.preview = not note.preview
  render()
end

function onClearClick() note.pendingClear = true render() end
function onClearConfirm()
  note.buffer = ""
  note.dirty = true
  note.rev = note.rev + 1
  note.pendingClear = false
  saveNote()
  render()
end
function onClearCancel() note.pendingClear = false render() end

local function noteCard()
  local statusText
  if note.dirty then
    statusText = "输入中…"
  elseif note.stamp ~= "" then
    statusText = "已保存 " .. note.stamp
  else
    statusText = "就绪"
  end
  local header = {
    ui.dragSource({ key = "drag-note", dragType = "card", payload = "note", previewAncestor = 2, tooltip = "拖动排序", width = 24, height = 24, align = "center", justify = "center" }, {
      ui.glyph({ name = "note", size = 14, color = "on_surface_variant" }),
    }),
    ui.label({ text = "临时笔记", fontSize = 11, color = "on_surface_variant", flexGrow = 1 }),
    ui.label({ text = statusText, fontSize = 10, color = "on_surface_variant" }),
    chevron("note"),
  }
  if note.pendingClear then
    table.insert(header, ui.button({ text = "确认清空", variant = "destructive", controlSize = "sm", onClick = "onClearConfirm" }))
    table.insert(header, ui.button({ glyph = "close", variant = "ghost", controlSize = "sm", onClick = "onClearCancel" }))
  else
    table.insert(header, ui.button({ glyph = note.preview and "pencil" or "eye", variant = "ghost", controlSize = "sm", tooltip = note.preview and "编辑" or "预览", onClick = "onTogglePreview" }))
    table.insert(header, ui.button({ glyph = "trash", variant = "ghost", controlSize = "sm", tooltip = "清空笔记", onClick = "onClearClick" }))
  end
  local block = {
    ui.row({ align = "center", gap = 6, onClick = function() open.note = not open.note persistLayout() render() end }, header),
  }
  if open.note then
    local opts = {}
    for _, f in ipairs(note.files) do table.insert(opts, f) end
    table.insert(opts, "＋ 新建便签")
    local body
    if note.preview then
      body = ui.scroll({ height = 240, fill = "surface_variant/0.35", radius = 8, padding = 8 }, {
        ui.markdown({ text = note.buffer ~= "" and note.buffer or "_（空）_", width = 300 }),
      })
    else
      -- frameVisible=false：不用输入框自带的高亮边框（圆角不受控、偏圆），
      -- 外框与预览模式保持同一规格（fill/radius 8/padding 8/height 240）
      body = ui.row({ fill = "surface_variant/0.35", radius = 8, padding = 8, height = 240, align = "stretch" }, {
        ui.input({
          key = "note-" .. note.rev,
          value = note.buffer,
          multiline = true,
          flexGrow = 1,
          frameVisible = false,
          placeholder = "随手记点什么…",
          onChange = "onNoteEdited",
        }),
      })
    end
    table.insert(block, ui.select({ options = opts, selectedIndex = note.sel, controlSize = "sm", onChange = "onNoteSwitch" }))
    table.insert(block, body)
  end
  return ui.column({ fill = "surface_variant/0.55", radius = 14, padding = 12, gap = 8, align = "stretch" }, block)
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

render = function()
  local blocks = {}
  for _, k in ipairs(order) do
    local builder = cardBuilders[k]
    if builder then
      -- 每张卡外层是投放区：拖别的卡到这=插到它前面；标题行是拖拽把手
      table.insert(blocks, ui.dropZone({
        key = "dz-" .. k,
        accepts = { "card" },
        value = "before|" .. k,
        onDrop = "onCardDrop",
        direction = "column",
      }, { builder() }))
    end
  end
  -- 列表末尾的插入区（拖到这里 = 移到最后）
  table.insert(blocks, ui.dropZone({
    key = "dz-end",
    accepts = { "card" },
    value = "end",
    onDrop = "onCardDrop",
    height = 6,
    expandOnDrag = true,
    hitSlop = 30,
  }))
  panel.render(ui.scroll({ flexGrow = 1 }, {
    ui.column({ gap = 10, align = "stretch" }, blocks),
  }))
end

function onOpen(_context)
  -- 搜索重置
  search.text = ""
  search.results = {}
  search.cmdText = nil
  search.cmdMode = false
  search.rev = search.rev + 1
  search.wantFocus = true
  if not apps.loaded then refreshApps() end
  refreshWins()
  refreshRecent()
  -- 笔记目录与迁移
  note.dir = noctalia.expandPath("~/Documents/notes")
  noctalia.mkdirAll(note.dir)
  note.files = scanNotes()
  if #note.files == 0 then
    local old = noctalia.expandPath("~/Documents/scratchpad.md")
    if noctalia.fileExists(old) then
      noctalia.renameFile(old, note.dir .. "/便签.md")
    end
    note.files = scanNotes()
  end
  if #note.files == 0 then
    noctalia.writeFile(note.dir .. "/便签.md", "")
    note.files = scanNotes()
  end
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
  -- 布局（卡片顺序 + 折叠状态）从磁盘恢复
  local layoutRaw = noctalia.readFile(layoutPath())
  if layoutRaw then
    local st = noctalia.json.decode(layoutRaw)
    if type(st) == "table" then
      if type(st.open) == "table" then
        for k in pairs(CARD_KEYS) do
          if type(st.open[k]) == "boolean" then open[k] = st.open[k] end
        end
      end
      if type(st.order) == "table" then
        local seen = {}
        local revived = {}
        for _, k in ipairs(st.order) do
          if CARD_KEYS[k] and not seen[k] then
            seen[k] = true
            table.insert(revived, k)
          end
        end
        for _, k in ipairs(order) do
          if not seen[k] then table.insert(revived, k) end
        end
        order = revived
      end
    end
  end
  panel.setWantsSecondTicks(true)
  render()
end

function onClose()
  saveNote()
  persistNoteState()
end

function update()
  noctalia.setUpdateInterval(1000)
  winsTick = winsTick + 1
  mediaTick = mediaTick + 1
  -- 媒体：有内容时每秒查询；完全空闲时 3 秒一次（回调只在实际变化时标脏）
  if media.ok or mediaTick % 3 == 1 then refreshMedia() end
  -- 窗口列表：展开时每秒，收起时 3 秒一次（收起态只需要数量）
  if open.wins or winsTick % 3 == 1 then refreshWins() end
  recent.tick = recent.tick + 1
  if recent.tick % 10 == 1 then refreshRecent() end
  -- 计时器推进
  if timer.running then
    local rem = (timer.deadlineMs - noctalia.nowMs()) / 1000
    if rem <= 0 then
      timer.running = false
      timer.done = true
      timer.remain = 0
      stateDirty = true
    else
      timer.remain = rem
    end
  end
  -- 系统采样
  sysmon.tick = sysmon.tick + 1
  local st = noctalia.systemStats()
  if st then
    local prevCpu = sysmon.stats and sysmon.stats.cpu and sysmon.stats.cpu.usagePercent
    local prevRam = sysmon.stats and sysmon.stats.ram and sysmon.stats.ram.usagePercent
    sysmon.stats = st
    pushHist(sysmon.cpuHist, ((st.cpu and st.cpu.usagePercent) or 0) / 100)
    if open.sysmon then
      stateDirty = true -- 曲线每秒移动
    else
      -- 收起态只有一行摘要：取整有变化才重绘
      local cpuNow = math.floor((st.cpu and st.cpu.usagePercent) or 0)
      local ramNow = math.floor((st.ram and st.ram.usagePercent) or 0)
      if cpuNow ~= math.floor(prevCpu or -1) or ramNow ~= math.floor(prevRam or -1) then
        stateDirty = true
      end
    end
  end
  if open.sysmon and sysmon.tick % 5 == 1 then refreshProcs() end
  -- 笔记自动保存
  if note.dirty then
    note.idle = note.idle + 1
    if note.idle >= 2 then saveNote() end
  end
  -- 渲染门控（性能）：只在"有东西在动"或数据变化时重绘
  local live = (media.ok and media.status == "Playing") or timer.running or open.sysmon or note.dirty
  if live or stateDirty then
    render()
  end
  stateDirty = false
end
