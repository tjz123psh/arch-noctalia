# Mobile Validation

Validate real device states with real content on real devices or emulators, not just design files or a single model.

## Device Matrix（设备矩阵，按风险选组合）

按风险选择组合，不必穷举。目标是覆盖会改变布局或行为的真实变量，不是跑遍所有机型。

### 屏幕尺寸与形态

| 类别 | 代表机型 | 检验重点 |
|---|---|---|
| 小屏紧凑 | iPhone SE(第2/3代)、紧凑 Android | 内容溢出、触摸目标拥挤、键盘遮挡 |
| 主流尺寸 | iPhone 15 / Pixel 8 | 基线布局、间距、层级 |
| 大屏 | iPhone 15 Pro Max / 大屏 Android | 单手可达性、拇指热区、留白利用 |
| 平板 | iPad / Android 平板 | 主从分栏、多列、非拉伸放大 |
| 折叠 | Galaxy Fold / Pixel Fold | 折叠态与展开态的重组、折痕避让 |

### 缺口与遮挡

| 类型 | 代表 | 检验重点 |
|---|---|---|
| 刘海 | iPhone 11-14 | 状态区避让、横屏两侧安全区 |
| 灵动岛 | iPhone 14 Pro 及以后 | 顶部内容避让、灵动岛交互不冲突 |
| 挖孔屏 | 多数现代 Android | 状态栏元素避开挖孔 |
| 方正无缺口 | iPhone SE、旧 Android | 无安全区时布局不留多余空隙 |

### 系统条件

- **主题**：浅色、深色、系统强调色 / Dynamic Color（Android 12+ 取壁纸色）。
- **字体**：默认、最大 Dynamic Type(iOS) / 字体缩放(Android)、加粗文本。
- **方向**：竖屏、横屏（若支持）、折叠 / 展开切换。
- **无障碍**：VoiceOver / TalkBack、reduce motion / 关闭动画、增大对比度。
- **输入**：触摸、外接键盘（iPad）、语音输入法、第三方输入法高度差异。

### 网络与生命周期

- 正常、弱网（高延迟 / 丢包）、离线、断网重连。
- 冷启动、热启动、切后台返回、来电 / 通知打断、锁屏解锁。
- 进程被系统回收后恢复、低内存告警、低电量模式。

### 内容极端值

- 空、加载、错误、权限拒绝。
- 超长标题与正文、单词不可断行、数字与货币极值。
- 多语言：CJK 密排、德语长词、RTL（阿拉伯语 / 希伯来语）镜像布局。

### 选择策略

单一功能改动：主流尺寸 + 一个小屏 + 深浅色 + 最大字体即可。
跨页面重设计或发布前：每类各取一个代表，叠加无障碍与弱网 / 生命周期路径。
Choose combinations by risk; cover the variables that actually change layout or behavior rather than every model that exists.

## Safe Areas & Layout

- Content avoids status bar, notch, Dynamic Island, Home Indicator, punch-hole, and rounded corners; use platform inset APIs, not hardcoded values.
- Bottom primary actions not obscured by Home Indicator or system gesture bar; tappable areas don't fall on system back gesture hot zones.
- When keyboard appears, input fields and primary buttons remain visible; content scrolls with keyboard, not hidden behind it.
- No horizontal clipping; long titles, translations, CJK, RTL, and maximum dynamic fonts don't overflow containers or truncate primary actions.
- Lists preserve scroll position and selection state after rotation, background-foreground switch, or font changes.

## Gestures & Touch

- Primary actions fall in thumb zone (bottom 1/3 of screen); one-hand reachable for critical path.
- Touch targets ≥ 44pt(iOS)/48dp(Android), adjacent targets adequately spaced, no accidental taps.
- In-app gestures don't conflict with system edge-back, control center/notification drawer pull-down, or multitasking gestures.
- Swipe actions provide visible alternative entry; long press has feedback, doesn't swallow primary action.
- iOS edge-back, Android system back / predictive back behavior meets expectations, doesn't break navigation stack.

## Accessibility

- VoiceOver(iOS) / TalkBack(Android) walk through main path: every control has readable name and role, order is reasonable.
- Dynamic type / font scaling at maximum: content not lost, not overlapping.
- Contrast ≥ 4.5:1 (body) / 3:1 (large text and UI components); color is not the only information carrier.
- Icon buttons have accessible label; state changes announced to screen reader.
- Respect reduce motion / animations off: transitions degrade to fade or instant switch, no half-finished animations.

## System & Lifecycle

- Permissions requested when needed; on denial, recoverable explanation, no crash, no infinite loop.
- Background-foreground switch, incoming call/notification interruption, lock-unlock: state and unsaved input preserved.
- Deep links, push notification taps, share-open arrive at correct screen with reasonable navigation stack.
- Weak network, timeout, reconnect: clear feedback and retry; no infinite spinner.
- Cold start, warm start, and process-killed recovery: no loss or duplication of user data.

## Performance

- Cold start to first interactive time is reasonable; launch screen not blank for long.
- Scrolling long lists, image feeds, and transitions stable and responsive, no visible frame drops or stutter.
- Animation on low-end devices and under reduce motion doesn't block interaction.
- Memory growth controlled; repeated entry/exit without leaks causing lag or system kill.
- Background tasks have progress, cancel, and error recovery; idle doesn't continuously drain battery.

## Report Format

List device/system version, size, theme, font level, input method, steps, evidence, expected, actual, and residual risk. Every "pass" should correspond to screenshot, screen recording, log, or automated test.

## Pre-Release Testing Checklist

Use this checklist before release:

### Visual
- [ ] All text 11pt or larger
- [ ] Color contrast meets WCAG AA (4.5:1 for text)
- [ ] Touch targets 44pt/48dp minimum
- [ ] No color-only information
- [ ] Works in light and dark mode

### Accessibility
- [ ] All interactive elements have labels
- [ ] Screen reader can access all features
- [ ] Keyboard navigation works (if supported)
- [ ] Dynamic changes announced
- [ ] Works at maximum text size (200% or AX5)

### Performance
- [ ] Lists use FlatList/VirtualizedList
- [ ] Images optimized and lazy loaded
- [ ] Animations use native driver
- [ ] No memory leaks (cleanup in useEffect)
- [ ] Bundle size analyzed

### Platform
- [ ] Follows iOS HIG (iOS)
- [ ] Follows Material Design (Android)
- [ ] Navigation consistent
- [ ] Back button works correctly
- [ ] Safe area insets respected

### Forms
- [ ] Correct keyboard types
- [ ] Labels persist (not just placeholders)
- [ ] Clear error messages
- [ ] Auto-complete attributes set
- [ ] Validation helpful, not blocking
