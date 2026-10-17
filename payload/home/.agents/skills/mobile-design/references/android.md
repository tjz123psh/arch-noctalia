# Android Design Reference

Material Design 3 要点，外加 Material 3 Expressive 设计方向（Android 16+）。

Android 专属设计模式与惯例的综合参考，基于 Google Material Design 规范。

## Material Design 原则

### 材质隐喻

**物理属性：**
- 表面与阴影建立层级
- 动效传达含义
- Elevation 定义重要性
- 光源方向一致（来自顶部）

**材质特征：**
- 有厚度（默认 1dp）
- 会投射阴影
- 不能穿透其他材质
- 可改变尺寸与形状

### 大胆、图形化、有意图

**排版：**
- Roboto 字族
- 层级清晰
- 颜色与留白有明确意图
- 基于栅格的布局

**颜色：**
- 鲜明、饱和的色彩
- Primary 与 Secondary 调色板
- 颜色使用有含义
- 对比度充足

### 动效传达含义

**响应式：**
- 用户发起的动作要感觉即时
- 视觉反馈确认输入
- 平滑的 60fps 动画

**自然：**
- ease-in/ease-out 曲线
- 符合真实物理
- 编排过的转场

**有意识：**
- 引导焦点与注意力
- 保持连续性
- 按层级排序的时间节奏

## 导航模式

### 底部导航

**使用时机：**
- 3-5 个顶级目的地
- 各目的地重要性相当
- 需要频繁切换

**规范：**
- 图标配文字标签
- 选中态清晰可辨
- 固定位置（始终可见）
- 一次点击即可切换
- 不要用于有先后顺序的任务

**实现：**
```kotlin
BottomNavigationView(
    modifier = Modifier.fillMaxWidth(),
    containerColor = MaterialTheme.colorScheme.surface
)
```

### 导航抽屉

**使用时机：**
- 5 个以上顶级目的地
- 导航频率较低
- 层级结构

**类型：**
- **Standard（标准）：** 临时出现（手机）
- **Modal（模态）：** 阻断与内容的交互
- **Permanent（常驻）：** 始终可见（平板 / 桌面）

**规范：**
- 相关目的地分组
- 高亮当前所在目的地
- 包含带应用品牌的头部
- 模态抽屉选中条目后关闭

### Top App Bar

**组成元素：**
- 导航图标（左）：返回或菜单
- 标题：页面标题或应用名
- 动作项（右）：0-3 个图标
- 溢出菜单：更多动作

**变体：**
- **Small：** 标准高度（手机 56dp、平板 64dp）
- **Medium：** 带副标题或搜索
- **Large：** 醒目标题，滚动时收起

**滚动行为：**
- Pin：保持可见
- Enter Always：向上滚动立即显示
- Scroll：随内容隐藏 / 显示
- Collapse：大标题收起为小标题

## 组件规范

### Floating Action Button (FAB)

**用途：**
- 页面上的主操作
- 最常见或最重要的任务
- 每屏一个

**位置：**
- 右下角：距边缘 16dp
- 位于底部导航之上
- 各屏位置保持一致

**尺寸：**
- 默认：直径 56dp
- Mini：直径 40dp
- Extended：宽度可变，带文字

**最佳实践：**
- 用于建设性动作（创建、撰写、添加）
- 避免用于破坏性动作
- 不要用于导航
- 需要时可随滚动隐藏

### 卡片

**用途：**
- 归组相关内容
- 进入详细信息的入口
- 呈现多种类型的内容

**构成：**
- 容器（带 elevation 的表面）
- 可选头部
- 内容区
- 可选动作

**Elevation：**
- 静止：1dp
- 浮起（hover）：8dp
- 最大：24dp

**类型：**
- **Elevated：** 带阴影（默认）
- **Filled：** 着色表面、无阴影
- **Outlined：** 带边框、无阴影

### 按钮

**按强调程度分类：**

**Filled Button（高强调）：**
- 主操作
- 视觉冲击最强
- 每屏克制使用

**Outlined Button（中强调）：**
- 次要操作
- 弱于 filled
- 强于 text

**Text Button（低强调）：**
- 三级操作
- 视觉重量最轻
- 与内容同排

**图标按钮：**
- 紧凑动作
- 工具栏与 App Bar
- 触摸目标 48dp

**尺寸：**
- 高度：最小 36-40dp
- 触摸目标：最小 48dp
- 水平内边距：16dp

## 排版

### Roboto 字族

**字重：**
- Light (300)
- Regular (400)
- Medium (500)
- Bold (700)

**变体：**
- Roboto：正文、UI
- Roboto Condensed：紧凑布局
- Roboto Mono：代码、表格式数据

### 字号体系

Material Design 3 字号体系：

```
Display Large:   57sp / Roboto Regular
Display Medium:  45sp / Roboto Regular
Display Small:   36sp / Roboto Regular

Headline Large:  32sp / Roboto Regular
Headline Medium: 28sp / Roboto Regular
Headline Small:  24sp / Roboto Regular

Title Large:     22sp / Roboto Medium
Title Medium:    16sp / Roboto Medium
Title Small:     14sp / Roboto Medium

Body Large:      16sp / Roboto Regular
Body Medium:     14sp / Roboto Regular
Body Small:      12sp / Roboto Regular

Label Large:     14sp / Roboto Medium
Label Medium:    12sp / Roboto Medium
Label Small:     11sp / Roboto Medium
```

### 最佳实践

**行长：**
- 最优：40-60 个字符
- 上限：75 个字符
- 窄栏更易读

**行高：**
- 正文：字号的 1.5×
- 标题：字号的 1.2×
- 让文字有呼吸感

**对齐：**
- LTR 语言左对齐
- RTL 语言右对齐
- 避免两端对齐（字间距不均）

## 色彩体系

### Material You（动态取色）

**色彩角色：**
- **Primary：** 品牌色、主要动作
- **Secondary：** 强调色、次要动作
- **Tertiary：** 突出显示、特殊元素
- **Error：** 错误与警告
- **Surface：** 背景与容器
- **Outline：** 边框与分隔线

**色彩变体：**
- Primary、On Primary
- Primary Container、On Primary Container
- （Secondary、Tertiary、Error 遵循同一模式）

### 主题化

**浅色主题：**
```kotlin
lightColorScheme(
    primary = Color(0xFF6750A4),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFEADDFF),
    onPrimaryContainer = Color(0xFF21005D),
    // ... more colors
)
```

**深色主题：**
```kotlin
darkColorScheme(
    primary = Color(0xFFD0BCFF),
    onPrimary = Color(0xFF381E72),
    primaryContainer = Color(0xFF4F378B),
    onPrimaryContainer = Color(0xFFEADDFF),
    // ... more colors
)
```

### 对比度要求

**文本对比度（WCAG AA）：**
- 大字（24sp+）：最小 3:1
- 小字：最小 4.5:1

**组件对比度：**
- UI 元素：对背景 3:1
- 边框与分隔线：最小 3:1

## 布局与间距

### 栅格系统

**列数：**
- 手机：4 列
- 平板：8 列
- 桌面：12 列

**页边距：**
- 手机：16dp
- 平板：24dp
- 桌面：24dp 以上

**沟槽（Gutter）：**
- 手机：16dp
- 平板：24dp
- 桌面：24dp

### 间距单位

**8dp 栅格：**
- 所有间距取 8dp 的倍数
- 元素对齐栅格
- 图标对齐 4dp 栅格

**常用间距：**
- Extra Small：4dp
- Small：8dp
- Medium：16dp
- Large：24dp
- Extra Large：32dp

### 触摸目标

**最小尺寸：**
- 触摸目标：48×48dp
- 图标按钮：图标 40dp、触摸区 48dp
- Checkbox / Radio：40dp

**间距：**
- 触摸目标之间：最小 8dp
- 关键动作：12dp 以上间距

## 动效与动画

### 时长

**短（100-200ms）：**
- 小幅位移
- 淡入淡出与简单转场
- 图标切换

**中（200-300ms）：**
- 页面转场
- 卡片展开
- 中等幅度位移

**长（300-500ms）：**
- 大幅变换
- 全屏转场
- 复杂编排

### 缓动曲线

**Standard Easing（减速）：**
```
cubic-bezier(0.4, 0.0, 0.2, 1)
```
- 元素进入屏幕
- 表面展开
- 大多数转场

**Emphasized Easing：**
```
cubic-bezier(0.2, 0.0, 0, 1)
```
- 重要入场
- Hero 转场
- 富有表现力的时刻

**Deceleration（减速）：**
```
cubic-bezier(0.0, 0.0, 0.2, 1)
```
- 元素退出屏幕
- 关闭对话框

**Acceleration（加速）：**
```
cubic-bezier(0.4, 0.0, 1, 1)
```
- 元素永久离开屏幕

### 转场

**Container Transform：**
- 页面之间无缝连接
- 元素展开填满屏幕
- 保持视觉连续性

**Shared Axis：**
- 表达页面之间的关系
- 空间或导航关系
- X、Y 或 Z 轴

**Fade Through：**
- 无关系的页面之间
- 简单交叉淡入
- 中途短暂停顿

**Fade：**
- 小组件的出现 / 消失
- 简单、不打扰

## 无障碍

### 读屏软件（TalkBack）

**内容描述：**
```kotlin
modifier = Modifier.semantics {
    contentDescription = "Add to cart"
    role = Role.Button
}
```

**最佳实践：**
- 描述元素是什么，而不是长什么样
- 包含状态信息（「已选中」）
- 播报动态内容变化
- 归组相关元素

### 触摸目标尺寸

**最小尺寸：**
- 标准：48×48dp
- 紧凑布局：36×36dp（谨慎使用）
- 间距：目标之间 8dp

**测试：**
- 使用大字体设置
- 开启 TalkBack 测试
- 确认触摸目标不重叠

### 颜色对比度

**Material Design 标准：**
- 主文本：浅色下 87% 不透明，深色下 100%
- 次要文本：浅色下 60% 不透明，深色下 70%
- 禁用文本：浅色下 38% 不透明，深色下 50%

**测试工具：**
- Android Accessibility Scanner
- Material Theme Builder 对比度检查器
- WCAG 对比度计算器

## 性能

### 减少 Overdraw

**优化图层：**
- 去掉不必要的背景
- 谨慎使用 clipToPadding
- 减少视图层级深度
- 用 ConstraintLayout 压平层级

**调试 Overdraw：**
- 设置 → 开发者选项 → 调试 GPU 过度绘制
- 目标：大部分区域为蓝色或绿色
- 避免红色（4× overdraw）

### 布局性能

**ConstraintLayout 的优势：**
- 扁平的视图层级
- 复杂布局性能好
- 支持响应式设计
- Chain 与 Barrier 特性

**RecyclerView 优化：**
```kotlin
// Set fixed size if possible
recyclerView.setHasFixedSize(true)

// Prefetch items
layoutManager.isItemPrefetchEnabled = true

// Recycle views aggressively
recyclerView.setRecycledViewPool(sharedPool)
```

### 图片加载

**最佳实践：**
- 用 Coil 或 Glide 做异步加载
- 加载合适的尺寸
- 积极缓存
- 加载中给占位
- 失败给错误态

## Material 组件

### Bottom Sheet

**类型：**
- **Standard：** 非模态，与内容共存
- **Modal：** 阻断内容，必须关闭

**状态：**
- 收起：露出 peek 高度
- 半展开：中间状态
- 展开：内容完整可见
- 隐藏：完全移出屏幕

### Chip

**类型：**
- **Assist：** 辅助完成任务（建议）
- **Filter：** 筛选内容（有选中 / 未选中态）
- **Input：** 表示复杂信息（标签）
- **Suggestion：** 动态建议

### 对话框

**类型：**
- **Alert：** 重要决策或信息
- **Simple：** 选项列表
- **Confirmation：** 确认 / 取消选择
- **Full-screen：** 复杂内容（手机）

**最佳实践：**
- 标题：清晰简洁的问题或陈述
- 内容：提供上下文，而不是重复标题
- 动作：1-2 个按钮（Dismiss / Confirm）
- 可关闭：用户可用返回键取消

### Snackbar

**用途：**
- 关于应用过程的简短消息
- 可选单个动作
- 4-10 秒后自动消失

**位置：**
- 屏幕底部（手机）
- 存在 FAB 时位于其上方
- 左下角（桌面）

**规范：**
- 一行文字（手机）
- 不超过两行（平板）
- 动作文字：全大写、简洁
- 不要遮挡重要 UI

## 测试与工具

### Layout Inspector

**功能：**
- 实时布局层级
- 视图属性
- 约束可视化
- 性能剖析

### Material Design 规范

**资源：**
- [Material Design 3](https://m3.material.io/)
- [Material Components](https://material.io/components)
- [Material Theme Builder](https://material-foundation.github.io/material-theme-builder/)

### 测试工具

- **Accessibility Scanner：** 自动化无障碍测试
- **Layout Validation：** 组件状态测试
- **Espresso：** UI 测试框架
- **Compose Preview：** 组件快速预览

### 设计工具

- Figma Material 3 Design Kit
- Sketch Material Design 资源
- Adobe XD Material 插件
- Android Studio Layout Editor

## Material 3 Expressive 方向

目标平台为 **Android 16+** 时用 Material 3 Expressive。更早的目标版本回退到标准 Material 3 模式。

### 设计思考

生成任何 UI 之前，先确定明确的设计方向：
- **Purpose（目的）**：这个界面要完成什么？用户到达这里时是什么情绪状态？
- **Personality（性格）**：选一个方向——鲜明 / 有活力、冷静 / 专注、温暖 / 亲和、大胆 / 编辑感、极简 / 精确、俏皮 / 弹性、工业 / 实用。M3 Expressive 提供的人格化工具远超旧版 Material，要用起来。
- **Hero moments（主角时刻）**：找出每屏值得复合表达的 1-2 个元素——同时使用形状变换 + 弹簧动画 + 强调字体 + 丰富色彩。其余部分保持克制。
- **Differentiation（辨识度）**：是什么让这个应用看起来像「被设计过」，而不是 Material Components 目录的演示？哪个交互会被用户记住？

**关键**：M3 Expressive 不是「到处加回弹」。它是一套有研究支撑的体系，六种设计手法——形状多样性、丰富色彩、字体强调、策略性容器、流体弹簧动效、组件灵活性——共同作用。目标是自然、有物理感的手感——像从书架上抽出一本书时旁边的书微微滑动，或把一条通知甩开时收到令人满意的触觉震动。专业应用把这些手法有选择地用在主角时刻；业余应用把它们无差别铺满全屏。

### M3 Expressive 设计准则

重点：

- **动效——用弹簧，不用 Tween**：每个动画都用弹簧物理，而不是 `tween(durationMillis)`。弹簧能从当前速度重新定向，无缝处理打断。使用 `MaterialTheme.motionScheme` 的 token——绝不硬编码弹簧参数。分两类：**Spatial specs**（回弹，阻尼约 0.6）用于位置、尺寸、旋转、形状。**Effects specs**（临界阻尼，damping = 1.0）用于颜色与不透明度。绝不把 spatial 弹簧用在颜色 / 不透明度上——alpha 冲过 100% 看起来就是坏了。
- **动效速度**：速度 token 与元素尺寸匹配。`fastSpatialSpec` 用于小组件（switch、按钮）。`defaultSpatialSpec` 用于半屏元素（sheet、抽屉）。`slowSpatialSpec` 用于全屏转场。开关上用慢弹簧会显得迟钝，页面转场用快弹簧会显得慌乱。
- **形状——拥抱张力**：M3 Expressive 在基础矩形之外新增 35 种形状——Pill、Diamond、Cookie9Sided、SoftBurst、Clover4Leaf、Heart 等。核心原则是有意的对比：把尖锐有角的形态与柔和圆润的形态混用。Chip 用胶囊、FAB 用圆角方块、模态用更大圆角。处处统一形状 = 模板应用。状态切换用形状变换（在 `RoundedPolygon` 实例间用 `Morph` 类），而不是简单交叉淡入。
- **色彩——用满 48 个角色**：扩展后的 `ColorScheme` 有 48 个具名角色，要用起来。Primary 用于关键动作，secondary 与 tertiary 用于支撑层级，12 个固定强调色用于在深浅色主题下必须完全一致的元素。5 级 surface 容器（`surfaceContainerLowest` 到 `surfaceContainerHighest`）替代基于不透明度的 elevation——用它们表达分层深度。所有东西都默认 primary-on-white 是浪费这套系统，而它能带来快 4 倍的元素识别速度。
- **排版——30 种样式与强调变体**：字号体系翻倍到 30 种样式。新增的 15 个 `*Emphasized` 变体（更高字重）用于「编辑感时刻」——标题、CTA、关键信息。全程统一 `bodyMedium` 会做出扁平的布局。主角内容用 `headlineLargeEmphasized`，支撑文本配 `bodyLarge`。强调与基线之间的对比创造视觉节奏。
- **新组件——替换已废弃模式**：`SegmentedButton` → `ButtonGroup`（相连按钮 + 溢出）。`BottomAppBar` → Docked / Floating Toolbar（集成 FAB）。堆叠小 FAB → `FloatingActionButtonMenu`（用 `ToggleFloatingActionButton` 展开）。另有：`SplitButtonLayout` 用于主次操作，`LoadingIndicator` 用形状变换多边形替代圆形 spinner。
- **FAB**：现在默认圆角方形，不再是圆形。有新尺寸配置可用。FAB 是人格锚点——自定义它的形状与动画。
- **导航**：Navigation Bar / Rail 上的胶囊形选中指示器。选中标签用 `secondary` 色，不再是 `onSurface`。进度指示器支持波浪形状选项与可配置轨道高度。
- **动态取色**：Android 12+ 上通过 `dynamicLightColorScheme` / `dynamicDarkColorScheme` 尊重 Material You 从壁纸提取的调色板。为旧设备提供符合品牌的静态回退。用 `Material Color Utilities` 把品牌强调色与用户的动态调色板调和。
- **Edge-to-Edge 与 Predictive Back**：Android 16 强制 edge-to-edge——内容绘制到系统栏之下，需要正确处理 `WindowInsets`。预测性返回手势会在用户滑动时预览目标页面——应用内转场必须与系统动画协调，而不是对抗。
- **自适应布局**：使用窗口尺寸类——compact（<600dp）用底部导航 + 单栏，medium（600–840dp）用导航栏 + 列表 / 详情，expanded（≥840dp）用常驻抽屉 + 多栏。动效随屏幕缩放：手机上更快更紧凑，平板上稍慢更舒展。

### 无障碍不可妥协

- 正文对比度 **4.5:1**，大字 **3:1**——用语义角色配对强制执行
- 尊重「移除动画」——当 `ANIMATOR_DURATION_SCALE` 为 0 时，回退到 `snap()` 或简单淡入；从 Expressive 方案切到 Standard
- 响应 Android 14 的 `UiModeManager.getContrast()`，适配高对比度主题
- 触摸目标最小 **48×48dp**，不受视觉形状变换影响
- 确保所有弹簧动画可被打断——这是弹簧体系的核心无障碍收益

### 绝不要做这些（Android 的「AI 味」标志）

- 可被打断的动效用 `tween(300)` 或任何硬编码 tween——这是头号反模式；弹簧能平滑重新定向，tween 会突兀跳变
- 把 spatial 弹簧（回弹）用在颜色或不透明度上——alpha 冲过 100% 或颜色闪到目标值之外会立刻被察觉
- 开关上用 `slowSpatialSpec`，或全屏转场用 `fastSpatialSpec`——速度要与元素尺寸匹配
- 每个元素都用统一的圆角矩形——35 种形状的意义就在于多样与对比
- 只用 `primary` 而忽略 secondary、tertiary 与全部 12 个固定强调角色
- 排版扁平、到处 `bodyMedium`——缺少强调变体会抹掉让 Expressive 与众不同的编辑质感
- 沿用稳定的 `1.4.0` 而不检查 Expressive API 是否可用——新组件需要 alpha 通道
- 固定方向布局——Android 16 在 ≥600dp 时忽略方向限制；自适应布局是强制要求
- 圆形 FAB——M3 Expressive 默认圆角方形
- 继续用旧的 `SegmentedButton` 或 `BottomAppBar`，而其替代者已存在
- 每个列表都用一模一样的卡片布局——按内容类型改变容器、形状与强调
- 忽略 `MaterialTheme.motionScheme`，把弹簧参数硬编码在调用处

### 专业与模板的分界

专业的 M3 Expressive 应用在主角时刻复合使用多种手法：详情页转场同时用 `Morph` 变换形状、用 effects 弹簧过渡颜色、用 spatial 弹簧缩放元素，并用 `headlineLargeEmphasized` 渲染标题。这种关键位置的复合表达——加上其他地方的克制——才是「设计过的应用」与「默认样式」的分界。

专业工作的可观察标志：按品牌性格调校过的自定义 `MotionScheme`、超出基础矩形的 `MaterialShapes` 策略性使用、贯穿视觉层级的完整 48 角色色彩体系、用 `ButtonGroup` 与 `FloatingActionButtonMenu` 替换废弃组件，以及状态切换用形状变换而不是简单的可见性开关。

收益最高的采纳顺序：先动效方案（改动收益最大、成本最低），再形状多样性，再扩展色彩，最后新组件。每个弹簧 token、形状变换与强调文本样式都是一个杠杆——手艺在于知道该在何时拉动哪个杠杆。
