# 侧边栏工作台

适配本机 Noctalia 5.2.1 + niri。界面按用户确认的[参考式样张](<design/reference-flat-proof.png>)制作：米白底、奶黄色块、橄榄拼接、自然波浪分色与轻投影；不再使用品牌口号、反光渐变和一格格描边按键。

## 打开与关闭

**Super + Shift + W**，写在 `~/.config/niri/conf.d/binds.kdl`，改完 `niri validate` 通过即热加载生效。

> 注意：`~/Projects/arch-noctalia` 的安装器会用它的 `payload/.../conf.d/binds.kdl` 覆盖这个文件，**重跑安装器会把这行绑定删掉**。2026-10-15 已经发生过一次。重装后请重新确认，或把同一行也加进安装器源文件。设备按键的真实效果无法用脚本注入验证（wtype 的虚拟键盘不经过 niri 快捷键处理），需要人工按一次确认。

~~~sh
# 任意目录都可使用
noctalia msg plugin pang/tide-sidebar:backend all toggle

# 仓库根目录的便捷入口
bash tide-sidebar/open.sh
bash tide-sidebar/open.sh notes
bash tide-sidebar/open.sh tools
bash tide-sidebar/open.sh hotspot
bash tide-sidebar/open.sh windows
~~~

- 只有四个窄标签：便签、工具、热点、窗口。
- 计算器与倒计时在同一个工具页，不再分成两页。
- 面板内 Ctrl+1～4 切页，Esc 先取消当前确认，再收起。
- 状态栏可添加 pang/tide-sidebar:toggle，控制中心可添加 pang/tide-sidebar:open；现有布局不会被擅自改动。
- 旧 pang/tide-sidebar:sidebar 面板 ID 保留为兼容转接，不再绘制旧版界面。

## 视觉与布局

- 卡片是连续的平整色块，不把每个字段都装进独立的黑框或亮边小盒子。
- 便签使用原生多行 TextView，淡奶黄纸面和深色文字，随侧栏高度填满；切换列表改为原生弹层，打开或收起不再挤压正文高度，底部操作区与波浪分色连成一块。
- 计算器为 4×6 无框键盘，右侧运算符共用一条窄色块；π 仍可直接输入。
- 倒计时采用“左侧深橄榄标题 / 状态＋右侧浅黄数字 / 输入 / 操作”的拼接块。
- 只保留功能文字，没有欢迎语、品牌大标题或诗句。

## 功能

**便签**：添加、切换、重命名、复制、删除到回收区、恢复、拖动及上下排序。正文停笔后自动保存，切换或收起时请求立即保存。单条正文最多 64 KiB，最多 80 条便签及 80 条可恢复删除，总标题与正文不超过 1 MiB；超限不静默截断。右下角铅笔菜单保留编辑类操作。

**计算器**：原生输入、选择、粘贴、按键输入、括号、加减乘除、幂、常数 pi/π/e、ans、sqrt、abs、百分比与历史。百分比固定表示除以 100，不是商业计算器加价模式；算式由独立解析器处理，不执行代码。

**倒计时**：1 秒至 99:59:59，可直接键入自填时分秒；点进数字框会选中原值，直接打字即可替换（不再被 2 位长度限制挡住）。预设只改下次时长。计时进行或暂停时改时长，会先出现“按新时长开始”的二次确认，只有确认才用新时长替换当前计时；否则继续沿用原计时。开始、暂停、继续、重置均需点击相应按钮。收起界面继续计时，到点通知；绝对截止时间可跨界面重载或 Shell 重启恢复。

**秒表**：与倒计时互相独立，可开始、暂停、继续、重置，并计次；累计用绝对时间锚点，收起界面不会暂停，重启 Shell 也能恢复。计次最多 100 次，写满后明确提示且不丢弃旧记录，界面只展开最近几次。秒表有自己的存档，不会改动倒计时。

**热点**（浅薄荷绿界面）：读取真实状态、名称 / 密码 / 频段设置、开启 / 关闭 / 应用并重启。仍调用原 rice-hotspot，不重新配置系统网络。开热点会断开单网卡当前 Wi-Fi；关闭后只是尽力恢复，可能需重新认证，操作前明确确认。没有为了测试切换真实热点。

**窗口**：按名称搜索、点击跳转、确认后正常关闭。跳转后侧边栏**保持打开**，可以连续切换多个窗口；要收起用左下角箭头、Esc 或 `Super+Shift+W`。始终使用明确的字符串窗口 ID，不省略 ID，不强杀进程。已消失窗口不会误操作当前焦点窗口。

## 数据没有迁移

原 Noctalia 服务仍是便签和计时数据的唯一写入方。新界面只展示状态并发送操作请求，不另建一套便签数据库。

~~~text
~/.local/state/noctalia/plugins/data/pang/tide-sidebar/private/
  notes-a.json / notes-b.json       原便签双存档
  timer-a.json / timer-b.json       原倒计时双存档
  stopwatch-a.json / stopwatch-b.json  秒表双存档（新增，与倒计时分开）
  preferences.json                 页面及动效偏好
  frontend/                        原生界面的私有状态快照
~~~

目录为 0700；启动与退出时各执行一次 `chmod -R go-rwx`，把已有文件收紧到 0600（运行期宿主新写入的快照会短暂回到 0644，仍在 0700 目录内）；如设置了 XDG_STATE_HOME，以宿主实际路径为准。数据不放进代码仓库。不根据改版前的旧快照回滚使用期间新增的便签或已经继续运行的计时。

写入后回读校验；已有但不可读的便签、两份都损坏的存档不会被当成空白覆盖。界面草稿不会被迟到的旧状态覆盖。一次粘贴 / 替换选区仅在编辑事务结束时发送最终文本，避免保存中间空正文。

## 动效和性能

控件只创建一次，状态更新只改必要属性；不再因为每秒计时、悬停或网络刷新而重建整棵界面树。开合、切页和列表展开使用原生过渡。波浪是小绘图区，仅在明确交互后短时变化，闲置和隐藏时停止绘制。

已按用户确认恢复完整动效，并移除了容易误触的侧栏减动效按钮。仍可通过插件设置或命令主动减少动效（**插件设置优先**：设置里打开“减少装饰动效”时，下面的 `motion on` 不会把它恢复）：

~~~sh
noctalia msg plugin pang/tide-sidebar:backend all motion on
noctalia msg plugin pang/tide-sidebar:backend all motion off
~~~

本机一次预热后的 6 秒观察：Noctalia 约 4.00%＋前端 1.67%，合计约单核 5.67%；收起后合计 1.17%。原生前端 RSS 约 217 MiB，是额外常驻界面的内存代价。它不是零开销，也不把 CPU 采样冒充 FPS 或输入延迟。

详见[性能记录及条件](<docs/performance-observation.json>)和[改版验收说明](<docs/reference-redesign.md>)。旧版样本包含开场动画、新版样本预热后才开始，不能据此声称严格减少了50%。

## 隐私与系统边界

- 没有安装新依赖、替换 Noctalia 二进制或更改全局 GTK 主题。
- 使用本机已有 GTK4 / GJS / gtk4-layer-shell；仅此前端进程按[官方要求](https://github.com/wmww/gtk4-layer-shell/blob/main/linking.md)预载 layer-shell 库，不把该变量传播给辅助程序。
- 热点状态查询不执行 rice-hotspot state、不读密码、不抢原脚本锁。
- 热点密码只在显式查看时进入本页内存，隐藏/切页/关闭即清除，30 秒后自动遮盖。复制可能进入系统剪贴板历史，界面有提示。
- 复制走 `Gdk.Clipboard.set`：本机 GIR 里它是 `gdk_clipboard_set_value(GValue)`（`set_text` 未导出）。已做真实往返验证（写入后读回一致），可用；`copy()` 会把异常返回成失败，界面提示与实际结果一致。
- 新密码走 0600 的一次性私有请求文件，用后删除；不放进插件命令参数或共享状态。原脚本内部向 nmcli 传密码参数的既有行为未改动。
- 丢弃原脚本包含密码的 stdout，屏蔽其密码通知，错误只转为固定提示；转发警告不会被普通刷新抹掉。
- API32 流式接口单行限制 64 KiB，大便签经过有界分片，完整重组后才交给原数据模型，不靠截断或降低正文上限规避。

## 验证与开发

~~~sh
# 数据逻辑、真实GTK控件离屏构造/回调、长文本传输、语法和清单
# 不修改真实便签/计时/网络，也不呈现测试窗口
python3 -B tide-sidebar/tests/run_all.py

# 可选：只改变侧栏可见性，采样两个进程的CPU/RSS，并恢复原可见状态
python3 -B tide-sidebar/tests/native_perf.py --allow-ui-toggle

# 可选：临时窗口内用真实键盘键入验证时长输入；计时状态全部为模拟数据
env GDK_BACKEND=wayland gjs -m tide-sidebar/tests/native_keyboard_spec.js --allow-test-window

# 可选：在真实 Wayland 层表面验证便签弹层定位/关闭且不挤压正文
env LD_PRELOAD=/usr/lib/libgtk4-layer-shell.so GDK_BACKEND=wayland gjs -m tide-sidebar/tests/native_popup_spec.js --allow-test-window

# 修改原生JS或CSS后只重载界面，保留后台计时与存档
noctalia msg plugin pang/tide-sidebar:backend all reload-ui
~~~

GTK 原生控件保留输入法、选区及撤销能力；离屏测试不代表已经逐项手动验收特定输入法的候选交互。本机真实布局和资源观察在 1920×1080、缩放1的 niri 会话完成；其它缩放率尚未逐一测试。

## 插件设置

在 **设置 → 插件 → 侧边栏工作台**（或 `noctalia msg settings-open-plugin pang/tide-sidebar`）里编辑；改完即时生效，不需要重启 Shell。截图：[设置页](<previews/plugin-settings.png>)。

| 设置 | 类型 | 默认 | 作用 |
|---|---|---|---|
| 减少装饰动效 | 布尔 | 关 | 停波浪与页面过渡，保留操作反馈 |
| 侧栏宽度 | 整数 380–640 | 450 | 侧栏表面的宽度（逻辑像素） |
| 记住上次的标签页 | 布尔 | 开 | 再次打开时回到上次的页面 |
| 起始标签页 | 选择 | 便签 | 不记住时使用的页面（关闭“记住”后才显示） |
| 倒计时默认时长 | 整数 1–5999 分 | 25 | 倒计时空闲时的默认时长 |
| 倒计时预设 | 字符串列表 | 5/15/25/60 | 预设按钮及其时长，无效项忽略，最多 6 个 |
| 关闭窗口前先确认 | 布尔 | 开 | 关闭时是否先弹确认卡片 |
| 默认热点名称 | 文本 | 空 | 脚本没有记录名称时预填的名称 |
| 默认热点频段 | 选择 | 2.4 GHz | 脚本没有记录频段时预选的频段 |
| 状态刷新间隔 | 整数 1–30 秒（高级） | 3 | 热点/窗口页打开时的状态查询间隔 |

每一项都接到真实行为：宽度改变层壳尺寸，预设决定按钮，默认时长用于空闲倒计时（已在用的倒计时不会被改写），热点默认值只在本机脚本尚未记录时生效。`tests/run_all.py` 会校验清单完整性、翻译键齐全、脚本只读已声明的键，并检查服务发布的每个快照通道都被前端读取。

## 结构

- [主壳](<native/main.js>)、[平色样式](<native/style.css>)、[小范围波浪绘制](<native/ui.js>)。
- [便签页](<native/views/notes.js>)、[合并工具页](<native/views/tools.js>)、[热点与窗口页](<native/views/system.js>)。
- [原后台](<service.luau>)继续负责持久化、倒计时、系统操作；[私有界面桥接](<lib/frontend.luau>)管理原生前端。
- [便签模型](<lib/notes.luau>)、[计算模型](<lib/calculator.luau>)、[倒计时模型](<lib/countdown.luau>)、[秒表模型](<lib/stopwatch.luau>)沿用可独立测试的逻辑。
- 每个页面的自测脚本在 [tests/](<tests/>)；视觉基准在 [design/](<design/>)，当前实机截图在 [previews/](<previews/>)。
- [系统助手](<helpers/system.py>)不依赖第三方Python包。
- [SDK 接口笔记](<docs/sdk-notes.md>)、[改版验收](<docs/reference-redesign.md>)、[性能记录](<docs/performance-observation.json>)、[项目复查](<docs/project-review.md>)。

停用插件不会删除便签。更新前先等便签显示已保存。不要通过重启整套 Shell 来代替界面重载或单个插件排查。
