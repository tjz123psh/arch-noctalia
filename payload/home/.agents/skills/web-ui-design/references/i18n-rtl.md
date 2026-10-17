# i18n 与 RTL

多语言不是把字符串抽出来翻译，而是让布局、方向、数字和日期在任何 locale 下都不破。默认界面会被更长的翻译撑开、被 RTL 语言镜像、被本地数字格式改变宽度——设计阶段就要留余地，而不是翻译回来再补。本文件以 Web 为主，末尾给出其他平台落点。

## 文本扩展

英文短标签翻成其他语言普遍变长。按最坏情况留空间，不要按英文原文卡死宽度：

| 英文原文长度 | 其他语言扩展率（预留） |
|---|---|
| ≤10 字符（按钮、标签） | +100%~200% |
| 11-20 字符 | +80%~100% |
| 21-50 字符 | +60%~80% |
| >50 字符（正文段落） | +30%~40% |

- 德语、芬兰语最易超长；CJK 更短但字符更高，行高要够
- 按钮、标签、导航项用弹性宽度，不硬编码 px；允许换行或截断加 tooltip，不允许挤压相邻元素
- 图标 + 文字的组合按文字侧可增长设计，图标不跟着拉伸
- 不要把文本嵌进图片（无法翻译且伤无障碍）

## RTL 镜像

RTL（阿拉伯语、希伯来语、波斯语、乌尔都语）不是把文字右对齐，而是整个界面沿垂直轴镜像。

**该镜像**：整体布局方向、阅读顺序、导航排列、返回/前进图标、进度方向、列表缩进、抽屉滑出侧、文本对齐。

**不该镜像**：媒体控件（播放/暂停/快进的物理约定）、时钟、大多数品牌 logo、电话号码、代码块、含 LTR 内嵌的图表数据、音量/亮度等物理量滑块（视产品约定）。

**判据**：图标表达"方向/顺序"就镜像（箭头、返回、下一步）；表达"物体/概念"就不镜像（放大镜、相机、播放三角）。搞不准时看该语言的原生 App 怎么做。

## 逻辑属性（首选实现手段）

用逻辑方向属性替代物理左右，一套代码自动适配 LTR/RTL：

- CSS：`margin-inline-start` 代替 `margin-left`，另用 `padding-inline`、`inset-inline`、`text-align: start`、`border-start-start-radius`；容器设 `dir="rtl"` 或用 `:dir()` 驱动
- 只有真正的物理固定（如媒体时间轴）才用物理左右
- 自查：全局搜索 `left`/`right` 残留，凡表达方向语义的都改逻辑属性

## 双向文本（bidi）

LTR 与 RTL 混排时（阿拉伯语句子里嵌英文品牌名、RTL 界面显示 LTR 用户名/URL/数字）：

- 用 Unicode 双向隔离（`\u2068`…`\u2069`）或 CSS `unicode-bidi: isolate` 包裹被嵌片段，防止标点跳到错误一侧
- 用户生成内容方向未知时设 `dir="auto"`，由首个强方向字符决定
- 输入框、搜索框在 RTL locale 下光标与占位符起始位置要正确

## locale 数据格式

同一份数据在不同 locale 下宽度和写法都变，别用字符串拼接：

- **数字**：千分位、小数点符号，阿拉伯语用东阿拉伯数字（٠١٢٣）。用 `Intl.NumberFormat`
- **货币**：符号位置、间距、小数位随 locale，不硬编码 `$`
- **日期时间**：顺序（年月日）、分隔符、12/24 小时、月份名长度差异大；用 `Intl.DateTimeFormat`，不手拼
- **复数**：不是"1 item / N items"两分。用 ICU MessageFormat / `Intl.PluralRules`（阿拉伯语 6 种复数形式，俄语 3 种）
- **排序、大小写、姓名顺序**（姓在前/名在前）也随 locale

## 伪本地化验证

正式翻译到位前，用伪本地化提前暴露问题——把英文替换为加长、加重音、加边界标记的变体（如 `[!!! Ëdït Prófîlé !!!]`）：

- 立刻暴露截断、溢出、硬编码字符串（没被替换的就是漏抽的）
- 配一个强制 RTL 的伪 locale，暴露未镜像的布局和物理左右残留
- 在最长语言 + RTL 两个极端下截图核对，纳入浏览器验收检查项

生成伪本地化文本用 `~/.agents/skills/_shared/scripts/pseudoloc.py`（零依赖），不要手编：

```bash
~/.agents/skills/_shared/scripts/pseudoloc.py "Edit Profile"              # accent + rtl 两版
~/.agents/skills/_shared/scripts/pseudoloc.py --mode accent en.json --json   # 只转 JSON 叶子值，保留 key
cat strings.txt | ~/.agents/skills/_shared/scripts/pseudoloc.py --mode rtl   # 逐行强制 RTL
```

accent 版按扩展率表自动加长并加 `[!!! … !!!]` 边界标记；rtl 版用 Unicode 隔离符包裹强制右到左；两版都保留原结构，可直接灌进界面截图核对。

## 自检

- 最长语言（德语/芬兰语）下按钮、导航、标签是否溢出或截断？
- 强制 RTL 下布局是否整体镜像，方向性图标是否跟着镜像，物体类图标是否保持不变？
- 是否还有物理 `left`/`right` 残留而非逻辑属性？
- 数字、货币、日期、复数是否走 locale 格式化 API 而非字符串拼接？
- 伪本地化里有没有没被替换的硬编码字符串？
- 双向混排处标点和数字是否落在正确一侧？
- 输入框在 RTL locale 下光标与占位符起始侧是否正确？

## 其他平台落点

| 平台 | i18n / RTL 主要手段 |
|---|---|
| Web | CSS 逻辑属性、`dir`、`lang`、`Intl.*`、ICU MessageFormat |
| Android | `start`/`end` 资源（`paddingStart`、`layout_marginEnd`）、`supportsRtl="true"`、`values-<lang>`、ICU |
| 桌面 GTK/Qt | 框架的 RTL 感知布局容器，不用绝对左右定位；gettext / Qt Linguist；locale 感知格式化 |
| TUI | 终端 RTL 支持有限，优先保证文本扩展不破网格；bidi 谨慎处理 |

非 Web 平台的界面设计不在本 skill 范围内（见 SKILL.md 跨端边界），上表只用于判断交付面边界与给出落点。
