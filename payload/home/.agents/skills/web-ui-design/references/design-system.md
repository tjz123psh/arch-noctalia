# 设计系统：Token、主题与组件库架构

用于建立或重构 token 层级、明暗与多品牌主题、组件库 API，以及设计工具到代码的同步管线。一次性页面布局和单个组件的样式细节不要走本篇（前者看 `layout.md`，后者看 `components.md`）；色彩与排版的价值取向见 `visual.md`。

## Token 层级

三层，逐层引用，组件只消费最上层需要的那一层：

```
Layer 1  Primitive（裸值）      blue-500: #3b82f6   space-4: 1rem
Layer 2  Semantic（角色）       accent-default → blue-500   surface-elevated
Layer 3  Component（局部）      button-bg → accent-default  card-border
```

- 改一次 Layer 2，所有组件跟随；换主题只需重映射 Layer 2，不动组件代码。
- 完整系统在四层上展开：品牌层（primary/secondary/accent，各带 50–950 全色阶）、中性层（文字/背景/边框/表面）、语义层（success/warning/error/info，每个再拆 background/foreground/border/icon）、扩展层（数据可视化色阶、插画色、渐变定义）。深色映射从一开始就设计，不事后补。
- 组件内不出现裸 hex/RGB；确需绕过时写明理由。

### 命名约定

结构 `[category]-[property]-[variant]-[state]`，例：`color-text-primary`、`color-border-input-focus`、`spacing-component-padding`、`typography-heading-lg`。

1. kebab-case，不用 camelCase 混写
2. 描述用途而非外形：`button-padding-horizontal` 优于 `btn-px`
3. 语义名优先：`danger` 优于 `red`
4. 带刻度：`spacing-4` / `font-size-lg`
5. 状态后缀：`-hover` `-focus` `-active` `-disabled`

### 定义与输出

```json
{
  "color": { "primitive": { "gray": { "50": { "value": "#fafafa" },
    "900": { "value": "#171717" } }, "blue": { "500": { "value": "#3b82f6" } } } },
  "semantic": { "light": {
    "background": { "default": { "value": "{color.primitive.gray.0}" } },
    "foreground": { "default": { "value": "{color.primitive.gray.900}" },
                    "muted": { "value": "{color.primitive.gray.600}" } },
    "border": { "default": { "value": "{color.primitive.gray.200}" } } } }
}
```

值用 `{a.b.c}` 引用而非复制，引用关系就是换主题的接口。

```css
:root {
  /* Primitives */
  --color-gray-50: #fafafa;
  --color-gray-900: #171717;
  --color-blue-500: #3b82f6;

  /* Semantic — light */
  --background-default: var(--color-white);
  --foreground-default: var(--color-gray-900);
  --foreground-muted: var(--color-gray-600);
  --border-default: var(--color-gray-200);
  --accent-default: var(--color-blue-500);
}
[data-theme="dark"] {
  --background-default: var(--color-gray-950);
  --foreground-default: var(--color-gray-50);
  --foreground-muted: var(--color-gray-400);
  --border-default: var(--color-gray-800);
  --accent-default: var(--color-blue-400);
}
```

暗色不是取反：语义名保持同一套，只换指向的 primitive；对比度按 `visual.md` 的阈值在同一命名下重新验证。

## 主题架构

```css
:root {
  color-scheme: light dark;
  --duration-fast: 150ms;  --ease-default: cubic-bezier(0.4, 0, 0.2, 1);
  --z-dropdown: 100; --z-sticky: 200; --z-modal: 300; --z-popover: 400; --z-tooltip: 500;
}
```

主题属性挂在根元素（`data-theme="light|dark"` 或 class），而不是靠组件树传值；同时写 `root.style.colorScheme`，让表单控件、滚动条等原生部件跟随。

实现要点：

- **选择优先于系统**：用户显式选过就用用户值，否则跟随 `prefers-color-scheme`，并监听其 `change` 实时更新。
- **持久化**：存 localStorage；读不到再回退 `system`。
- **首屏闪烁（FOUC）**：在 `<head>` 里放一段内联脚本，在首次绘制前读出选择并写入根元素属性；脚本内容为可信静态字符串，动态来源必须先净化。
- **切换瞬间抑制过渡**：切主题前后临时注入 `*{transition:none!important}` 并强制一次重排，避免所有元素一起淡变。
- **主题切换控件**：提供 light / dark / system 三态与 `aria-label`，当前态要有视觉标记，不要只靠图标形状。
- **多品牌**：品牌层用 `[data-brand="..."]` 覆盖品牌色阶、字体角色与圆角/阴影基调；语义层和组件层不动，保证组件在所有品牌下可用。品牌之间差异应落在色、字、形状基调上，而不是换一套 token 名字体系。
- **降级模式**：`prefers-reduced-motion: reduce` 把时长 token 归零并压掉动画；`prefers-contrast: high` 收紧文字/边框对比；`forced-colors: active` 下给关键控件补边框（`border: 2px solid currentColor`）与下划线，不依赖颜色。

React 侧的最小实现：一个 context 提供 `theme` / `resolvedTheme` / `setTheme` / `toggleTheme`，effect 负责解析 system、写根元素属性与 `color-scheme`、订阅媒体查询；`useTheme` 在 provider 外抛错而不是返回 undefined。SSR 场景避免在服务端渲染出与客户端不一致的主题属性（`suppressHydrationWarning` 或用内联脚本定稿）。

## 组件架构

- **Compound components**：根组件持有隐式状态（context），`Item`/`Trigger`/`Content` 消费它；导出用 `Object.assign(Root, { Item, Trigger, Content })`。适合 Accordion、Tabs、Menu 这类"结构由使用方拼装"的组件。context 缺失时抛错，不要静默降级。
- **Polymorphic（`as` prop）**：用 `AsProp<C>` + `Omit<React.ComponentPropsWithoutRef<C>, ...>` + `forwardRef` 保留类型与 ref 透传；渲染成 `a`/`Link` 时行为与样式都不变。
- **Slot / `asChild`**：用 `@radix-ui/react-slot` 把样式与 props 合并到子元素上，让链接穿上按钮的外观而不嵌套 `<a><button>`。
- **Headless hooks**：行为与样式分离。受控/非受控双模式（`pressed` 传入即为受控，否则用内部 state）；返回 `{ pressed, toggle, buttonProps }` 这类可直接展开的 props，并内建 `role`、`aria-*` 与方向键/Home/End 键盘处理。
- **Variant 系统（CVA）**：`cva(base, { variants, compoundVariants, defaultVariants })` 给出类型安全的 variant / size 组合；`compoundVariants` 处理组合特例，不写条件 className 拼接。
- **响应式 variant**：容器或组件的尺寸档位用 `ResponsiveValue<T>`（`{ base, sm, md, lg }`）映射到断点 class，避免在组件里散落 `md:` 前缀判断。
- **组合方式**：数据列表用 render props（`renderItem` / `renderEmpty` / `keyExtractor`）；需要读取内部状态时用 children-as-function。两者都不引入额外的状态层。

组件 API 纪律：优先组合而非配置爆炸；受控与非受控都要支持；始终 forwardRef；未知 props 透传；给合理默认值；显式类型；variant 组合要可枚举（Storybook 或等价文档）；把键盘与读屏当接口的一部分测试。

## Token 管线与治理

Style Dictionary 配置把同一份 token 源编到多平台：

```javascript
module.exports = {
  source: ["tokens/**/*.json"],
  platforms: {
    css:    { transformGroup: "css",        buildPath: "dist/css/",
              files: [{ destination: "variables.css", format: "css/variables",
                        options: { outputReferences: true } }] },
    scss:   { transformGroup: "scss",       buildPath: "dist/scss/",
              files: [{ destination: "_variables.scss", format: "scss/variables" }] },
    ios:    { transformGroup: "ios-swift",  buildPath: "dist/ios/",
              files: [{ destination: "DesignTokens.swift", format: "ios-swift/class.swift",
                        className: "DesignTokens" }] },
    android:{ transformGroup: "android",    buildPath: "dist/android/",
              files: [{ destination: "colors.xml", format: "android/colors" }] },
  },
};
```

`outputReferences: true` 保留引用关系，生成物里仍是变量指向变量；自定义 transform（如 px→rem）注册后复用。

治理：

1. 变更按 API 变更对待——提案、设计与工程评审、跨平台验证、通知使用方、标记弃用、过渡期后删除
2. 弃用写进 token 本身：`deprecated: true` + `deprecatedMessage` + `replacedBy`，而不是只发公告
3. 自动化校验：对比度是否满足阈值、引用是否存在、有无循环引用、命名是否符合约定；CI 里跑，别靠人眼
4. 设计工具（Penpot 等）到代码的同步放进 CI，token 变更触发构建与视觉回归

常见问题与对应动作：token 泛滥（补层级，不是继续加名字）；命名混用（统一 kebab-case 与语义名）；缺暗色映射（每个语义 token 都要有暗色指向）；硬编码（组件里出现裸值就回填 token）；循环引用（校验期拦下）；平台缺口（同一 token 源必须给所有目标平台产出，不能只在 Web 上有值）。
