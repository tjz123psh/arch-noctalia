# -*- coding: utf-8 -*-
# rice-menu.py — Nautilus 中文右键增强（niri + Noctalia 桌面自制）
import os
import subprocess
from urllib.parse import unquote, urlparse

from gi.repository import Nautilus, GObject

IMAGE_EXT = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".tif", ".tiff",
             ".avif", ".jxl", ".svg", ".ico", ".heic"}
NOCTALIA = "/usr/bin/noctalia"
KITTY = "/usr/bin/kitty"
WLCOPY = "/usr/bin/wl-copy"
NOMACS = "/usr/bin/nomacs"
NVIM = "/usr/bin/nvim"
PKEXEC = "/usr/bin/pkexec"
NAUTILUS = "/usr/bin/nautilus"


def local_path(info):
    """FileInfo -> 本地绝对路径（非本地 URI 返回 None）"""
    if info is None or info.get_uri_scheme() != "file":
        return None
    return unquote(urlparse(info.get_uri()).path)


def parent_of(path):
    return path.rsplit("/", 1)[0] or "/"


def is_image(path):
    name = path.rsplit("/", 1)[-1]
    return "." in name and ("." + name.rsplit(".", 1)[-1].lower()) in IMAGE_EXT


def spawn(argv):
    try:
        subprocess.Popen(argv, start_new_session=True,
                         stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


def copy_text(text):
    try:
        p = subprocess.Popen([WLCOPY], stdin=subprocess.PIPE,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        p.communicate(text.encode())
    except Exception:
        pass


class RiceMenu(GObject.GObject, Nautilus.MenuProvider):
    """文件 / 文件夹 / 空白处的中文右键菜单"""

    def __init__(self):
        super().__init__()
        if os.environ.get("RICE_MENU_DEBUG"):
            print("rice-menu: provider loaded", flush=True)

    def _item(self, key, label, tip, icon, cb, *extra):
        try:
            item = Nautilus.MenuItem(name="RiceMenu::" + key, label=label,
                                     tip=tip, icon=icon)
        except TypeError:
            item = Nautilus.MenuItem(name="RiceMenu::" + key, label=label, tip=tip)
        item.connect("activate", cb, *extra)
        return item

    # ---------------- 回调 ----------------
    def cb_terminal(self, menu, target_dir):
        spawn([KITTY, "--directory", target_dir or "/"])

    def cb_nvim(self, menu, paths):
        if paths:
            spawn([KITTY, "--directory", parent_of(paths[0]), NVIM] + paths)

    def cb_nomacs(self, menu, paths):
        if paths:
            spawn([NOMACS] + paths)

    def cb_wallpaper(self, menu, path):
        spawn([NOCTALIA, "msg", "wallpaper-set", path])

    def cb_copy_path(self, menu, paths):
        copy_text("\n".join(paths))

    def cb_admin(self, menu, path):
        spawn([PKEXEC, NAUTILUS, path])

    # ---------------- 菜单 ----------------
    def get_file_items(self, files):
        paths = [p for p in (local_path(f) for f in files) if p]
        if not paths:
            return []
        dirs = [p for p in paths if p in [local_path(f) for f in files if f.is_directory()]]
        term_dir = dirs[0] if dirs else parent_of(paths[0])
        all_images = all(is_image(p) for p in paths)

        items = [
            self._item("term", "在终端中打开", "用 kitty 打开所在目录",
                       "utilities-terminal", self.cb_terminal, term_dir),
            self._item("nvim", "用 Neovim 编辑", "kitty + nvim",
                       "accessories-text-editor", self.cb_nvim, paths),
        ]
        if all_images:
            items.append(self._item("nomacs", "用 nomacs 打开", "图片查看器",
                                    "image-x-generic", self.cb_nomacs, paths))
            if len(paths) == 1:
                items.append(self._item("wall", "设为桌面壁纸",
                                        "Noctalia 立刻换壁纸（带过渡动画）",
                                        "preferences-desktop-wallpaper",
                                        self.cb_wallpaper, paths[0]))
        items.append(self._item("copy", "复制完整路径", "复制到剪贴板",
                                "edit-copy", self.cb_copy_path, paths))
        if dirs:
            items.append(self._item("admin", "以管理员身份打开",
                                    "会弹出授权窗口（polkit）",
                                    "dialog-password", self.cb_admin, dirs[0]))
        return items

    def get_background_items(self, current_folder):
        path = local_path(current_folder)
        if not path:
            return []
        return [
            self._item("b_term", "在终端中打开", "用 kitty 打开当前文件夹",
                       "utilities-terminal", self.cb_terminal, path),
            self._item("b_copy", "复制文件夹路径", "复制到剪贴板",
                       "edit-copy", self.cb_copy_path, [path]),
            self._item("b_admin", "以管理员身份打开", "会弹出授权窗口（polkit）",
                       "dialog-password", self.cb_admin, path),
        ]
