# 侧边栏工作台

适配本机 Noctalia 5.4.0 + niri 26.04。界面按[实机视觉基准](<design/reference-flat-proof.png>)制作：米白底、奶黄色块、橄榄拼接、自然波浪分色与轻投影；不再使用品牌口号、反光渐变和一格格描边按键。

## 打开与关闭

**Super + Shift + W**，写在 `~/.config/niri/conf.d/binds.kdl`，改完 `niri validate` 通过即热加载生效。

> 注意：`~/Projects/arch-noctalia` 的安装器会用它的 `payload/.../conf.d/binds.kdl` 覆盖这个文件，**重跑安装器会把这行绑定删掉**。2026-10-15 已经发生过一次。重装后请重新确认，或把同一行也加进安装器源文件。设备按键的真实效果无法用脚本注入验证（wtype 的虚拟键盘不经过 niri 快捷键处理），需要人工按一次确认。

~~~sh
# 任意目录都可使用
noctalia msg plugin pang/tide-sidebar:backend all toggle

# 仓库根目录的便捷入口
bash tide-sidebar/open.sh
bash tide-sidebar/open.sh home
bash tide-sidebar/open.sh notes
bash tide-sidebar/open.sh tools
bash tide-sidebar/open.sh hotspot
bash tide-sidebar/open.sh windows
~~~

- 五个窄标签：首页、便签、工具、热点、窗口。
- 首页三张卡：时钟（日期 / 电池 / 运行时长 + 潮汐）、系统概览（CPU·内存·NVMe·网络 四行紧凑条 + 16 核律动 + Top 3 任务）、工作台（工程与书签）。
- 计算器与倒计时在同一个工具页，不再分成两页。
- 面板内 Ctrl+1～5 切页，Esc 先取消当前确认，再收起。
- 状态栏可添加 pang/tide-sidebar:toggle，控制中心可添加 pang/tide-sidebar:open；现有布局不会被擅自改动。
- 旧 pang/tide-sidebar:sidebar 面板 ID 保留为兼容转接，不再绘制旧版界面。

## 视觉与布局

**配色不写死，跟着壁纸走。** `native/palette.js` 读 Noctalia 生成的 `~/.config/gtk-4.0/noctalia.css`（36 个 `@define-color`），推导出 `@t_bg / @t_surf0 / @t_surf1 / @t_surf2` 三级表面、两档文字灰、强调色及其透明变体，`style.css` 只引用这些 token。壁纸或调色板一变，Noctalia 重写该文件，侧栏用 `Gio.FileMonitor` 热重载并重新着色——所以它在深色、浅色、任何壁纸下都是"同一个物种"。调色板缺失时回退到内置的一套，不会白屏。

- **三级表面**：窗口底 `t_bg` → 卡片 `t_surf1` → 行/控件 `t_surf2`，每层 1px 内高光 + 低透明外阴影，靠明度台阶而不是描边框出层次。
- **强调色只出现在该在的地方**：当前页、主按钮、开关态、当前窗口。其余一律灰阶——艳不艳由"用得少"决定，不由饱和度堆出来。
- 便签：卡片内是原生多行 TextView，字号 14 / 行高宽松；切换列表已并入卡片顶部（不再浮在卡片外面错位）；底部改 8px 细波线，不再用 54px 实心色块。
- 计算器：4×6 键盘，按键是深一档的圆角块 + 1px 描边；右侧运算符列单独成组；等号用强调色。
- 倒计时/秒表：同一套卡片语法，主操作=强调色，次操作=描边按钮。
- **字体**：`Adwaita Sans`（与顶栏同源，中文回退 Noto Sans CJK），字阶 12 / 13 / 15 / 18，数字开 `tabular-nums`（跳秒不抖）。
- **点击目标**：所有可交互元素 ≥32px，列表行 ≥36px；导航条 56px 宽、图标 24px、文字 11px。
- 只保留功能性文字：工程副标题、窗口页说明、热点页脚注、空态第二行都已删除。

## 功能

**首页**：实时跳动数字时钟与公历/周次、电池充电状态与系统运行时间；时钟卡片底部双层半透明自然流动潮汐水波；CPU 总负载脉冲走势图与核心硬件温度（带温控呼吸指示灯）；多核 16 线程动态律动矩阵（类似音频均衡器的各核心实时调度可视化）；RAM 内存占用胶囊进度条与可用/缓存细分；NVMe 存储读写双向对冲示波器；实时网络双流吞吐走势图；前台活跃任务（Top Tasks）实时监控雷达与动态能量槽。

其中 **工作台与书签** 卡片由 `~/.config/noctalia/workspaces.json` 驱动（首次自动生成模板，安装器亦以 seed 形式带一份默认值，重装不覆盖）：`workspaces` 数组里每项是一条工程（`name` / `path` / `desc` / `icon`，`path` 支持 `~/` 展开），右侧「终端」「Code」分别用 kitty `--directory` 与 `code` 打开；`bookmarks` 数组里每项是一条网址（`name` / `url` / `icon`），点击用 `xdg-open` 拉起默认浏览器。卡片右上角的铅笔图标直接打开这个 JSON，每次展开侧栏都会重新读取，改完保存即刻生效。

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

便签/计时/偏好写入先落到 `.pending` 再 rename 回读，进程在写入中途被杀不会留下半截正式存档；单个损坏槽会备份为 `.corrupt-*` 后从空白恢复，两份都损坏才阻止覆盖。界面草稿不会被迟到的旧状态覆盖。一次粘贴 / 替换选区仅在编辑事务结束时发送最终文本，避免保存中间空正文。

## 输入法（fcitx5 / Wayland）

原生前端由 `GTK_IM_MODULE=wayland` 启动，便签 `GtkTextView` 也显式设了 `im_module: 'wayland'`，走合成器的 `text-input-v3`。原因：本机全局设了 `GTK_IM_MODULE=fcitx`，而 `fcitx5-gtk4` 模块在 layer-shell 表面上拿不到正确的屏幕坐标，候选窗会算到屏幕底部、把正在输入的拼音挡住；改用 Wayland 原生协议后候选窗严格贴光标下方展开。便签正文底部留了 160px 过底空间（`bottom_margin`）并随光标自动滚动，保证候选窗永远有地方往下放，不会向上翻转盖住输入行。

## 动效和性能

控件只创建一次，状态更新只改必要属性；不再因为每秒计时、悬停或网络刷新而重建整棵界面树。开合、切页和列表展开使用原生过渡：开合是 620ms 伸展 / 560ms 收回的贴边横向抽屉，交互 120ms、展开 160ms、切页 220ms，子页 host 在启动时按导航顺序创建，方向始终跟随 rail/Ctrl+1–4；隐藏状态下切页时长 0；便签弹层与窗口列表打开时逐行淡入，计时器开始/完成时波浪轻脉冲。减少动效时这些时长归零（包括波浪与逐行淡入）。波浪只剩两种形态：首页时钟卡是两条 1.6px 的强调色细描边（缓慢横移），便签与计算器是 8–10px 的单条波线——都不再有大面积实心色块。页面收起（`onHide`）即 `stopBreathe()` 注销帧回调并冻结 CSS 关键帧，隐藏期不产生绘制与动画开销。

已按用户确认恢复完整动效，并移除了容易误触的侧栏减动效按钮。仍可通过插件设置或命令主动减少动效（**插件设置优先**：设置里打开“减少装饰动效”时，下面的 `motion on` 不会把它恢复）：

~~~sh
noctalia msg plugin pang/tide-sidebar:backend all motion on
noctalia msg plugin pang/tide-sidebar:backend all motion off
~~~

收起满 15 分钟（可在插件设置里改成 0–120，0 为常驻）后前端退出，隐藏期间内存归零；后台服务继续跑便签、倒计时和通知，再打开约 0.4 秒冷启。前端使用会话默认的 GL 渲染，以保证标签页切换的 220ms Stack 滑动稳定在 144fps。本机前端的常驻 RSS 约 207–223 MiB；这是流畅切页与低内存之间的取舍，cairo 路径虽然约 102 MiB，但切页只有 48–72fps。它不是零开销，也不把 CPU 采样冒充 FPS 或输入延迟。

详见[性能记录及条件](<docs/performance-observation.json>)和[改版验收说明](<docs/reference-redesign.md>)。旧版样本包含开场动画、新版样本预热后才开始，不能据此声称严格减少了50%。

## 隐私与系统边界

- 没有安装新依赖、替换 Noctalia 二进制或更改全局 GTK 主题。
- 使用本机已有 GTK4 / GJS / gtk4-layer-shell；仅此前端进程按[官方要求](https://github.com/wmww/gtk4-layer-shell/blob/main/linking.md)预载 layer-shell 库，不把该变量传播给辅助程序。
- 热点状态查询不执行 rice-hotspot state、不读密码、不抢原脚本锁。
- 热点密码只在显式查看时进入本页内存，隐藏/切页/关闭即清除，30 秒后自动遮盖。复制后会记录该文本；隐藏/30 秒/操作成功时异步比对并清空剪贴板，只有剪贴板仍是这份密码时才清，不会误删后来复制的内容。
- 复制走 `Gdk.Clipboard.set`：本机 GIR 里它是 `gdk_clipboard_set_value(GValue)`（`set_text` 未导出）。已做真实往返验证（写入后读回一致），可用；`copy()` 会把异常返回成失败，界面提示与实际结果一致。
- 新密码走 0600 的一次性私有请求文件，不放进插件命令参数或共享状态。后台取得操作锁后才消费请求；操作忙/失败时文件保留，前端密码也保留到本次 feedback，成功或超时才清空，避免“文件已删、输入已清、操作失败”。原脚本内部向 nmcli 传密码参数的既有行为未改动。
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
| 编辑器命令 | 文本 | 空 | 工作台「打开工程/配置」用的命令；留空自动探测 code → codium → zed → kitty -e nvim，都没有则退回 xdg-open |
| 状态刷新间隔 | 整数 1–30 秒（高级） | 3 | 热点/窗口页打开时的状态查询间隔 |
| 闲置退出 | 整数 0–120 分（高级） | 15 | 收起超过该时长后退出原生前端，隐藏期间不占内存；0 表示常驻，再次打开约需半秒 |

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
