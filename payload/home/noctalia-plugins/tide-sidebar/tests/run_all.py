#!/usr/bin/env python3
"""Offline checks only: never toggles a hotspot or opens/closes a real window."""
from pathlib import Path
import json
import re
import subprocess
import sys
import tomllib

ROOT = Path(__file__).resolve().parents[2]
PLUGIN = ROOT / "tide-sidebar"


def run(argv):
    print("+ " + " ".join(map(str, argv)), flush=True)
    try:
        result = subprocess.run(argv, cwd=ROOT, check=False, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except FileNotFoundError as error:
        print("Missing test tool: " + str(error.filename), file=sys.stderr)
        raise SystemExit(2)
    print(result.stdout, end="", flush=True)
    if result.returncode:
        raise SystemExit(result.returncode)
    return result.stdout


# Channels the service publishes but no view consumes (diagnostics only).
WRITE_ONLY_CHANNELS = {"geometry"}


def check_channel_parity():
    """Every published snapshot channel must be one the native front end reads."""
    lua = (PLUGIN / "lib/frontend.luau").read_text(encoding="utf-8")
    declared = set(re.findall(r"([a-z_]+)=true", re.search(r"local names=\{([^}]*)\}", lua).group(1)))
    js = (PLUGIN / "native/main.js").read_text(encoding="utf-8")
    raw = re.search(r"const channels = \[([^\]]*)\]", js).group(1)
    bridged = {item.strip().strip("'\"") for item in raw.split(",") if item.strip()}
    missing = sorted(declared - bridged - WRITE_ONLY_CHANNELS)
    if missing:
        raise SystemExit("native/main.js never reads published channels: " + ", ".join(missing))
    extra = sorted(bridged - declared)
    if extra:
        raise SystemExit("native/main.js listens to unpublished channels: " + ", ".join(extra))
    print("PASS: " + str(len(declared)) + " snapshot channels wired to the native front end")


def check_documentation_links():
    """Relative links (and their anchors) in the repository docs must resolve."""
    broken, checked = [], 0
    for path in [ROOT / "README.md", PLUGIN / "README.md", *sorted((PLUGIN / "docs").glob("*.md"))]:
        for target in re.findall(r"\]\(<?([^)>]+)>?\)", path.read_text(encoding="utf-8")):
            if target.startswith(("http://", "https://")):
                continue
            checked += 1
            file_part, _, anchor = target.partition("#")
            destination = path.parent / (file_part or path.name)
            if not destination.exists():
                broken.append(path.name + " -> " + target)
                continue
            if anchor and destination.suffix == ".md":
                headings = {re.sub(r"^#+\s*", "", line).strip()
                            for line in destination.read_text(encoding="utf-8").splitlines() if line.startswith("#")}
                if anchor not in headings:
                    broken.append(path.name + " -> " + target + " (no such heading)")
    if broken:
        raise SystemExit("Broken documentation links: " + "; ".join(broken))
    print("PASS: " + str(checked) + " documentation links and anchors resolve")

def check_plugin_settings():
    """Declared settings must be complete, translated, and the only keys read."""
    manifest = tomllib.loads((PLUGIN / "plugin.toml").read_text(encoding="utf-8"))
    settings = manifest.get("setting", [])
    if not settings:
        raise SystemExit("plugin.toml declares no settings")
    keys = []
    for entry in settings:
        for field in ("key", "type", "label_key", "default"):
            if field not in entry:
                raise SystemExit("Setting is missing " + field + ": " + repr(entry))
        keys.append(entry["label_key"])
        if "description_key" in entry:
            keys.append(entry["description_key"])
        for option in entry.get("options", []):
            keys.append(option["label_key"])
    for name in ("en.json", "zh-Hans.json"):
        data = json.loads((PLUGIN / "translations" / name).read_text(encoding="utf-8"))
        for key in keys:
            node = data
            for part in key.split("."):
                if not isinstance(node, dict) or part not in node:
                    raise SystemExit(name + " is missing translation " + key)
                node = node[part]
            if not isinstance(node, str) or not node.strip():
                raise SystemExit(name + " has an empty translation for " + key)
    declared = {entry["key"] for entry in settings}
    service = (PLUGIN / "service.luau").read_text(encoding="utf-8")
    used = set(re.findall(r'setting\("([a-z0-9_]+)"', service))
    used |= set(re.findall(r'getConfig\("([a-z0-9_]+)"', service))
    undeclared = sorted(used - declared)
    if undeclared:
        raise SystemExit("service.luau reads undeclared settings: " + ", ".join(undeclared))
    print("PASS: " + str(len(settings)) + " plugin settings, " + str(len(keys)) + " translation keys resolved in en and zh-Hans")


for test in ("notes_spec.lua", "tools_spec.lua", "stopwatch_spec.lua", "service_spec.lua", "frontend_spec.lua", "panel_spec.lua"):
    run(["lua", str(PLUGIN / "tests" / test)])
run([sys.executable, "-B", str(PLUGIN / "tests/system_spec.py"), "-q"])
run(["node", str(PLUGIN / "tests/native_transport_spec.mjs")])
native_env = ["env", "LD_PRELOAD=/usr/lib/libgtk4-layer-shell.so", "GDK_BACKEND=wayland", "G_DEBUG=fatal-warnings"]
run([*native_env, "gjs", "-m", str(PLUGIN / "native/main.js"), "--check"])
for name in ("native_notes_spec.js", "native_tools_spec.js", "native_system_spec.js"):
    run([*native_env, "gjs", "-m", str(PLUGIN / "tests" / name)])

sources = ["panel.luau", "service.luau", "widget.luau", "shortcut.luau",
           "lib/notes.luau", "lib/calculator.luau", "lib/countdown.luau",
           "lib/frontend.luau", "lib/stopwatch.luau"]
for name in sources + ["README.md", "open.sh", "translations/en.json", "translations/zh-Hans.json", "docs/sdk-notes.md"]:
    text = (PLUGIN / name).read_text(encoding="utf-8")
    if any(ord(char) < 32 and char not in "\n\r\t" for char in text):
        raise SystemExit("Unexpected control character in " + name)
check_plugin_settings()
check_channel_parity()
check_documentation_links()
run(["bash", "-n", str(PLUGIN / "open.sh")])
run(["luac", "-p", *[str(PLUGIN / name) for name in sources]])
report = run(["noctalia", "plugins", "lint", str(PLUGIN)])
# Noctalia v5.2.1 can return exit 0 even when author lint reports errors.
summary = re.search(r"(?m)^\s*(\d+) errors?, (\d+) warnings?\s*$", report)
if not summary or int(summary.group(1)):
    raise SystemExit("Noctalia lint did not confirm zero errors")
print("PASS: logic, native GTK construction, callbacks, transport and metadata checks. No user data or visible windows changed.")
