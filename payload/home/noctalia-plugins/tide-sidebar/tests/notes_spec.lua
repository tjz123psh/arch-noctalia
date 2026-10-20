local Notes = dofile("tide-sidebar/lib/notes.luau")
local total = 0
local function check(ok, name) assert(ok, name); total = total + 1 end
local s = Notes.empty(1000)
check(Notes.active(s).title == "随手记", "initial note")
local s2 = assert(Notes.apply(s, "edit", {body="第一行\n第二行"}, 1100))
check(Notes.active(s).body == "", "immutable previous state")
check(Notes.active(s2).body == "第一行\n第二行", "multiline edit")
s = assert(Notes.apply(s2, "add", {title="另一张"}, 1200))
check(#s.notes == 2 and s.activeId == "note-2", "add and select")
s = assert(Notes.apply(s, "rename", {title="  新名字  "}, 1300))
check(Notes.active(s).title == "新名字", "rename trims")
check(not Notes.apply(s, "rename", {title="  "}, 1400), "reject empty title")
s = assert(Notes.apply(s, "move", {to=1}, 1400))
check(s.notes[1].id == "note-2", "reorder by stable id")
s = assert(Notes.apply(s, "delete", {}, 1500))
check(#s.notes == 1 and #s.trash == 1 and s.activeId == "note-1", "delete is recoverable")
s = assert(Notes.apply(s, "restore", {id="note-2"}, 1600))
check(#s.notes == 2 and #s.trash == 0 and s.activeId == "note-2", "restore with original id")
s = assert(Notes.apply(s, "select", {id="note-1"}, 1700))
check(Notes.active(s).body == "第一行\n第二行", "switch preserves body")
check(not Notes.apply(s, "edit", {body=string.rep("x",65537)},1800), "reject too large edit")
check(not Notes.apply(s, "select", {id="../bad"},1800), "reject missing id")
check(not Notes.apply(s, "move", {to=0},1800), "reject invalid destination")
local corrupt = {version=1,revision=1,nextId=2,activeId="note-1",notes={s.notes[1],s.notes[1]},trash={}}
check(not Notes.validate(corrupt), "reject duplicate IDs")
-- A small in-memory codec lets the persistence protocol be tested without dependencies.
local db, encoded, serial = {}, {}, 0
local io = {
  read=function(k) return db[k] end,
  write=function(k,v) db[k]=v return true end,
  encode=function(v) serial=serial+1 local key="json:"..serial encoded[key]=assert(Notes.validate(v)) return key end,
  decode=function(v) return encoded[v] end,
}
local initial, slot = Notes.load(io,2000)
check(initial and slot == nil, "missing snapshots initialize")
slot = assert(Notes.save(io,s,nil))
check(slot == "notes-a.json", "first snapshot")
s = assert(Notes.apply(s,"add",{},2100))
slot = assert(Notes.save(io,s,slot))
check(slot == "notes-b.json", "alternate snapshot")
local loaded = assert(Notes.load(io,2200))
check(loaded.revision == s.revision, "load latest revision")
db["notes-b.json"] = "broken"
local recovered, oldSlot, warning = Notes.load(io,2300)
check(recovered and oldSlot == "notes-a.json" and warning, "recover corrupt newest snapshot")
local old = db["notes-a.json"]
io.write=function(k,v) db[k]="partial" return false end
check(not Notes.save(io,s,oldSlot) and db["notes-a.json"]==old,"failed save preserves good slot")
db["notes-a.json"]="broken"
check(not Notes.load(io,2400), "both corrupt must not initialize or overwrite")
print("notes_spec: "..total.." checks passed")
