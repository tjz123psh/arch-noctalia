#!/usr/bin/env python3
"""Filesystem/CLI regression tests. Only test-owned temporary fixtures are changed."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
HELPER = Path(__file__).resolve().parents[1] / "notes.py"
spec = importlib.util.spec_from_file_location("sidebar_notes", HELPER)
notes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notes)


class NotesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sidebar-notes-spec-")
        self.root = Path(self.temp.name).resolve()
        self.name = "工作 ' 引号.md"
        self.path = self.root / self.name

    def tearDown(self):
        # Disposable fixtures, used only by this test, recreated on the next run.
        assert self.root.parent == Path(tempfile.gettempdir()).resolve()
        assert self.root.name.startswith("sidebar-notes-spec-")
        self.temp.cleanup()

    def put(self, value):
        self.path.write_bytes(value.encode() if isinstance(value, str) else value)
        return self.get()

    def get(self):
        return notes.read_note(str(self.root), self.name)["note"]

    def change(self, original, action, value, done=None):
        return notes.mutate_note(str(self.root), self.name, original["revision"], action, value, done)["note"]

    def test_markdown_parser_skips_code_and_metadata(self):
        fence = chr(96) * 3
        text = "---\n- [ ] metadata\n---\n# Heading\n- [ ] todo\n  * [X] child\n1. [x] ordered\n"
        text += fence + "md\n- [ ] example\n" + fence + "\n    - [ ] indented code\n> - [ ] quote\n"
        text += "~~~\n- [ ] tilde code\n~~~\n- [ ] last"
        parsed = self.put(text)
        self.assertEqual([t["text"] for t in parsed["tasks"]], ["todo", "child", "ordered", "last"])
        self.assertEqual(parsed["taskCount"], 4)
        self.assertEqual(parsed["doneCount"], 2)

    def test_toggle_preserves_bom_crlf_and_no_final_newline(self):
        original = b"\xef\xbb\xbf" + "- [ ] 中文\r\n正文\r\n- [X] 第二条".encode()
        before = self.put(original)
        after = self.change(before, "toggle", "1", "1")
        self.assertEqual(self.path.read_bytes(), original.replace(b"[ ]", b"[x]", 1))
        self.assertEqual(after["doneCount"], 2)
        self.change(after, "toggle", "3", "0")
        self.assertTrue(self.path.read_bytes().endswith("- [ ] 第二条".encode()))

    def test_duplicate_labels_use_physical_line_identity(self):
        before = self.put("- [ ] same\n- [ ] same\n")
        self.change(before, "toggle", "2", "1")
        self.assertEqual(self.path.read_text(), "- [ ] same\n- [x] same\n")

    def test_idempotent_check_does_not_normalize_uppercase(self):
        before = self.put("- [X] already done")
        self.change(before, "toggle", "1", "1")
        self.assertEqual(self.path.read_text(), "- [X] already done")

    def test_append_keeps_all_original_bytes_and_newline_style(self):
        original = "旧正文\r\n不要改写".encode()
        before = self.put(original)
        task = "检查 '引号' $HOME $(echo nope) <b> & 链接"
        after = self.change(before, "add", task)
        self.assertEqual(self.path.read_bytes(), original + ("\r\n- [ ] " + task + "\r\n").encode())
        self.assertEqual(after["tasks"][0]["text"], task)

    def test_stale_revision_preserves_external_changes(self):
        before = self.put("- [ ] old\n")
        external = "标题\n- [ ] external\n"
        self.path.write_text(external)
        with self.assertRaisesRegex(notes.NoteError, "外部修改"):
            self.change(before, "toggle", "1", "1")
        self.assertEqual(self.path.read_text(), external)

    def test_same_bytes_replaced_inode_is_still_stale(self):
        before = self.put("- [ ] same bytes\n")
        replacement = self.root / "new.tmp"
        replacement.write_bytes(self.path.read_bytes())
        os.replace(replacement, self.path)
        with self.assertRaises(notes.NoteError):
            self.change(before, "toggle", "1", "1")
        self.assertEqual(self.path.read_text(), "- [ ] same bytes\n")

    def test_change_between_read_and_commit_is_rejected(self):
        before = self.put("- [ ] old\n")
        verify = notes.ensure_current
        def replace_before_verify(*args):
            self.path.write_text("external editor wins\n")
            return verify(*args)
        with patch.object(notes, "ensure_current", side_effect=replace_before_verify):
            with self.assertRaises(notes.NoteError):
                self.change(before, "toggle", "1", "1")
        self.assertEqual(self.path.read_text(), "external editor wins\n")

    def test_invalid_names_and_symlinks_never_escape_root(self):
        before = self.put("- [ ] safe\n")
        for name in ["../elsewhere.md", "/tmp/elsewhere.md", ".hidden.md", "a\nb.md", "a.txt"]:
            with self.assertRaises(notes.NoteError):
                notes.read_note(str(self.root), name)
        alias = self.root / "alias.md"
        alias.symlink_to(self.path)
        with self.assertRaises(OSError):
            notes.read_note(str(self.root), alias.name)
        root_alias = self.root / "directory-link"
        root_alias.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(OSError):
            notes.read_note(str(root_alias), self.name)
        self.assertEqual(self.get()["revision"], before["revision"])

    def test_hardlinked_file_is_not_mutated(self):
        before = self.put("- [ ] original\n")
        os.link(self.path, self.root / "alias.md")
        with self.assertRaises(notes.NoteError):
            self.change(before, "toggle", "1", "1")
        self.assertEqual(self.path.read_text(), "- [ ] original\n")

    def test_read_limits_and_invalid_encoding(self):
        self.path.write_bytes(b"a" * (notes.MAX_BYTES + 1))
        with self.assertRaises(notes.NoteError):
            self.get()
        self.path.write_bytes(b"- [ ] \xff\n")
        with self.assertRaises(UnicodeError):
            self.get()

    def test_bounded_results_and_hidden_files(self):
        before = self.put("- [ ] x\n" * 102 + "a" * 1000)
        self.assertEqual(len(before["tasks"]), 100)
        self.assertTrue(before["truncated"])
        self.assertEqual(len(before["preview"]), 600)
        with self.assertRaises(notes.NoteError):
            self.change(before, "add", "would not be visible")
        (self.root / ".hidden.md").write_text("- [ ] hidden")
        (self.root / "folder").mkdir()
        (self.root / "folder" / "nested.md").write_text("- [ ] nested")
        (self.root / "alias.md").symlink_to(self.path)
        result = notes.list_notes(str(self.root))
        self.assertEqual([n["name"] for n in result["notes"]], [self.name])
        self.assertNotIn("preview", result["notes"][0])
        self.assertEqual(result["notes"][0]["taskCount"], 102)

    def test_scan_limit(self):
        for index in range(105):
            (self.root / (str(index) + ".md")).write_text("- [ ] task\n")
        result = notes.list_notes(str(self.root))
        self.assertTrue(result["truncated"])
        self.assertEqual(len(result["notes"]), 100)

    def test_invalid_add_and_unclosed_blocks_preserve_original(self):
        before = self.put("text\n")
        for value in ["", "  ", "two\nlines", "trailing\n", "a\x00b", "a\tb", "x" * 501]:
            with self.assertRaises(notes.NoteError):
                self.change(before, "add", value)
            self.assertEqual(self.path.read_text(), "text\n")
        for value in ["---\nmetadata\n", "~~~python\nexample\n"]:
            before = self.put(value)
            with self.assertRaises(notes.NoteError):
                self.change(before, "add", "not hidden inside a block")
            self.assertEqual(self.path.read_text(), value)

    def test_write_failure_does_not_destroy_other_content(self):
        before = self.put("正文\n- [ ] task\n")
        original = self.path.read_bytes()
        with patch.object(notes.os, "pwrite", side_effect=PermissionError("mock failure")):
            with self.assertRaises(OSError):
                self.change(before, "toggle", "2", "1")
        self.assertEqual(self.path.read_bytes(), original)

    def test_cli_and_concurrent_stale_writers(self):
        before = self.put("- [ ] one\n- [ ] two\n")
        commands = [[sys.executable, str(HELPER), "toggle", str(self.root), self.name, before["revision"], str(line), "1"] for line in (1, 2)]
        workers = [subprocess.Popen(c, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for c in commands]
        results = []
        try:
            for child in workers:
                stdout, stderr = child.communicate(timeout=10)
                self.assertEqual(stderr, "")
                results.append(json.loads(stdout))
        finally:
            for child in workers:
                if child.poll() is None:
                    child.kill()
                    child.wait()
        self.assertEqual(sum(r["ok"] for r in results), 1)
        self.assertEqual(self.path.read_text().count("[x]"), 1)
        self.assertTrue(any(r.get("error") in ("conflict", "busy") for r in results))


    def test_create_never_overwrites_existing_names_or_symlinks(self):
        (self.root / "便签.md").write_text("original")
        (self.root / "便签-2.md").symlink_to(self.root / "missing.md")
        created = notes.create_note(str(self.root))["note"]
        self.assertEqual(created["name"], "便签-3.md")
        self.assertEqual(created["text"], "")
        self.assertTrue(created["editable"])
        self.assertEqual((self.root / "便签.md").read_text(), "original")
        self.assertTrue((self.root / "便签-2.md").is_symlink())
        self.assertEqual((self.root / created["name"]).stat().st_mode & 0o777, 0o600)

    def test_full_save_preserves_exact_text_and_permissions(self):
        self.put("old text\n")
        self.path.chmod(0o640)
        before = self.get()
        text = "正常便签\n第二行 '引用' $HOME\n\n- [ ] 待办\n  保留缩进  "
        result = notes.save_note(str(self.root), self.name, before["revision"], text)["note"]
        self.assertEqual(self.path.read_bytes(), text.encode())
        self.assertEqual(result["text"], text)
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o640)
        self.assertEqual(result["taskCount"], 1)

    def test_editor_roundtrip_preserves_bom_crlf_and_avoids_noop_rewrite(self):
        raw = b"\xef\xbb\xbf" + "第一行\r\n第二行\r\n".encode()
        before = self.put(raw)
        self.assertEqual(before["text"], "第一行\n第二行\n")
        same = notes.save_note(str(self.root), self.name, before["revision"], before["text"])["note"]
        self.assertEqual(same["revision"], before["revision"])
        result = notes.save_note(str(self.root), self.name, same["revision"], "改过\n第二行\n")["note"]
        self.assertEqual(self.path.read_bytes(), b"\xef\xbb\xbf" + "改过\r\n第二行\r\n".encode())
        self.assertEqual(result["text"], "改过\n第二行\n")

    def test_full_save_failure_never_truncates_live_file(self):
        before = self.put("important original\n")
        with patch.object(notes, "write_all", side_effect=OSError("simulated disk failure")):
            with self.assertRaises(OSError):
                notes.save_note(str(self.root), self.name, before["revision"], "new text")
        self.assertEqual(self.path.read_text(), "important original\n")
        self.assertFalse(any(p.name.startswith(".sidebar-edit-") for p in self.root.iterdir()))

    def test_full_save_rechecks_external_change_after_staging(self):
        before = self.put("original\n")
        write = notes.write_all
        def external_edit(fd, data):
            write(fd, data)
            self.path.write_text("external change wins\n")
        with patch.object(notes, "write_all", side_effect=external_edit):
            with self.assertRaises(notes.NoteError):
                notes.save_note(str(self.root), self.name, before["revision"], "my draft")
        self.assertEqual(self.path.read_text(), "external change wins\n")
        self.assertFalse(any(p.name.startswith(".sidebar-edit-") for p in self.root.iterdir()))

    def test_save_copy_keeps_external_version_and_all_draft_text(self):
        before = self.put("original\n")
        self.path.write_text("externally updated\n")
        draft = "我的多行草稿\n必须保留\n"
        with self.assertRaises(notes.NoteError):
            notes.save_note(str(self.root), self.name, before["revision"], draft)
        copy = notes.create_note(str(self.root), draft)["note"]
        self.assertEqual(copy["text"], draft)
        self.assertEqual((self.root / copy["name"]).read_text(), draft)
        self.assertEqual(self.path.read_text(), "externally updated\n")

    def test_editor_limits_reject_unsafe_argv_without_losing_original(self):
        before = self.put("keep original")
        for invalid in ["x" * (notes.MAX_EDIT_BYTES + 1), "a\x00b"]:
            with self.assertRaises(notes.NoteError):
                notes.save_note(str(self.root), self.name, before["revision"], invalid)
            self.assertEqual(self.path.read_text(), "keep original")
        big = self.put("x" * (notes.MAX_EDIT_BYTES + 1))
        self.assertFalse(big["editable"])
        self.assertEqual(big["text"], "")

    def test_explicit_empty_body_is_saved_without_deleting_the_note(self):
        before = self.put("clear this text")
        after = notes.save_note(str(self.root), self.name, before["revision"], "")["note"]
        self.assertTrue(self.path.is_file())
        self.assertEqual(self.path.read_bytes(), b"")
        self.assertEqual(after["text"], "")


    def test_post_commit_save_rejects_external_acknowledgement(self):
        before = self.put("base")
        actual_fsync = os.fsync
        injected = []
        def external_after_commit(fd):
            actual_fsync(fd)
            if stat.S_ISDIR(os.fstat(fd).st_mode) and not injected:
                self.assertEqual(self.path.read_text(), "my draft")
                self.path.write_text("external update after commit")
                injected.append(True)
        with patch.object(notes.os, "fsync", side_effect=external_after_commit):
            with self.assertRaises(notes.NoteError) as caught:
                notes.save_note(str(self.root), self.name, before["revision"], "my draft")
        self.assertTrue(injected)
        self.assertEqual(caught.exception.code, "conflict")
        self.assertEqual(self.path.read_text(), "external update after commit")

    def test_post_toggle_change_preserves_external_addition(self):
        before = self.put("- [ ] task\n")
        actual_fsync = os.fsync
        injected = []
        def external_after_write(fd):
            actual_fsync(fd)
            if not injected:
                self.assertEqual(self.path.read_text(), "- [x] task\n")
                self.path.write_text("- [x] task\nexternal addition\n")
                injected.append(True)
        with patch.object(notes.os, "fsync", side_effect=external_after_write):
            with self.assertRaises(notes.NoteError) as caught:
                self.change(before, "toggle", "1", "1")
        self.assertEqual(caught.exception.code, "conflict")
        self.assertEqual(self.path.read_text(), "- [x] task\nexternal addition\n")

    def test_post_append_change_is_not_returned_as_our_success(self):
        before = self.put("body\n")
        actual_fsync = os.fsync
        injected = []
        def external_after_append(fd):
            actual_fsync(fd)
            if not injected:
                self.assertEqual(self.path.read_text(), "body\n- [ ] new task\n")
                self.path.write_text("external version\n")
                injected.append(True)
        with patch.object(notes.os, "fsync", side_effect=external_after_append):
            with self.assertRaises(notes.NoteError) as caught:
                self.change(before, "add", "new task")
        self.assertEqual(caught.exception.code, "conflict")
        self.assertEqual(self.path.read_text(), "external version\n")

    def test_post_create_change_preserves_the_external_file(self):
        created = self.root / "便签.md"
        actual_fsync = os.fsync
        injected = []
        def external_after_create(fd):
            actual_fsync(fd)
            if stat.S_ISREG(os.fstat(fd).st_mode) and not injected:
                self.assertEqual(created.read_text(), "copy this draft")
                created.write_text("external version of created file")
                injected.append(True)
        with patch.object(notes.os, "fsync", side_effect=external_after_create):
            with self.assertRaises(notes.NoteError) as caught:
                notes.create_note(str(self.root), "copy this draft")
        self.assertEqual(caught.exception.code, "conflict")
        self.assertEqual(created.read_text(), "external version of created file")

    def test_all_supported_line_endings_toggle_exactly_one_byte(self):
        for first, second in [(b"\n", b"\n"), (b"\r", b"\r"),
                              (b"\r\n", b"\r\n"), (b"\r", b"\n"), (b"\n", b"\r\n")]:
            with self.subTest(first=first, second=second):
                original = "标题".encode() + first + b"- [ ] first" + second + b"- [ ] second"
                before = self.put(original)
                self.assertEqual([t["line"] for t in before["tasks"]], [2, 3])
                result = self.change(before, "toggle", "2", "1")
                self.assertEqual(self.path.read_bytes(), original.replace(b"[ ]", b"[x]", 1))
                self.assertEqual([(t["text"], t["done"]) for t in result["tasks"]],
                                 [("first", True), ("second", False)])

    def test_cli_returns_conflict_not_a_revision_after_external_replace(self):
        before = self.put("base")
        actual_replace = os.replace
        def external_after_replace(*args, **kwargs):
            actual_replace(*args, **kwargs)
            self.assertEqual(self.path.read_text(), "my draft")
            self.path.write_text("external final version")
        output = io.StringIO()
        with patch.object(notes.os, "replace", side_effect=external_after_replace):
            with contextlib.redirect_stdout(output):
                code = notes.main(["save", str(self.root), self.name, before["revision"], "my draft"])
        reply = json.loads(output.getvalue())
        self.assertEqual(code, 1)
        self.assertFalse(reply["ok"])
        self.assertEqual(reply["error"], "conflict")
        self.assertNotIn("note", reply)
        self.assertEqual(self.path.read_text(), "external final version")


if __name__ == "__main__":
    unittest.main(verbosity=2)
