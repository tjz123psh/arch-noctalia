# Mobile Accessibility Reference

按 WCAG 2.1 AA 标准与各平台最佳实践实现移动端无障碍的综合指南。

## 视觉无障碍

### 颜色对比度

**WCAG 要求：**
- [ ] 正文（< 18pt）：对比度最低 4.5:1
- [ ] 大字（≥ 18pt 或 ≥ 14pt 加粗）：对比度最低 3:1
- [ ] UI 组件与图形：对比度最低 3:1
- [ ] 焦点指示器：对背景对比度 3:1

**测试工具：**
- WebAIM Contrast Checker
- Stark（Figma / Sketch 插件）
- iOS Accessibility Inspector
- Android Accessibility Scanner

**常见问题：**
- 白底上的灰字（经常不达标）
- 文本字段里过浅的占位符
- 禁用态按钮文字过浅
- 次要操作的对比度不足

### 颜色使用

**不要只靠颜色传达信息：**
- [ ] 颜色编码的信息要有图标伴随
- [ ] 用图案或形状区分元素
- [ ] 所有状态都有文字标签
- [ ] 错误 / 成功给多重视觉线索

**示例：**
- ✅ 绿色对勾 + 「成功」文字
- ❌ 只用绿色背景表示成功
- ✅ 红色边框 + 错误图标 + 错误文字
- ❌ 只用红字表示错误

### 色盲支持

**需要考虑的类型：**
- 绿色盲（红绿，最常见）
- 红色盲（红绿）
- 蓝色盲（蓝黄）
- 全色盲

**最佳实践：**
- [ ] 用色盲模拟器测试设计
- [ ] 颜色之外叠加图案（图表、图形）
- [ ] 避免只用红绿作区分
- [ ] 确保信息不依赖颜色也能获取

**测试：**
- Color Oracle（macOS、Windows、Linux）
- Sim Daltonism（macOS）
- Chrome DevTools 视觉缺陷模拟

## 排版与可读性

### 字号

**最小尺寸：**
- [ ] 正文：最小 16sp/pt（绝对下限 14sp）
- [ ] 标签与说明文字：最小 11pt
- [ ] 触摸目标的标签：最小 14sp 才易读

**Dynamic Type 支持：**
- [ ] iOS：支持 Dynamic Type（`preferredFont`）
- [ ] Android：支持字体缩放（sp 单位）
- [ ] 在最大的无障碍字号档位（AX5、200%）下测试
- [ ] 布局能自适应而不截断
- [ ] 文字不出现横向滚动

### 行长与间距

**最佳可读性：**
- [ ] 行长：40-60 字符最优，75 为上限
- [ ] 行高：正文取字号的 1.5×
- [ ] 段落间距：清晰的视觉分隔
- [ ] 字间距：避免过紧

### 字重与字形

**可读性：**
- [ ] 小字用足够的字重
- [ ] 正文避免全大写（更难读）
- [ ] 强调靠加粗 / 中等字重，而不只靠字号
- [ ] 大段文字避免斜体

## 触摸目标与控件

### 最小尺寸

**平台要求：**
- [ ] iOS：所有可交互元素最小 44×44 pt
- [ ] Android：所有触摸目标最小 48×48 dp
- [ ] 目标之间间距：最小 8dp/pt
- [ ] 关键动作加大尺寸（56dp FAB）

**测试：**
- [ ] 用手指测试，不用鼠标 / 触控笔
- [ ] 在真机而非模拟器上验证
- [ ] 测试单手使用
- [ ] 考虑大屏上的拇指热区

### 间距与布局

**防误触：**
- [ ] 相邻按钮之间有足够间距
- [ ] 破坏性动作与主操作分开
- [ ] 不可逆操作需要确认
- [ ] 禁用态视觉上明确可辨

**边界情况：**
- [ ] 列表项操作有足够的触摸区域
- [ ] 滑动操作可发现且容错
- [ ] 开关足够大（最小 51×31 pt）
- [ ] Checkbox / Radio 最小 40×40 dp

## 读屏支持

### iOS VoiceOver

**元素无障碍属性：**
```swift
// Set accessibility properties
element.isAccessibilityElement = true
element.accessibilityLabel = "Add to cart" // What it is
element.accessibilityHint = "Adds item to shopping cart" // What it does
element.accessibilityTraits = .button // Type of element
element.accessibilityValue = "2 items" // Current value/state
```

**检查清单：**
- [ ] 所有可交互元素都有标签
- [ ] 标签简洁且描述准确
- [ ] 标签里不要包含元素类型（「按钮」「图片」）
- [ ] 用 traits 表达元素类型
- [ ] 复杂交互提供 hint
- [ ] 相关元素按逻辑分组
- [ ] 装饰性元素设置 `accessibilityElementsHidden`

### Android TalkBack

**内容描述：**
```kotlin
// Jetpack Compose
modifier = Modifier.semantics {
    contentDescription = "Add to cart"
    stateDescription = "2 items in cart"
    role = Role.Button
}

// XML
android:contentDescription="Add to cart"
android:importantForAccessibility="yes"
```

**检查清单：**
- [ ] 所有 ImageButton 都有 `contentDescription`
- [ ] 图标有有意义的描述
- [ ] 装饰性图片：`importantForAccessibility="no"`
- [ ] 复杂视图用 `contentDescription` 归组
- [ ] 动态内容变化有播报
- [ ] 自定义视图支持 TalkBack 手势

### 焦点管理

**iOS 焦点顺序：**
- [ ] 阅读顺序符合逻辑（从上到下、从左到右）
- [ ] 自定义顺序用 `accessibilityElements` 数组
- [ ] 焦点移到新呈现的内容
- [ ] 关闭模态后焦点回到触发元素
- [ ] 跳过重复内容（提供跳过链接）

**Android 焦点顺序：**
- [ ] 遍历顺序跟随视觉布局
- [ ] 自定义顺序用 `accessibilityTraversalBefore/After`
- [ ] 播报页面标题变化
- [ ] 播报动态内容更新
- [ ] 避免焦点陷阱（用户能走出去）

### 播报

**动态内容：**
```swift
// iOS
UIAccessibility.post(notification: .announcement,
                     argument: "Item added to cart")

// Android
view.announceForAccessibility("Item added to cart")
```

**何时播报：**
- [ ] 内容异步加载完成
- [ ] 表单提交成功 / 失败
- [ ] 列表项被添加 / 移除
- [ ] 错误消息
- [ ] 计时器 / 倒计时更新

## 键盘与替代输入

### 键盘导航

**iOS：**
- [ ] 支持硬件键盘快捷键
- [ ] Tab 键在字段之间移动
- [ ] 回车键提交表单
- [ ] Escape 关闭模态

**Android：**
- [ ] 方向键（D-pad）导航正常
- [ ] Tab 导航顺序符合逻辑
- [ ] Enter / Space 激活聚焦元素
- [ ] 返回键行为可预期

### 焦点指示器

**视觉反馈：**
- [ ] 聚焦元素有明确指示（边框、高亮）
- [ ] 焦点指示器满足 3:1 对比度要求
- [ ] 焦点指示器在所有状态下可见
- [ ] 不要移除焦点轮廓而不给替代

### Switch Control（iOS）与 Switch Access（Android）

**兼容性：**
- [ ] 所有可交互元素都能到达
- [ ] 扫描顺序符合逻辑
- [ ] 简单选择即可完成动作
- [ ] 避免基于时间的交互

## 动效与动画

### Reduce Motion

**尊重用户偏好：**
```swift
// iOS
if UIAccessibility.isReduceMotionEnabled {
    // Use simple fade or no animation
} else {
    // Use full animation
}

// Android
val animationDuration = if (isReduceMotionEnabled()) 0L else 300L
```

**规范：**
- [ ] 提供减弱动效的替代方案
- [ ] 只保留必要的动效（不做装饰性动效）
- [ ] 减弱动效下避免视差效果
- [ ] 用交叉淡入替代滑动 / 缩放
- [ ] 允许瞬时切换

### 前庭功能障碍

**避免：**
- [ ] 过度视差滚动
- [ ] 快速动画或闪烁
- [ ] 大面积位移
- [ ] 模拟 3D 运动
- [ ] 带动态效果的自动播放视频

### 癫痫预防

**关键要求：**
- [ ] 内容闪烁不超过每秒 3 次
- [ ] 不做大面积闪烁
- [ ] 避免红色闪烁图案
- [ ] 含闪烁的视频要给出警告

## 表单与输入

### 标签与说明

**清晰性：**
- [ ] 所有输入都有可见标签
- [ ] 字段聚焦时标签仍然可见
- [ ] 必填字段明确标注
- [ ] 输入前提供说明
- [ ] 帮助文本可获取且能被读屏读取

**错误处理：**
- [ ] 错误被识别并描述
- [ ] 错误消息出现在对应字段旁
- [ ] 给出修正建议
- [ ] 表单顶部有错误摘要
- [ ] 出错时保留用户已填内容

### 输入类型

**键盘优化：**
- [ ] 使用与输入内容匹配的键盘类型
- [ ] 邮箱字段显示邮箱键盘
- [ ] 电话字段显示数字键盘
- [ ] URL 字段显示 URL 键盘
- [ ] 自动大小写设置正确

### 校验

**无障碍校验：**
- [ ] 实时校验结果有播报
- [ ] 错误消息与字段关联
- [ ] `aria-invalid`（Web）或 `accessibilityValue`（原生）
- [ ] 成功确认有播报
- [ ] 不要只靠颜色表达错误

## 媒体与内容

### 图片

**替代文本：**
- [ ] 信息性图片有描述性 alt 文本
- [ ] 装饰性图片标记为装饰性
- [ ] 复杂图片提供长描述
- [ ] 图表提供数据表替代
- [ ] Logo 的 alt 文本包含公司名

**图片中的文字：**
- [ ] 尽量避免图片内文字
- [ ] 无法避免时提供文本替代
- [ ] 确保图片内文字对比度足够

### 视频与音频

**字幕：**
- [ ] 所有视频都有字幕
- [ ] 字幕准确且同步
- [ ] 所有讲话与重要声音都配字幕
- [ ] 允许用户开关字幕

**音频描述：**
- [ ] 视频提供音频描述
- [ ] 描述重要的视觉信息
- [ ] 替代方案：提供文字稿

**文字稿：**
- [ ] 提供完整文字稿
- [ ] 包含所有讲话与声音
- [ ] 标明说话人
- [ ] 描述重要动作 / 画面

### 自动播放内容

**用户控制：**
- [ ] 不自动播放带声音的内容（或不超过 3 秒）
- [ ] 提供暂停 / 停止控件
- [ ] 控件在 3 次交互内可达
- [ ] 暂停后不自动恢复

## 测试方法

### 自动化测试

**工具：**
- iOS Accessibility Inspector
- Android Accessibility Scanner
- Espresso 无障碍检查
- XCTest 无障碍审计

**定期执行：**
- [ ] 纳入 CI/CD 流程
- [ ] 每次发布前
- [ ] UI 大改之后

### 人工测试

**读屏测试：**
- [ ] 只用 VoiceOver / TalkBack 走完整个应用
- [ ] 所有内容与动作都可访问
- [ ] 阅读顺序符合逻辑
- [ ] 所有状态都有播报
- [ ] 动态更新有播报

**键盘测试：**
- [ ] 只用键盘完成所有任务
- [ ] Tab 顺序符合逻辑
- [ ] 焦点指示器可见
- [ ] 没有键盘陷阱

**视觉测试：**
- [ ] 在最大文字尺寸（200% 或 AX5）下测试
- [ ] 在高对比度模式下测试
- [ ] 用色盲模拟器测试
- [ ] 在强光下测试（如适用）

### 用户测试

**纳入残障用户：**
- [ ] 招募各类残障用户
- [ ] 读屏用户
- [ ] 运动障碍用户
- [ ] 低视力用户
- [ ] 认知障碍用户

**观察真实使用：**
- [ ] 观察辅助技术实际被怎么使用
- [ ] 找出痛点
- [ ] 收集反馈
- [ ] 根据发现迭代

## 平台专属特性

### iOS 无障碍特性

**支持这些特性：**
- [ ] Dynamic Type（文字大小）
- [ ] VoiceOver（读屏）
- [ ] Voice Control（语音控制）
- [ ] Switch Control（辅助开关）
- [ ] Reduce Motion
- [ ] Reduce Transparency
- [ ] Increase Contrast
- [ ] Differentiate Without Color
- [ ] On/Off Labels（开关）
- [ ] Button Shapes

### Android 无障碍特性

**支持这些特性：**
- [ ] 字体大小与显示尺寸缩放
- [ ] TalkBack（读屏）
- [ ] Voice Access（语音控制）
- [ ] Switch Access（辅助开关）
- [ ] 移除动画（减弱动效）
- [ ] 高对比度文本
- [ ] 颜色校正
- [ ] 颜色反转

## 常见错误

### 不要做这些：

**视觉：**
- ❌ 只用颜色传达信息
- ❌ 文字小于 11pt
- ❌ 对比度不足（正文 < 4.5:1）
- ❌ 触摸目标小于 44pt / 48dp

**读屏：**
- ❌ 按钮 / 图片缺少无障碍标签
- ❌ 标签里包含元素类型（「按钮」「图片」）
- ❌ 表单字段没有标签
- ❌ 不播报动态内容变化

**交互：**
- ❌ 基于时间的交互没有替代方案
- ❌ 只能用特定手势完成动作
- ❌ 自动播放内容没有控件
- ❌ 键盘焦点不可见

**内容：**
- ❌ 图片没有 alt 文本
- ❌ 视频没有字幕
- ❌ 音频没有文字稿
- ❌ 闪烁内容（每秒 > 3 次）

## 资源

### 官方规范

- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)
- [iOS Accessibility](https://developer.apple.com/accessibility/ios/)
- [Android Accessibility](https://developer.android.com/guide/topics/ui/accessibility)

### 测试工具

- [Accessibility Inspector (Xcode)](https://developer.apple.com/library/archive/documentation/Accessibility/Conceptual/AccessibilityMacOSX/OSXAXTestingApps.html)
- [Accessibility Scanner (Android)](https://play.google.com/store/apps/details?id=com.google.android.apps.accessibility.auditor)
- [Color Contrast Analyzers](https://www.tpgi.com/color-contrast-checker/)

### 学习资源

- [WebAIM](https://webaim.org/)
- [A11y Project](https://www.a11yproject.com/)
- [Deque University](https://dequeuniversity.com/)
- [Google Accessibility Courses](https://www.udacity.com/course/web-accessibility--ud891)

## 无障碍声明模板

```markdown
# Accessibility Statement for [App Name]

We are committed to ensuring digital accessibility for people with disabilities.
We continually improve the user experience for everyone and apply relevant
accessibility standards.

## Conformance Status
[App Name] is partially conformant with WCAG 2.1 level AA. Partially conformant
means that some parts of the content do not fully conform to the accessibility
standard.

## Measures
[Organization] takes the following measures to ensure accessibility:
- Include accessibility throughout our internal policies
- Integrate accessibility into our procurement practices
- Provide continual accessibility training for our staff
- Include people with disabilities in our design personas
- Test with assistive technology users

## Feedback
We welcome your feedback on the accessibility of [App Name]. Please contact us:
- Email: [email]
- Phone: [phone]
- Address: [address]

## Technical Specifications
Accessibility of [App Name] relies on the following technologies:
- iOS 15.0+
- Android 10.0+
- Screen readers (VoiceOver, TalkBack)
- Voice control systems

## Known Limitations
Despite our efforts, some limitations may exist:
- [List any known issues]
- [Expected timeline for fixes]

This statement was last updated on [Date].
```

## 常见无障碍错误与修复

### 触摸目标问题

### ❌ 错误：触摸目标太小

**问题：**
```typescript
// BAD: Button too small (32×32pt)
<TouchableOpacity style={{ width: 32, height: 32 }}>
  <Icon name="close" size={16} />
</TouchableOpacity>
```

**影响：**
- 用户经常点不中
- 在大屏手机上尤其令人受挫
- 无障碍不达标

**✅ 修复：**
```typescript
// GOOD: Minimum 44×44pt with hitSlop for smaller visuals
<TouchableOpacity
  style={{ width: 32, height: 32 }}
  hitSlop={{ top: 6, bottom: 6, left: 6, right: 6 }} // Extends to 44×44
>
  <Icon name="close" size={16} />
</TouchableOpacity>

// BETTER: Make actual button larger
<TouchableOpacity style={{ width: 44, height: 44, alignItems: 'center', justifyContent: 'center' }}>
  <Icon name="close" size={20} />
</TouchableOpacity>
```

### ❌ 错误：触摸目标挨得太近

**问题：**
```typescript
// BAD: No spacing between buttons
<View style={{ flexDirection: 'row' }}>
  <Button title="Cancel" onPress={onCancel} />
  <Button title="Delete" onPress={onDelete} />
</View>
```

**影响：**
- 误点到错误的按钮
- 对破坏性动作尤其关键

**✅ 修复：**
```typescript
// GOOD: Adequate spacing (12-16pt minimum)
<View style={{ flexDirection: 'row', gap: 16 }}>
  <Button title="Cancel" onPress={onCancel} />
  <Button title="Delete" onPress={onDelete} />
</View>

// BETTER: Separate destructive actions
<View style={{ gap: 12 }}>
  <Button title="Delete" variant="destructive" onPress={onDelete} />
  <Button title="Cancel" variant="secondary" onPress={onCancel} />
</View>
```

### 排版问题

### ❌ 错误：文字太小

**问题：**
```typescript
// BAD: 10pt text
<Text style={{ fontSize: 10 }}>Important information here</Text>
```

**影响：**
- 难以阅读
- WCAG 不达标
- 无障碍问题

**✅ 修复：**
```typescript
// GOOD: 12pt minimum for captions
<Text style={{ fontSize: 12 }}>Important information here</Text>

// BETTER: 14-16pt for body text
<Text style={{ fontSize: 15 }}>Important information here</Text>
```

### ❌ 错误：行高不当

**问题：**
```typescript
// BAD: No line height specified
<Text style={{ fontSize: 16 }}>
  Long paragraph of text that wraps to multiple lines.
  This becomes hard to read without proper spacing.
</Text>
```

**影响：**
- 行与行糊在一起
- 可读性下降
- 眼睛疲劳

**✅ 修复：**
```typescript
// GOOD: 1.5× line height for body text
<Text style={{ fontSize: 16, lineHeight: 24 }}>
  Long paragraph of text that wraps to multiple lines.
  This is much easier to read with proper line spacing.
</Text>
```

### ❌ 错误：正文用全大写

**问题：**
```typescript
// BAD: All caps makes reading difficult
<Text style={{ fontSize: 14, textTransform: 'uppercase' }}>
  This entire paragraph is in all caps which makes it significantly harder
  to read because we recognize words by their shape and all caps removes
  that visual cue making every word look like a rectangle.
</Text>
```

**影响：**
- 阅读速度变慢
- 像在喊叫
- 无障碍问题

**✅ 修复：**
```typescript
// GOOD: Use title case for headings only
<Text style={{ fontSize: 14 }}>
  This paragraph uses normal sentence case which is much easier to read
  and doesn't feel like the app is shouting at you.
</Text>

// OK: All caps for short labels/buttons only
<Text style={{ fontSize: 12, textTransform: 'uppercase', letterSpacing: 1 }}>
  Submit
</Text>
```

### 颜色与对比度

### ❌ 错误：对比度不足

**问题：**
```typescript
// BAD: Light gray on white (2.1:1 contrast)
<Text style={{ color: '#CCCCCC', backgroundColor: '#FFFFFF' }}>
  Important message
</Text>
```

**影响：**
- 强光下无法阅读
- 不满足 WCAG AA（需要 4.5:1）
- 无障碍不合规

**✅ 修复：**
```typescript
// GOOD: Dark gray on white (7:1 contrast)
<Text style={{ color: '#595959', backgroundColor: '#FFFFFF' }}>
  Important message
</Text>

// BETTER: Use semantic color system
const colors = {
  text: {
    primary: '#14171A',   // 15.8:1
    secondary: '#657786', // 4.6:1
  },
  background: '#FFFFFF',
};

<Text style={{ color: colors.text.secondary }}>
  Important message
</Text>
```

### ❌ 错误：只用颜色作为指示

**问题：**
```typescript
// BAD: Color alone indicates status
<View>
  <Text style={{ color: 'red' }}>Error occurred</Text>
  <Text style={{ color: 'green' }}>Success!</Text>
</View>
```

**影响：**
- 色盲用户会漏掉信息
- 黑白屏上无法分辨
- 无障碍不达标

**✅ 修复：**
```typescript
// GOOD: Color + icon + text
<View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
  <Icon name="error" color="red" />
  <Text style={{ color: 'red' }}>Error occurred</Text>
</View>

<View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
  <Icon name="check-circle" color="green" />
  <Text style={{ color: 'green' }}>Success!</Text>
</View>
```

### 读屏与播报

### ❌ 错误：缺少无障碍标签

**问题：**
```typescript
// BAD: No label on icon button
<TouchableOpacity onPress={onShare}>
  <Icon name="share" size={24} />
</TouchableOpacity>
```

**影响：**
- 读屏只念出「按钮」，没有上下文
- 用户不知道这个按钮做什么
- WCAG 不达标

**✅ 修复：**
```typescript
// GOOD: Descriptive label
<TouchableOpacity
  onPress={onShare}
  accessibilityRole="button"
  accessibilityLabel="Share this post"
  accessibilityHint="Opens the share sheet to send to friends"
>
  <Icon name="share" size={24} />
</TouchableOpacity>
```

### ❌ 错误：标签里带元素类型

**问题：**
```typescript
// BAD: Redundant "button" in label
<TouchableOpacity
  accessibilityLabel="Share button"
  accessibilityRole="button"
>
  <Text>Share</Text>
</TouchableOpacity>
```

**影响：**
- 读屏念成「分享按钮 按钮」
- 冗余、烦人
- 体验差

**✅ 修复：**
```typescript
// GOOD: Label without type (role provides that)
<TouchableOpacity
  accessibilityLabel="Share"
  accessibilityRole="button"
>
  <Text>Share</Text>
</TouchableOpacity>
```

### ❌ 错误：不播报动态变化

**问题：**
```typescript
// BAD: No announcement when item added
function addToCart(item) {
  setCartItems([...cartItems, item]);
  // User doesn't know anything happened
}
```

**影响：**
- 读屏用户收不到反馈
- 不确定操作结果
- 无障碍体验差

**✅ 修复：**
```typescript
// GOOD: Announce the change
import { AccessibilityInfo } from 'react-native';

function addToCart(item) {
  setCartItems([...cartItems, item]);

  // Announce to screen reader users
  AccessibilityInfo.announceForAccessibility(
    `${item.name} added to cart`
  );
}
```

### 表单设计

### ❌ 错误：键盘类型不对

**问题：**
```typescript
// BAD: Default keyboard for email
<TextInput
  placeholder="Email"
  value={email}
  onChangeText={setEmail}
/>
```

**影响：**
- 要额外切到符号页才能打 @
- 体验差
- 输入更慢

**✅ 修复：**
```typescript
// GOOD: Email keyboard
<TextInput
  placeholder="Email"
  value={email}
  onChangeText={setEmail}
  keyboardType="email-address"
  autoCapitalize="none"
  autoComplete="email"
/>

// Number input
<TextInput
  placeholder="Phone"
  keyboardType="phone-pad"
  autoComplete="tel"
/>

// URL input
<TextInput
  placeholder="Website"
  keyboardType="url"
  autoCapitalize="none"
/>
```

### ❌ 错误：输入框没有标签

**问题：**
```typescript
// BAD: Only placeholder, disappears when typing
<TextInput
  placeholder="Enter your name"
  value={name}
  onChangeText={setName}
/>
```

**影响：**
- 用户忘记这个字段是填什么的
- 无障碍不达标
- 体验差

**✅ 修复：**
```typescript
// GOOD: Persistent label + placeholder
<View>
  <Text style={styles.label}>Name</Text>
  <TextInput
    placeholder="John Doe"
    value={name}
    onChangeText={setName}
    accessibilityLabel="Name"
  />
</View>

// BETTER: Floating label (advanced)
<FloatingLabelInput
  label="Name"
  placeholder="John Doe"
  value={name}
  onChangeText={setName}
/>
```

### ❌ 错误：错误提示写得差

**问题：**
```typescript
// BAD: Generic error
{error && <Text style={{ color: 'red' }}>Error</Text>}
```

**影响：**
- 用户不知道错在哪
- 无法修正问题
- 令人受挫

**✅ 修复：**
```typescript
// GOOD: Specific, actionable error
{error && (
  <View style={styles.errorContainer} accessibilityRole="alert">
    <Icon name="error" color="#D32F2F" />
    <Text style={styles.errorText}>
      {error.message || 'Please enter a valid email address'}
    </Text>
  </View>
)}

// BETTER: Inline validation
<TextInput
  value={email}
  onChangeText={setEmail}
  onBlur={validateEmail}
  style={[styles.input, emailError && styles.inputError]}
/>
{emailError && (
  <Text style={styles.errorHint}>
    Example: user@example.com
  </Text>
)}
```
