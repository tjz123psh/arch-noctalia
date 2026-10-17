---
name: niri-ipc
description: "Query or control live Niri state with `niri msg`: outputs, workspaces, windows, focus, move/close, spawn, and reload. Not for general desktop advice."
when-to-use: >
  Use when you need to query Niri state (outputs/workspaces/windows/focused window) or perform
  actions (focus/move/close windows, switch workspaces, spawn commands, reload config) from an
  agent running on a Niri session. Do not use for general Linux desktop advice.
---

# Niri IPC

Control Niri through the `niri msg` CLI (preferred) or by writing JSON requests
to `$NIRI_SOCKET`. Assumes Linux with Niri running and `$NIRI_SOCKET` set
(usually true inside the Niri session).

## Quick start

Use the bundled helper (wrapper around `niri msg --json`). Before running an
example, resolve the documented placeholder once in the current shell:

```bash
SKILL_DIR="$HOME/.agents/skills/niri-ipc"
```

`SKILL_DIR` below is a shell variable, not a literal command.

```bash
SKILL_DIR/scripts/niri.py version
SKILL_DIR/scripts/niri.py outputs
SKILL_DIR/scripts/niri.py workspaces
SKILL_DIR/scripts/niri.py windows
SKILL_DIR/scripts/niri.py focused-window
```

For complex automation (pick a window by title/app_id, then act by id), query
`windows` first, then act on the matched id — or use the substring helpers in
`niri_ctl.py`.

## Scripts and command catalog

Four helpers under `scripts/`:

- `niri.py` — query state and pass through actions (`action ...`).
- `niri_ctl.py` — high-level window matching by title/app_id substring.
- `niri_layout.py` — save/list/restore workspace layout presets.
- `niri_socket.py` — raw newline-delimited JSON to `$NIRI_SOCKET`.

Full command examples for all four: read `SKILL_DIR/references/commands.md`.

## Config hot-reload guard

When modifying `~/.config/niri/config.kdl`, validate and apply after every
change. Snapshot first so you can roll back.

```bash
# Snapshot current layout before reload
SKILL_DIR/scripts/niri_layout.py save auto-before-reload

# Reload config (on syntax error, niri keeps the old config)
SKILL_DIR/scripts/niri.py action load-config-file

# If nothing happens, check logs:
journalctl --user -u niri --no-pager -n 10
```

Roll back with `niri_layout.py load auto-before-reload` if the new config feels
wrong.

## Troubleshooting

- `NIRI_SOCKET is not set`: run inside your Niri session, or export the socket
  path.
- Socket protocol details and schema: read `SKILL_DIR/references/ipc.md`.
- `niri msg` parsing errors after an upgrade: restart the compositor (new
  `niri msg` against old compositor is a common mismatch).
