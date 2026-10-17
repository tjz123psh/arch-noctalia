# iOS vs Android 平台差异速查

iOS 与 Android 关键设计差异的逐项对照。用于判断哪些必须分开做、哪些可以统一。

## 导航模式

| 方面 | iOS | Android |
|--------|-----|---------|
| **返回按钮** | 左上角 | 左上角或硬件返回键 |
| **主操作** | 右上角 | Floating Action Button（右下）或右上角 |
| **Tab 栏** | 底部（3-5 项） | 底部（3-5 项）或顶部 Tabs |
| **更多选项** | 底部 Tab「More」或 Action Sheet | 右上溢出菜单（⋮） |
| **导航抽屉** | 较少使用 | 5 个以上分区时常见 |
| **关闭模态** | 导航栏上的「Cancel」或「Done」 | 硬件返回键或关闭图标 |
| **页面转场** | 从右侧推入（层级关系） | 上滑或淡入（随转场类型而异） |

## 视觉设计

| 元素 | iOS | Android |
|---------|-----|---------|
| **字体** | San Francisco | Roboto |
| **状态栏** | 浅色 / 深色内容 | 透明，由应用控制 |
| **App Bar** | Navigation Bar（44pt） | Top App Bar（手机 56dp、平板 64dp） |
| **图标** | 描边、极简 | 填充或描边（Material Icons） |
| **阴影** | 细微、少用 | Elevation 体系（1-24dp） |
| **分隔线** | 通栏或内缩 | 通栏、居中或内缩 |
| **圆角** | 圆角（随组件而异） | 圆角（随组件取 4-28dp） |
| **动画** | 弹簧物理、带回弹 | 缓动曲线、不回弹 |

## 触摸目标

| 方面 | iOS | Android |
|--------|-----|---------|
| **最小尺寸** | 44×44 pt | 48×48 dp |
| **图标按钮** | 44×44 pt | 48×48 dp |
| **列表项** | 高度最小 44pt | 高度最小 48-56dp |
| **FAB** | 不适用（不使用） | 默认 56dp，mini 40dp |
| **Switch** | 51×31 pt | 52×32 dp |
| **Checkbox** | 22×22 pt | 40×40 dp |

## 排版

| 样式 | iOS（Points） | Android（SP） |
|-------|--------------|--------------|
| **Large Title** | 34pt Bold | Display Large 57sp |
| **Title** | 28pt Bold | Headline Large 32sp |
| **Headline** | 17pt Semibold | Title Large 22sp |
| **Body** | 17pt Regular | Body Large 16sp |
| **Callout** | 16pt Regular | Body Medium 14sp |
| **Caption** | 12pt Regular | Body Small 12sp |
| **Footnote** | 13pt Regular | Label Medium 12sp |
| **最小值** | 11pt | 12sp |

## 组件

### 按钮

| 类型 | iOS | Android |
|------|-----|---------|
| **Filled** | 圆角矩形、实色 | 圆角（20dp）、带阴影 |
| **Outlined** | 边框、透明填充 | 1dp 边框、无阴影 |
| **Text** | 无背景、无边框 | 无背景、无边框 |
| **高度** | 最小 44pt | 标准 40dp |
| **内边距** | 水平 16pt | 水平 16dp |
| **大小写** | Title Case | 全大写（文本按钮） |

### Switch

| 方面 | iOS | Android |
|--------|-----|---------|
| **尺寸** | 51×31 pt | 52×32 dp |
| **样式** | 胶囊形，开启时着色 | 带轨道的拨动开关 |
| **动画** | 平滑滑动 | 滑块滑动 + 涟漪 |
| **标签** | 位于左侧 | 位于左侧或右侧 |

### 列表项

| 方面 | iOS | Android |
|--------|-----|---------|
| **高度** | 最小 44pt | 最小 56dp（单行）、72dp（双行） |
| **分隔线** | 通栏或内缩 16pt | 通栏或内缩 16dp |
| **头像** | 40-60pt | 40dp（单行）、56dp（双行 / 三行） |
| **滑动操作** | 从右侧滑动 | 从左侧或右侧滑动 |
| **选中态** | 右侧勾选标记 | 左侧 Checkbox 或右侧勾选标记 |

### 卡片

| 方面 | iOS | Android |
|--------|-----|---------|
| **阴影** | 细微阴影 | Elevation（默认 1dp，浮起 8dp） |
| **圆角** | 10-12pt 半径 | 12dp 半径 |
| **内边距** | 16pt | 16dp |
| **间距** | 8-16pt | 8dp |

### 文本字段

| 方面 | iOS | Android |
|--------|-----|---------|
| **样式** | 带边框的圆角矩形 | Filled 或 Outlined |
| **标签** | 占位符或浮动标签 | 默认浮动标签 |
| **高度** | 最小 44pt | 56dp |
| **聚焦** | 蓝色边框或阴影 | 底线高亮 |
| **错误** | 下方红字 | 红色标签 + 底线 |

## 手势

| 手势 | iOS | Android |
|---------|-----|---------|
| **返回** | 左缘滑动 | 左缘滑动或返回键 |
| **菜单** | 不适用 | 左缘滑动（有抽屉时） |
| **刷新** | 顶部下拉 | 顶部下拉 |
| **列表项操作** | 列表项左滑 | 长按或滑动 |
| **上下文菜单** | 长按（iOS 13+） | 长按 |
| **关闭模态** | 下拉（iOS 13+） | 返回键 |

## 对话框与提示

| 方面 | iOS | Android |
|--------|-----|---------|
| **样式** | 居中模态、圆角 | 居中对话框、带阴影 |
| **标题** | 加粗、居中 | 中等字重、左对齐 |
| **正文** | 常规、居中 | 常规、左对齐 |
| **按钮** | 2 个横向，3 个及以上纵向 | 横向（右对齐） |
| **按钮顺序** | Cancel 在左、Confirm 在右 | Cancel 在左、Confirm 在右 |
| **关闭方式** | 仅按钮 | 按钮或返回键 |

## 加载状态

| 类型 | iOS | Android |
|------|-----|---------|
| **Activity Indicator** | 旋转圆点 | 环形进度 |
| **进度条** | 细线 | 较粗的线、圆角端点 |
| **骨架屏** | 灰色占位块 | 常用 shimmer 效果 |
| **下拉刷新** | 顶部 spinner | 顶部环形进度 |

## 表单

| 元素 | iOS | Android |
|---------|-----|---------|
| **键盘回车键** | 「Return」「Done」「Next」 | 对勾、箭头 |
| **选择器** | 滚轮 | 下拉菜单 |
| **日期选择** | 滚轮（内联或模态） | 日历视图或下拉 |
| **时间选择** | 滚轮 | 表盘 |
| **分段控件** | 胶囊按钮（iOS） | Chip 组（Android） |
| **步进器** | -/+ 按钮 | 不适用（改用文本字段） |

## 通知与 Toast

| 类型 | iOS | Android |
|------|-----|---------|
| **推送通知** | 顶部横幅 | 顶部横幅 |
| **应用内横幅** | 顶部出现 | 顶部出现 |
| **Toast / Snackbar** | 非原生（用第三方库） | 底部 Snackbar |
| **持续时间** | 3-5 秒 | 4-10 秒 |
| **操作** | 按钮在右 | 按钮在右 |

## 搜索

| 方面 | iOS | Android |
|--------|-----|---------|
| **搜索栏** | 圆角、灰色背景 | 白 / 灰底带边框 |
| **位置** | 导航栏或工具栏内 | App Bar 内或独立 |
| **取消按钮** | 聚焦时出现 | 出现返回箭头 |
| **清除按钮** | 输入时右侧 X | 输入时右侧 X |
| **语音搜索** | 较少使用 | 常见（麦克风图标） |

## 设置

| 模式 | iOS | Android |
|---------|-----|---------|
| **布局** | 分节的分组列表 | Preference 屏幕 |
| **Switch** | 行右侧 | 行右侧 |
| **导航** | 展开指示符（›） | App Bar 中的返回箭头 |
| **组织方式** | 扁平层级 | 可嵌套 |

## 触觉反馈

| 类型 | iOS | Android |
|------|-----|---------|
| **选择** | 轻点 | 可选振动 |
| **冲击** | Light / Medium / Heavy | 因设备而异 |
| **通知** | Success / Warning / Error | 标准化程度较低 |
| **使用** | Taptic Engine 表现丰富 | 依赖设备 |

## 平台独有能力

### iOS 独有

- **3D Touch / Haptic Touch**：Peek and pop（旧版）或上下文菜单（iOS 13+）
- **Live Text**：图片中的文字识别
- **Face ID / Touch ID**：生物识别认证
- **Dynamic Island**：状态栏交互（iPhone 14 Pro+）
- **Action Extensions**：带自定义动作的分享面板
- **Widgets**：固定尺寸的主屏幕小组件
- **App Clips**：轻量应用体验

### Android 独有

- **Floating Action Button (FAB)**：主操作按钮
- **Navigation Drawer**：侧边导航菜单
- **Material You**：动态色彩主题（Android 12+）
- **Widgets**：更灵活的尺寸与布局
- **Live Wallpapers**：动态背景
- **Custom Launchers**：第三方主屏幕
- **返回键**：硬件或虚拟返回按钮
- **分屏**：同时运行两个应用

## 色彩体系

### iOS

| 模式 | 背景 | 主文本 | 次要文本 |
|------|------------|--------------|----------------|
| **浅色** | 白色 | Black 87% | Black 60% |
| **深色** | #000000 | White 100% | White 60% |

**系统色：**
- Tint 色（默认蓝）
- 语义色（label、secondaryLabel、tertiaryLabel）
- 背景色（systemBackground、secondarySystemBackground）

### Android

| 模式 | Surface | On Surface | On Surface Variant |
|------|---------|------------|-------------------|
| **浅色** | #FFFFFF | #1C1B1F | #49454F |
| **深色** | #1C1B1F | #E6E1E5 | #CAC4D0 |

**Material Design 3：**
- Primary、Secondary、Tertiary 色彩角色
- Surface 容器（surface、surfaceVariant、surfaceContainer）
- 彩色背景上文本用的 On-color 变体

## 动画

### iOS

- **弹簧动画**：默认，带回弹手感
- **时长**：通常 0.3-0.4s
- **缓动**：ease-in-ease-out 或弹簧
- **可交互**：可被打断并反向回退

### Android

- **Material motion**：强调动效编排
- **时长**：
  - 小：100-200ms
  - 中：200-300ms
  - 大：300-500ms
- **缓动**：
  - Standard：cubic-bezier(0.4, 0.0, 0.2, 1)
  - Emphasized：cubic-bezier(0.2, 0.0, 0, 1)
- **转场**：Container transform、shared axis、fade through

## 实现建议

### 何时使用平台专属设计

**必须不同：**
- 导航模式（底部 Tab 与抽屉的取舍）
- 返回按钮行为
- 系统 UI（状态栏、导航栏）

**通常不同：**
- 主操作位置（右上角与 FAB）
- 模态呈现方式
- 搜索 UI

**可以统一：**
- 列表布局
- 卡片设计
- 排版（使用品牌自定义字体时）
- 配色方案

### React Native 的 Platform API

```typescript
import { Platform } from 'react-native';

// Conditional rendering
{Platform.OS === 'ios' ? <IOSComponent /> : <AndroidComponent />}

// Platform-specific values
const styles = StyleSheet.create({
  container: {
    paddingTop: Platform.OS === 'ios' ? 20 : 0,
    ...Platform.select({
      ios: {
        shadowColor: '#000',
        shadowOffset: { width: 0, height: 2 },
        shadowOpacity: 0.25,
        shadowRadius: 3.84,
      },
      android: {
        elevation: 5,
      },
    }),
  },
});

// Platform-specific files
// Component.ios.tsx - Used on iOS
// Component.android.tsx - Used on Android
// Component.tsx - Fallback for both
```

## 快速决策指南

### 是否应遵循平台惯例？

**是——必须遵循：**
- 导航模式
- 系统手势
- 返回按钮行为
- 状态栏处理
- 文本选择

**也许——可以考虑遵循：**
- 主按钮样式
- 模态呈现方式
- 搜索界面
- 设置页

**不需要——可以统一：**
- 品牌色
- 自定义插画
- 内容布局
- 排版（使用品牌字体时）
- 卡片 / 列表项设计

### 双端测试

**关键检查：**
- [ ] 导航在每个平台上都有原生手感
- [ ] 返回按钮行为符合预期
- [ ] 触摸目标达到最小尺寸（44pt / 48dp）
- [ ] 文本可读（达到平台标准）
- [ ] 动效时机与幅度合适
- [ ] 安全区已避让（iOS 刘海、Android 手势条）
- [ ] 双端深色模式都正常
- [ ] 键盘行为正确

## 资源

### 官方规范
- [iOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Material Design 3](https://m3.material.io/)

### 工具
- [SF Symbols](https://developer.apple.com/sf-symbols/)（iOS 图标）
- [Material Symbols](https://fonts.google.com/icons)（Android 图标）
- [React Navigation](https://reactnavigation.org/)（跨端导航）
- [React Native Paper](https://reactnativepaper.com/)（Material Design）

## 常见导航错误与修复

### ❌ 错误：导航模式前后不一致

**问题：**
```typescript
// BAD: Mixed navigation (drawer on some screens, tabs on others)
// Screen A has drawer
<DrawerNavigator>
  <Screen name="Home" />
</DrawerNavigator>

// Screen B has tabs
<TabNavigator>
  <Screen name="Profile" />
</TabNavigator>
```

**影响：**
- 用户困惑
- 体验不一致
- 违反平台惯例

**✅ 修复：**
```typescript
// GOOD: Consistent pattern throughout
<TabNavigator>
  <Screen name="Home" component={HomeScreen} />
  <Screen name="Profile" component={ProfileScreen} />
  <Screen name="Settings" component={SettingsScreen} />
</TabNavigator>
```

### ❌ 错误：返回按钮行为错误

**问题：**
```typescript
// BAD: Back button exits app instead of going to previous screen
<Button
  title="Back"
  onPress={() => BackHandler.exitApp()}
/>
```

**影响：**
- 数据丢失
- 用户受挫
- 违反平台惯例

**✅ 修复：**
```typescript
// GOOD: Use navigation to go back
<Button
  title="Back"
  onPress={() => navigation.goBack()}
/>

// Or use hardware back button handling
useEffect(() => {
  const backHandler = BackHandler.addEventListener(
    'hardwareBackPress',
    () => {
      navigation.goBack();
      return true; // Prevent default behavior
    }
  );

  return () => backHandler.remove();
}, [navigation]);
```
