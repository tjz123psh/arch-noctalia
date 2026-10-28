# Noctalia 5.2.1 / plugin_api 32 SDK 核实笔记

结论：可以用原生 Luau 插件做侧栏、编辑、拖放、后台服务和轻量动画；没有 QML 服务对象、通用 canvas/shapes 或可自定义的 CSS 动画。以下按 v5.2.1 实际导出/属性白名单记录，避免套用旧版 Noctalia 或浏览器 API。

## 核实范围与版本

- 本机包查询：`pacman -Qo /usr/bin/noctalia` → noctalia 5.2.1-1。未修改宿主、系统配置或插件启用状态。
- 当初核对时用的本机稀疏源码缓存已删除；对应源码以 [v5.2.1 标签](<https://github.com/noctalia-dev/noctalia/tree/v5.2.1>) 为准（当时的 HEAD 为 `6ef43e2bf2f3d5b4205ec72a72e34a2ab76ce3b4`，与 tag 一致）。
- [API 版本常量](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/scripting/plugin_api.h>)：最高 32；require 为 22、argv 子进程为 24、输入 frameVisible 为 27、容器 tooltip 为 32。
- [运行时文档](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/docs/user/plugins/development/runtime-api.mdx>)、[UI 文档](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/docs/user/plugins/development/declarative-ui.mdx>)、[入口与生命周期](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/docs/user/plugins/development/entries.mdx>)。

## 1. Panel 声明、尺寸与生命周期

示例配置语法（不是新增启用状态）：

~~~toml
[[panel]]
id = "panel"
entry = "panel.luau"
width = 460
height = "fill"
placement = "floating"
position = "center_left"
keyboard_focus = "on_demand"
open_near_click = false
dismiss_on_outside_click = true
layer = "top"
~~~

- 正确键名是 `keyboard_focus`，不是 `keyword_focus`。
- width/height 各为正数逻辑像素或 `"fill"`；fill 仅适用于 floating。没有 `panelfill`、面板背景 `fill` 或运行时 `panel.setSize()`。
- position 全集：auto、center、top_left、top_center、top_right、center_left、center_right、bottom_left、bottom_center、bottom_right。左侧 top_left 和 center_left 均合法。
- keyboard_focus：on_demand / exclusive / none；none 必须搭配 dismiss_on_outside_click=false，且不能捕获键盘。
- persistent=true 的面板独立于普通面板槽，必须不响应外点关闭、不用 exclusive、不用 ui.select；始终 floating。
- 普通带装饰面板每边扣 **14 逻辑像素**宿主内距。width=460 时内部可用宽约 432，根树自己的 padding 还要另外扣。让根布局 stretch，勿把根树 width 再写成 manifest 宽。
- fill 轴由 compositor 扣 exclusive zones；普通浮动面板外侧还留 8 逻辑像素屏边距。不能把输出裸分辨率当内部高度。

准确 API：

~~~lua
panel.render(tree)
panel.close()
panel.setWantsSecondTicks(boolean) -- update()，仅打开期间
panel.setNeedsFrameTick(boolean)   -- onFrameTick(deltaMs)，仅打开期间
noctalia.togglePanel("author/plugin:panel")

function onOpen(context) end       -- context 是 panel-open 的可选字符串
function onClose() end
function update() end
function onFrameTick(deltaMs)
  local dt = tonumber(deltaMs) or 0 -- 此版源码实际按字符串投递
end
function onKey(chord, pressed) end -- chord:string；pressed:boolean
function onExit(signal, reason) end
~~~

- 面板 runtime 首次打开时才创建，普通关闭不销毁 VM；状态和 watch 跨开合保留。
- 关闭时先停 tick，再排队调用 onClose，场景随后拆除。重开原生输入控件重新创建。
- onExit 在 reload/disable/uninstall/shutdown 之前调用；SIGKILL/崩溃没有保证。持久编辑建议变更后短延迟保存，onClose/onExit 再补保存，不只靠退出时保存。
- 帧事件会合并，慢脚本只收到最新帧，不保证每帧调用。插件自己算缓动并重渲染；无 animate/tween/transition/transform API。
- capture_keys 在 manifest 声明；未声明键不投递。输入框优先接收可打印键；Escape/用户 Cancel 始终归宿主；无自动重复按键事件。

源码：[面板实现](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/shell/panel/plugin_panel.cpp#L196-L283>)、[宿主内距](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/shell/panel/panel_manager.cpp#L2757-L2770>)、[样式常量](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/ui/style.h#L23-L29>)、[位置枚举](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/config/config_types.h>)。

## 2. UI 构造器与样式白名单

每个构造器都是 `ui.type(props, children?)`，返回普通树表。每个节点可有稳定 `key`；公共属性：width、height、flexGrow、opacity、visible。长度均为逻辑 px，width/height 在 UI props 中是数字，不是 `"fill"`。

真实导出：column、row、box、label、glyph、image、separator、spacer、progress、button、graph、input、markdown、select、slider、toggle、scroll、dragSource、dropZone。**没有 canvas、path、shape、stack、grid、absolute positioning。**

| 控件 | 额外属性 |
| --- | --- |
| row / column | gap, padding, paddingH, paddingV, align, justify, fill, radius, border, borderWidth, minWidth, minHeight, onClick, onHover, tooltip |
| box | fill, radius, border, borderWidth, softness, onClick, onHover, tooltip |
| label | text, fontSize, color, fontWeight, maxWidth, maxLines, textAlign, fontFamily, baseline |
| glyph | name, size, color |
| image | path, radius, fit, border, borderWidth, onClick, onHover, tooltip |
| button | text, glyph, fontSize, glyphSize, variant, contentAlign, enabled, selected, onClick, onRightClick, tooltip, controlSize, onHover |
| graph | values, values2, color, color2, lineWidth, fillOpacity, onPointerMove, onPointerLeave |
| progress | progress, fill, track, radius |
| scroll | fill, radius, border, borderWidth, gap, padding, paddingH, paddingV, align, justify, stickToBottom, onScroll, scrollToBottomRev |
| input | value, placeholder, fontSize, enabled, password, multiline, focus, onChange, onSubmit, controlSize, submitOnEnter, frameVisible |
| select | options, selectedIndex, enabled, placeholder, onChange, controlSize |
| slider | min, max, step, value, enabled, onChange, onDragEnd, controlSize |
| toggle | checked, enabled, onChange |
| markdown | text |
| separator | thickness, color, spacing, orientation |

- padding、paddingH、paddingV、radius 都是单个数字，不是四边数组。paddingH/V 覆盖 padding 对应轴。无 shadow/boxShadow/自定义阴影；box 没有 padding。
- align=start/center/end/stretch，默认跨轴 stretch；justify=start/center/end/space_between。
- 颜色：palette role、role/alpha（如 `primary/0.6`）、#rrggbb、#rrggbbaa。opacity 会连子内容一起透明；只透明底色应给 fill 带 alpha。
- button variant=default/primary/secondary/destructive/outline/ghost；contentAlign=start/center/end；controlSize=sm/md/lg，分别 32/38/44 逻辑 px，显式 height 优先。
- **button 没有 fill、textColor、color、radius。**自定义彩色按钮用可点击 row/column + label(color)/glyph(color)。
- 未传的很多 props 会保留此前值；动态可见/禁用等状态最好每次显式传当前值，不靠 nil 撤销。

来源：[构造器全集](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/scripting/ui_prelude.h>)、[属性白名单](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/ui/ui_tree_reconciler.cpp#L457-L523>)、[内距/圆角解析](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/ui/ui_tree_reconciler.cpp#L1184-L1278>)。

## 3. 回调、文本编辑与拖放

回调接受 Luau 闭包，或入口脚本全局函数名。模块全局不会成为入口全局，跨模块 UI 回调优先直接传闭包。

- onClick()：无参数。
- onHover(state, key)：两个字符串，state 是 `"true"` 或 `"false"`；仅最内层 hover 目标报告，交互子节点可能让父容器报离开。
- toggle onChange(value)：字符串 `"true"/"false"`；slider 是数字的字符串；input 是完整当前文本。
- select selectedIndex 是 **零基**；onChange(indexText, selectedText) 两字符串。
- graph onPointerMove(normX, normY)：0..1 的字符串；onPointerLeave() 无参数。
- scroll onScroll(offset, maxOffset)：两数字字符串。

### 输入编辑器

- input 非受控：value 只在创建时播种，后续 render 不会覆盖宿主文本缓冲；稳定 key 保持光标/选择；要程序改文本需换 key 重建。
- focus=true 同样只创建时抢焦。不要每个动画帧换 key。
- multiline=true 支持换行、选择、复制、滚动、撤销；给 height 或 flexGrow。multiline 与 password 不能并用。
- 默认 Enter 换行、Ctrl+Enter 提交；submitOnEnter=true 时 Enter 提交、Shift+Enter 换行，Ctrl+Enter 仍提交。
- **不支持 textColor/color/selectionColor/fontFamily/fill/border/radius。**支持 fontSize。
- 宿主实际文字为 OnSurface，placeholder 为 OnSurfaceVariant，选区/光标为 Primary；输入底色聚焦 Surface、未聚焦 SurfaceVariant。深色宿主与浅色卡片混搭时，保留原生 frame，或把编辑区背景设成匹配的 palette surface。
- frameVisible=false 仅隐藏原生背景/边框，不改变文字色。

来源：[受控行为和回调实现](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/ui/ui_tree_reconciler.cpp#L1651-L1762>)、[输入配色](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/ui/controls/input.cpp#L1510-L1613>)。

### 面板内拖放

~~~lua
ui.dragSource({
  key = "grip-" .. noteId,
  dragType = "note", payload = noteId,
  previewAncestor = 1, liftFromLayout = true,
  width = 24, height = 24,
}, { ui.glyph({ name = "menu-2", size = 14 }) })

ui.dropZone({
  key = "before-" .. noteId,
  accepts = { "note" }, value = "before:" .. noteId,
  onDrop = function(payload, target) reorder(payload, target) end,
  direction = "column", height = 3, expandOnDrag = true, hitSlop = 20,
})
~~~

- 两者继承 flex 布局样式。dragSource 必填 dragType/payload，另有 enabled、tooltip、previewAncestor(0..8)、liftFromLayout。
- dropZone 必填 accepts/value/onDrop；另有 enabled、direction(row/column)、expandOnDrag、hitSlop。onDrop(payload,value) 不提供坐标。
- 仅同一 panel 内左键拖放；放在外面取消；拖动时不能滚轮滚动，需提供按钮式排序替代。
- payload≤16KiB；dragType、value、回调名、每个 accepts 项≤256B；accepts 最多16项。

来源：[拖放参考与限制](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/docs/user/plugins/development/declarative-ui.mdx#L473-L536>)。

## 4. 图形、SVG 与动画

- graph 的 values/values2 是归一化 0..1 数组，最多两条脚本曲线；fillOpacity 为 0..1；无 graph radius/背景/第三曲线/自定义shader。可每隔约33ms重算轻量装饰波浪，不把它标成真实系统数据。
- box 是圆角矩形；label/glyph/image 可组合。没有任意 canvas、path、shape 或 transform。
- ui.image 的本地 SVG 经 librsvg 栅格化，支持 contain/cover/stretch；不是带 DOM 的交互 SVG，也不是动画 SVG 引擎。
- 同路径、同目标尺寸的 image 重渲染不会重新读文件；无 watch/revision prop。动态图片需换路径或重建 key，切勿逐帧写 SVG 期待自动更新。
- 底层图片 loader 能解 data URI，但 panel 路径解析会把它当插件相对路径拼接，所以 panel.image 不应使用 data URI。
- 开关/按钮等宿主控件有自己的交互动画，但插件无配置其时长/曲线的 SDK。

来源：[graph props 应用](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/ui/ui_tree_reconciler.cpp#L1549-L1580>)、[SVG loader](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/render/core/image_file_loader.cpp#L398-L521>)、[image 缓存判断](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/ui/ui_tree_reconciler.cpp#L1377-L1385>)、[panel 图片路径解析](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/shell/panel/plugin_panel.cpp#L486-L500>)。

## 5. 模块、service、消息和状态

~~~lua
local calculator = require("./lib/calculator.luau")
noctalia.setUpdateInterval(1000)
function update() end
function onConfigChanged() end
function onEnable() end
function onOutputsChanged() end
function onIpc(event, payload) end
function onExit(signal, reason) end

noctalia.state.set("snapshot", value)
local initial = noctalia.state.get("snapshot")
noctalia.state.watch("snapshot", function(value) end)
~~~

- require 必须以 ./ 或 ../ 开头且显式以 .luau 结尾；相对调用所在模块文件，而非工作目录。模块必须返回一个非 nil 值；各 entry 独立 VM/模块缓存，不能用 require 共享运行时内存。
- 成功 require 的模块被监听，修改会热重载所属 entry；循环 require 报错；失败模块不缓存、不监听。
- service 用 manifest `[[service]] id="service", entry="service.luau"` 声明。顶层初始化在每次载入运行；setUpdateInterval 下限16ms，默认1000ms。
- onEnable 仅显式启用成功时调用，不是每次启动回调。service 有 onConfigChanged 就原地更新配置，否则重启 runtime。onOutputsChanged 表示输出集合/几何变化。
- onExit(signal,reason)：signal=2/15/0，reason=shutdown/reload/disable/uninstall。普通 onClose 不是 onExit。
- state 为每插件进程内 JSON 值复制；只可用 plain data，非磁盘持久化。service reload 保留旧值，不能把 reload 当清空。
- watch 不立即重放已有值，初始化须 get；每次 set 均通知，即使值相同。无 unwatch 返回句柄；runtime teardown 统一清理订阅。只顶层注册一次，不要 onOpen 重复 watch；避免 watch 回写自身形成循环。
- 磁盘持久化：pluginDataDir() → readFile/writeFile/renameFile + json.decode/encode。不要写 pluginDir()，git materialized runtime 更新可能覆盖。json.decode/encode 失败返回 nil,error；readFile 失败返回 nil,error；writeFile 返回 bool,可选error。

外部消息语法：

~~~sh
noctalia msg plugin author/plugin:service all event optional-payload
noctalia msg panel-toggle author/plugin:panel
noctalia msg panel-open author/plugin:panel optional-context
~~~

service/panel 是单例，消息 target 应为 all。参数落到 onIpc(event,payload)，payload 保留事件名后的原始文本。插件内部传递状态/请求优先 state，不用反复 shell 出 IPC。

来源：[模块与入口](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/docs/user/plugins/development/entries.mdx>)、[service 实现](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/scripting/plugin_service_host.cpp>)、[状态 store](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/scripting/plugin_state_store.cpp>)、[订阅注册/清理](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/scripting/script_runtime.cpp#L744-L755>)、[IPC](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/docs/user/ipc/plugins.mdx>)。

## 6. 子进程、系统服务、窗口和时间

~~~lua
local accepted = noctalia.runAsync({ executable, "arg1", dynamicValue }, function(result)
  -- result.exitCode:number; stdout/stderr:string
  -- timedOut/stdoutTruncated/stderrTruncated:boolean
end, 60000)

noctalia.runAsync({ executable, "arg1" }) -- 无callback：detached，不捕获结果
noctalia.runStream("shell command", function(line) end)
noctalia.commandExists("program")
noctalia.getenv("HOME")
noctalia.outputs() -- {name,description,width,height,x,y,scale,focused}[]
noctalia.focusedOutputName()
noctalia.appIconPath(appId, sizePx)
noctalia.copyToClipboard(text, "text/plain") -- bool；原生内存路径，不经argv
local epochMs = noctalia.nowMs()
local clockText = noctalia.formatTime("%H:%M", epochMs / 1000)
~~~

- runAsync 第一参数字符串会经 /bin/sh -c；数组直接 exec，每项保留一个参数。动态用户值优先数组，勿拼 shell。
- 返回 true 仅受理，不是 exitCode=0。第三参数 timeoutMs 是毫秒，默认5000、硬截断为 **50..60000**；传100000并不会等100秒。
- 每 entry 最多8个带回调子进程，全局32；stdout/stderr 各最多1MiB。必须检查 accepted、exitCode、timedOut 和截断标记。
- 捕获子进程是独立进程组。超时向组及主 pid 发 SIGTERM，最多等约100ms，再 SIGKILL；普通子进程也被清理。没有捕获任务取消句柄；卸载不能替代 helper 的自身截止/清理。
- runStream 只有命令字符串+逐行stdout回调；reload/停止 runtime 会终止活动 stream。与 runAsync 的捕获任务不是同一种生命周期。
- **没有 services.command、Network/Toplevel 服务对象、窗口枚举/聚焦/关闭 Lua API**。本版本全部 noctalia.* 导出里没有这些能力；通过经过校验的 niri/Python JSON helper 对接，不能借用 v4 QML API。
- appIconPath 可把窗口 appId 解析到本地图标；无匹配 desktop entry 时按图标名找。缓存解析结果，不每帧调用。
- nowMs 是 system_clock Unix epoch 墙钟毫秒，非 monotonic；跨重启 deadline 可以用，但须接受系统调时影响。formatTime 第二参是 Unix **秒**，不是毫秒。
- copyToClipboard(text,mime) 两个参数都必填且非空；适合秘密显式复制，不能把秘密放到进程 argv、通知或日志。此调查未读取用户剪贴板。

来源：[宿主导出全集](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/scripting/luau_host.cpp#L1758-L1838>)、[超时常量和解析](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/scripting/luau_host.cpp#L60-L65>)、[超时第三参数](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/scripting/luau_host.cpp#L189-L198>)、[进程组终止](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/core/process/process.cpp#L336-L355>)、[结果字段](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/scripting/luau_host.cpp#L2594-L2621>)、[剪贴板](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/scripting/luau_host.cpp#L820-L836>)、[时间](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/scripting/luau_host.cpp#L586-L590>)。

## 7. 翻译、widget、shortcut 最小入口

- 翻译目录是 `translations/`，不是 i18n/；默认 `en.json`，简体中文 `zh-Hans.json`（不是 zh_CN），繁体中文 zh-Hant。
- 宿主先读英语，再读当前语言覆盖；noctalia.tr(key, substitutions?) 用此目录。设置声明用 label_key/description_key，select options 也用 label_key；不能用 label/description 代替。
- [翻译加载源码](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/scripting/plugin_i18n.cpp#L39-L49>)、[语言 tag 规则](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/src/i18n/language_tag.cpp>)、[manifest 参考](<https://github.com/noctalia-dev/noctalia/blob/v5.2.1/docs/user/plugins/development/manifest.mdx>)。

~~~toml
[[widget]]
id = "widget"
entry = "widget.luau"

[[shortcut]]
id = "open"
entry = "shortcut.luau"
~~~

~~~lua
-- widget.luau
function update()
  barWidget.setGlyph("menu-2")
  barWidget.setText("潮汐")
  barWidget.setTooltip("打开潮汐侧栏")
end
function onClick() noctalia.togglePanel("pang/tide-sidebar:panel") end
update()

-- shortcut.luau（另一个entry文件）
shortcut.setLabel("潮汐")
shortcut.setIcon("menu-2")
shortcut.setActive(false)
shortcut.setEnabled(true)
function onClick() noctalia.togglePanel("pang/tide-sidebar:panel") end
~~~

barWidget.render(tree) 也可用，但一旦调用，其树取代内置 glyph/text，之后 setText/setGlyph 不再显示效果。bar 不取键盘，不能放 input/select/scroll；bar 没有 frame tick API。声明入口不等于已经启用或放进用户栏/控制中心。
