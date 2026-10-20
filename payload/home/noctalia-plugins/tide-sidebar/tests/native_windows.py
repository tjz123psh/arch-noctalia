#!/usr/bin/env python3
"""Opt-in Wayland test. Creates and closes ONLY two test-owned Kitty windows.

Run manually: python3 tide-sidebar/tests/native_windows.py --allow-test-windows
Requires the enabled plugin, niri, Kitty and the current Wayland session.
Never toggles a network or closes any window that was not created by this test.
"""
import argparse
import json
import os
import subprocess
import time
import uuid


def command(*args):
    return subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=8).stdout


def windows():
    return json.loads(command("niri", "msg", "--json", "windows"))


def wait_for(predicate, label, seconds=6):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.08)  # bounded synchronization with the compositor, not a background job
    raise AssertionError(label)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--allow-test-windows", action="store_true")
    args = parser.parse_args()
    if not args.allow_test_windows:
        parser.error("explicit --allow-test-windows is required")
    marker = "tide-test-" + uuid.uuid4().hex
    processes = []
    owned = set()
    created = []
    command("noctalia", "msg", "panel-close", "pang/tide-sidebar:sidebar")

    def act(action, ident):
        assert ident in owned, "refusing to operate on a non-test window"
        return command("noctalia", "msg", "plugin", "pang/tide-sidebar:backend",
                       "all", action + "-window", ident)

    try:
        for suffix in ("a", "b"):
            app_id = marker + "-" + suffix
            process = subprocess.Popen(
                ["kitty", "--class", app_id, "--title", "潮汐侧栏 · 临时验收 " + suffix.upper(),
                 "/bin/sh", "-c", "printf 'Tide sidebar temporary verification window.\\nNo user files are opened.\\n'; exec sleep 60"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            processes.append(process)
            row = wait_for(lambda: next((w for w in windows() if w.get("app_id") == app_id), None),
                           "test window did not appear")
            ident = str(row["id"])
            owned.add(ident)
            created.append(ident)
        a, b = created
        wait_for(lambda: any(str(w["id"]) == b and w.get("is_focused") for w in windows()),
                 "second test window did not receive focus")
        act("focus", a)
        wait_for(lambda: any(str(w["id"]) == a and w.get("is_focused") for w in windows()),
                 "plugin failed to focus the first test window")
        print("PASS native plugin focus: second test window -> first test window")
        for ident in (a, b):
            act("close", ident)
            wait_for(lambda: all(str(w["id"]) != ident for w in windows()),
                     "plugin failed to close its test window")
            print("PASS native plugin normal close: test-owned window")
        print("PASS native window verification: no existing window was targeted")
    finally:
        for row in windows():
            ident = str(row["id"])
            if row.get("app_id", "").startswith(marker + "-"):
                owned.add(ident)
                try:
                    act("close", ident)
                except (subprocess.SubprocessError, AssertionError):
                    pass
        for process in processes:
            try:
                process.wait(timeout=4)
            except subprocess.TimeoutExpired:
                # Only an exact Popen handle created above, never pgrep/pkill or a user's app.
                process.terminate()
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=2)


if __name__ == "__main__":
    main()
