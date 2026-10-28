# 声明式面板迁移评估（Noctalia 5.4 / plugin_api 42）

> 2026-10-28 实测。结论先行：**值得迁，但不能一次性重写**；先用已经跑通的「窗口」页原型做样板，
> 按 窗口 → 工具 → 便签 的顺序逐页替换，便签页是唯一可能劝退的一页。

## 1. 现状（原生 GTK 前端）

| 项 | 数值 | 来源 |
|---|---|---|
| 常驻进程 | 1 个 `gjs`（前台渲染），另需 `gtk4-layer-shell` 系统包 | `ps -C gjs` |
| 内存 | **219 MiB RSS**（空载，面板未打开） | 同上 |
| CPU | 空载 1.2%，动画时更高 | 同上 |
| 代码量 | JS+CSS 共 2539 行（main 343 / ui 107 / views 1867 / style 206 / transport 16） | `wc -l` |
| 与主题的关系 | 自己写死颜色（`#EFE6CC`、`#78671C`…）+ 自己画层，换主题不跟随 | `native/style.css` |
| 启动链 | Luau 服务 `runStream` 拉 gjs，`LD_PRELOAD=libgtk4-layer-shell.so` 才能画层 | `lib/frontend.luau:90` |

> 2026-10-25 的机制审查里「侧边栏装完起不来」那条 P1，根因就是 `gtk4-layer-shell` 没进包清单——
> 这条依赖链是原生方案的固有成本。

## 2. 声明式面板能做到什么

5.4 的 `[[panel]]` 用 `ui.*` 树描述界面，不需要额外进程：

- **一比一可替换**：`ui.column/row`（gap/padding/align/justify/fill/radius/border）、`ui.scroll`（滚动、
  stickToBottom、revealKey）、`ui.label`（字号/字重/颜色/行数）、`ui.glyph`、`ui.button`
  （variant/selected/onClick/onRightClick/tooltip）、`ui.toggle`、`ui.slider`、`ui.select`、
  `ui.input`（单行/多行、submitOnEnter）、`ui.progress`、`ui.separator`、`ui.spacer`、`ui.markdown`、
  `ui.image`（本地文件）、`ui.graph`（折线/面积）、拖放、键盘焦点、右键菜单。
- **拿不到**：CSS 阴影（`box-shadow`）、渐变、任意自绘（波分色块、装饰曲线）、原生 TextView 的
  撤销栈与 Pango 细节、逐像素的圆角/描边对齐。
- **高度**：`height = "content"` + `max_height`（42 起），面板随内容伸缩并带动画；超出部分交给
  `ui.scroll`。
- **系统集成**：`noctalia.osd.show()` 可弹系统 OSD（本次已接入倒计时/热点）。

## 3. 逐页可行性

| 页面 | 原生实现 | 声明式可行性 | 说明 |
|---|---|---|---|
| 窗口 | `views/system.js` 548 行 | **已验证** | `panel-windows.luau` 169 行复刻完成（列表/焦点/切换/关闭/刷新），真机 420×216 渲染正常 |
| 工具（计算器/倒计时/秒表/热点） | `views/tools.js` 825 行 | 高 | 全是按钮/输入框/进度条，唯一要改的是把「按下瞬间的波浪动画」换成 `ui.progress` 或去掉 |
| 便签 | `views/notes.js` 494 行 | **中低** | `ui.input(multiline)` 能输入，但没有原生 TextView 的撤销栈、自动增高和 Pango 排版；数据层（`notes-*.json`、revision 校验、64 KiB 上限）可原样复用 |
| 外观（圆角卡片/拼接色块/投影） | `style.css` 206 行 | 低 | 声明式只有 fill/radius/border；投影和拼接分色要么放弃，要么用 `ui.image` 贴预渲染图 |

## 4. 成本对比

| | 原生 GTK（现状） | 声明式面板 |
|---|---|---|
| 进程 | +1 个 gjs 常驻 | 0（挂在 shell 里） |
| 内存 | +219 MiB | 与 shell 共享，几乎为 0 |
| 依赖 | +gtk4-layer-shell（曾导致 P1） | 无 |
| 主题联动 | 自己写死颜色 | 自动跟随主题/换壁纸 |
| 外观上限 | 任意自绘 | 无阴影/渐变 |
| 代码量 | 2539 行 JS+CSS | 原型 169 行/页，按 3 页估算 500–700 行 Luau |

## 5. 建议路线（按页替换，不求一次到位）

1. **窗口页**（已完成原型）：与原生版并存，用 `panel-open pang/tide-sidebar:windows-proto` 对比观感。
2. **工具页**：下一个试点，把倒计时/秒表/热点搬进声明式面板；计算器保留 `lib/calculator.luau` 不动。
3. **便签页**：最后做，且先只做「列表 + 只读预览」，编辑仍回原生；等 `ui.input` 的多行体验能接受再谈替换。
4. **收尾**：三页都认可后，删掉 `native/`、`lib/frontend.luau` 与 `gtk4-layer-shell` 依赖，
   `plugin_api` 保持 42，插件体积和内存一起下降。

**劝退条件**（任一成立就停在原生方案）：便签编辑体验明显退化；`ui.scroll` 在 40+ 条便签时卡顿；
外观差距让日常使用不舒服。

## 6. 复现方式

```bash
noctalia msg panel-open pang/tide-sidebar:windows-proto   # 打开原型
noctalia msg panel-close                                   # 关闭
python tests/run_all.py                                    # 插件回归（含 lint）
```

截图量测（用于核对面板尺寸）：`grim` 抓图后 `magick compare -metric AE` 或
`magick ... -connected-components` 取变化区域的包围盒。
