#!/usr/bin/env python3
"""Offline only. Every subprocess is mocked; no desktop/network actions occur.
Run: python3 -B tide-sidebar/tests/system_spec.py
"""
import contextlib
import fcntl
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

SPEC = importlib.util.spec_from_file_location("tide_system", Path(__file__).parents[1] / "helpers/system.py")
system = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = system
SPEC.loader.exec_module(system)

# Deliberately invented fixture value. No test opens a real user's password file.
FAKE_SECRET = "ONLY-TEST-PASSPHRASE-9876"
UUID = "12345678-1234-1234-1234-123456789abc"


class FakeRunner:
    def __init__(self):
        self.calls = []
        self.on = False
        self.ssid = "Test network"
        self.band = "bg"
        self.mode = "ap"
        self.shared = "shared"
        self.nm_failure = False
        self.niri_result = None
        self.operation_result = system.Result()
        self.on_operation = None
        self.action_result = system.Result()
        self.window_rows = [{"id": 23, "title": "Sample app", "app_id": "org.test.App",
                             "workspace_id": 3, "is_focused": True}]

    def __call__(self, argv, **kwargs):
        argv = list(argv)
        self.calls.append((argv, kwargs))
        if argv[0] == "/usr/bin/timeout":
            if self.on_operation:
                self.on_operation(argv, kwargs)
            if self.operation_result.code == 0:
                self.on = argv[-1] == "on"
            return self.operation_result
        if argv[:4] == ["/usr/bin/niri", "msg", "--json", "windows"]:
            return self.niri_result or system.Result(stdout=json.dumps(self.window_rows))
        if argv[:3] == ["/usr/bin/niri", "msg", "action"]:
            return self.action_result
        if argv[0] != "/usr/bin/nmcli":
            raise AssertionError("Unexpected command: " + repr(argv))
        if self.nm_failure:
            return system.Result(code=1, stderr=FAKE_SECRET)
        fields = argv[5]
        if fields == "DEVICE,TYPE,STATE,CONNECTION":
            return system.Result(stdout="wlp3s0:wifi:connected:" + ("rice-hotspot" if self.on else "Existing wifi") + "\n")
        if fields == "NAME,UUID,TYPE,DEVICE":
            return system.Result(stdout=("rice-hotspot:" + UUID + ":802-11-wireless:wlp3s0\n") if self.on else "Existing wifi:" + UUID + ":802-11-wireless:wlp3s0\n")
        if fields.startswith("802-11-wireless.ssid"):
            escaped_ssid = self.ssid.replace("\\", "\\\\").replace(":", "\\:")
            return system.Result(stdout="802-11-wireless.ssid:" + escaped_ssid + "\n802-11-wireless.band:" + self.band + "\n802-11-wireless.mode:" + self.mode + "\nipv4.method:" + self.shared + "\n")
        if fields == "IP4.ADDRESS":
            return system.Result(stdout="IP4.ADDRESS[1]:10.42.0.1/24\n")
        raise AssertionError("Unexpected nmcli fields: " + fields)


class BackendSpec(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tide-system-test-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.state = self.home / "state/rice-hotspot"
        self.state.mkdir(parents=True, mode=0o700)
        self.script = self.home / "scripts/desktop/rice-hotspot"
        self.script.parent.mkdir(parents=True)
        self.script.write_text("#!/bin/sh\nexit 99\n")
        self.script.chmod(0o700)
        self.paths = system.Paths(self.home, self.state, self.home / "config/rice-hotspot.conf",
                                  self.home / "runtime/noctalia-tide-sidebar", self.script)
        self.runner = FakeRunner()
        self.backend = system.Backend(env={"HOME": str(self.home), "PATH": "/usr/bin:/bin"},
                                      paths=self.paths, runner=self.runner)
        self.state.joinpath("ssid").write_text(self.runner.ssid)
        self.state.joinpath("band_desired").write_text("bg")
        self.process_guard = patch.object(system.subprocess, "run", side_effect=AssertionError("No real subprocess is allowed in tests"))
        self.process_guard.start()
        self.addCleanup(self.process_guard.stop)
        self.popen_guard = patch.object(system.subprocess, "Popen", side_effect=AssertionError("No real subprocess is allowed in tests"))
        self.popen_guard.start()
        self.addCleanup(self.popen_guard.stop)

    def request(self, data):
        path = Path(self.backend.prepare_request()["path"])
        path.write_text(json.dumps(data), encoding="utf-8")
        return path

    def assert_error(self, code, callback):
        with self.assertRaises(system.BackendError) as caught:
            callback()
        self.assertEqual(caught.exception.code, code)
        self.assertNotIn(FAKE_SECRET, str(caught.exception))

    def test_snapshot_never_reads_password_or_config_or_creates_lock(self):
        password = self.state / "password"
        password.write_text(FAKE_SECRET)
        password.chmod(0o600)
        self.paths.config.parent.mkdir()
        self.paths.config.write_text("RICE_HOTSPOT_PASSWORD=" + FAKE_SECRET)
        original = system._read_small
        read_names = []
        def guarded(path, limit, **kwargs):
            read_names.append(Path(path).name)
            self.assertIn(Path(path).name, ("ssid", "band_desired"))
            return original(path, limit, **kwargs)
        with patch.object(system, "_read_small", side_effect=guarded):
            result = self.backend.snapshot()
        self.assertEqual(read_names, ["ssid", "band_desired"])
        self.assertFalse(self.paths.private.exists())
        self.assertFalse((self.state / "lock").exists())
        self.assertFalse(result["hotspot"]["on"])
        self.assertFalse(result["hotspot"]["pending"])
        self.assertIsNone(result["hotspot"]["clients"])
        self.assertNotIn(FAKE_SECRET, json.dumps(result))
        for argv, _ in self.runner.calls:
            self.assertNotIn(str(self.script), argv)
            self.assertNotIn("--show-secrets", argv)
            self.assertFalse(any("security.psk" in item for item in argv))
        self.assertEqual(set(result["hotspot"]), {"available", "on", "ssid", "iface", "gateway", "band", "desiredBand",
                                                 "desiredSsidKnown", "desiredBandKnown", "pending", "clients", "error", "warning"})

    def test_recorded_hotspot_state_is_reported_as_known(self):
        # Nothing recorded yet: the sidebar is allowed to apply its own defaults.
        for name in ("ssid", "band_desired"):
            (self.state / name).unlink(missing_ok=True)
        self.assertFalse(self.backend.snapshot()["hotspot"]["desiredSsidKnown"])
        self.assertFalse(self.backend.snapshot()["hotspot"]["desiredBandKnown"])
        (self.state / "ssid").write_text("Tide test")
        (self.state / "band_desired").write_text("a\n")
        hot = self.backend.snapshot()["hotspot"]
        self.assertTrue(hot["desiredSsidKnown"])
        self.assertTrue(hot["desiredBandKnown"])
        self.assertEqual(hot["desiredBand"], "a")
        self.assertEqual(hot["ssid"], "Tide test")

    def test_snapshot_never_acquires_even_an_existing_script_lock(self):
        (self.state / "lock").write_text("")
        with patch.object(system.fcntl, "flock", side_effect=AssertionError("Snapshot must not lock")):
            self.assertTrue(self.backend.snapshot()["ok"])

    def test_ssid_spaces_are_preserved_in_remembered_state(self):
        self.runner.on = True
        self.runner.ssid = "  Test network  "
        self.state.joinpath("ssid").write_text(self.runner.ssid)
        hot = self.backend.hotspot_snapshot()
        self.assertEqual(hot["ssid"], self.runner.ssid)
        self.assertIsNone(hot["pending"])

    def test_invalid_utf8_request_ssid_is_rejected_without_exception_text(self):
        self.assert_error("invalid_ssid", lambda: self.backend._validate_request({"ssid": "\ud800"}))

    def test_malformed_active_connection_output_is_unknown_not_off(self):
        original = self.runner
        def malformed(argv, **kwargs):
            if "NAME,UUID,TYPE,DEVICE" in argv:
                return system.Result(stdout="malformed-connection-row")
            return original(argv, **kwargs)
        self.backend.runner = malformed
        hot = self.backend.hotspot_snapshot()
        self.assertIsNone(hot["on"])
        self.assertTrue(hot["error"])

    def test_active_state_uses_actual_band_and_unknown_password_comparison(self):
        self.runner.on = True
        self.state.joinpath("band_desired").write_text("a")
        hot = self.backend.hotspot_snapshot()
        self.assertTrue(hot["on"])
        self.assertEqual(hot["band"], "bg")
        self.assertEqual(hot["desiredBand"], "a")
        self.assertIsNone(hot["pending"])
        self.assertIn("回落不算待应用", hot["warning"])
        self.assertEqual(hot["gateway"], "10.42.0.1/24")

    def test_pending_is_true_only_for_known_public_difference(self):
        self.runner.on = True
        self.runner.ssid = "Externally changed"
        self.assertIs(self.backend.hotspot_snapshot()["pending"], True)

    def test_nmcli_escaping_preserves_colon_and_backslash(self):
        self.assertEqual(system.split_nmcli(r"a\:b:c\\d:"), ["a:b", "c\\d", ""])
        self.runner.on = True
        self.runner.ssid = "Room:A\\B"
        self.state.joinpath("ssid").write_text(self.runner.ssid)
        hot = self.backend.hotspot_snapshot()
        self.assertEqual(hot["ssid"], self.runner.ssid)
        self.assertIsNone(hot["pending"])

    def test_query_failure_is_unknown_not_off_and_discards_diagnostics(self):
        self.runner.nm_failure = True
        result = self.backend.snapshot()
        self.assertIsNone(result["hotspot"]["on"])
        self.assertFalse(result["hotspot"]["available"])
        self.assertNotIn(FAKE_SECRET, json.dumps(result))

    def test_same_named_non_ap_connection_disables_hotspot_controls(self):
        self.runner.on = True
        self.runner.mode = "infrastructure"
        hot = self.backend.hotspot_snapshot()
        self.assertFalse(hot["available"])
        self.assertIsNone(hot["on"])
        self.assertTrue(hot["error"])

    def test_public_state_symlink_is_not_followed(self):
        target = self.home / "private-other-file"
        target.write_text(FAKE_SECRET)
        self.state.joinpath("ssid").unlink()
        self.state.joinpath("ssid").symlink_to(target)
        result = self.backend.snapshot()
        self.assertNotIn(FAKE_SECRET, json.dumps(result))

    def test_prepare_consume_is_private_single_use_and_keeps_password_off_argv(self):
        path = self.request({"ssid": "$(do-not-execute)", "password": FAKE_SECRET, "band": "a"})
        self.assertEqual(stat.S_IMODE(self.paths.private.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        observed = {}
        def inspect(argv, kwargs):
            self.assertFalse(path.exists())
            self.assertNotIn(FAKE_SECRET, " ".join(argv))
            self.assertEqual(kwargs["env"]["RICE_HOTSPOT_PASSWORD"], FAKE_SECRET)
            self.assertEqual(kwargs["env"]["RICE_HOTSPOT_SSID"], "$(do-not-execute)")
            self.assertTrue(kwargs["discard_stdout"])
            shim_dir = Path(kwargs["env"]["PATH"].split(os.pathsep)[0])
            observed["shim_dir"] = shim_dir
            self.assertEqual((shim_dir / "notify-send").read_text(), "#!/bin/sh\nexit 0\n")
            self.assertEqual(stat.S_IMODE((shim_dir / "notify-send").stat().st_mode), 0o700)
            self.assertEqual(argv, ["/usr/bin/timeout", "--kill-after=2s", "40s", str(self.script), "on"])
        self.runner.on_operation = inspect
        self.runner.operation_result = system.Result(stdout="密码:" + FAKE_SECRET, stderr=FAKE_SECRET)
        result = self.backend.hotspot_action("on", str(path))
        self.assertTrue(result["ok"])
        self.assertNotIn(FAKE_SECRET, json.dumps(result))
        self.assertFalse(observed["shim_dir"].exists())
        self.assertFalse(path.exists())
        self.assertIsNone(result["hotspot"]["warning"])
        self.assert_error("request_unavailable", lambda: self.backend._consume_request(str(path)))

    def test_inherited_shell_hooks_and_credentials_are_not_reused(self):
        self.backend.env.update({"RICE_HOTSPOT_PASSWORD": FAKE_SECRET, "RICE_HOTSPOT_NET_HELPER": "/wrong/helper",
                                 "BASH_ENV": "/wrong/env", "BASH_FUNC_notify-send%%": "unsafe", "ENV": "/wrong/env"})
        path = self.request({"password": "", "band": "bg"})
        self.backend.hotspot_action("apply", str(path))
        operation = [item for item in self.runner.calls if item[0][0] == "/usr/bin/timeout"][0]
        env = operation[1]["env"]
        self.assertNotIn("RICE_HOTSPOT_PASSWORD", env)
        self.assertNotIn("RICE_HOTSPOT_NET_HELPER", env)
        self.assertNotIn("BASH_ENV", env)
        self.assertNotIn("ENV", env)
        self.assertNotIn("BASH_FUNC_notify-send%%", env)
        self.assertEqual(operation[0][-1], "on")

    def test_script_warning_classification_never_returns_original_text(self):
        path = self.request({})
        self.runner.operation_result = system.Result(stderr="[warn] 自动回落到 2.4GHz " + FAKE_SECRET + "\n转发放行没成功\n没能自动连回")
        result = self.backend.hotspot_action("on", str(path))
        self.assertTrue(result["ok"])
        self.assertIn("共享网络转发", result["warning"])
        self.assertIn("恢复原 Wi-Fi", result["warning"])
        self.assertNotIn(FAKE_SECRET, json.dumps(result))
        self.assertNotIn("[warn]", json.dumps(result))

    def test_off_needs_no_password_request_and_does_not_read_saved_password(self):
        original = system._read_small
        def public_only(path, limit, **kwargs):
            self.assertNotEqual(Path(path).name, "password")
            return original(path, limit, **kwargs)
        with patch.object(system, "_read_small", side_effect=public_only):
            result = self.backend.hotspot_action("off")
        self.assertTrue(result["ok"])
        operation = [item for item in self.runner.calls if item[0][0] == "/usr/bin/timeout"][0]
        self.assertEqual(operation[0][-1], "off")

    def test_timeout_returns_current_state_and_never_retries(self):
        self.runner.on = True  # A timed-out apply can leave the old AP running.
        self.runner.operation_result = system.Result(code=124, stderr=FAKE_SECRET)
        path = self.request({"band": "a"})
        result = self.backend.hotspot_action("apply", str(path))
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "hotspot_timeout")
        self.assertTrue(result["hotspot"]["on"])
        self.assertEqual(sum(argv[0] == "/usr/bin/timeout" for argv, _ in self.runner.calls), 1)
        self.assertNotIn(FAKE_SECRET, json.dumps(result))

    def test_flock_contention_consumes_request_without_starting_script(self):
        lock = self.state / "lock"
        with lock.open("w") as handle:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            path = self.request({"password": FAKE_SECRET})
            self.assert_error("busy", lambda: self.backend.hotspot_action("on", str(path)))
            self.assertFalse(path.exists())
            self.assertFalse(self.runner.calls)

    def test_helper_lock_serializes_panels_and_ipc(self):
        with self.backend._operation_lock():
            self.assert_error("busy", lambda: self.backend.hotspot_action("off"))
        self.assertFalse(self.runner.calls)

    def test_script_lock_race_is_mapped_to_busy_without_output_leak(self):
        self.runner.operation_result = system.Result(code=1, stderr="上一次热点操作还在进行 " + FAKE_SECRET)
        result = self.backend.hotspot_action("off")
        self.assertEqual(result["error"], "busy")
        self.assertNotIn(FAKE_SECRET, json.dumps(result))

    def test_discard_exact_request_and_reject_foreign_path(self):
        path = self.request({"password": FAKE_SECRET})
        self.assertTrue(self.backend.discard_request(str(path))["ok"])
        self.assertFalse(path.exists())
        other = self.home / path.name
        other.write_text(FAKE_SECRET)
        self.assert_error("invalid_request_path", lambda: self.backend.discard_request(str(other)))
        self.assertTrue(other.exists())

    def test_request_symlink_and_hardlink_are_rejected_without_reading_target(self):
        target = self.home / "unrelated-file"
        target.write_text(FAKE_SECRET)
        target.chmod(0o600)
        first = self.request({})
        first.unlink()
        first.symlink_to(target)
        self.assert_error("request_unavailable", lambda: self.backend._consume_request(str(first)))
        self.assertTrue(first.is_symlink())
        second = self.request({})
        second.unlink()
        os.link(target, second)
        self.assert_error("unsafe_request", lambda: self.backend._consume_request(str(second)))
        self.assertTrue(target.exists())

    def test_insecure_and_non_regular_requests_fail_closed(self):
        path = self.request({})
        path.chmod(0o644)
        self.assert_error("unsafe_request", lambda: self.backend._consume_request(str(path)))
        fifo = self.paths.private / ("request-" + "a" * 32 + ".json")
        os.mkfifo(fifo, 0o600)
        self.assert_error("unsafe_request", lambda: self.backend._consume_request(str(fifo)))

    def test_invalid_oversize_or_bad_json_requests_are_consumed(self):
        for content in ("{", "x" * (system.MAX_REQUEST + 1), json.dumps({"notAllowed": FAKE_SECRET})):
            path = self.request({})
            path.write_text(content)
            self.assert_error("invalid_request", lambda: self.backend._consume_request(str(path)))
            self.assertFalse(path.exists())

    def test_request_validation_limits_are_byte_and_type_safe(self):
        bad = [({"ssid": ""}, "invalid_ssid"), ({"ssid": "界" * 11}, "invalid_ssid"),
               ({"ssid": "bad\nname"}, "invalid_ssid"), ({"password": "short"}, "invalid_password"),
               ({"password": "x" * 64}, "invalid_password"), ({"password": 12345}, "invalid_request"),
               ({"band": "5GHz"}, "invalid_band"), ([], "invalid_request")]
        for request, code in bad:
            with self.subTest(code=code):
                self.assert_error(code, lambda: self.backend._validate_request(request))
        self.assertEqual(self.backend._validate_request({"password": " 123456 "})["password"], " 123456 ")
        self.assertEqual(self.backend._validate_request({"password": "a" * 64})["password"], "a" * 64)

    def test_expired_cleanup_touches_only_verified_exact_request_files(self):
        old = self.request({"password": FAKE_SECRET})
        os.utime(old, (time.time() - 600, time.time() - 600))
        unrelated = self.paths.private / "notes.json"
        unrelated.write_text("retain")
        os.utime(unrelated, (time.time() - 600, time.time() - 600))
        target = self.home / "unrelated-secret"
        target.write_text(FAKE_SECRET)
        symlink = self.paths.private / ("request-" + "b" * 32 + ".json")
        symlink.symlink_to(target)
        self.backend.prepare_request()
        self.assertFalse(old.exists())
        self.assertTrue(unrelated.exists())
        self.assertTrue(symlink.is_symlink())
        self.assertTrue(target.exists())

    def test_reveal_is_explicit_private_and_never_generates_password(self):
        self.assert_error("password_unavailable", self.backend.reveal)
        self.assertFalse((self.state / "password").exists())
        password = self.state / "password"
        password.write_text(FAKE_SECRET)
        password.chmod(0o600)
        result = self.backend.reveal()
        self.assertEqual(result, {"ok": True, "password": FAKE_SECRET})
        self.assertFalse(self.runner.calls)
        password.chmod(0o644)
        self.assert_error("password_unavailable", self.backend.reveal)

    def test_windows_have_string_uint64_ids_and_only_public_fields(self):
        self.runner.window_rows = [{"id": system.UINT64_MAX, "title": "Name\nwith control", "app_id": None,
                                    "workspace_id": 99, "is_focused": True, "private": FAKE_SECRET},
                                   {"id": "invalid", "title": "skip"}]
        windows, error = self.backend.windows()
        self.assertIsNone(error)
        self.assertEqual(windows, [{"id": str(system.UINT64_MAX), "title": "Name with control", "appId": "",
                                    "workspaceId": "99", "focused": True}])
        self.assertNotIn(FAKE_SECRET, json.dumps(windows))

    def test_focus_and_close_always_use_explicit_id_and_no_shell(self):
        for action in ("focus", "close"):
            result = self.backend.window_action(action, "00023")
            self.assertTrue(result["ok"])
            self.assertEqual(self.runner.calls[-1][0], ["/usr/bin/niri", "msg", "action", action + "-window", "--id", "23"])
        for ident in ("", "23;echo bad", "--id", "-1", "1.0", "1e2", " 23", "１２", True, 1.5, str(system.UINT64_MAX + 1)):
            before = len(self.runner.calls)
            self.assert_error("invalid_window_id", lambda: self.backend.window_action("close", ident))
            self.assertEqual(len(self.runner.calls), before)

    def test_stale_window_is_not_closed(self):
        self.assert_error("window_gone", lambda: self.backend.window_action("close", "999"))
        self.assertTrue(all("action" not in argv for argv, _ in self.runner.calls))

    def test_invalid_windows_or_action_failures_do_not_leak_output(self):
        self.runner.niri_result = system.Result(stdout=FAKE_SECRET)
        result = self.backend.snapshot()
        self.assertEqual(result["windows"], [])
        self.assertTrue(result["windowsError"])
        self.assertNotIn(FAKE_SECRET, json.dumps(result))
        self.runner.niri_result = None
        self.runner.action_result = system.Result(code=1, stderr=FAKE_SECRET)
        self.assert_error("window_action_failed", lambda: self.backend.window_action("focus", "23"))

    def test_invalid_cli_never_runs_actions_or_prints_exception_data(self):
        for argv in (["close"], ["focus"], ["hotspot"], ["state"], ["password"], ["toggle"]):
            self.assert_error("invalid_command", lambda: system.dispatch(self.backend, argv))
        self.assertFalse(self.runner.calls)
        with patch.object(system, "Backend", return_value=self.backend), patch.object(system, "dispatch", side_effect=ValueError(FAKE_SECRET)):
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                self.assertEqual(system.main(["snapshot"]), 1)
            self.assertNotIn(FAKE_SECRET, output.getvalue())
            self.assertEqual(json.loads(output.getvalue())["error"], "internal_error")


class RunnerSpec(unittest.TestCase):
    def test_guarded_operation_uses_devnull_and_preserves_group_membership(self):
        process = Mock(pid=555555, returncode=0)
        process.communicate.return_value = (None, "static warning")
        with patch.object(system.subprocess, "Popen", return_value=process) as mocked:
            result = system.Runner()(["/usr/bin/timeout", "40s", "fixture"], timeout=45, env={}, discard_stdout=True)
        self.assertEqual(result.stdout, "")
        self.assertEqual(mocked.call_args.kwargs["stdout"], subprocess.DEVNULL)
        self.assertNotIn("start_new_session", mocked.call_args.kwargs)
        self.assertNotIn("process_group", mocked.call_args.kwargs)

    def test_last_resort_timeout_kills_exact_guard_group_not_just_shell(self):
        process = Mock(pid=555555, returncode=-9)
        process.communicate.side_effect = [subprocess.TimeoutExpired(["fixture"], 45, stderr=FAKE_SECRET), (None, FAKE_SECRET)]
        with patch.object(system.subprocess, "Popen", return_value=process), patch.object(system.os, "killpg") as kill_group:
            result = system.Runner()(["/usr/bin/timeout", "40s", "fixture"], timeout=45, env={}, discard_stdout=True)
        kill_group.assert_called_once_with(555555, system.signal.SIGKILL)
        process.kill.assert_called_once_with()
        self.assertTrue(result.timed_out)
        self.assertEqual(result.stderr, "")

    def test_runner_discards_stdout_while_only_capturing_internal_diagnostics(self):
        completed = subprocess.CompletedProcess(["fixture"], 0, stdout=None, stderr="static warning")
        with patch.object(system.subprocess, "run", return_value=completed) as mocked:
            result = system.Runner()(["fixture"], timeout=5, env={}, discard_stdout=True, capture_diagnostics=True)
        self.assertEqual(result.stdout, "")
        self.assertEqual(mocked.call_args.kwargs["stdout"], subprocess.DEVNULL)
        self.assertEqual(mocked.call_args.kwargs["stderr"], subprocess.PIPE)
        self.assertNotIn("shell", mocked.call_args.kwargs)
        self.assertNotIn("start_new_session", mocked.call_args.kwargs)

    def test_timeout_exception_output_is_never_retained(self):
        exception = subprocess.TimeoutExpired(["fixture"], 1, output=FAKE_SECRET, stderr=FAKE_SECRET)
        with patch.object(system.subprocess, "run", side_effect=exception):
            result = system.Runner()(["fixture"], timeout=1, env={})
        self.assertTrue(result.timed_out)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
