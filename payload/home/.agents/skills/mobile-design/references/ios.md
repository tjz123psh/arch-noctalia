# iOS Design Reference

Human Interface Guidelines baseline for iOS app UI: navigation, safe areas and inset
model, touch targets, type scale, controls, gestures, motion, launch experience, and
VoiceOver.

## Navigation

| Pattern | iOS Usage | Notes |
|---|---|---|
| **Tab Bar** | 3-5 同级目的地，固定底部 | 超出 5 项后系统折叠为 "More" |
| **Navigation Stack** | 层级内容，左上返回 | 标题居中；大标题在滚动时收起 |
| **Segmented Control** | 同级视图切换 | Pill 形分段，不等同 Tabs |
| **Modal Sheet** | 临时表单、选择 | 下滑关闭；大尺寸 sheet 可推到全屏 |
| **Action Sheet** | 底部滑出选项列表 | 用于破坏性/多项选择确认 |
| **Wizard** | 分步流程 | 与分步指示一致，可返回上一步 |

- **Drawer 不推荐**：侧边抽屉藏起主导航，与 iOS 预期不符；导航项过多时优先重构 IA，而不是塞抽屉。
- **返回**：左上返回按钮 + 左缘滑动返回；两者必须同时可用，且不破坏导航栈。
- **Modal 关闭**：下滑手势（iOS 13+）或导航栏 Cancel / Done；关闭后把焦点交回触发元素。

## Touch Targets

- 最小 **44×44 pt**（所有可交互元素，含图标按钮）。
- 相邻目标间距 ≥ 8pt；破坏性动作与主操作分离。
- 列表行最小高度 44pt；文本字段最小高度 44pt。
- Switch 51×31 pt；Checkbox 22×22 pt（触控区仍需 44pt）。
- 拇指热区为屏幕下 1/3：主要动作放这里，顶部只放低频或危险动作。

## Safe Area and Insets

- 避让刘海、灵动岛（iPhone 14 Pro+）、Home Indicator、圆角，以及横屏时的两侧安全区。
- 用 `safeAreaInsets` / `UILayoutGuide` 等平台 API 计算避让，**不要硬编码**坐标或高度。
- 底部主操作不得被 Home Indicator 或系统手势条遮挡，可点区域不落在系统返回手势热区。
- 键盘弹出时输入框与主按钮保持可见，内容随键盘滚动，不被键盘盖住。
- 无缺口的方正机型（如 iPhone SE）不应留下多余空白。

## Typography

| Style | iOS (pt) | Android 对应 |
|---|---|---|
| Large Title | 34pt Bold | Display Large 57sp |
| Title | 28pt Bold | Headline Large 32sp |
| Headline | 17pt Semibold | Title Large 22sp |
| Body | 17pt Regular | Body Large 16sp |
| Callout | 16pt Regular | Body Medium 14sp |
| Caption | 12pt Regular | Body Small 12sp |
| Footnote | 13pt Regular | Label Medium 12sp |
| Minimum | 11pt | 12sp |

- 字体 **SF Pro / SF Compact**；等宽场景用 SF Mono。
- 正文字号 ≥ 16pt；标签最小 11pt。
- 支持 **Dynamic Type**（`preferredFont` / 文本样式），不要硬编码固定高度与固定字号。
- 最大辅助字号（AX5，约 200%）下布局不得截断、重叠或丢失内容。
- 行高 1.5× 字号（正文），标题 1.2×；行宽 40-60 字符最优、75 上限。
- 不要用全大写排正文（按钮等短标签可用）。

## Controls and Components

| 组件 | iOS 形态 | Android 对照 |
|---|---|---|
| Filled Button | 圆角矩形实色，标题式大小写 | 20dp 圆角 + 阴影 |
| Outlined Button | 边框 + 透明填充 | 1dp 边框、无阴影 |
| Text Button | 无背景无边框 | 无背景无边框 |
| Button 高度 | 最小 44pt | 标准 40dp |
| 返回 | 左上角 | 左上角或硬件/手势返回 |
| 主操作 | 右上角 | FAB（右下）或右上角 |
| 更多选项 | 底部 "More" 或 Action Sheet | 右上溢出菜单 ⋮ |
| List Item | 最小 44pt；头像 40-60pt | 单行 56dp / 双行 72dp |
| Divider | 通栏或内缩 16pt | 通栏或内缩 16dp |
| Card | 细微阴影，圆角 10-12pt | Elevation 1-8dp，圆角 12dp |
| Text Field | 圆角矩形带边框，占位符或浮动标签 | Filled / Outlined，浮动标签为标准 |
| Switch | 51×31 pt，药丸形，开启时着色 | 52×32 dp |
| Dialog | 居中圆角，标题加粗居中 | 居中 elevation，标题左对齐 |
| Dialog 按钮 | 2 个横向、3+ 个纵向；Cancel 左 Confirm 右 | 横向右对齐，Cancel 左 Confirm 右 |
| Dialog 关闭 | 仅按钮 | 按钮或系统返回 |
| Toast / Snackbar | **非原生**（需第三方库） | 底部 Snackbar |

- 组件状态：default / pressed / focused / loading / disabled / error / empty / offline / permission-denied 一个都不能缺。
- 点击反馈为高亮或变暗（Android 为 ripple）；不要给 iOS 控件强加 Android 的涟漪反馈。
- 图标使用 **SF Symbols**，不要混用 Material Symbols。
- 语义色：tint（默认蓝）、label / secondaryLabel / tertiaryLabel、systemBackground / secondarySystemBackground。

## Gestures

| Gesture | iOS | Android |
|---|---|---|
| Back | 左缘滑动 | 系统返回（左右缘）或返回键 |
| Swipe list item | 原生标准（删除 / 标记） | 支持但不普遍 |
| Long press | 上下文菜单（iOS 13+） | 长按选择 / 多选 |
| Pull down | 刷新 | 刷新 |
| Pinch | 缩放 | 缩放 |
| Dismiss modal | 下滑（iOS 13+） | 返回键 |

- 应用内手势不得与系统边缘返回、控制中心 / 通知中心下拉、多任务手势冲突。
- 滑动操作必须提供可见的替代入口；长按要有反馈，且不吞掉主操作。

## Motion

- 默认为**弹簧动画**，带轻微回弹（bounce）；时长约 0.3-0.4s；缓入缓出或弹簧曲线。
- 可中断、可反向：手势驱动的转场要跟随手指，松手后按速度接续。
- 时长基线：Tap 反馈 ≤ 100ms；Toggle 200-300ms；页面转场 300-350ms；长按 500ms 触发。
- 尊重 **Reduce Motion**（`UIAccessibility.isReduceMotionEnabled`）：降级为淡入或瞬时切换，去掉视差与大幅位移，不留半截动画。
- 闪烁内容不得超过每秒 3 次，避免大面积闪烁。

## Launch Experience

1. **Launch Screen** —— 仅静态图，不要放交互内容或动画。
2. **Splash Gate（交互式入口）** —— 全屏品牌展示，点击/上滑触发淡出进入主界面；适用于游戏、创作工具、品牌类应用；需支持键盘触发与交叉淡出。
3. **Onboarding** —— 以收益驱动、可跳过、权限渐进式请求。
4. **Permission Requests** —— 用到时才请求，不在首屏一次性索要全部权限；拒绝后可恢复、有解释、不崩溃。

## Icons and Images

- **App Icon**：1024×1024 px，**不要预先切圆角**（系统处理遮罩）。
- 图片格式用 WebP / AVIF，提供响应式尺寸，显式声明宽高避免布局跳动。
- 长列表用虚拟化渲染，图片懒加载并给占位与错误态。

## Accessibility (VoiceOver)

```swift
element.isAccessibilityElement = true
element.accessibilityLabel = "Add to cart"          // 它是什么
element.accessibilityHint = "Adds item to shopping cart" // 它会做什么
element.accessibilityTraits = .button               // 元素类型
element.accessibilityValue = "2 items"              // 当前值/状态
```

- [ ] 所有可交互元素都有标签，标签简洁准确
- [ ] 标签内**不要**包含元素类型（"按钮"、"图片"）——类型由 traits 表达
- [ ] 复杂交互提供 hint；相关元素逻辑分组
- [ ] 装饰性元素设 `accessibilityElementsHidden`
- [ ] 焦点顺序符合阅读顺序（从上到下、从左到右），自定义用 `accessibilityElements`
- [ ] 新呈现内容获得焦点；关闭模态后焦点回到触发元素
- [ ] 动态变化主动播报：`UIAccessibility.post(notification: .announcement, argument:)`
- [ ] 对比度：正文 ≥ 4.5:1，大字与 UI 组件 ≥ 3:1；颜色不是唯一信息载体
- [ ] 按钮文字与背景满足对比度，禁用态仍可辨认

**iOS 无障碍特性**：Dynamic Type、VoiceOver、Voice Control、Switch Control、Reduce Motion、Reduce Transparency、Increase Contrast、Differentiate Without Color、On/Off Labels、Button Shapes。

**iOS 独有平台能力**：Haptic Touch / 3D Touch、Live Text、Face ID / Touch ID、Dynamic Island 交互、Action Extensions、Widgets、App Clips。

## iOS Common Mistakes

- ❌ 硬编码安全区偏移，遇灵动岛或横屏即裁切。
- ❌ 自造返回按钮替代左缘滑动返回，或返回直接退出应用。
- ❌ 图标按钮没有无障碍标签，VoiceOver 只读出 "button"。
- ❌ 只用占位符当字段标签，输入后标签消失。
- ❌ 固定字号与固定行高，Dynamic Type 拉大后文字截断。
- ❌ 把 Android 的 FAB、涟漪反馈、抽屉导航直接搬到 iOS。
- ❌ 只用颜色表达状态（红=错误，绿=成功），色盲用户无法分辨。
