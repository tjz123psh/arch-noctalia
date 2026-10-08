#!/usr/bin/env python3
"""Run generated scripts against disposable fixtures, never the real desktop/data."""
import concurrent.futures
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def command(kind):
    script = r'''
local env = setmetatable({arg={"sidebar/panel.luau", "--harness"}}, {__index=_G})
local H=assert(loadfile("sidebar/tests/sidebar_spec.lua", "t", env))()
local h=H.harness() h.env.onOpen()
if KIND == "apps" then h:step(300) h:step(16)
else h:settle() h.env.onNoteSwitch("2") end
for _,req in ipairs(h.async) do
  local c=req.command
  if KIND == "apps" and type(c)=="string" and c:find("XDG_DATA_DIRS",1,true) then io.write(c) return end
  if KIND == "notes" and type(c)=="table" and c[4]=="sidebar-note-create" then io.write(c[3]) return end
end
error("script not found")
'''.replace('KIND', repr(kind))
    return subprocess.run(["lua", "-"], input=script, text=True, cwd=ROOT,
                          capture_output=True, check=True).stdout

def desktop(name, extra=""):
    return "[Desktop Entry]\nType=Application\nName=" + name + "\nExec=example %U\n" + extra

with tempfile.TemporaryDirectory(prefix="sidebar-shell-spec-") as temporary:
    # Cleanup is limited to this test-created exact path and its own fixtures.
    base = Path(temporary).resolve()
    assert base.parent == Path(tempfile.gettempdir()).resolve()
    assert base.name.startswith("sidebar-shell-spec-")
    user = base / "user data"
    system = base / "system data"
    for root in (user, system):
        (root / "applications").mkdir(parents=True)
    (user / "applications" / "hidden.desktop").write_text(desktop("Hidden", "Hidden=true\n"))
    (system / "applications" / "hidden.desktop").write_text(desktop("Hidden system"))
    (system / "applications" / "one.desktop").write_text(desktop("Same"))
    (system / "applications" / "two.desktop").write_text(desktop("Same"))
    (system / "applications" / "nested").mkdir()
    (system / "applications" / "nested" / "space name.desktop").write_text(desktop("Nested", "Terminal=true\n"))
    child_env = dict(os.environ, XDG_DATA_HOME=str(user), XDG_DATA_DIRS=str(system), LC_ALL="C")
    scan = subprocess.run(["sh", "-c", command("apps")], text=True, env=child_env,
                          capture_output=True, check=True)
    rows = [line.split("\t") for line in scan.stdout.splitlines()]
    assert len(rows) == 5 and all(len(row) == 7 for row in rows), scan.stdout
    assert rows[0][5:] == ["hidden.desktop", "0"]
    assert any(row[5] == "nested-space name.desktop" and row[3] == "1" for row in rows)
    assert all(row[1] == "example %U" for row in rows), "Exec placeholders must remain intact"
    print("PASS generated XDG scanner: priority, hidden tombstones, nested paths, spaces, unchanged Exec")

    notes = base / "notes with spaces"
    notes.mkdir()
    original = notes / "便签.md"
    external = notes / "便签-2.md"
    original.write_text("original note")
    external.write_text("external note")
    (notes / "便签-3.md").symlink_to(base / "absent-target")
    create = command("notes")
    def new_note(_):
        return subprocess.run(["sh", "-c", create, "sidebar-note-create", str(notes)],
                              capture_output=True, text=True, check=True).stdout.strip()
    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        names = list(pool.map(new_note, range(12)))
    assert len(set(names)) == 12
    assert original.read_text() == "original note" and external.read_text() == "external note"
    assert not (base / "absent-target").exists()
    assert all((notes / name).read_text() == "" for name in names)
    print("PASS exclusive note creation: 12 concurrent writers, existing content, dangling symlinks, spaced directory")
print("2 isolated shell integration tests passed")
