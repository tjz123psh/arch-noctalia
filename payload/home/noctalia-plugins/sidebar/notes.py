#!/usr/bin/env python3
"""Local Markdown editor with revision-checked saves and exclusive creation.

Writers from this helper lock the directory. External editors may ignore that
advisory lock; check revisions immediately before committing. Full saves use a
same-directory temporary file and atomic replace, never truncate the live file.
"""
import contextlib
import fcntl
import hashlib
import json
import os
import re
import stat
import sys
import uuid

MAX_EDIT_BYTES = 64 * 1024  # Safe argv size; larger notes remain externally editable.
MAX_BYTES = 256 * 1024
MAX_NOTES = 100
MAX_ENTRIES = 2000
MAX_TASKS = 100
TASK = re.compile(rb"^ {0,3}(?:[-+*]|[0-9]{1,9}[.)])[ \t]+\[([ xX])\](?:[ \t]+(.*))?$")
FENCE = re.compile(b"^ {0,3}(" + bytes([96]) + b"{3,}|~{3,})(.*)$")


class NoteError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code, self.message = code, message


def valid_name(name):
    try:
        encoded = name.encode("utf-8")
    except (AttributeError, UnicodeError):
        return False
    return (not name.startswith(".")
            and name.lower().endswith(".md") and len(encoded) <= 255
            and "/" not in name and "\\" not in name
            and all(ord(c) >= 32 and ord(c) != 127 for c in name))


def identity(st):
    return st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns, st.st_ctime_ns


def revision(data, st):
    return hashlib.sha256(data).hexdigest() + ":" + ":".join(map(str, identity(st)))


def clean_text(text, limit):
    text = "".join(c if ord(c) >= 32 and ord(c) != 127 else " " for c in text)
    return text if len(text) <= limit else text[:limit - 1] + "…"


def parse_tasks(data):
    """Return physical line + exact checkbox offset; never parse code as tasks.

    Standard list markers with 0..3 leading spaces are supported. Four-space
    indented code, fenced code, blockquotes and leading YAML frontmatter are not.
    """
    data.decode("utf-8-sig")  # Invalid UTF-8 must never be rewritten.
    tasks, fence, frontmatter, offset = [], None, False, 0
    for number, raw in enumerate(data.splitlines(keepends=True), 1):
        line = raw.rstrip(b"\r\n")
        bom = 3 if number == 1 and line.startswith(b"\xef\xbb\xbf") else 0
        line = line[bom:]
        if number == 1 and line == b"---":
            frontmatter = True
        elif frontmatter:
            if line in (b"---", b"..."):
                frontmatter = False
        else:
            marker = FENCE.match(line)
            if fence:
                if (marker and marker[1][:1] == fence[:1]
                        and len(marker[1]) >= len(fence) and not marker[2].strip()):
                    fence = None
            elif marker:
                fence = marker[1]
            else:
                match = TASK.match(line)
                if match:
                    text = (match[2] or b"").decode("utf-8").strip()
                    tasks.append({"line": number, "text": clean_text(text, 240) or "（未命名待办）",
                                  "done": match[1].lower() == b"x",
                                  "offset": offset + bom + match.start(1)})
        offset += len(raw)
    return tasks


@contextlib.contextmanager
def root_handle(root, writing=False):
    root = os.path.abspath(os.path.expanduser(root))
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        if writing:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise NoteError("busy", "另一项便签操作正在保存，请稍后重试") from None
        yield root, fd
    finally:
        os.close(fd)


@contextlib.contextmanager
def note_handle(dirfd, name, writing=False):
    if not valid_name(name):
        raise NoteError("invalid_name", "只能操作便签目录内的普通 Markdown 文件")
    flags = (os.O_RDWR if writing else os.O_RDONLY) | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC
    fd = os.open(name, flags, dir_fd=dirfd)
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or (writing and st.st_nlink != 1):
            raise NoteError("unsafe_file", "不修改符号链接、硬链接或特殊文件")
        yield fd
    finally:
        os.close(fd)


def snapshot(fd):
    before = os.fstat(fd)
    if before.st_size > MAX_BYTES:
        raise NoteError("too_large", "便签超过 256 KiB，请用外部编辑器处理")
    data = os.pread(fd, MAX_BYTES + 1, 0)
    after = os.fstat(fd)
    if identity(before) != identity(after) or len(data) != after.st_size:
        raise NoteError("conflict", "便签已在外部修改，请刷新后重试；未覆盖原文件")
    if len(data) > MAX_BYTES:
        raise NoteError("too_large", "便签超过 256 KiB，请用外部编辑器处理")
    data.decode("utf-8-sig")
    return data, after


def ensure_current(root, dirfd, name, fd, data, original):
    root_now = os.stat(root, follow_symlinks=False)
    root_open = os.fstat(dirfd)
    path_now = os.stat(name, dir_fd=dirfd, follow_symlinks=False)
    current, st = snapshot(fd)
    if (not stat.S_ISDIR(root_now.st_mode)
            or (root_now.st_dev, root_now.st_ino) != (root_open.st_dev, root_open.st_ino)
            or not stat.S_ISREG(path_now.st_mode) or path_now.st_nlink != 1
            or identity(path_now) != identity(original) or identity(st) != identity(original)
            or current != data):
        raise NoteError("conflict", "便签已在外部修改，请刷新后重试；未覆盖原文件")


def note_result(name, data, st):
    tasks = parse_tasks(data)
    text = data.decode("utf-8-sig").replace("\r\n", "\n")
    editable = len(data) <= MAX_EDIT_BYTES and b"\x00" not in data
    return {"name": name, "title": name[:-3], "revision": revision(data, st),
            "text": text if editable else "", "editable": editable,
            "preview": text[:600],
            "tasks": [{k: v for k, v in t.items() if k != "offset"} for t in tasks[:MAX_TASKS]],
            "taskCount": len(tasks), "doneCount": sum(t["done"] for t in tasks),
            "truncated": len(tasks) > MAX_TASKS}


def committed_result(root, dirfd, name, fd, expected_data):
    """A success acknowledgement must describe our bytes, not a later writer's."""
    current, st = snapshot(fd)
    if current != expected_data:
        raise NoteError("conflict", "保存后便签又被外部修改；已保留外部版本，请另存当前输入")
    ensure_current(root, dirfd, name, fd, current, st)
    return {"ok": True, "note": note_result(name, current, st)}


def list_notes(root):
    notes, candidates, truncated = [], [], False
    with root_handle(root) as (_, dirfd):
        with os.scandir(dirfd) as entries:
            for index, entry in enumerate(entries):
                if index >= MAX_ENTRIES:
                    truncated = True
                    break
                if valid_name(entry.name) and entry.is_file(follow_symlinks=False):
                    candidates.append(entry.name)
        truncated = truncated or len(candidates) > MAX_NOTES
        for name in sorted(candidates, key=str.casefold)[:MAX_NOTES]:
            item = {"name": name, "title": name[:-3], "taskCount": 0, "doneCount": 0}
            try:
                with note_handle(dirfd, name) as fd:
                    data, _ = snapshot(fd)
                tasks = parse_tasks(data)
                item.update(taskCount=len(tasks), doneCount=sum(t["done"] for t in tasks))
            except (NoteError, OSError, UnicodeError):
                item["unreadable"] = True
            notes.append(item)
    return {"ok": True, "notes": notes, "truncated": truncated}


def read_note(root, name):
    with root_handle(root) as (_, dirfd), note_handle(dirfd, name) as fd:
        data, st = snapshot(fd)
        return {"ok": True, "note": note_result(name, data, st)}


def mutate_note(root, name, expected, action, value, done=None):
    with root_handle(root, writing=True) as (root, dirfd), note_handle(dirfd, name, writing=True) as fd:
        data, st = snapshot(fd)
        if revision(data, st) != expected:
            raise NoteError("conflict", "便签已在外部修改，请刷新后重试；未覆盖原文件")
        tasks = parse_tasks(data)
        committed = data
        if action == "toggle":
            if done not in ("0", "1"):
                raise NoteError("invalid_task", "无效的待办状态")
            task = next((t for t in tasks if str(t["line"]) == value), None)
            if task is None:
                raise NoteError("invalid_task", "原待办已不存在，请刷新后重试")
            ensure_current(root, dirfd, name, fd, data, st)
            if task["done"] != (done == "1"):
                offset = task["offset"]
                if os.pread(fd, 1, offset) != data[offset:offset + 1]:
                    raise NoteError("conflict", "待办已改变，请刷新后重试")
                replacement = b"x" if done == "1" else b" "
                if os.pwrite(fd, replacement, offset) != 1:
                    raise NoteError("write_failed", "保存未确认，请刷新后检查")
                committed = data[:offset] + replacement + data[offset + 1:]
        elif action == "add":
            if any(ord(c) < 32 or ord(c) == 127 for c in value):
                raise NoteError("invalid_text", "请输入 1–500 字的单行待办")
            value = value.strip()
            if not value or len(value) > 500:
                raise NoteError("invalid_text", "请输入 1–500 字的单行待办")
            if len(tasks) >= MAX_TASKS:
                raise NoteError("too_many_tasks", "此便签已满 100 项，请在编辑器中整理后再添加")
            newline = b"\r\n" if b"\r\n" in data else b"\n"
            addition = (b"" if not data or data.endswith((b"\n", b"\r")) else newline)
            addition += b"- [ ] " + value.encode("utf-8") + newline
            if len(data) + len(addition) > MAX_BYTES:
                raise NoteError("too_large", "便签超过 256 KiB，请用外部编辑器处理")
            # If an unclosed fence/frontmatter would hide the appended task, refuse.
            if len(parse_tasks(data + addition)) != len(tasks) + 1:
                raise NoteError("open_block", "便签末尾有未闭合的代码块或元数据，请先在编辑器中修正")
            ensure_current(root, dirfd, name, fd, data, st)
            fcntl.fcntl(fd, fcntl.F_SETFL, fcntl.fcntl(fd, fcntl.F_GETFL) | os.O_APPEND)
            if os.write(fd, addition) != len(addition):
                raise NoteError("write_failed", "保存未确认，请刷新后检查")
            committed = data + addition
        else:
            raise NoteError("invalid_action", "不支持的便签操作")
        os.fsync(fd)
        return committed_result(root, dirfd, name, fd, committed)


def editor_bytes(text, original=b""):
    if "\x00" in text:
        raise NoteError("invalid_text", "便签不能包含空字符，当前输入尚未保存")
    normalized = text.replace("\r\n", "\n")
    if b"\r\n" in original:
        normalized = normalized.replace("\n", "\r\n")
    data = normalized.encode("utf-8")
    if original.startswith(b"\xef\xbb\xbf"):
        data = b"\xef\xbb\xbf" + data
    if len(data) > MAX_EDIT_BYTES:
        raise NoteError("too_large", "侧栏编辑限 64 KiB；请保留输入并用外部编辑器处理")
    return data


def write_all(fd, data):
    view = memoryview(data)
    while view:
        written = os.write(fd, view)
        if written <= 0:
            raise NoteError("write_failed", "保存失败，原便签未被截断")
        view = view[written:]
    os.fsync(fd)


def create_note(root, text=""):
    data = editor_bytes(text)
    with root_handle(root, writing=True) as (root, dirfd):
        for index in range(1, 10001):
            name = "便签.md" if index == 1 else f"便签-{index}.md"
            try:
                fd = os.open(name, os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                             0o600, dir_fd=dirfd)
            except FileExistsError:
                continue
            try:
                write_all(fd, data)
                os.fsync(dirfd)
                return committed_result(root, dirfd, name, fd, data)
            finally:
                os.close(fd)
        raise NoteError("too_many_notes", "便签名称已用完，请先在文件管理器中整理")


def save_note(root, name, expected, text):
    with root_handle(root, writing=True) as (root, dirfd), note_handle(dirfd, name, writing=True) as fd:
        original, st = snapshot(fd)
        if revision(original, st) != expected:
            raise NoteError("conflict", "文件已被外部修改；已保留你的输入，没有覆盖磁盘版本")
        data = editor_bytes(text, original)
        if data == original:
            return {"ok": True, "note": note_result(name, original, st)}
        temporary = ".sidebar-edit-" + uuid.uuid4().hex
        tmpfd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                        0o600, dir_fd=dirfd)
        try:
            os.fchmod(tmpfd, stat.S_IMODE(st.st_mode) & 0o777)
            write_all(tmpfd, data)
            ensure_current(root, dirfd, name, fd, original, st)
            # Replace only after the complete new content is durable and checked.
            os.replace(temporary, name, src_dir_fd=dirfd, dst_dir_fd=dirfd)
            os.fsync(dirfd)
        finally:
            os.close(tmpfd)
            # This exact hidden file was created exclusively by this save, is not
            # a note, and is recoverable from the editor buffer; no glob cleanup.
            try:
                os.unlink(temporary, dir_fd=dirfd)
            except FileNotFoundError:
                pass
        with note_handle(dirfd, name) as current_fd:
            return committed_result(root, dirfd, name, current_fd, data)


def main(args):
    try:
        if len(args) == 2 and args[0] == "list":
            result = list_notes(args[1])
        elif len(args) == 3 and args[0] == "read":
            result = read_note(args[1], args[2])
        elif len(args) == 6 and args[0] == "toggle":
            result = mutate_note(args[1], args[2], args[3], "toggle", args[4], args[5])
        elif len(args) == 5 and args[0] == "add":
            result = mutate_note(args[1], args[2], args[3], "add", args[4])
        elif len(args) in (2, 3) and args[0] == "create":
            result = create_note(args[1], args[2] if len(args) == 3 else "")
        elif len(args) == 5 and args[0] == "save":
            result = save_note(args[1], args[2], args[3], args[4])
        else:
            raise NoteError("invalid_args", "便签操作参数无效")
        code = 0
    except NoteError as e:
        result, code = {"ok": False, "error": e.code, "message": e.message}, 1
    except UnicodeError:
        result, code = {"ok": False, "error": "encoding", "message": "便签不是有效的 UTF-8 文件，未修改"}, 1
    except OSError:
        result, code = {"ok": False, "error": "io_error", "message": "无法读取或保存便签，请检查目录、权限并刷新确认"}, 1
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
