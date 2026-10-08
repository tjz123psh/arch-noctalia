#!/usr/bin/env python3
"""Run generated scripts against disposable fixtures, never the real desktop/data."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def command():
    script = r'''
local env = setmetatable({arg={"sidebar/panel.luau", "--harness"}}, {__index=_G})
local H=assert(loadfile("sidebar/tests/sidebar_spec.lua", "t", env))()
local h=H.harness() h.env.onOpen()
h:step(300) h:step(16)
for _,req in ipairs(h.async) do
  local c=req.command
  if type(c)=="string" and c:find("XDG_DATA_DIRS",1,true) then io.write(c) return end
end
error("script not found")
'''
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
    scan = subprocess.run(["sh", "-c", command()], text=True, env=child_env,
                          capture_output=True, check=True)
    rows = [line.split("\t") for line in scan.stdout.splitlines()]
    assert len(rows) == 5 and all(len(row) == 7 for row in rows), scan.stdout
    assert rows[0][5:] == ["hidden.desktop", "0"]
    assert any(row[5] == "nested-space name.desktop" and row[3] == "1" for row in rows)
    assert all(row[1] == "example %U" for row in rows), "Exec placeholders must remain intact"
    print("PASS generated XDG scanner: priority, hidden tombstones, nested paths, spaces, unchanged Exec")
print("1 isolated shell integration test passed")
