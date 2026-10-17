# React Native UI 组件库

主流 React Native UI 库的综合指南，含适用场景与 2026 年推荐。

## Material Design 组件库

### React Native Paper

**最适合：** Android 优先的应用、需要符合 Material Design 3

**优点：**
- 官方 Material Design 3 实现
- 主题化支持出色
- 内置深色模式
- 组件集完整
- 维护活跃
- 无障碍较好

**缺点：**
- 在 iOS 上可能显得不协调
- 部分定制受限
- 影响包体积

**安装：**
```bash
npm install react-native-paper react-native-vector-icons
```

**用法：**
```typescript
import { Button, Card, Text } from 'react-native-paper';

<Card>
  <Card.Title title="Card Title" subtitle="Card Subtitle" />
  <Card.Content>
    <Text variant="bodyMedium">Card content</Text>
  </Card.Content>
  <Card.Actions>
    <Button>Cancel</Button>
    <Button mode="contained">OK</Button>
  </Card.Actions>
</Card>
```

**何时使用：**
- 以 Android 为主的应用
- 品牌形象即 Material Design
- 需要完整的主题化能力
- 快速原型

**官网：** https://reactnativepaper.com/

---

### React Native Elements

**最适合：** 跨平台应用、需要高度可定制的组件

**优点：**
- 与平台无关
- 高度可定制
- 文档完善
- 社区大
- 支持 TypeScript

**缺点：**
- 设计主张弱于 Paper
- 需要更多样式工作
- 部分组件样式偏旧

**安装：**
```bash
npm install @rneui/themed @rneui/base
```

**用法：**
```typescript
import { Button, Card, Icon } from '@rneui/themed';

<Card>
  <Card.Title>CARD TITLE</Card.Title>
  <Card.Divider />
  <Card.Image source={{ uri: 'image.jpg' }} />
  <Text style={{ marginBottom: 10 }}>
    The idea with React Native Elements is more about component structure
  </Text>
  <Button
    icon={<Icon name="code" color="#ffffff" />}
    buttonStyle={{ borderRadius: 0 }}
    title="VIEW NOW"
  />
</Card>
```

**何时使用：**
- 需要灵活性而非既定主张
- 自建设计系统
- 追求双端一致
- 作为组件起步套件

**官网：** https://reactnativeelements.com/

---

## iOS 取向的组件库

### React Native iOS Kit

**最适合：** iOS 优先的应用、需要原生手感

**优点：**
- 原生 iOS 外观与手感
- 支持 SF Symbols
- iOS 专属组件
- 紧密遵循 HIG

**缺点：**
- 仅支持 iOS（在 Android 上效果不好）
- 社区较小
- 更新频率较低

**何时使用：**
- 仅发布 iOS 的应用
- 需要原生 iOS 组件
- 严格遵循 Apple HIG

---

## 跨平台 UI 套件

### NativeBase

**最适合：** 快速开发、跨平台一致的 UI

**优点：**
- 组件库体量大
- 内置响应式工具类
- 主题系统
- 无障碍特性
- 可与 Expo 配合

**缺点：**
- 包体积大
- 设计主张较强
- 主题化有学习曲线

**安装：**
```bash
npm install native-base react-native-svg react-native-safe-area-context
```

**用法：**
```typescript
import { Box, Heading, VStack, FormControl, Input, Button } from "native-base";

<Box safeArea p="2" py="8" w="90%" maxW="290">
  <Heading size="lg" fontWeight="600">
    Welcome
  </Heading>
  <VStack space={3} mt="5">
    <FormControl>
      <FormControl.Label>Email</FormControl.Label>
      <Input />
    </FormControl>
    <FormControl>
      <FormControl.Label>Password</FormControl.Label>
      <Input type="password" />
    </FormControl>
    <Button mt="2" colorScheme="indigo">
      Sign in
    </Button>
  </VStack>
</Box>
```

**何时使用：**
- 需要大量现成组件
- 快速原型
- 需要响应式设计
- 要求兼容 Expo

**官网：** https://nativebase.io/

---

### Tamagui

**最适合：** 性能敏感的应用、通用（Web + 原生）

**优点：**
- 极快（编译期优化）
- 通用（React Native + Web）
- 现代样式系统
- 动画能力出色
- 可 tree-shake

**缺点：**
- 库较新（成熟度不足）
- 学习曲线更陡
- 范式不同

**安装：**
```bash
npm install tamagui @tamagui/config
```

**用法：**
```typescript
import { Button, Card, H2, Paragraph } from 'tamagui';

<Card elevate size="$4" bordered>
  <Card.Header padded>
    <H2>Card Title</H2>
  </Card.Header>
  <Card.Footer padded>
    <Paragraph>Card content goes here</Paragraph>
    <Button>Action</Button>
  </Card.Footer>
</Card>
```

**何时使用：**
- 性能是关键
- 同时面向 Web 与原生
- 需要现代动画能力
- 愿意学习新范式

**官网：** https://tamagui.dev/

---

## 专用库

### React Native UI Lib（Wix 出品）

**最适合：** 企业级应用、组件需求广泛

**优点：**
- 经过生产验证（Wix 线上环境）
- 组件覆盖全面
- Modifiers API
- 性能出色
- 维护活跃

**缺点：**
- 有学习曲线
- API 主张较强
- 文档还有提升空间

**安装：**
```bash
npm install react-native-ui-lib
```

**用法：**
```typescript
import { View, Card, Button, Text } from 'react-native-ui-lib';

<Card flex>
  <Card.Section
    content={[
      { text: 'You're Invited!', text70: true, dark10: true },
      { text: 'Join us for a day of fun', text90: true, dark50: true },
    ]}
  />
  <Card.Section
    content={[
      { text: 'RSVP', text80: true, primary: true },
    ]}
  />
</Card>
```

**何时使用：**
- 企业规模的应用
- 需要经过验证的组件
- 认可 Modifiers 思路
- 性能要求高

**官网：** https://wix.github.io/react-native-ui-lib/

---

## 工具型库

### React Native Reusables

**最适合：** 无样式组件、最大灵活性

**优点：**
- 无预设样式（完全可控）
- 默认即可访问
- TypeScript 优先
- 包体积小
- 可组合

**缺点：**
- 所有样式都要自己写
- 前期工作量更大
- 社区较小

**何时使用：**
- 自建设计系统
- 需要完全控制
- 无障碍优先
- 不想用库自带样式

**官网：** https://rnr-docs.vercel.app/

---

### Gluestack UI

**最适合：** 无样式组件 + 工具类 props

**优点：**
- 无样式 + 主题化变体
- 无障碍表现出色
- 通用（Web + 原生）
- 支持 TypeScript
- 现代开发体验

**缺点：**
- 相对较新
- 生态较小
- 示例较少

**安装：**
```bash
npm install @gluestack-ui/themed @gluestack-style/react
```

**何时使用：**
- 想要无样式组件
- 需要主题化灵活性
- 无障碍是关键
- 通用应用（Web + 原生）

**官网：** https://gluestack.io/

---

## 动画库

### React Native Reanimated

**最适合：** 复杂动画、60fps 性能

**优点：**
- 运行在原生线程
- 与手势集成
- 性能出色
- 开发活跃
- 行业标准

**缺点：**
- API 与 Animated 不同
- 有学习曲线
- 调试更困难

**安装：**
```bash
npm install react-native-reanimated react-native-gesture-handler
```

**用法：**
```typescript
import Animated, { useSharedValue, withSpring } from 'react-native-reanimated';

const width = useSharedValue(100);

<Animated.View style={{ width }} />

// Animate
width.value = withSpring(200);
```

**何时使用：**
- 需要平滑动画
- 手势驱动的 UI
- 性能要求高
- 遵循行业最佳实践

**官网：** https://docs.swmansion.com/react-native-reanimated/

---

### Moti

**最适合：** 声明式动画、快速写动画

**优点：**
- 构建在 Reanimated 之上
- 类似 Framer Motion 的 API
- 非常易用
- 适合简单动画

**缺点：**
- 是 Reanimated 的封装
- 复杂场景可控性较弱

**安装：**
```bash
npm install moti
```

**用法：**
```typescript
import { MotiView } from 'moti';

<MotiView
  from={{ opacity: 0, scale: 0.5 }}
  animate={{ opacity: 1, scale: 1 }}
  transition={{ type: 'timing', duration: 500 }}
/>
```

**何时使用：**
- 简单动画
- 有 Framer Motion 使用经验
- 快速开发
- 偏好声明式写法

**官网：** https://moti.fyi/

---

## 表单库

### React Hook Form

**最适合：** 复杂表单、表单校验

**优点：**
- 性能出色（非受控）
- 支持 TypeScript
- 校验集成（Zod、Yup）
- 包体积小
- Web + 原生

**缺点：**
- 非受控范式
- 有学习曲线

**安装：**
```bash
npm install react-hook-form
```

**用法：**
```typescript
import { useForm, Controller } from 'react-hook-form';

const { control, handleSubmit } = useForm();

<Controller
  control={control}
  name="email"
  rules={{ required: true }}
  render={({ field: { onChange, value } }) => (
    <TextInput
      value={value}
      onChangeText={onChange}
      placeholder="Email"
    />
  )}
/>
```

**何时使用：**
- 复杂表单
- 需要校验
- 性能要求高
- TypeScript 项目

**官网：** https://react-hook-form.com/

---

### Formik

**最适合：** 传统表单处理

**优点：**
- 易于上手
- 受控组件
- 文档完善
- 社区大

**缺点：**
- 重渲染多于 RHF
- 包体积更大
- 不够现代

**何时使用：**
- 简单表单
- 偏好受控组件
- 团队已有 Formik 经验

**官网：** https://formik.org/

---

## 图标库

### React Native Vector Icons

**最适合：** 常规图标需求

**优点：**
- 3000+ 图标
- 多个图标字族
- 易于使用
- 可定制

**安装：**
```bash
npm install react-native-vector-icons
```

**用法：**
```typescript
import Icon from 'react-native-vector-icons/MaterialIcons';

<Icon name="home" size={30} color="#000" />
```

**官网：** https://github.com/oblador/react-native-vector-icons

---

### Lucide React Native

**最适合：** 现代、一致的图标

**优点：**
- 设计美观一致
- 可 tree-shake
- 支持 TypeScript
- 持续更新

**安装：**
```bash
npm install lucide-react-native
```

**用法：**
```typescript
import { Home, User, Settings } from 'lucide-react-native';

<Home color="black" size={24} />
```

**官网：** https://lucide.dev/

---

## 库对照矩阵

| 库 | 包体积 | 学习曲线 | 可定制性 | 平台 | 维护状态 |
|---------|-------------|----------------|---------------|----------|-------------|
| **React Native Paper** | 中 | 低 | 中 | Android 优先 | 活跃 |
| **React Native Elements** | 小 | 低 | 高 | 跨平台 | 活跃 |
| **NativeBase** | 大 | 中 | 中 | 跨平台 | 活跃 |
| **Tamagui** | 小* | 高 | 高 | 通用 | 活跃 |
| **UI Lib** | 中 | 中 | 中 | 跨平台 | 活跃 |
| **Reusables** | 极小 | 低 | 最大 | 跨平台 | 活跃 |
| **Gluestack** | 小 | 中 | 高 | 通用 | 活跃 |

*开启优化后

## 选型指南

### 按项目类型选

**MVP / 原型：**
- NativeBase（开发最快）
- React Native Paper（Material Design）
- React Native Elements（灵活）

**生产应用：**
- Tamagui（性能 + 通用）
- UI Lib（经过生产验证）
- 用 Reusables 自建（完全可控）

**以 Android 为主：**
- React Native Paper（Material Design 3）
- NativeBase（支持 Material）

**以 iOS 为主：**
- 自建组件（符合 HIG）
- React Native Elements（可定制）

**双端一致：**
- React Native Elements
- NativeBase
- 自建共享组件

**Web + 原生：**
- Tamagui（通用支持最好）
- Gluestack UI
- NativeBase

### 按团队情况选

**小团队：**
- NativeBase（现成组件）
- React Native Paper（组件全面）

**大团队：**
- UI Lib（企业级验证）
- 自建设计系统

**设计主导：**
- Reusables（无样式）
- Tamagui（灵活）
- 自建组件

## 组合使用多个库

可以同时使用多个库：

```typescript
// Common combinations:

// 1. UI Kit + Animation
import { Button } from 'react-native-paper';
import Animated from 'react-native-reanimated';

// 2. Headless + Icons
import { Dialog } from '@gluestack-ui/themed';
import { X } from 'lucide-react-native';

// 3. Forms + UI
import { Controller } from 'react-hook-form';
import { TextInput } from 'react-native-paper';
```

**最佳实践：**
- 只用一个主 UI 库
- 加一个动画库（Reanimated）
- 按需加表单库（RHF）
- 加一个图标库
- 避免混用功能重叠的 UI 库

## 安装最佳实践

### 对等依赖

始终检查对等依赖：
```bash
npm info react-native-paper peerDependencies
```

### 原生模块链接

部分库需要原生链接：
```bash
npx pod-install ios  # iOS
```

### Metro 配置

部分库需要配置 Metro：
```javascript
// metro.config.js
module.exports = {
  transformer: {
    // Enable experimental features if needed
  },
};
```

## 性能建议

### Tree Shaking

只导入需要的部分：
```typescript
// ❌ BAD: Imports everything
import * as RNE from '@rneui/themed';

// ✅ GOOD: Tree-shakeable
import { Button } from '@rneui/themed';
```

### 代码分割

重量级组件懒加载：
```typescript
const HeavyChart = lazy(() => import('./HeavyChart'));
```

### 包体积分析

分析库的影响：
```bash
npx react-native-bundle-visualizer
```

## 迁移策略

### 从无库到有库

1. 从新页面开始
2. 封装包装组件
3. 逐步迁移旧页面
4. 移除旧样式

### 在两个库之间迁移

1. 盘点组件使用情况
2. 建立组件映射（旧 → 新）
3. 建兼容层
4. 增量迁移
5. 移除旧库

## 结论

**2026 年推荐：**

1. **通用场景：** React Native Elements 或 Tamagui
2. **Material Design：** React Native Paper
3. **最大控制力：** Gluestack UI 或 Reusables
4. **性能关键：** Tamagui
5. **企业级：** UI Lib
6. **快速开发：** NativeBase

从简单开始，按需增长。不要用不需要的库过度工程化。
