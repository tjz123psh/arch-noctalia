# 布局与响应式

先定阅读路径与内容关系（见 SKILL.md 第 1 段），再用这里的 CSS 工具实现。内容覆盖：布局模型与间距系统、断点策略、流体布局、容器查询、响应式组件模式、打印与偏好查询。

## 布局模型

### 何时用哪个

| 模型 | 何时用 | 避免 |
|-------|----------|------------|
| Flexbox | 一维对齐（行或列） | 复杂二维网格 |
| Grid | 二维布局、页面骨架 | 简单线性堆叠 |
| Stack（flex column） | 元素的垂直列表 | 并排元素 |
| Cluster（flex row wrap） | 标签、徽标、行内组 | 严格网格对齐 |

### 页面骨架

```
标准页:
┌──────────────────────────────────┐
│ Header / Nav                     │
├────────┬─────────────────────────┤
│ Sidebar│ Main Content            │
│        │                         │
│        │                         │
├────────┴─────────────────────────┤
│ Footer                           │
└──────────────────────────────────┘

内容聚焦页:
┌──────────────────────────────────┐
│ Header                           │
├──────────────────────────────────┤
│     ┌────────────────────┐       │
│     │ Constrained Content│       │
│     │ (max-width: 65ch)  │       │
│     └────────────────────┘       │
├──────────────────────────────────┤
│ Footer                           │
└──────────────────────────────────┘
```

## 间距系统

### 基准单位

选 4px 或 8px 为基准，所有间距由它派生。

| Scale | 4px 基准 | 8px 基准 | 常见用途 |
|-------|---------|----------|------------|
| 1 | 4px | 8px | 行内间隙、图标内边距 |
| 2 | 8px | 16px | 元素间距、输入框内边距 |
| 3 | 12px | 24px | 卡片内边距、组间距 |
| 4 | 16px | 32px | 区块间距 |
| 6 | 24px | 48px | 主要区块分隔 |
| 8 | 32px | 64px | 页面级区块 |
| 12 | 48px | 96px | Hero 区块 |

### 按用途区分间距类型

系统化时不要只有一个 `gap`，按用途命名：

- **Inset**：容器内边距。可等边，也可 squish（上下小左右大）/ stretch（反之）
- **Stack**：垂直堆叠元素间距
- **Inline**：行内水平间距
- **Grid gap**：网格/flex 项间距

相关项用小间距（sm/md），不同区块用大间距（lg/xl）；**组间距必须大于组内间距**（这是邻近律的落地）。

### 密度模式

同一系统三档，靠整体平移一档实现：**Compact**（每档减一级，数据密集视图）/ **Comfortable**（默认）/ **Spacious**（每档加一级，阅读型页面）。

### 间距规则

1. **相关元素间距更小** — 标签 + 输入框比表单组之间更紧
2. **不相关元素间距更大** — 不同区块要有清晰分隔
3. **嵌套减少间距** — 内层容器比外层更紧
4. **垂直节奏有意义** — 一致的垂直间距改善扫视

### Margin vs Gap vs Padding

| 属性 | 何时用 |
|----------|-------------|
| `gap` | flex/grid 子元素之间（优先） |
| `padding` | 容器内部间距 |
| `margin` | 兄弟元素之间（少用） |

**优先 `gap` 而非 margin** — 避免 margin 塌陷和首尾 margin 问题。

## 内容宽度

| 内容类型 | 最大宽度 | 原因 |
|-------------|-----------|--------|
| 正文 | 60-75ch | 最佳行长 |
| 表单 | 400-600px | 防止输入框过宽 |
| 卡片网格 | 1200-1400px | 标准内容区 |
| 全出血 | 100% | Hero 图、背景 |
| 仪表盘 | 无上限（带侧栏） | 数据密度需要空间 |

## 对齐原则

1. **文本左对齐** — LTR 的自然阅读方向
2. **标题居中** — 仅用于 hero 或单行标题
3. **数字右对齐** — 表格中按小数位对齐
4. **对齐到网格** — 所有元素应吸附到间距网格
5. **减少对齐点** — 隐形线越少，布局越干净

## 布局组件（React）

优先可复用布局组件，而非重复 CSS 模式：

```tsx
// Stack: 子元素之间的垂直间距
<Stack gap="md">
  <Heading>Title</Heading>
  <Text>Description</Text>
  <Button>Action</Button>
</Stack>

// Cluster: 水平可换行分组
<Cluster gap="sm">
  <Badge>React</Badge>
  <Badge>TypeScript</Badge>
</Cluster>

// Container: 最大宽度 + 居中
<Container maxWidth="prose">
  <Article>{content}</Article>
</Container>
```

**规则：** 反复写 `display: flex; flex-direction: column; gap: ...` 就抽成 `<Stack>`；`<Cluster>`、`<Container>`、`<Grid>` 同理。

## 盒模型默认值

```css
/* 全局设置（CSS reset / 全局样式） */
*, *::before, *::after {
  box-sizing: border-box;
}
```

## 常见布局错误

| 错误 | 修复 |
|---------|-----|
| 嵌套滚动容器 | 每个视图一个可滚动区 |
| 内容贴边 | 容器始终留内边距 |
| 沟槽不一致 | 用间距 token，不用随机值 |
| 内容固定高度 | 用 min-height，让内容呼吸 |
| 移动端横向滚动 | 约束宽度，检查溢出 |

---

# 断点策略

断点关注内容需求而非设备尺寸。现代响应式用更少、由内容驱动的断点，配合流体技术。

## 移动优先

先写最小屏幕的样式，再为大屏渐进增强。

```css
/* 基准样式（移动优先） */
.component {
  display: flex;
  flex-direction: column;
  padding: 1rem;
}

/* 大屏增强 */
@media (min-width: 640px) {
  .component { flex-direction: row; padding: 1.5rem; }
}

@media (min-width: 1024px) {
  .component { padding: 2rem; }
}
```

好处：移动设备只加载必要的 CSS；特性是叠加而非删减；迫使先聚焦核心内容；层叠关系更简单。

## 常见断点刻度

```css
/* Tailwind 默认：sm 640 / md 768 / lg 1024 / xl 1280 / 2xl 1536 */
/* Bootstrap 5：sm 576 / md 768 / lg 992 / xl 1200 / xxl 1400 */

/* 极简三档 */
:root {
  --bp-md: 600px;
  --bp-lg: 1024px;
}
@media (min-width: 600px) { /* Medium */ }
@media (min-width: 1024px) { /* Large */ }
```

| 名称 | Min Width | 目标 |
|------|-----------|------|
| `sm` | 640px | 大屏手机（横屏） |
| `md` | 768px | 平板 |
| `lg` | 1024px | 小桌面 / 横屏平板 |
| `xl` | 1280px | 桌面 |
| `2xl` | 1536px | 大桌面 |

**规则：**

1. **内容决定断点** — 布局坏掉的位置就是断点，不是设备宽度
2. **用区间而非点** — 为断点之间设计，不只测断点本身
3. **最多 3-4 个断点** — 更多只增加维护负担
4. **测奇怪尺寸** — 900px、1100px、375px，而不只是断点边界
5. **断点也是 token** — 容器宽度与断点值一起进 token

```css
:root {
  --breakpoint-md: 768px;
  --container-lg: 1024px;
}
.container {
  width: 100%;
  max-width: var(--container-lg);
  margin-inline: auto;
  padding-inline: var(--space-4);
}
```

### 内容断点怎么找

```javascript
// 逐步改宽度，记录溢出位置
for (let width = 320; width <= 1920; width += 10) {
  element.style.width = `${width}px`;
  if (element.scrollWidth > element.clientWidth) {
    breakpoints.push({ width, issue: "overflow" });
  }
}
```

### 特性查询 @supports

```css
@supports (display: grid) {
  .layout { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); }
}

@supports (container-type: inline-size) {
  .card-container { container-type: inline-size; }
  @container (min-width: 400px) { .card { flex-direction: row; } }
}

/* 旧浏览器兜底 */
@supports not (gap: 1rem) {
  .flex-container > * + * { margin-left: 1rem; }
}

/* 特性 + 尺寸组合 */
@supports (display: grid) {
  @media (min-width: 768px) {
    .layout { display: grid; grid-template-columns: 250px 1fr; }
  }
}
```

## 响应式重构（不是等比缩放）

对每个宽度状态明确：什么必须持续可见；什么可以合并、移入抽屉或按需显示；比较关系如何保留；主操作如何保持可达；密度、导航与输入方式如何变化。

| 组件 | 窄屏 | 中屏 | 宽屏 |
|--------|--------|--------|--------|
| 导航 | 汉堡菜单或底部 tab（主 nv 最多 5 项，触发区 ≥44×44px） | 折叠顶部导航或横向滚动 | 横向顶部导航 + 下拉 |
| 侧栏 | 抽屉或独立页 | 可折叠（仅图标或抽屉） | 常驻侧栏 |
| 表格 | 每行卡片化，或只留优先列 | 横向滚动 + 首列 sticky | 完整表格 |

```
三列 → 两列 → 单列:
┌───┬───┬───┐     ┌───┬───┐     ┌───┐
│ 1 │ 2 │ 3 │     │ 1 │ 2 │     │ 1 │
└───┴───┴───┘     ├───┴───┤     ├───┤
                  │   3   │     │ 2 │
                  └───────┘     ├───┤
                                │ 3 │
                                └───┘
```

卡片网格优先用 `auto-fit` 而非逐档媒体查询：

```css
.cards {
  display: grid;
  gap: 1.5rem;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr));
}
```

窄屏表格转卡片：

```css
@media (max-width: 639px) {
  .responsive-table thead { display: none; }
  .responsive-table tr {
    display: block; margin-bottom: 1rem;
    border: 1px solid var(--border); border-radius: 0.5rem; padding: 1rem;
  }
  .responsive-table td {
    display: flex; justify-content: space-between;
    padding: 0.5rem 0; border: none;
  }
  .responsive-table td::before {
    content: attr(data-label); font-weight: 600;
  }
}
```

# 流体布局与排版

用相对单位和数学函数平滑缩放，减少媒体查询，尺度更自然。

```css
/* clamp(minimum, preferred, maximum) */
.heading { font-size: clamp(1.5rem, 5vw, 3rem); }
```

### 计算流体值

```css
/* 公式：clamp(min, base + scale * vw, max) */
/* 16px @320px 视口 → 24px @1200px 视口 */
/* slope = (24-16)/(1200-320) = 0.00909 */
/* y 轴截距 = 16 - 0.00909*320 = 13.09px = 0.818rem */
.text { font-size: clamp(1rem, 0.818rem + 0.909vw, 1.5rem); }
```

```javascript
function fluidType({ minFontSize, maxFontSize, minViewport = 320, maxViewport = 1200 }) {
  const minFontRem = minFontSize / 16, maxFontRem = maxFontSize / 16;
  const minViewportRem = minViewport / 16, maxViewportRem = maxViewport / 16;
  const slope = (maxFontRem - minFontRem) / (maxViewportRem - minViewportRem);
  const yAxisIntersection = minFontRem - slope * minViewportRem;
  return `clamp(${minFontRem}rem, ${yAxisIntersection.toFixed(4)}rem + ${(slope * 100).toFixed(4)}vw, ${maxFontRem}rem)`;
}
```

### 完整流体刻度

```css
:root {
  --text-xs:  clamp(0.75rem, 0.7rem + 0.25vw, 0.875rem);
  --text-sm:  clamp(0.875rem, 0.8rem + 0.375vw, 1rem);
  --text-base:clamp(1rem, 0.9rem + 0.5vw, 1.125rem);
  --text-lg:  clamp(1.125rem, 1rem + 0.625vw, 1.25rem);
  --text-xl:  clamp(1.25rem, 1.1rem + 0.75vw, 1.5rem);
  --text-2xl: clamp(1.5rem, 1.2rem + 1.5vw, 2rem);
  --text-3xl: clamp(1.875rem, 1.4rem + 2.375vw, 2.5rem);
  --text-4xl: clamp(2.25rem, 1.5rem + 3.75vw, 3.5rem);
  --text-5xl: clamp(3rem, 1.8rem + 6vw, 5rem);

  /* 行高反向缩放 */
  --leading-tight: 1.25;
  --leading-normal: 1.5;
  --leading-relaxed: 1.75;

  /* 流体间距 */
  --space-3xs:clamp(0.25rem, 0.2rem + 0.25vw, 0.375rem);
  --space-2xs:clamp(0.375rem, 0.3rem + 0.375vw, 0.5rem);
  --space-xs: clamp(0.5rem, 0.4rem + 0.5vw, 0.75rem);
  --space-sm: clamp(0.75rem, 0.6rem + 0.75vw, 1rem);
  --space-md: clamp(1rem, 0.8rem + 1vw, 1.5rem);
  --space-lg: clamp(1.5rem, 1.2rem + 1.5vw, 2rem);
  --space-xl: clamp(2rem, 1.5rem + 2.5vw, 3rem);
  --space-2xl:clamp(3rem, 2rem + 5vw, 5rem);
  --space-3xl:clamp(4rem, 2.5rem + 7.5vw, 8rem);

  /* 流体容器宽度 */
  --container-xs: min(100% - 2rem, 20rem);
  --container-md: min(100% - 2rem, 45rem);
  --container-lg: min(100% - 2rem, 65rem);
  --container-xl: min(100% - 3rem, 80rem);
}
```

**规则：** `clamp()` 必须同时给上下界；在 320px 与 2560px 极端值测试；正文不要用裸 `vw` 而不加 `clamp()`（会破坏缩放）。

### 流体网格与内在尺寸

```css
.auto-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 250px), 1fr)); gap: var(--space-md); }

/* 随容器变向的 switcher */
.switcher { display: flex; flex-wrap: wrap; gap: var(--space-md); }
.switcher > * { flex-grow: 1; flex-basis: calc((30rem - 100%) * 999); }

/* 可折叠侧栏 */
.with-sidebar { display: flex; flex-wrap: wrap; gap: var(--space-lg); }
.with-sidebar > :first-child { flex-basis: 300px; flex-grow: 1; }
.with-sidebar > :last-child { flex-basis: 0; flex-grow: 999; min-width: 60%; }

/* 内在尺寸 */
.button { width: fit-content; min-width: 8rem; padding-inline: var(--space-md); }
.modal { width: min(90vw, 600px); max-height: min(90vh, 800px); }
```

## 视口单位

```css
.full-height { min-height: 100dvh; }   /* 计移动浏览器 UI，推荐 */
.hero { min-height: 100svh; }          /* 最小视口 */
.backdrop { height: 100lvh; }          /* 最大视口 */
.fixed-nav { position: fixed; inset-inline: 0; top: 0; height: max(60px, 8vh); }

/* 刘海屏安全区 */
.safe-area {
  padding-top: env(safe-area-inset-top);
  padding-bottom: env(safe-area-inset-bottom);
}
```

移动端不要用 `100vh`（会顶出浏览器 UI 造成滚动），不要给 `body` 加 `overflow: hidden`（iOS 滚动异常）。

## 图片与媒体

```css
img { max-width: 100%; height: auto; }
.video-container { aspect-ratio: 16 / 9; width: 100%; }
```

```tsx
// 艺术指导：不同屏幕不同裁剪
<picture>
  <source media="(min-width: 1024px)" srcSet="/hero-wide.webp" type="image/webp" />
  <source media="(min-width: 768px)" srcSet="/hero-medium.webp" type="image/webp" />
  <source srcSet="/hero-mobile.webp" type="image/webp" />
  <img src="/hero-mobile.jpg" alt="Hero image description"
       className="w-full h-auto" loading="eager" fetchpriority="high" />
</picture>

// 分辨率切换
<img
  src={product.image}
  srcSet={`${product.image}?w=400 400w, ${product.image}?w=800 800w, ${product.image}?w=1200 1200w`}
  sizes="(max-width: 640px) 100vw, (max-width: 1024px) 50vw, 33vw"
  alt={product.name} className="w-full h-auto object-cover" loading="lazy" />
```

规则：用 `srcset` + `sizes` 分发合适分辨率；首屏外图片 `loading="lazy"`；**显式写 width/height 或 aspect-ratio 防 CLS**；用 `aspect-ratio` 做响应式容器。

## 触摸与输入

| 元素 | 最小 | 推荐 |
|-----------|----------|-------------|
| 点击目标 | 44×44px | 48×48px |
| 目标间距 | 8px | 12px |
| 输入框高度 | 44px | 48px |
| 按钮高度 | 44px | 48px |

规则：可见元素可以更小，只要点击区用 padding 扩展到 44px；主操作放移动端下半屏（拇指区）；触摸设备避免 hover 依赖的交互，补 `:active` 反馈。

## 打印与偏好查询

```css
@media print {
  .nav, .sidebar, .footer, .ads { display: none; }
  * { background: white !important; color: black !important; box-shadow: none !important; }
  h1, h2, h3 { page-break-after: avoid; }
  img, table { page-break-inside: avoid; }
  a[href^="http"]::after { content: " (" attr(href) ")"; font-size: 0.8em; }
}

@media (prefers-color-scheme: dark) { :root { --bg: #1a1a1a; --text: #f0f0f0; } }

@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}

@media (prefers-contrast: high) {
  :root { --text: #000; --bg: #fff; --border: #000; }
  .button { border: 2px solid currentColor; }
}

@media (prefers-reduced-data: reduce) {
  .hero-video { display: none; }
  .hero-image { display: block; }
}
```

---

# 容器查询

让组件响应父容器宽度而非视口，是真正可复用组件的基础。现代浏览器支持良好（Chrome 105+ / Firefox 110+ / Safari 16+），旧浏览器给降级。

## 基础

```css
/* 最常用：按行内尺寸建立包含上下文 */
.container { container-type: inline-size; }

/* 命名容器 */
.card-wrapper { container-type: inline-size; container-name: card; }
.card-wrapper { container: card / inline-size; }   /* 简写 */

@container card (min-width: 400px) { .card-content { display: flex; } }
```

## 查询语法

```css
@container (min-width: 300px) { }
@container (max-width: 500px) { }
@container (300px <= width <= 600px) { }        /* 区间 */
@container (min-width: 400px) and (max-width: 800px) { }
@container (max-width: 300px) or (min-width: 800px) { }
@container not (min-width: 400px) { }
```

## 容器查询单位

| 单位 | 含义 |
|---|---|
| `cqw` / `cqh` | 容器宽 / 高的 1% |
| `cqi` / `cqb` | 容器行内 / 块向尺寸的 1% |
| `cqmin` / `cqmax` | cqi 与 cqb 中较小 / 较大者 |

```css
.card-title { font-size: clamp(1rem, 4cqi, 2rem); }
.card-body { padding: clamp(0.75rem, 4cqi, 1.5rem); }
```

## 样式查询

按自定义属性值查询（支持仍有限）：

```css
.card { --layout: stack; }
@container style(--layout: stack) { .card-content { flex-direction: column; } }
@container style(--layout: inline) { .card-content { flex-direction: row; } }
.card.horizontal { --layout: inline; }
```

## 实用模式

```css
/* 响应式卡片 */
.card-container { container: card / inline-size; }
.card { display: flex; flex-direction: column; gap: 1rem; padding: clamp(1rem, 4cqi, 2rem); }
@container card (min-width: 400px) {
  .card { flex-direction: row; align-items: flex-start; }
  .card-image { width: 40%; aspect-ratio: 1; }
  .card-content { flex: 1; }
}
@container card (min-width: 600px) {
  .card-image { width: 250px; }
  .card-title { font-size: 1.5rem; }
  .card-actions { display: flex; gap: 0.5rem; }
}

/* 仪表盘 widget：按自身宽度调整图表高度与列数 */
.widget-container { container: widget / inline-size; }
@container widget (min-width: 300px) {
  .widget { --chart-height: 200px; }
  .widget-stats { grid-template-columns: repeat(2, 1fr); }
}
@container widget (min-width: 500px) {
  .widget { --chart-height: 250px; padding: 1.5rem; }
  .widget-stats { grid-template-columns: repeat(4, 1fr); }
}

/* 导航：窄时只显示图标，宽时展开文字并转横排 */
.nav-container { container: nav / inline-size; }
.nav-link-text { display: none; }
@container nav (min-width: 200px) { .nav-link-text { display: block; } }
@container nav (min-width: 600px) { .nav { flex-direction: row; } }
```

```tsx
// Tailwind v3.2+（@tailwindcss/container-queries 插件）
function Card({ title, image, description }) {
  return (
    <div className="@container">
      <article className="flex flex-col @md:flex-row @md:gap-4">
        <img src={image} alt="" className="w-full @md:w-48 aspect-video @md:aspect-square object-cover rounded-lg" />
        <div className="p-4 @md:p-0">
          <h2 className="text-lg @md:text-xl font-semibold">{title}</h2>
          <p className="mt-2 text-muted-foreground @lg:text-lg">{description}</p>
        </div>
      </article>
    </div>
  );
}

// 命名容器
<div className="@container/main">
  <aside className="@container/sidebar">...</aside>
  <main className="@lg/main:grid @lg/main:grid-cols-2">...</main>
</div>
```

## 降级与性能

```css
/* 默认（降级）样式 + 支持时增强 */
.card { display: flex; flex-direction: column; }
@supports (container-type: inline-size) {
  .card-container { container-type: inline-size; }
  @container (min-width: 400px) { .card { flex-direction: row; } }
}

/* 或媒体查询兜底 + 容器查询增强 */
@media (min-width: 768px) { .card { flex-direction: row; } }
@supports (container-type: inline-size) {
  @media (min-width: 768px) { .card { flex-direction: column; } }  /* 重置 */
  @container (min-width: 400px) { .card { flex-direction: row; } }
}
```

- 不要过度嵌套容器：`container-type` 逐层叠加有代价，按需在组件边界放一个即可
- 优先 `inline-size`，`size` 包含更贵，只在确实需要按块向尺寸查询时用
- 调试：`CSS.supports("container-type", "inline-size")` 与 `ResizeObserver`

## 断点自动化检查

```javascript
for (const [name, width] of Object.entries(breakpoints)) {
  await page.setViewportSize({ width, height: 800 });
  const hasOverflow = await page.evaluate(() =>
    document.documentElement.scrollWidth > document.documentElement.clientWidth);
  const offscreen = await page.evaluate(() =>
    Array.from(document.querySelectorAll("*")).filter((el) => {
      const r = el.getBoundingClientRect();
      return r.right > window.innerWidth || r.left < 0;
    }).length);
  results.push({ breakpoint: name, width, hasOverflow, offscreen });
}
```

# 常见响应式错误

| 错误 | 修复 |
|---------|-----|
| 桌面优先样式 | 先移动端，向上增强 |
| 固定宽度 | 用 `%`、`fr`、`max-width`、`min-width` |
| 移动端隐藏内容 | 重组，不要隐藏 |
| 点击目标过小 | 最小 44×44px |
| 仅 hover 交互 | 提供触摸/键盘替代 |
| `body { overflow: hidden }` | iOS 滚动问题 |
| 移动端 `100vh` | 用 `100dvh` 或 JS |
| 横向溢出 | 见 SKILL.md 验收段硬检查 |

## 参考

- [Tailwind 响应式设计](https://tailwindcss.com/docs/responsive-design)
- [Modern CSS Solutions](https://moderncss.dev/) / [Defensive CSS](https://defensivecss.dev/)
- [Utopia 流体排版计算器](https://utopia.fyi/) / [Every Layout](https://every-layout.dev/)
- [MDN 容器查询](https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_container_queries) / [CSS Containment Spec](https://www.w3.org/TR/css-contain-3/)
