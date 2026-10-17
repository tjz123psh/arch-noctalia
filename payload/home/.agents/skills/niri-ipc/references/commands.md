# Niri IPC command catalog

Detailed command examples. Before using these snippets, set `SKILL_DIR="$HOME/.agents/skills/niri-ipc"`; it is a shell variable naming this skill's directory. For socket
protocol/schema see `ipc.md`.

## Query state (`niri.py`)

```bash
SKILL_DIR/scripts/niri.py version
SKILL_DIR/scripts/niri.py outputs
SKILL_DIR/scripts/niri.py workspaces
SKILL_DIR/scripts/niri.py windows
SKILL_DIR/scripts/niri.py focused-window
```

## Actions (`niri.py action ...`)

```bash
# Focus workspace by index
SKILL_DIR/scripts/niri.py action focus-workspace 2

# Move focused window to workspace
SKILL_DIR/scripts/niri.py action move-window-to-workspace 3

# Focus a window by id
SKILL_DIR/scripts/niri.py action focus-window 123

# Close focused window
SKILL_DIR/scripts/niri.py action close-window

# Reload niri config
SKILL_DIR/scripts/niri.py action load-config-file

# Spawn (no shell)
SKILL_DIR/scripts/niri.py action spawn -- alacritty

# Spawn through shell
SKILL_DIR/scripts/niri.py action spawn-sh -- 'notify-send hello'
```

## High-level helpers (window matching, `niri_ctl.py`)

Refer to windows by **title/app_id substring** instead of ids:

```bash
# List windows (optionally filtered)
SKILL_DIR/scripts/niri_ctl.py list-windows --query firefox

# Focus a window by substring match
SKILL_DIR/scripts/niri_ctl.py focus firefox

# Close a matched window (focus then close)
SKILL_DIR/scripts/niri_ctl.py close firefox

# Move a matched window to a workspace (by index or by name)
SKILL_DIR/scripts/niri_ctl.py move-to-workspace firefox 3
SKILL_DIR/scripts/niri_ctl.py move-to-workspace firefox web

# Focus a workspace by index or name
SKILL_DIR/scripts/niri_ctl.py focus-workspace 2
SKILL_DIR/scripts/niri_ctl.py focus-workspace web
```

## Workspace layout presets (`niri_layout.py`)

Save, list, and restore window arrangements — useful for context switching
between coding, browsing, chat, etc.

```bash
# Save current layout
SKILL_DIR/scripts/niri_layout.py save coding

# Restore a saved layout (moves windows to their workspaces)
SKILL_DIR/scripts/niri_layout.py load coding

# List saved layouts
SKILL_DIR/scripts/niri_layout.py list

# Show current workspace overview
SKILL_DIR/scripts/niri_layout.py status
```

## Raw socket access (`niri_socket.py`)

Talk to `$NIRI_SOCKET` directly (newline-delimited JSON):

```bash
# Send a simple request (JSON string)
SKILL_DIR/scripts/niri_socket.py raw '"FocusedWindow"'

# Batch requests: one JSON request per line on stdin
printf '%s\n' '"FocusedWindow"' '"Workspaces"' | SKILL_DIR/scripts/niri_socket.py stdin

# Event stream (prints JSON events until interrupted)
SKILL_DIR/scripts/niri_socket.py event-stream
```

## Output configuration

```bash
SKILL_DIR/scripts/niri.py output --help
```

## Working directly with `niri msg`

If you don't want the helper script, call Niri directly:

```bash
niri msg --json windows
niri msg --json action focus-workspace 2
```

Tip: if `niri msg` parsing errors happen after upgrades, restart the compositor
(new `niri msg` against old compositor is a common mismatch).

## Event stream

For status bars/daemons: Niri can stream events.

```bash
# Raw JSON event lines (runs until interrupted)
SKILL_DIR/scripts/niri.py event-stream

# Just a few lines for a quick test
SKILL_DIR/scripts/niri.py event-stream --lines 5
```

Event-driven automation: the `event-stream` feeds JSON lines as events happen.
An agent can subscribe to react to desktop changes:

```
WindowOpened   →  auto-arrange tiles or notify context
WorkspaceFocus →  update agent's "where the user is"
WindowClosed   →  clean up tracking state
```
