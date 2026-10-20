# 项目复查（2026-10-15）

复查范围：`tide-sidebar/` 全部源码与文档，以及它在本机的实际运行状态。方法：逐文件通读代码、比对文档与实现、核对宿主 API 证据（GIR / 运行日志 / 实际进程与文件权限）、重跑统一回归入口；另有两路独立只读审查（数据/服务层、原生界面层）在并行进行，结论会在收到后追加到本文件。

## 1. 事实基线（复查当时）

- 插件 `pang/tide-sidebar` 2.1.0 已启用；原生前端子进程 1 个（pid 2686，父进程 noctalia，启动于 17:27:04，RSS 约 225 MiB）。
- 数据目录 `~/.local/state/noctalia/plugins/data/pang/tide-sidebar/private/` 权限 0700；内有 notes-a/b、timer-a/b、stopwatch-a/b、preferences.json 与 `frontend/` 快照目录。
- 统一回归 `python3 -B tide-sidebar/tests/run_all.py` 退出码 0：notes 21、tools 95/3362 断言、stopwatch 22、service 68/500、frontend 15、panel 7、system 35、transport 7、native_notes 93、native_tools 110、native_system 36。
- 运行日志近期没有本插件相关 ERR/WRN；只有无关的蓝牙、网络与 PipeWire 警告。
- 侧栏当前处于收起状态（control.json `visible=false`）。

## 2. 发现

### 高：快捷键绑定会被安装器覆盖（已发生一次）

`~/Projects/arch-noctalia` 的 `payload/home/.config/niri/conf.d/binds.kdl` 与运行配置此前字节数完全一致（17643），2026-10-15 14:39 一次部署把它整体覆盖，我加在 33 行的 `Super+Shift+W` 被删除；同一时刻插件也被停用，所以按键完全没有反应。已在 17:39 补回并通过 `niri validate`，现在与 payload 的差异恰好只有那两行。

风险：只要再跑一次安装器就会重演。建议把同一行加进 payload 源文件（属于 `arch-noctalia` 的一处可 git 审阅改动，需用户同意）。

附带局限：按键效果**无法用脚本验证**。实测用 wtype 注入 Super+Shift+F11 触发临时探针绑定，探针文件未生成，证明 wtype 的虚拟键盘不经过 niri 快捷键处理。之前基于注入得出的“按键已验证”结论不成立，已在 README 更正为“需人工按一次确认”。

### ~~中：复制到剪贴板很可能无效，且界面报成功~~ → 已结案：实际可用（2026-10-15 验证）

本机 GIR 证据：`gdk_clipboard_set` 与 `gdk_clipboard_set_text` 都是 `introspectable="0"`（`set_text` 未导出，与早前探测一致）；GJS 里能取到的 `clipboard.set` 实为 `gdk_clipboard_set_value(shadows="set")`，其参数类型是 `GObject.Value`。

代码 `native/main.js:61-64` 直接 `get_clipboard().set(String(text))`，返回 `true`；三个调用点里 `notes.js:327` 与 `system.js:138` 有 try/catch，而 `tools.js:74-77` 没有。GIR 位置：`/usr/share/gir-1.0/Gdk-4.0.gir` 第 1573 行（`set`，introspectable=0）、1656 行（`set_text`，introspectable=0）、1737 行（`set_value`，shadows=set，参数 `GObject.Value`）。因此：若字符串→GValue 的封装不成立，计算器“结果已复制”会抛异常且不提示，便签/密码会提示失败——**相互矛盾**。

结论状态：**已验证可用**。真实往返验证：写入 `TIDE-CLIP-CHECK-1792` 后读回完全一致（验证时原剪贴板不含文本，没有内容被顶掉，脚本未打印任何剪贴板内容）。`main.js` 的 `copy()` 已改为捕获异常并返回真实结果，因此界面提示不再可能与实际不符；`tools.js` 本身就用 `!== false` 判断返回值，无需再改。

### ~~中：倒计时的存档韧性弱于便签与秒表~~ → 已修（2026-10-15）

`service.luau:139-157` 的 `loadTimer` 只用 `readJson`：文件存在但不可读时，会静默回到默认 15 分钟待机，并在下一次保存时覆盖其中一个槽位。相比之下便签有 `existing_unreadable` 保护（`service.luau:48-56`，检查点在第 52-53 行），秒表也有 `found` 检查（`service.luau:89-101`，检查点在第 93、100 行）。已补齐：`loadTimer` 现在也记录 `found`，读不出时明确提示“倒计时存档无法读取，已从默认时长开始；旧文件将在下次保存时被覆盖”，不静默覆盖。新增两条回归（不可读存档 / 可读存档胜过损坏的兄弟文件），服务规格现为 72 项、514 断言全部通过。

### ~~中：快照文件权限可再收紧~~ → 已修（2026-10-15）

`frontend/*.json` 与 `notes-*.json` 等实际权限都是 **644**（目录 0700 挡住了其他用户，所以不是真实泄露）。其中 `frontend/notes.json` 含完整便签正文。已改为启动与退出各执行一次 `chmod -R go-rwx -- <私有目录>`：目录仍是 0700。重载后实测：notes-a/b、timer-a/b、stopwatch-a/b、preferences.json 均为 **600**；运行期由宿主新写入的 `frontend/*.json` 仍会是 644（宿主写文件不给更严权限），退出时再次收紧。

### 低：文档与代码的漂移（已修三处）

README 已更正：① 快捷键那段改为写明“写在哪个文件 + 会被安装器覆盖 + 需人工按键确认”；② 增补剪贴板未验证的说明；③ 说明“插件设置里的‘减少装饰动效’优先于 `motion on` 命令”。

仍待补：`docs/reference-redesign.md` §最终本机检查里“用户已用实体键盘确认可以开关”需要注明时间点（该绑定随后被覆盖）。

### ~~低：死代码与杂物~~ → 已清理（2026-10-15）

- `lib/theme.luau`、`lib/view.luau`：现在只有 `view.luau` 引用 `theme.luau`，没有任何入口引用它们（`panel.luau` 已改为兼容转接，`service.luau` 只 require notes/countdown/calculator/frontend/stopwatch）。属于旧 Noctalia-UI 版本的残留。已移入 `.backups/legacy-lua-ui/`（该目录里本来就有同一份副本）—— 插件 `lib/` 现在只剩 calculator、countdown、frontend、notes、stopwatch。
- `previews/` 只保留与当前实现一致的 `light-note-live.png`、`mint-hotspot-live.png`、`stopwatch-tools-live.png`；其余 7 张已移入 `.backups/legacy-previews/`，`docs/reference-redesign.md` 的图片链接同步改到现行截图。
- `frontend/geometry.json` 只被写入、没有任何读取方（`native/main.js:23` 的 channels 列表不含 geometry），属于诊断残留。
- `.backups/tide-sidebar-before-native-20261014/transition-metadata.json` 里存着改版前的便签文件哈希（无正文）。

### 低：健壮性小项

- 前端进程按设计常驻（隐藏时仍每 4 秒心跳），这是 225 MiB 的代价；停用插件时它会被杀掉（此前停用期间实测无残留进程）。
- `restart()` 等 600 ms 后重启界面，理论上旧进程若卡住会出现两个层壳窗口；目前没有观察到，属低概率。
- `preferences` 的页签白名单与 `needsSystem` 判断里仍留着 `home/calculator/timer` 这些旧别名，新界面不会产生，属无害残留。

### 可复查的最小命令（已验证过形式，未执行会改环境的那些）

```sh
# 只读：确认运行配置里是否还有绑定，以及它是否被安装器 payload 覆盖
grep -n 'tide-sidebar' ~/.config/niri/conf.d/binds.kdl ~/Projects/arch-noctalia/payload/home/.config/niri/conf.d/binds.kdl
niri validate -c ~/.config/niri/config.kdl

# 会替换系统剪贴板内容（需要人工同意后运行）：验证 gdk_clipboard_set_value 是否真的写入
gjs -c "imports.gi.versions.Gtk='4.0'; imports.gi.versions.Gdk='4.0'; const Gtk=imports.gi.Gtk, Gdk=imports.gi.Gdk; Gtk.init(); const c=Gdk.Display.get_default().get_clipboard(); try { c.set('tide-clipboard-check') } catch(e) { print('set() threw: '+e.message); Gtk.main_quit() } c.read_text_async(null,(o,r)=>{ try { print('read back: '+c.read_text_finish(r)) } catch(e) { print('read failed: '+e.message) } Gtk.main_quit() }); Gtk.main()"
```
## 3. 建议顺序

1. 把 `Super+Shift+W` 也写进 `arch-noctalia` payload（防止再次丢失）；在统一检查里加一条**只读**环境校验：运行配置里是否存在该绑定，缺失就以清晰信息提示（正是本次事故的回归闸）。
2. 给剪贴板找一条可验证路径：先用现有函数做一次“写入→读回”的临时验证（需要用户同意替换剪贴板内容），再把返回值改成真实结果；顺手给 `tools.js` 的复制加上与另两处一致的 try/catch。
3. 给 `loadTimer` 补上与秒表/便签一致的“存在但不可读”保护。
4. 初始化后把数据文件收紧到 0600。
5. ✅ 已完成：死代码与过期截图移入 `.backups/`；`docs/reference-redesign.md` 补了快捷键被覆盖的时间点与“脚本无法验证按键”的说明。

已完成：第 2 项（剪贴板）、第 3 项（倒计时存档）、第 4 项（权限）、第 5 项（清理）。第 1 项按用户要求不做（不改 `arch-noctalia`）。

## 4. 明确未做/未验证

- 没有切换真实热点，没有用手机验证热点联网。
- 剪贴板往返验证已完成（写入后读回一致），原剪贴板内容不在场，未丢失。
- 没有验证真实按键（工具手段无效，见上）。
- 没有测试其它缩放率、其它合成器；本机结论都限于 1920×1080、scale 1 的 niri 会话。
