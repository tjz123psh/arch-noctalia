#!/usr/bin/env python3
"""Run actual generated timer workers in disposable dirs; no desktop notifications."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
LABEL = "完成 '示例' <b> & $(echo noop)"
TASK = {"label": LABEL, "note": "今日 '计划'.md", "line": 2}
LUA = r'''
local e=setmetatable({arg={"--harness"}},{__index=_G})
local T=assert(loadfile("sidebar/tests/notes_spec.lua","t",e))()
local h=T.new()
h.env.noctalia.pluginDataDir=function() return assert(os.getenv("TIMER_TEST_DIR")) end
local encode=h.env.noctalia.json.encode
h.env.noctalia.json.encode=function(v)
  if v.label then return assert(os.getenv("TIMER_TEST_TASK")) end
  return encode(v)
end
if os.getenv("TIMER_TEST_GENERIC")=="1" then h.env.onTimerSetSec(30); h.env.onTimerToggle()
else h.env.onNoteFocus(2) end
io.write(T.take(h,"start").command)
'''


def wait_for(predicate, timeout=6):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.025)
    return False


def alive(pid):
    try:
        state = Path(f"/proc/{pid}/stat").read_text().rsplit(") ", 1)[1].split()[0]
        return state not in ("Z", "X")
    except (FileNotFoundError, ProcessLookupError):
        return False


class TimerWorkerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sidebar-timer-spec-")
        self.base = Path(self.temp.name).resolve()
        self.data = self.base / "data '目录'"
        self.data.mkdir()
        self.pf = self.data / "timer.pid"
        self.log = self.base / "notifications.jsonl"
        self.bin = self.base / "bin"
        self.bin.mkdir()
        stub = self.bin / "notify-send"
        stub.write_text("#!/usr/bin/env python3\nimport json,os,sys\nwith open(os.environ['TIMER_TEST_LOG'],'a') as f: f.write(json.dumps(sys.argv[1:],ensure_ascii=False)+'\\n')\n")
        stub.chmod(0o700)
        self.env = dict(os.environ, PATH=str(self.bin) + ":" + os.environ.get("PATH", "/usr/bin:/bin"),
                        TIMER_TEST_DIR=str(self.data), TIMER_TEST_LOG=str(self.log),
                        TIMER_TEST_TASK=json.dumps(TASK, ensure_ascii=False))
        self.workers = []

    def tearDown(self):
        # Only revoke this test's exact owned record; never signal any user PID.
        if self.pf.exists() and not self.pf.is_symlink():
            self.pf.write_text("")
        for pid in self.workers:
            self.assertTrue(wait_for(lambda: not alive(pid)), "test worker did not exit")
        assert self.base.parent == Path(tempfile.gettempdir()).resolve()
        assert self.base.name.startswith("sidebar-timer-spec-")
        self.temp.cleanup()

    def command(self, generic=False):
        env = dict(self.env, TIMER_TEST_GENERIC="1" if generic else "0")
        return subprocess.run(["lua", "-"], input=LUA, text=True, cwd=ROOT, env=env,
                              capture_output=True, check=True, timeout=10).stdout

    def run_command(self, command):
        return subprocess.run(["sh", "-c", command], env=self.env, text=True,
                              capture_output=True, timeout=10)

    def start(self, command):
        result = self.run_command(command)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        kind, pid, birth, token = result.stdout.strip().split()
        self.assertEqual(kind, "LIVE")
        self.workers.append(int(pid))
        raw = f"v2 {pid} {birth} {token}"
        self.assertEqual(self.pf.read_text().strip(), raw)
        return raw

    @staticmethod
    def action(command, action, raw):
        # These generated control parameters contain only protocol numbers/dashes.
        return command.replace("action='start'", f"action='{action}'", 1).replace("expected=''", f"expected='{raw}'", 1)

    def test_focus_notification_and_matching_private_metadata(self):
        command = self.command()
        self.assertIn("secs='1500'", command)
        # Exercise the actual 25m worker protocol with a one-second test duration.
        raw = self.start(command.replace("secs='1500'", "secs='1'", 1))
        sidecar = self.data / "timer.pid.task"
        owner, payload = sidecar.read_text().splitlines()
        self.assertEqual(owner, raw)
        self.assertEqual(json.loads(payload), TASK)
        self.assertEqual(sidecar.stat().st_mode & 0o777, 0o600)
        self.assertTrue(wait_for(lambda: self.log.exists() and self.log.stat().st_size > 0))
        args = json.loads(self.log.read_text().splitlines()[0])
        self.assertEqual(args[:3], ["-a", "sidebar-panel", "专注计时"])
        self.assertIn("25 分钟到了", args[3])
        self.assertIn("完成 '示例' &lt;b&gt; &amp; $(echo noop)", args[3])
        self.assertEqual(self.pf.read_text(), "")

    def test_stop_and_generic_timer_do_not_inherit_task(self):
        command = self.command()
        raw = self.start(command)
        probe = self.run_command(self.action(command, "probe", raw))
        self.assertEqual(probe.returncode, 0)
        self.assertTrue(probe.stdout.startswith("LIVE "))
        stop = self.run_command(self.action(command, "stop", raw))
        self.assertEqual(stop.returncode, 0)
        self.assertEqual(stop.stdout.strip(), "STOPPED")
        self.assertTrue(wait_for(lambda: not alive(self.workers[0])))
        self.assertFalse(self.log.exists())
        generic = self.command(generic=True)
        self.assertIn("title='计时器'", generic)
        new = self.start(generic)
        self.assertNotEqual(new, raw)
        self.assertEqual((self.data / "timer.pid.task").read_text(), new + "\n\n")
        self.assertEqual(self.run_command(self.action(generic, "stop", new)).returncode, 0)

    def test_symlink_metadata_is_rejected_before_start(self):
        target = self.base / "unrelated.txt"
        target.write_text("do not overwrite")
        (self.data / "timer.pid.task").symlink_to(target)
        result = self.run_command(self.command())
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_text(), "do not overwrite")
        self.assertFalse(self.pf.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
