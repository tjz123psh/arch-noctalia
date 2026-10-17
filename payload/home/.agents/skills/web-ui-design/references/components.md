# 组件与 React 实现

组件设计原则、状态覆盖、常见组件模式、表单、加载与空状态，以及 React 架构（组件边界、hooks、状态归属、元框架边界、性能）。

## 组件设计原则

1. **单一职责** — 一个组件做好一件事
2. **组合优于配置** — 优先 `children` 与复合组件，而非 prop 开关堆叠
3. **默认受控** — 父级持有状态，组件通过回调上报变化
4. **默认可访问** — 键盘、屏幕阅读器、焦点内建
5. **token 化样式** — 用设计 token，不写硬编码值
6. **转发 ref** — 包装原生元素的 UI 组件要 `forwardRef`

**清晰优于炫技**；**一致优于新奇**（偏离既有模式要有理由）；**内容驱动布局**（结构跟随信息层次，而非装饰）；**服务端取数，客户端交互**。

## 状态覆盖

每个交互组件都要定义它**适用**的状态：

| 状态 | 视觉 | 必须 |
|-------|--------|----------|
| Default/Rest | 常规外观 | 是 |
| Hover | 轻微背景/边框变化（≤200ms 反馈） | 是 |
| Focus | 可见焦点环（≥2px，对比 ≥3:1） | 是 |
| Active/Pressed | 轻微下沉或颜色变化 | 是 |
| Disabled | 降低不透明度（0.5）、`cursor: not-allowed` | 适用时 |
| Loading | spinner 或骨架替换内容 | 适用时 |
| Error | 红色边框/文字 + 错误消息 | 适用时 |
| Selected | 强调背景或对勾 | 适用时 |

当产品有数据、异步、提交、网络或权限语义时，额外定义 loading / error / success / empty / offline / 无权限态。**状态必须反映真实产品行为**，不要机械地给静态控件补骨架屏、绿色成功或离线文案。

## 常见组件模式

### 按钮

| 变体 | 用于 |
|---------|---------|
| Primary（实心） | 每个可见区域一个主操作 |
| Secondary（描边） | 辅助操作 |
| Ghost/Tertiary | 低强调、行内操作 |
| Destructive | 删除、移除、不可逆操作 |
| Icon-only | 工具栏、紧凑空间（必须 `aria-label`） |

规则：每个可见区域只一个主按钮；按钮文案用动词——"保存""删除""创建项目"，不用 "OK""提交"；破坏性按钮用危险色并远离安全操作；禁用按钮要说明原因（tooltip 或邻近文字）；最小宽度 80px，最小高度 36px（触摸 44px）。

### 表单输入

```
┌─────────────────────────┐
│ Label                   │  ← 始终可见，位于输入框上方
│ ┌─────────────────────┐ │
│ │ Placeholder...      │ │  ← 占位符不是标签
│ └─────────────────────┘ │
│ Helper text             │  ← 可选引导
│ Error message           │  ← 出错时替换 helper
└─────────────────────────┘
```

- 每个输入都有可见 `<label>`（JSX 用 `htmlFor`，不是 `for`）
- 占位符聚焦即消失，绝不能当唯一标签
- 错误消息说清错在哪、怎么改；错误放字段下方，不用 tooltip（触摸/键盘不可达）
- 相关字段视觉分组；标记必填项（星号或 "(required)"），若多数必填则改标可选项
- 优先受控输入；复杂表单用表单库
- 可能时用 server action / route action 提交

### 模态 / 对话框

- 用原生 `<dialog>` 或 headless 库（Radix、Ark UI、React Aria）
- 打开时焦点锁在内部；`Esc` 关闭；关闭后焦点回到触发元素
- 背板阻断页面其余交互；最大宽 90vw 或 600px，最大高 85vh 并可滚动
- 有标题栏与关闭按钮；操作用于底部（主操作在右，取消在左）
- 开关状态放在最近的父组件，不放全局

### 下拉 / 选择

- 触发器有 `aria-expanded`；方向键在选项间导航；`Esc` 关闭且不选择
- 选中项用对勾或高亮标识；最多可见 8–10 项后滚动；支持输入首字母跳转

### Toast / 通知

| 类型 | 时长 | 可关闭 |
|------|----------|-------------|
| 成功 | 3–5 秒 | 自动消失 |
| 信息 | 5–8 秒 | 自动 + 手动 |
| 警告 | 常驻 | 手动 |
| 错误 | 常驻 | 手动 |

右下或右上堆叠，最多同时 3 条；非紧急用 `aria-live="polite"`，错误用 `"assertive"`；适用时带操作（"撤销""查看""重试"）；不阻断页面交互。

### 卡片

```
┌─────────────────────────────┐
│ [图片/媒体]                  │  ← 可选
├─────────────────────────────┤
│ 标题                         │
│ 可能跨多行的描述……            │
│ 元数据 / 标签                 │
├─────────────────────────────┤
│ [操作]                       │  ← 可选页脚
└─────────────────────────────┘
```

整卡可点时用 `<a>` 或 `<article>` 内嵌链接；网格内卡片高度一致（`min-height` 或 flex）；长描述可截断并给"展开"；内边距与其他组件一致。**卡片准入测试**（见 SKILL.md 判断段）：去掉圆角、阴影、背景后关系仍更清楚就不要卡片。

### 表格

表头滚动时 sticky；可排序列显示排序指示（箭头）；数值列右对齐；用斑马纹或行边框提高可扫视性；行操作用内联图标按钮或选中 + 工具栏；窄屏横向滚动或转卡片；空态给出说明和操作，不是空表格。

## 表单校验时机

| 时机 | 用在哪 | 原因 |
|---|---|---|
| onBlur | 邮箱、URL、电话等格式校验 | 用户已结束输入，不打断思维 |
| onSubmit | 必填字段首次检查 | 用户还没到这些字段 |
| onChange + debounce | 密码强度、用户名可用性 | 用户主动寻求反馈 |
| onChange | 密码确认匹配等依赖字段 | 需要实时确认 |

核心规则：

1. 首次交互 → onBlur，让用户完成输入
2. 字段已有错误 → 切到 onChange，修正时给即时确认
3. 提交时 → 校验全部字段，焦点移到第一个错误
4. 异步校验 → 300–500ms debounce + `AbortController` 取消旧请求，并有 loading 指示
5. 未触达字段 → 提交时才校验，不要提前闪错误
6. 粘贴 → `InputEvent.inputType === "insertFromPaste"` 时延迟到 blur

### 表单类型与布局

| 类型 | 布局 | 校验策略 | 典型字段数 |
|---|---|---|---|
| 登录 | 单列，2–3 字段 | 提交时校验 | 2–3 |
| 注册 | 单列分组 | onBlur + 提交 | 5–8 |
| 结账 | 多步向导 | 每步 onBlur + 步提交 | 10–20 |
| 配置/设置 | 分组 + 折叠面板 | 即时（onChange 内联） | 8–30 |
| 搜索/筛选 | 行内紧凑 | 300ms debounce | 2–8 |
| 调查/反馈 | 单列，多选择控件 | 每页提交 | 5–15 |
| 长表单 | 分组 + 进度指示 | 每段 onBlur | 15+ |

### 错误消息分发

| 错误类型 | 位置 | 说明 |
|---|---|---|
| 字段内联 | 字段下方 | 基础位置，关联 `aria-describedby` |
| 摘要顶部 | 表单上方 | 长表单（>6 字段）必须；每项锚链接到字段 |
| 全局横幅 | 表单上方 | 仅系统级错误（网络中断、服务端错误） |

字段状态 token 示例：

```json
{
  "error":   { "border": "red-500", "bg": "red-50",  "text": "red-700" },
  "warning": { "border": "amber-500", "bg": "amber-50", "text": "amber-700" },
  "success": { "border": "green-500", "bg": "green-50", "text": "green-700" },
  "neutral": { "border": "gray-300", "bg": "white",   "text": "gray-900" }
}
```

| 错误写法 | 友好写法 |
|---|---|
| "Invalid input" | "邮箱需要包含 @" |
| "You entered an invalid date" | "请使用格式 MM/DD/YYYY" |
| "Error" | "密码至少需要 8 个字符" |
| "Required field" | "请填写您的姓名" |

表单无障碍要求（详见 `accessibility.md`）：`aria-invalid="true"` 标记失败字段；`aria-describedby` 指向错误消息；错误出现用 `role="alert"` 即时播报，非关键反馈用 `role="status"`；错误文本对比度 ≥4.5:1；颜色不是唯一提示；提交失败后焦点移到第一个错误字段。

表单反模式：禁用提交按钮直到"合法"；每次按键都校验；用 tooltip 报错；只有红框没有文字；出错清空表单；校验摘要作为唯一提示；用 `alert()` 报错；异步校验无 loading；提交按钮写 "Submit"。

## 加载与空状态

| 模式 | 何时用 | React 做法 |
|---------|----------|----------------|
| 骨架 | 布局已知，用内容替换 | `<Suspense fallback={<Skeleton />}>` |
| Spinner | 布局未知，短暂等待（<3s） | `<Suspense fallback={<Spinner />}>` |
| 进度条 | 时长或百分比已知 | 受控组件 + 进度状态 |
| 行内 spinner | 特定元素内加载 | `useTransition` / `isPending` |
| 乐观 UI | 操作大概率成功 | `useOptimistic` 或查询库的乐观更新 |

- 始终展示加载态，不要让用户盯着空白
- 优先 `<Suspense>` 边界而非手写 `isLoading`；边界放在能独立加载的最小单元外
- 非紧急更新用 `useTransition` 保持界面响应

每个列表/表格/视图都需要空态：

```
┌─────────────────────────┐
│       [插画]            │  ← 可选
│  还没有项目              │  ← 清晰标题
│  创建第一个项目开始使用。 │  ← 有帮助的说明
│  [创建项目]              │  ← 主操作
└─────────────────────────┘
```

## React 架构

### 组件层次

| 层 | 服务端/客户端 | 持有状态 | 取数 |
|-------|-----------------|------------|--------------|
| Route/Page | 服务端（loader/RSC） | 否 | 是 |
| Feature | 客户端（通常） | 是 | 否（经 props/context 传入） |
| UI | 皆可 | 否（受控） | 否 |

尺寸建议：UI 组件 <80 行，Feature 组件 <150 行，>200 行就拆子组件或抽 hook；一个组件一个文件（紧耦合的复合组件例外）。

### Props 设计

```tsx
// 好：最小、可组合
type ButtonProps = {
  variant: "primary" | "secondary" | "ghost" | "destructive"
  size: "sm" | "md" | "lg"
  children: React.ReactNode
  disabled?: boolean
  onClick?: () => void
}

// 差：布尔 prop 泛滥
type ButtonProps = {
  isPrimary?: boolean; isSecondary?: boolean
  isSmall?: boolean; isLarge?: boolean
  label: string  // ← 用 children
}
```

用可辨识联合代替布尔标志；`children` 承载内容，需要 JSX 灵活性时不设 `label`/`text` 字符串 prop；可选 prop 要有合理默认；每组件约 7 个 prop 以内，更多说明该组合了。包装原生元素的 UI 组件要转发 ref：

```tsx
const Input = React.forwardRef<HTMLInputElement, InputProps>(
  ({ className, ...props }, ref) => (
    <input ref={ref} className={cn("...", className)} {...props} />
  )
)
```

### 组合

```tsx
// 好：可组合                  // 差：配置对象
<Card>                         <Card
  <CardHeader>                   title="Title"
    <CardTitle>Title</CardTitle> body="Body"
  </CardHeader>                  footer={<Actions />}
  <CardContent>Body</CardContent> />
</Card>
```

复合组件（`Tabs.List` / `Tabs.Trigger`）用于总是一起工作的关联组件；render props / slots 用于父级需要控制子级渲染方式的场景（如 `renderEmpty`）。

### Hooks 与副作用纪律

| 需求 | 用什么 | 不用 |
|------|-----|-----|
| 从 props/state 派生 | 渲染期计算 | `useEffect` + `setState` |
| 响应用户事件 | 事件处理器 | `useEffect` |
| 与外部系统同步 | `useEffect` + cleanup | 发起后不管的 effect |
| 取数 | 元框架 loader / `useSuspenseQuery` | `useEffect` + `fetch` |
| 一次性初始化 | `useRef` + 惰性初始化 | `useEffect` 配 `[]` |

**规则：** 如果在 `useEffect` 里基于其他 state 设置 state，你多半不需要那个 effect。自定义 hook：以 `use` 开头、一个 hook 一个关注点、1–2 个返回值用元组否则用对象、hook 里不写 JSX。

### 状态归属

```
这个 state 放在哪？
├─ URL / 路由参数        → URL state（useParams、searchParams）
├─ 服务端数据            → 服务端状态（TanStack Query、loader）
├─ 单个组件              → useState / useReducer
├─ 父 + 子               → 提到父级，用 props 传
├─ 同功能的远距离组件     → Context（限定在该功能内）
├─ 真正全局（主题、认证） → 应用根 Context 或全局 store
└─ 表单状态              → 表单库或 useActionState
```

规则：URL 是最好的全局状态（可分享、可收藏、后退可用）；服务端数据属于缓存而不是组件 state；Context 用于依赖注入（主题、i18n），不是通用 store；除非确实需要，不要引入 Redux/Zustand。

### 元框架约定（TanStack Start / Next.js / Remix 通用）

| 关注点 | 放哪 |
|---------|------|
| 取数 | 路由 loader / 服务端组件 |
| 变更 | server action / route action |
| 导航 | 框架 `<Link>`，不用 `<a>` |
| Head/meta | 框架的 head 管理 |
| 鉴权守卫 | 路由中间件 / layout loader |
| 错误处理 | 路由错误边界 |
| 代码分割 | 按路由（自动） |

| 服务端（默认） | 客户端（`"use client"` / islands） |
|-------------------|----------------------------------|
| 取数、数据库查询 | 事件处理器（onClick、onChange） |
| 鉴权检查、重定向 | 浏览器 API（localStorage 等） |
| HTML 生成、SEO | 挂载后才变化的状态 |
| 元数据 | 只能在客户端跑的第三方库 |

**规则：** 一切从服务端开始，需要交互时才加 `"use client"`，并把客户端边界尽量下推。

### 性能

| 模式 | 何时 |
|---------|------|
| `React.lazy` + `Suspense` | 首屏不需要的重组件 |
| `useMemo` | 输入相同的昂贵计算 |
| `useCallback` | 给子组件 `memo` 或 effect 依赖提供稳定引用 |
| `React.memo` | 组件频繁重渲染且 props 不变 |
| 虚拟化 | 列表 >50 项 |
| 图片优化 | 框架 `<Image>` + 懒加载 |

**规则：** 不要默认 memo 化，先测量再优化。

### React 反模式

| 反模式 | 修复 |
|-------------|-----|
| Prop 钻取超过 3 层 | Context 或组合（传组件而非传数据） |
| 用 `useEffect` 派生状态 | 渲染期计算 |
| 用 `useEffect` 取数 | 元框架 loader 或 TanStack Query |
| 巨型上帝组件 | 拆成 feature + UI 组件 |
| 字符串 ref / `findDOMNode` | `useRef` + `forwardRef` |
| 动态列表用索引作 key | 稳定的唯一 ID |
| JSX 内联对象/数组字面量 | 提取为常量或按需 `useMemo` |
| props 里用 `any` | 正确的泛型类型 |
| 把服务端数据复制进 state | 以查询/loader 缓存为准 |

## 设计评审清单

写或评审前端代码时逐条核对：

- [ ] **层次**：最重要的内容/操作是否视觉主导？
- [ ] **一致性**：相似元素外观与行为是否一致？
- [ ] **间距**：间距是否系统化（不是随意像素值）？
- [ ] **对比度**：文字/背景组合是否满足 WCAG AA（4.5:1）？
- [ ] **交互状态**：可点元素是否有 hover、focus、active、disabled？
- [ ] **响应式**：移动、平板、桌面宽度下是否都成立？
- [ ] **键盘**：所有交互元素是否可到达并可操作？
- [ ] **加载态**：空/加载/错误态是否设计过，而不只是顺利路径？
- [ ] **点击目标**：移动端是否至少 44×44px？
- [ ] **内容溢出**：长文本、缺图、边界数据下布局是否成立？

React 追加项：组件边界是否单一关注点；props 是否最小且类型良好、没有布尔泛滥；是否用 `children`/render props 而非巨型配置对象；effect 是否必要（派生状态/事件处理器能否替代）；列表 key 是否稳定有意义；memo 化是否只在测量后使用；取数是否在服务端、客户端 JS 是否最小；异步/可能失败的区域是否有错误边界；加载态是否用 Suspense 处理。

## 前端反模式

| 反模式 | 问题 | 修复 |
|-------------|---------|-----|
| 魔法数字 | `margin: 13px` 破坏系统 | 用间距 token |
| 硬编码颜色 | 到处 `#3b82f6` | 用语义色 token |
| 仅 hover 可供性 | 键盘/触摸用户看不到 | 始终显示可供性，hover 只做增强 |
| 固定尺寸 | 换内容/屏幕就坏 | 用 min/max + 流体尺寸 |
| z-index 军备竞赛 | 飙升到 `z-index: 9999` | 用分层体系（base、dropdown、modal、toast） |
| 截断且无法访问 | `text-overflow: ellipsis` 藏内容 | 加 tooltip 或展开机制 |
