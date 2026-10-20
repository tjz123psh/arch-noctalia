--!nonstrict
-- Pure, single-writer notes model. Deletion moves an entry to recoverable trash.
local M = {}
M.MAX_NOTES = 80
M.MAX_TRASH = 80
M.MAX_BODY_BYTES = 65536
M.MAX_TOTAL_BYTES = 1048576
M.MAX_TITLE_BYTES = 180

local function finite(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end
local function copyEntry(n)
  return { id = n.id, title = n.title, body = n.body, createdAt = n.createdAt, updatedAt = n.updatedAt, deletedAt = n.deletedAt }
end
local function copy(s)
  local out = { version = 1, revision = s.revision, nextId = s.nextId, activeId = s.activeId, notes = {}, trash = {} }
  for _, n in ipairs(s.notes) do table.insert(out.notes, copyEntry(n)) end
  for _, n in ipairs(s.trash) do table.insert(out.trash, copyEntry(n)) end
  return out
end
local function title(value)
  if type(value) ~= "string" then return nil, "请输入便签名称" end
  value = value:gsub("[\r\n\t]", " "):match("^%s*(.-)%s*$")
  if value == "" then return nil, "名称不能为空" end
  if #value > M.MAX_TITLE_BYTES then return nil, "名称过长，请控制在 60 个汉字以内" end
  if value:find("%z") then return nil, "名称包含无效字符" end
  return value
end
local function indexOf(list, id)
  for i, n in ipairs(list) do if n.id == id then return i end end
  return nil
end
function M.active(s)
  local i = indexOf(s.notes, s.activeId)
  return i and s.notes[i] or nil
end
function M.empty(now)
  now = finite(now) and math.floor(now) or 0
  return { version = 1, revision = 0, nextId = 2, activeId = "note-1", notes = {
    { id = "note-1", title = "随手记", body = "", createdAt = now, updatedAt = now }
  }, trash = {} }
end
function M.validate(s)
  if type(s) ~= "table" or s.version ~= 1 or type(s.notes) ~= "table" or type(s.trash) ~= "table"
    or not finite(s.revision) or s.revision < 0 or s.revision % 1 ~= 0
    or not finite(s.nextId) or s.nextId < 1 or s.nextId % 1 ~= 0 then return nil, "便签数据格式不正确" end
  if #s.notes > M.MAX_NOTES or #s.trash > M.MAX_TRASH then return nil, "便签数量超出安全上限" end
  local seen, total = {}, 0
  for _, list in ipairs({ s.notes, s.trash }) do
    for _, n in ipairs(list) do
      if type(n) ~= "table" or type(n.id) ~= "string" or not n.id:match("^note%-%d+$") or seen[n.id]
        or not title(n.title) or type(n.body) ~= "string" or #n.body > M.MAX_BODY_BYTES
        or not finite(n.createdAt) or not finite(n.updatedAt) then return nil, "便签内容损坏，未覆盖原文件" end
      local number = tonumber(n.id:match("%d+$"))
      if not number or number >= s.nextId then return nil, "便签编号损坏" end
      seen[n.id] = true
      total = total + #n.body + #n.title
    end
  end
  if total > M.MAX_TOTAL_BYTES then return nil, "便签总内容超过 1 MiB，未保存" end
  if #s.notes > 0 and not indexOf(s.notes, s.activeId) then return nil, "当前便签编号不正确" end
  if #s.notes == 0 and s.activeId ~= "" then return nil, "当前便签编号不正确" end
  return copy(s)
end
function M.apply(s, action, args, now)
  args = type(args) == "table" and args or {}
  now = finite(now) and math.floor(now) or 0
  local out = copy(s)
  local id = args.id or out.activeId
  local i = indexOf(out.notes, id)
  if action == "add" then
    if #out.notes >= M.MAX_NOTES then return nil, "最多保留 80 条便签" end
    local t, err = title(args.title or "新便签")
    if not t then return nil, err end
    local n = { id = "note-" .. out.nextId, title = t, body = "", createdAt = now, updatedAt = now }
    out.nextId = out.nextId + 1
    table.insert(out.notes, n)
    out.activeId = n.id
  elseif action == "restore" then
    if #out.notes >= M.MAX_NOTES then return nil, "便签数量已达上限" end
    local ti = indexOf(out.trash, id)
    if not ti then return nil, "这条便签已恢复或不存在" end
    local n = table.remove(out.trash, ti)
    n.deletedAt = nil
    n.updatedAt = now
    table.insert(out.notes, n)
    out.activeId = n.id
  else
    if not i then return nil, "便签已不存在，请重新选择" end
    if action == "select" then
      out.activeId = id
    elseif action == "edit" then
      if type(args.body) ~= "string" then return nil, "内容格式不正确" end
      if #args.body > M.MAX_BODY_BYTES then return nil, "每条便签最多 64 KiB；原内容未被覆盖" end
      out.notes[i].body = args.body
      out.notes[i].updatedAt = now
    elseif action == "rename" then
      local t, err = title(args.title)
      if not t then return nil, err end
      out.notes[i].title = t
      out.notes[i].updatedAt = now
    elseif action == "delete" then
      if #out.trash >= M.MAX_TRASH then return nil, "回收区已满（80 条）；为保护内容，本次未删除" end
      local n = table.remove(out.notes, i)
      n.deletedAt = now
      table.insert(out.trash, 1, n)
      if out.activeId == id then
        local next = out.notes[math.min(i, #out.notes)]
        out.activeId = next and next.id or ""
      end
    elseif action == "move" then
      local to = tonumber(args.to)
      if not to or to % 1 ~= 0 or to < 1 or to > #out.notes then return nil, "目标位置不正确" end
      table.insert(out.notes, to, table.remove(out.notes, i))
    else
      return nil, "未知便签操作"
    end
  end
  out.revision = out.revision + 1
  return M.validate(out)
end

-- Alternating snapshots: an interrupted write never destroys the last good copy.
-- read/encode/decode/write are supplied by the host; false/nil means failure.
function M.load(io, now)
  local candidates, found, errors = {}, false, {}
  for _, slot in ipairs({ "notes-a.json", "notes-b.json" }) do
    local raw, readError = io.read(slot)
    if readError then return nil, nil, "已有便签快照无法读取。为保护原内容，已停止写入，请检查文件权限。" end
    if raw ~= nil and raw ~= "" then
      found = true
      local ok, value = pcall(io.decode, raw)
      local valid = ok and M.validate(value) or nil
      if valid then table.insert(candidates, { state = valid, slot = slot }) else table.insert(errors, slot) end
    elseif raw == "" then
      found = true
      table.insert(errors, slot)
    end
  end
  table.sort(candidates, function(a, b) return a.state.revision > b.state.revision end)
  if candidates[1] then
    return candidates[1].state, candidates[1].slot, #errors > 0 and "已从另一份快照恢复便签" or nil
  end
  if found then return nil, nil, "两份便签快照都无法读取。原文件已保留，禁止覆盖，请先备份检查。" end
  return M.empty(now), nil, nil
end
function M.save(io, state, previousSlot)
  local valid, err = M.validate(state)
  if not valid then return nil, err end
  local nextSlot = previousSlot == "notes-a.json" and "notes-b.json" or "notes-a.json"
  local ok, encoded = pcall(io.encode, valid)
  if not ok or type(encoded) ~= "string" then return nil, "便签编码失败，未保存" end
  local wrote, result = pcall(io.write, nextSlot, encoded)
  if not wrote or not result then return nil, "便签写入失败；上一份快照仍保留" end
  if io.read(nextSlot) ~= encoded then return nil, "便签保存校验失败；上一份快照仍保留" end
  return nextSlot
end
return M
