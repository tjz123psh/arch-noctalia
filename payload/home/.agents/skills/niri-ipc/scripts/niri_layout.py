#!/usr/bin/env python3
"""
niri_layout.py — workspace layout presets for Niri.

Save, list, and restore window arrangements per workspace.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

LAYOUT_DIR = Path.home() / ".config" / "niri" / "layouts"

def _niri_msg(*args: str) -> dict:
    result = subprocess.run(
        ["niri", "msg", "--json", *args],
        capture_output=True, text=True,
    )
    return json.loads(result.stdout)

def _niri_action(action: str, *args: str) -> None:
    subprocess.run(["niri", "msg", "action", action, *args])

def _get_focused_output() -> str:
    """Return the name of the currently focused output."""
    outputs = _niri_msg("outputs")
    for out in outputs:
        if out.get("is-focused", False):
            return out.get("name", "")
    return ""

def save(name: str) -> None:
    """Save current window layout as a named preset."""
    layout_dir = LAYOUT_DIR
    layout_dir.mkdir(parents=True, exist_ok=True)

    workspaces = _niri_msg("workspaces")
    windows = _niri_msg("windows")
    focused = _niri_msg("focused-window")

    preset = {
        "name": name,
        "workspaces": [],
        "focused_workspace": None,
    }

    for ws in workspaces:
        ws_id = ws.get("id")
        ws_idx = ws.get("idx")
        ws_name = ws.get("name", "")
        if ws_name == "":
            ws_name = str(ws_idx)

        ws_windows = [w for w in windows if w.get("workspace_id") == ws_id]

        workspace_info = {
            "id": ws_id,
            "index": ws_idx,
            "name": ws_name,
            "windows": [
                {
                    "app_id": w.get("app_id", ""),
                    "title": w.get("title", ""),
                    "id": w.get("id"),
                }
                for w in ws_windows
            ],
        }
        preset["workspaces"].append(workspace_info)

        if ws.get("is-focused", False):
            preset["focused_workspace"] = ws_idx

    filepath = layout_dir / f"{name}.json"
    filepath.write_text(json.dumps(preset, indent=2, ensure_ascii=False))
    print(f"✅  Layout '{name}' saved ({len(windows)} windows, {len(workspaces)} workspaces)")


def load(name: str) -> None:
    """Restore a named layout preset."""
    filepath = LAYOUT_DIR / f"{name}.json"
    if not filepath.exists():
        print(f"❌  Layout '{name}' not found at {filepath}")
        sys.exit(1)

    preset = json.loads(filepath.read_text())

    # For now: just move windows and workspaces
    # More nuanced restore could spawn apps, etc.
    for ws in preset["workspaces"]:
        ws_idx = ws["index"]
        for win in ws["windows"]:
            app_id = win.get("app_id", "")
            title = win.get("title", "")
            # Try to find window by app_id and move it
            windows = _niri_msg("windows")
            matches = [
                w for w in windows
                if w.get("app_id") == app_id
                and w.get("workspace_id") != ws.get("id")
            ]
            for match in matches:
                wid = match["id"]
                _niri_action("move-window-to-workspace", str(ws_idx), str(wid))

    # Focus the saved workspace
    if preset.get("focused_workspace"):
        _niri_action("focus-workspace", str(preset["focused_workspace"]))

    print(f"✅  Layout '{name}' restored")


def list_presets() -> None:
    """List all saved layout presets."""
    if not LAYOUT_DIR.exists():
        print("No saved layouts.")
        return

    presets = sorted(LAYOUT_DIR.glob("*.json"))
    if not presets:
        print("No saved layouts.")
        return

    for p in presets:
        data = json.loads(p.read_text())
        ws_count = len(data.get("workspaces", []))
        win_count = sum(len(ws.get("windows", [])) for ws in data.get("workspaces", []))
        print(f"  {p.stem}: {ws_count} workspaces, {win_count} windows")


def status() -> None:
    """Show current workspace layout overview."""
    workspaces = _niri_msg("workspaces")
    windows = _niri_msg("windows")

    for ws in workspaces:
        ws_id = ws.get("id")
        ws_idx = ws.get("idx")
        ws_name = ws.get("name", "")
        focused = " ◂" if ws.get("is-focused", False) else ""

        ws_windows = [w for w in windows if w.get("workspace_id") == ws_id]
        win_str = ", ".join(w.get("app_id", "?") for w in ws_windows[:3])
        if len(ws_windows) > 3:
            win_str += f" +{len(ws_windows)-3}"

        label = ws_name if ws_name else f"WS #{ws_idx}"
        print(f"  {label}{focused}: {win_str}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: niri_layout.py <save|load|list|status> [name]")
        sys.exit(1)

    command = sys.argv[1]

    if command == "save":
        if len(sys.argv) < 3:
            print("Usage: niri_layout.py save <name>")
            sys.exit(1)
        save(sys.argv[2])

    elif command == "load":
        if len(sys.argv) < 3:
            print("Usage: niri_layout.py load <name>")
            sys.exit(1)
        load(sys.argv[2])

    elif command == "list":
        list_presets()

    elif command == "status":
        status()

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)
