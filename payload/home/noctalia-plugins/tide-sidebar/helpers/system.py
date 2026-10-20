#!/usr/bin/env python3
"""Small, dependency-free JSON bridge for the Tide sidebar.

CLI (all arguments are separate argv items):
  snapshot
  prepare-request
  discard-request PATH
  hotspot on|off|apply [PATH]   # on/apply require a prepared, single-use request
  focus ID | close ID
  reveal                      # explicit user action ONLY; do not broadcast/log its result

A request contains only optional ssid/password/band keys. An empty password means
reuse the script's saved password. Credentials never go in argv or public state.
Snapshot never executes rice-hotspot or reads its configuration/password. All
network changes remain owned by the existing script; its stdout is discarded,
notifications suppressed, and stderr reduced to fixed, non-secret warning codes.
"""
from __future__ import annotations

import contextlib
import fcntl
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import signal
import socket
import stat
import subprocess
import tempfile
import time
from dataclasses import dataclass

MAX_REQUEST = 4096
MAX_OUTPUT = 1024 * 1024
QUERY_TIMEOUT = 2.0
OPERATION_SECONDS = 40
REQUEST_NAME = re.compile(r"request-[0-9a-f]{32}\.json\Z")
UINT64_MAX = (1 << 64) - 1


class BackendError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(code)  # never carry subprocess output or request data
        self.code = code
        self.message = message


@dataclass(frozen=True)
class Result:
    code: int = 0
    stdout: str = ""
    stderr: str = ""
    timed_out: bool = False
    missing: bool = False


class Runner:
    """Queries have no descendants; script operations have their own timeout guard."""
    def __call__(self, argv, *, timeout, env, discard_stdout=False,
                 capture_diagnostics=False):
        try:
            if discard_stdout and list(argv)[:1] == ["/usr/bin/timeout"]:
                return self._guarded_operation(argv, timeout=timeout, env=env)
            result = subprocess.run(
                list(argv), stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL if discard_stdout else subprocess.PIPE,
                stderr=subprocess.PIPE if capture_diagnostics else subprocess.DEVNULL,
                text=True, encoding="utf-8", errors="replace", env=env,
                timeout=timeout, check=False,
            )
            out = result.stdout or ""
            if len(out.encode("utf-8")) > MAX_OUTPUT:
                return Result(code=1)
            return Result(result.returncode, out, result.stderr or "")
        except FileNotFoundError:
            return Result(code=127, missing=True)
        except subprocess.TimeoutExpired:
            # Do not copy TimeoutExpired.stdout/stderr into an error message.
            return Result(code=124, timed_out=True)
        except OSError:
            return Result(code=1)

    @staticmethod
    def _guarded_operation(argv, *, timeout, env):
        # coreutils timeout creates a group whose ID is its own PID. Its own
        # 40s+2s deadline is primary; the 45s Python guard also kills that exact
        # group if the guard itself fails. Never create an escaping session.
        process = subprocess.Popen(list(argv), stdin=subprocess.DEVNULL,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                                   text=True, encoding="utf-8", errors="replace", env=env)
        try:
            _, diagnostics = process.communicate(timeout=timeout)
            return Result(code=process.returncode, stderr=diagnostics or "")
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.kill()
            try:
                process.communicate(timeout=1)
            except subprocess.TimeoutExpired:
                if process.stderr:
                    process.stderr.close()
                process.wait(timeout=1)
            return Result(code=124, timed_out=True)


@dataclass(frozen=True)
class Paths:
    home: Path
    state: Path
    config: Path
    private: Path
    script: Path

    @classmethod
    def from_env(cls, env):
        home = Path(env.get("HOME") or str(Path.home())).absolute()
        state = Path(env.get("XDG_STATE_HOME") or home / ".local/state") / "rice-hotspot"
        config = Path(env.get("XDG_CONFIG_HOME") or home / ".config") / "rice-hotspot.conf"
        runtime = env.get("XDG_RUNTIME_DIR")
        base = Path(runtime) if runtime else Path(env.get("XDG_CACHE_HOME") or home / ".cache")
        return cls(home, state.absolute(), config.absolute(),
                   (base / "noctalia-tide-sidebar").absolute(),
                   home / "scripts/desktop/rice-hotspot")


def failure(code, message, **extra):
    return {"ok": False, "error": code, "message": message, **extra}


def display_text(value, limit=160):
    if not isinstance(value, str):
        return ""
    # Window titles and SSIDs are untrusted display data, never commands/markup.
    return "".join(" " if ord(c) < 32 or 127 <= ord(c) < 160 else c for c in value)[:limit]


def split_nmcli(line):
    """nmcli -t escapes colons and backslashes; str.split(':') is not safe."""
    parts, piece = [], []
    escaped = False
    for char in line:
        if escaped:
            if char not in (":", "\\"):
                piece.append("\\")
            piece.append(char)
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == ":":
            parts.append("".join(piece))
            piece = []
        else:
            piece.append(char)
    if escaped:
        piece.append("\\")
    parts.append("".join(piece))
    return parts


def window_id(value):
    if isinstance(value, bool) or not isinstance(value, (str, int)):
        raise BackendError("invalid_window_id", "窗口编号必须是纯数字。")
    text = str(value)
    if not re.fullmatch(r"[0-9]{1,20}", text) or int(text) > UINT64_MAX:
        raise BackendError("invalid_window_id", "窗口编号无效。")
    return str(int(text))


def _read_small(path, limit, *, secret=False):
    """Do not follow a state-file symlink or a hardlink to some other file."""
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
            raise OSError("unsafe file")
        if secret and stat.S_IMODE(info.st_mode) & 0o077:
            raise OSError("unsafe permissions")
        if info.st_size > limit:
            raise OSError("oversize file")
        data = os.read(fd, limit + 1)
        if len(data) > limit:
            raise OSError("oversize file")
        return data.decode("utf-8")
    finally:
        os.close(fd)


class Backend:
    def __init__(self, *, env=None, paths=None, runner=None):
        self.env = dict(os.environ if env is None else env)
        self.paths = paths or Paths.from_env(self.env)
        self.runner = runner or Runner()

    def _query(self, argv):
        env = {**self.env, "LC_ALL": "C", "LANG": "C"}
        return self.runner(argv, timeout=QUERY_TIMEOUT, env=env)

    def _nmcli(self, fields, command):
        return self._query(["/usr/bin/nmcli", "--terse", "--escape", "yes", "--fields",
                            fields, *command])

    def _public_state(self, name, default=""):
        try:
            return _read_small(self.paths.state / name, 256).rstrip("\n")
        except (OSError, UnicodeError):
            return default

    def _script_available(self):
        return self.paths.script.is_file() and os.access(self.paths.script, os.X_OK)

    @staticmethod
    def _existing_lock_busy(path):
        # Read-only probing: NEVER create or truncate rice-hotspot's lock file.
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
        except OSError:
            return False
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
                return False
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return True
            fcntl.flock(fd, fcntl.LOCK_UN)
            return False
        finally:
            os.close(fd)
    def hotspot_snapshot(self):
        # "Recorded" values come from rice-hotspot's own state files. The sidebar only
        # applies its plugin settings when the script never recorded anything.
        recorded_ssid = self._public_state("ssid", None)
        recorded_band = self._public_state("band_desired", None)
        ssid_known = isinstance(recorded_ssid, str) and recorded_ssid != ""
        desired_ssid = recorded_ssid if ssid_known else socket.gethostname() + "-hotspot"
        desired_band = recorded_band if recorded_band in ("a", "bg") else "bg"
        hot = {"available": False, "on": None, "ssid": display_text(desired_ssid),
               "iface": "", "gateway": "", "band": None, "desiredBand": desired_band,
               "desiredSsidKnown": ssid_known, "desiredBandKnown": recorded_band in ("a", "bg"),
               "pending": None, "clients": None, "error": None, "warning": None}
        devices = self._nmcli("DEVICE,TYPE,STATE,CONNECTION", ["device", "status"])
        if devices.code:
            hot["error"] = "无法读取 NetworkManager 状态。"
            return hot
        wifi = [split_nmcli(line) for line in devices.stdout.splitlines()]
        wifi = [row for row in wifi if len(row) == 4 and row[1] == "wifi"]
        if not wifi:
            hot["error"] = "未找到 Wi-Fi 设备。"
            return hot
        hot["iface"] = display_text(wifi[0][0], 64)
        hot["available"] = self._script_available()
        if not hot["available"]:
            hot["error"] = "热点脚本不可用。"
        active = self._nmcli("NAME,UUID,TYPE,DEVICE", ["connection", "show", "--active"])
        if active.code:
            hot["error"] = "无法确定热点是否开启。"
            return hot
        rows = [split_nmcli(line) for line in active.stdout.splitlines() if line]
        if any(len(row) != 4 for row in rows):
            hot["error"] = "热点连接列表格式无效，无法确定当前状态。"
            return hot
        aps = [row for row in rows if len(row) == 4 and row[0] == "rice-hotspot"
               and row[2] in ("wifi", "802-11-wireless")]
        warnings = []
        if not aps:
            hot["on"], hot["pending"] = False, False
        else:
            ap = aps[0]
            if not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", ap[1]):
                hot["error"] = "热点连接信息无效。"
                return hot
            profile = self._nmcli(
                "802-11-wireless.ssid,802-11-wireless.band,802-11-wireless.mode,ipv4.method",
                ["connection", "show", "uuid", ap[1]],
            )
            if profile.code:
                hot["error"] = "无法读取热点连接信息。"
                return hot
            values = {}
            for line in profile.stdout.splitlines():
                pair = split_nmcli(line)
                if len(pair) == 2:
                    values[pair[0]] = pair[1]
            if values.get("802-11-wireless.mode") != "ap":
                hot["error"] = "同名连接不是热点，已禁用热点操作。"
                hot["available"] = False
                return hot
            actual_ssid = values.get("802-11-wireless.ssid", "")
            actual_band = values.get("802-11-wireless.band")
            hot.update(on=True, ssid=display_text(actual_ssid), iface=display_text(ap[3], 64),
                       band=actual_band if actual_band in ("bg", "a") else None)
            # Compare only public metadata. Do not claim to have compared the password.
            hot["pending"] = True if actual_ssid != desired_ssid else None
            if re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.:-]{0,63}", ap[3]):
                addresses = self._nmcli("IP4.ADDRESS", ["device", "show", ap[3]])
                if addresses.code == 0:
                    for line in addresses.stdout.splitlines():
                        pair = split_nmcli(line)
                        if len(pair) == 2 and pair[0].startswith("IP4.ADDRESS"):
                            try:
                                address = ipaddress.ip_interface(pair[1])
                                if address.version == 4:
                                    hot["gateway"] = str(address)
                                    break
                            except ValueError:
                                pass
            if hot["band"] == "bg" and desired_band == "a":
                warnings.append("请求的是 5 GHz，实际使用 2.4 GHz（回落不算待应用）。")
            if values.get("ipv4.method") != "shared":
                warnings.append("此热点未使用共享网络模式，客户端可能无法上网。")
        if self.paths.config.exists():
            warnings.append("检测到脚本配置文件；后台未读取其密码，待应用状态可能不完整。")
        hot["warning"] = " ".join(warnings) or None
        return hot

    def windows(self):
        result = self._query(["/usr/bin/niri", "msg", "--json", "windows"])
        if result.code:
            return [], "无法读取 niri 窗口列表。"
        try:
            source = json.loads(result.stdout)
            if not isinstance(source, list):
                raise ValueError()
            windows = []
            for row in source[:512]:
                if not isinstance(row, dict):
                    continue
                try:
                    ident = window_id(row.get("id"))
                except BackendError:
                    continue
                workspace = row.get("workspace_id")
                try:
                    workspace = window_id(workspace) if workspace is not None else None
                except BackendError:
                    workspace = None
                windows.append({"id": ident, "title": display_text(row.get("title"), 240),
                                "appId": display_text(row.get("app_id")),
                                "workspaceId": workspace,
                                "focused": row.get("is_focused") is True})
            return windows, None
        except (ValueError, TypeError):
            return [], "niri 返回了无法识别的窗口列表。"

    def snapshot(self):
        hot = self.hotspot_snapshot()
        windows, error = self.windows()
        return {"ok": True, "hotspot": hot, "windows": windows, "windowsError": error}

    def window_action(self, action, ident):
        if action not in ("focus", "close"):
            raise BackendError("invalid_action", "窗口操作无效。")
        ident = window_id(ident)
        windows, error = self.windows()
        if error:
            raise BackendError("windows_unavailable", error)
        if not any(row["id"] == ident for row in windows):
            raise BackendError("window_gone", "该窗口已关闭，请刷新列表。")
        # Always explicit --id; close-window without it closes the focused window.
        result = self._query(["/usr/bin/niri", "msg", "action", action + "-window", "--id", ident])
        if result.code:
            raise BackendError("window_action_failed", "窗口操作未完成，可能已被关闭。")
        return {"ok": True, "action": action, "id": ident}

    def _private_dir(self, create=False):
        path = self.paths.private
        if create:
            path.mkdir(mode=0o700, parents=True, exist_ok=True)
        try:
            info = path.lstat()
            if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
                raise OSError()
            return os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
        except OSError:
            raise BackendError("private_storage_unavailable", "私有请求目录不可用或权限不安全。") from None

    def prepare_request(self):
        # Use a directory fd for all exact-name operations, never a glob/delete.
        directory = self._private_dir(create=True)
        try:
            self._prune_requests(directory)
            name = "request-" + secrets.token_hex(16) + ".json"
            fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                         0o600, dir_fd=directory)
            try:
                os.fchmod(fd, 0o600)
                os.write(fd, b"{}")
            finally:
                os.close(fd)
        finally:
            os.close(directory)
        return {"ok": True, "path": str(self.paths.private / name)}

    def _prune_requests(self, directory):
        # Only our old, private, single-link regular files in this exact directory.
        for name in os.listdir(directory):
            if not REQUEST_NAME.fullmatch(name):
                continue
            try:
                info = os.stat(name, dir_fd=directory, follow_symlinks=False)
            except FileNotFoundError:
                continue
            if (stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid()
                    and stat.S_IMODE(info.st_mode) == 0o600 and info.st_nlink == 1
                    and time.time() - info.st_mtime > 300):
                os.unlink(name, dir_fd=directory)

    def _request_name(self, path):
        candidate = Path(path)
        if not candidate.is_absolute() or candidate.parent != self.paths.private or not REQUEST_NAME.fullmatch(candidate.name):
            raise BackendError("invalid_request_path", "请求文件路径无效。")
        return candidate.name

    def _consume_request(self, path, *, discard=False):
        name = self._request_name(path)
        directory = self._private_dir()
        fd = None
        verified = False
        try:
            fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, dir_fd=directory)
            info = os.fstat(fd)
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                    or stat.S_IMODE(info.st_mode) != 0o600 or info.st_nlink != 1):
                raise BackendError("unsafe_request", "请求文件权限不安全。")
            verified = True
            if discard:
                return {}
            if info.st_size > MAX_REQUEST:
                raise BackendError("invalid_request", "请求内容过大。")
            data = os.read(fd, MAX_REQUEST + 1)
            if len(data) > MAX_REQUEST:
                raise BackendError("invalid_request", "请求内容过大。")
            try:
                request = json.loads(data.decode("utf-8"))
            except (UnicodeError, ValueError):
                raise BackendError("invalid_request", "请求内容无效。") from None
            return self._validate_request(request)
        except OSError:
            raise BackendError("request_unavailable", "请求文件不存在或不可安全读取。") from None
        finally:
            if fd is not None:
                os.close(fd)
            if verified:
                # This exact file was validated under the still-open directory fd.
                try:
                    os.unlink(name, dir_fd=directory)
                except FileNotFoundError:
                    pass
            os.close(directory)

    @staticmethod
    def _validate_request(request):
        if not isinstance(request, dict) or set(request) - {"ssid", "password", "band"}:
            raise BackendError("invalid_request", "请求只能包含热点名称、密码和频段。")
        result = {}
        for key in ("ssid", "password", "band"):
            value = request.get(key)
            if value is None:
                continue
            if not isinstance(value, str):
                raise BackendError("invalid_request", "热点设置必须是文本。")
            if key == "ssid":
                try:
                    size = len(value.encode("utf-8"))
                except UnicodeError:
                    raise BackendError("invalid_ssid", "热点名称不是有效的 UTF-8 文本。") from None
                if not 1 <= size <= 32 or any(ord(c) < 32 or ord(c) == 127 for c in value):
                    raise BackendError("invalid_ssid", "热点名称须为 1–32 个 UTF-8 字节，不能含换行。")
                result[key] = value
            elif key == "password":
                if not value:
                    continue  # Empty input means reuse; never trim a real passphrase.
                valid = all(32 <= ord(c) <= 126 for c in value) and 8 <= len(value) <= 63
                valid = valid or bool(re.fullmatch(r"[0-9a-fA-F]{64}", value))
                if not valid:
                    raise BackendError("invalid_password", "密码须为 8–63 个可打印 ASCII 字符，或 64 位十六进制密钥。")
                result[key] = value
            elif value not in ("a", "bg"):
                raise BackendError("invalid_band", "频段只能选 2.4 GHz 或 5 GHz。")
            else:
                result[key] = value
        return result

    def discard_request(self, path):
        self._consume_request(path, discard=True)
        return {"ok": True}

    @contextlib.contextmanager
    def _operation_lock(self):
        directory = self._private_dir(create=True)
        fd = None
        try:
            fd = os.open("operation.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC,
                         0o600, dir_fd=directory)
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600:
                raise BackendError("unsafe_lock", "热点操作锁权限不安全。")
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise BackendError("busy", "已有热点操作正在进行，请稍后重试。") from None
            if self._existing_lock_busy(self.paths.state / "lock"):
                raise BackendError("busy", "已有热点操作正在进行，请稍后重试。")
            yield
        finally:
            if fd is not None:
                os.close(fd)
            os.close(directory)

    def hotspot_action(self, action, request_path=None):
        if action not in ("on", "off", "apply"):
            raise BackendError("invalid_action", "热点操作无效。")
        if action != "off" and request_path is None:
            raise BackendError("request_required", "请通过私有请求文件提交热点设置。")
        request = self._consume_request(request_path) if request_path is not None else {}
        if not self._script_available():
            raise BackendError("hotspot_script_missing", "热点脚本不可用。")
        with self._operation_lock():
            with tempfile.TemporaryDirectory(prefix="operation-", dir=self.paths.private) as temporary:
                shim = Path(temporary) / "notify-send"
                shim.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
                shim.chmod(0o700)
                env = {key: value for key, value in self.env.items()
                       if not key.startswith(("RICE_HOTSPOT_", "BASH_FUNC_"))
                       and key not in ("BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS")}
                env.update(LC_ALL="C", LANG="C", PATH=temporary + os.pathsep + env.get("PATH", "/usr/bin:/bin"))
                if action != "off":
                    for key, value in request.items():
                        env["RICE_HOTSPOT_" + key.upper()] = value
                argv = ["/usr/bin/timeout", "--kill-after=2s", str(OPERATION_SECONDS) + "s",
                        str(self.paths.script), "off" if action == "off" else "on"]
                result = self.runner(argv, timeout=OPERATION_SECONDS + 5, env=env,
                                     discard_stdout=True, capture_diagnostics=True)
                # Only fixed classifications survive this scope. No raw diagnostics,
                # script stdout, request JSON, or environment is ever returned/logged.
                warning_codes = []
                diagnostics = result.stderr
                if "自动回落到 2.4GHz" in diagnostics:
                    warning_codes.append("fallback")
                if any(text in diagnostics for text in ("转发放行没成功", "跳过转发放行", "热点客户端可能上不了网")):
                    warning_codes.append("forwarding")
                if "没能自动连回" in diagnostics:
                    warning_codes.append("wifi_restore")
                busy = "上一次热点操作还在进行" in diagnostics
                timed_out = result.timed_out or result.code in (124, 137)
                succeeded = result.code == 0
        hot = self.hotspot_snapshot()
        warning_text = {"fallback": "5 GHz 启动未成功，已尝试回落到 2.4 GHz。",
                        "forwarding": "共享网络转发未确认成功，客户端可能无法上网。",
                        "wifi_restore": "未能自动恢复原 Wi-Fi，请在网络面板重新连接。"}
        warnings = [warning_text[code] for code in warning_codes]
        if hot["warning"]:
            warnings.append(hot["warning"])
        warning = " ".join(dict.fromkeys(warnings)) or None
        if timed_out:
            return failure("hotspot_timeout", "热点操作超时并已终止；请检查当前网络状态，不会自动重试。",
                           action=action, hotspot=hot, warning=warning)
        if busy:
            return failure("busy", "已有热点操作正在进行，请稍后重试。", action=action, hotspot=hot, warning=warning)
        if not succeeded:
            return failure("hotspot_failed", "热点操作未完成；可能已部分生效，请检查当前网络状态。",
                           action=action, hotspot=hot, warning=warning)
        return {"ok": True, "action": action, "hotspot": hot, "warning": warning,
                "message": "热点操作已完成。"}

    def reveal(self):
        # This is intentionally the only password-file read in the entire backend.
        # Do not call this from snapshot, polling, diagnostics, or service broadcasts.
        try:
            password = _read_small(self.paths.state / "password", 256, secret=True)
            if not password:
                raise OSError()
            validated = self._validate_request({"password": password})
            return {"ok": True, "password": validated["password"]}
        except (OSError, UnicodeError, BackendError, KeyError):
            raise BackendError("password_unavailable", "尚无可安全读取的已保存密码；请先开启热点。") from None


def dispatch(backend, argv):
    if argv == ["snapshot"]:
        return backend.snapshot()
    if argv == ["prepare-request"]:
        return backend.prepare_request()
    if argv == ["reveal"]:
        return backend.reveal()
    if len(argv) == 2 and argv[0] == "discard-request":
        return backend.discard_request(argv[1])
    if len(argv) == 2 and argv[0] in ("focus", "close"):
        return backend.window_action(argv[0], argv[1])
    if len(argv) in (2, 3) and argv[0] == "hotspot":
        return backend.hotspot_action(argv[1], argv[2] if len(argv) == 3 else None)
    raise BackendError("invalid_command", "系统命令格式无效。")


def main(argv=None):
    import sys
    try:
        response = dispatch(Backend(), sys.argv[1:] if argv is None else argv)
    except BackendError as error:
        response = failure(error.code, error.message)
    except Exception:
        # Never interpolate exception text: it can contain paths, request data,
        # or subprocess output. No traceback belongs in the shell's log.
        response = failure("internal_error", "系统接口暂时不可用。")
    print(json.dumps(response, ensure_ascii=False, separators=(",", ":")))
    return 0 if response.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
