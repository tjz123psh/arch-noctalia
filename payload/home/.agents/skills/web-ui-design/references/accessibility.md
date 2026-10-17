# 无障碍

WCAG 2.2 AA 的落地清单、键盘与焦点、语义 HTML、ARIA、对比度、表单无障碍、自动化与人工验证方法。对比度的具体色值算法与 token 体系见 `visual.md`。

## 指导原则

无障碍不是特性，而是质量属性。从设计阶段开始建，事后返工成本高 5–10 倍。

## 一致性等级

| 等级 | 说明 | 用于 |
|------|------|------|
| **A** | 最低无障碍 | 法律基线 |
| **AA** | 标准一致性（目标） | 多数法规 |
| **AAA** | 增强无障碍 | 特殊需求 |

POUR 原则：**Perceivable**（用户能感知内容？）/ **Operable**（能操作界面？）/ **Understandable**（能理解内容？）/ **Robust**（能配合辅助技术？）。

## POUR 检查清单

### 1. Perceivable 可感知

| 要求 | 做法 |
|------------|-----|
| 文本替代 | 所有 `<img>` 有有意义的 `alt`（装饰图用 `alt=""`）；有含义的图标有可访问名称；复杂图有长描述 |
| 颜色独立 | 绝不用颜色单独传达信息；链接不靠颜色区分；错误态不只靠颜色 |
| 对比 | 正文 4.5:1，大字与 UI 元件 3:1（详见 `visual.md`） |
| 缩放 | 200% 缩放不丢内容、不出现横向滚动；400% 缩放无二维滚动，320px 宽仍可访问 |
| 非文本对比 | UI 元件 3:1，焦点指示可见 |
| 文本间距 | 行高 1.5×、段距 2×、字距 0.12×、词距 0.16× 时内容不丢失 |
| 动效 | 尊重 `prefers-reduced-motion`，无自动播放动画 |

```html
<!-- 好 -->
<img src="chart.png" alt="Sales increased 25% from Q1 to Q2" />
<img src="decorative-line.png" alt="" />

<!-- 差 -->
<img src="chart.png" />
<img src="decorative-line.png" alt="decorative line" />
```

### 2. Operable 可操作

| 要求 | 做法 |
|------------|-----|
| 键盘可达 | 所有功能可用 Tab/Shift+Tab 触达，自定义控件可键盘操作 |
| 无键盘陷阱 | 用户总能 Tab 离开；模态陷阱是可控例外，关闭后焦点归还 |
| 焦点可见 | 每个可聚焦元素有清晰、高对比的焦点指示 |
| 焦点不被遮挡 | WCAG 2.2：焦点元素不被 sticky 头部等完全遮挡 |
| 跳转链接 | 页面顶部有"跳到主要内容"链接，landmark 区域已定义 |
| 时间限制 | 超时可延长、提前警告，自动刷新可关闭 |
| 暂停/停止/隐藏 | 移动内容和自动更新内容可暂停；闪烁不超过 3 次/秒且面积 <25% 视口 |
| 点击目标 | 移动端最小 44×44px，目标间距 ≥8px |

```html
<a href="#main" class="skip-link">Skip to main content</a>
<main id="main">...</main>
```

```css
:focus-visible { outline: 2px solid var(--accent-primary); outline-offset: 2px; }
:focus:not(:focus-visible) { outline: none; }  /* 只有在自定义替代存在时 */
```

### 3. Understandable 可理解

| 要求 | 做法 |
|------------|-----|
| 页面语言 | `<html lang="en">` 正确设置；局部语言变化用 `lang` 标注 |
| 标题与标签 | 标题描述内容，标签描述用途；标题层级正确，不只靠视觉大小 |
| 链接目的 | 链接脱离上下文也能理解，不用 "点击这里"/"阅读更多" |
| 可预测 | 聚焦不触发上下文变化，输入不自动提交；导航与重复组件顺序一致；同功能用相同标签 |
| 错误识别 | 错误清晰标识并与字段关联 |
| 标签与说明 | 所有输入有可见标签，必填项已标注，格式提示已给出 |
| 错误建议 | 错误消息给出具体修正建议 |
| 错误预防 | 法律/金融类表单可逆、可复查、提交前校验 |

```html
<!-- 差 -->
<a href="report.pdf">Click here</a>
<!-- 好 -->
<a href="report.pdf">Download Q4 Sales Report (PDF)</a>

<!-- 错误与字段关联 -->
<input aria-describedby="email-error" aria-invalid="true" />
<span id="email-error" role="alert">Please enter valid email</span>

<!-- 语言变化 -->
<p>The French word <span lang="fr">bonjour</span> means hello.</p>

<!-- 指令不依赖形状/颜色 -->
"Click the red button" → "Click Submit (red button)"
```

### 4. Robust 健壮

| 要求 | 做法 |
|------------|-----|
| 有效 HTML | 语义元素正确嵌套，无重复 ID，标签闭合（WCAG 2.2 已弃用 4.1.1 解析条款，仍是良好实践） |
| 名称/角色/值 | 自定义控件有可访问名称、正确角色，状态变化被播报 |
| 状态消息 | 状态更新被播报，live region 使用正确 |

```html
<!-- 可访问的自定义复选框 -->
<div role="checkbox" aria-checked="false" tabindex="0" aria-labelledby="label"></div>
<span id="label">Accept terms</span>

<div role="status" aria-live="polite">3 items added to cart</div>
<div role="alert" aria-live="assertive">Error: Form submission failed</div>
```

## 键盘导航

```
Tab:        下一个可聚焦元素
Shift+Tab:  上一个
Enter:      激活按钮/链接
Space:      切换复选框、激活按钮
Escape:     关闭模态/下拉/浮层
方向键:      在复合控件内导航（tabs、菜单、listbox）
```

焦点管理规则：

1. **Tab 序符合视觉顺序**（LTR 为左上到右下）
2. **模态焦点陷阱** — Tab 停在打开的模态内；`Esc` 关闭
3. **焦点归还** — 关闭模态/下拉后焦点回到触发元素
4. **不用 `tabindex` > 0** — 只用 `tabindex="0"` 或 `"-1"`
5. **焦点环可见** — 绝不 `outline: none` 而不给替代

## 语义 HTML

| 需求 | 用 | 不用 |
|------|-----|-----|
| 导航 | `<nav>` | `<div class="nav">` |
| 按钮动作 | `<button>` | `<div onclick>`、`<a href="#">` |
| 页面链接 | `<a href="...">` | 用 `<button>` 做导航 |
| 表单输入 | `<input>` + `<label>` | `<div contenteditable>` |
| 标题 | `<h1>`–`<h6>` | `<div class="heading">` |
| 列表 | `<ul>/<ol>` + `<li>` | 嵌套 `<div>` |
| 表格数据 | `<table>` | `<div>` 拼的 CSS 网格 |
| 区块 | `<section>`、`<article>`、`<main>` | 通用 `<div>` |

**规则：** 原生元素能做到就用它。ARIA 是补缺口，不是替代 HTML。

## ARIA 要点

| 模式 | 关键 ARIA | 说明 |
|---------|----------|-------|
| 模态对话框 | `role="dialog"`, `aria-modal="true"`, `aria-labelledby` | 陷阱焦点，关闭时归还 |
| 标签面板 | `role="tablist"`, `role="tab"`, `role="tabpanel"`, `aria-selected` | 方向键导航 |
| 下拉菜单 | `role="menu"`, `role="menuitem"`, `aria-expanded` | 方向键 + Escape |
| 实时区域 | `aria-live="polite"` 或 `"assertive"` | 动态内容更新 |
| 加载态 | `aria-busy="true"` | 加在正在更新的容器上 |
| 切换按钮 | `aria-pressed="true/false"` | toggle 类按钮 |
| 错误 | `aria-invalid="true"`, `aria-describedby` | 输入关联错误消息 |

ARIA 规则：

1. **原生 HTML 能做就别用 ARIA** — `<button>` 优于 `<div role="button">`
2. **ARIA 交互元素必须有键盘支持** — 只有角色不够
3. **不要改原生语义** — `<h2 role="button">` 是错的
4. **可见标签优于 `aria-label`** — 明眼用户也受益
5. **用真实屏幕阅读器测试** — 没有屏幕阅读器，ARIA bug 是看不见的

## 表单无障碍（WCAG 2.2 AA 摘要）

- `aria-invalid="true"` — 字段校验失败时设置
- `aria-describedby="error-id"` — 字段指向错误消息
- `role="alert"` — 错误出现时即时播报；`role="status"` — 非关键反馈
- 错误文本对比度 ≥4.5:1；颜色不是唯一提示（配图标 + 文字）
- 提交失败后焦点移到第一个错误字段
- 尊重 `prefers-reduced-motion`
- 校验时机策略（onBlur / onSubmit / debounce）见 `components.md`

## React 相关

| HTML | JSX | 说明 |
|------|-----|-------|
| `for` | `htmlFor` | 用在 `<label>` 上 |
| `class` | `className` | 标准 JSX |
| `tabindex` | `tabIndex` | JSX 用驼峰 |
| `aria-*` | `aria-*` | 与 HTML 相同（连字符） |

- 状态变化后用 `useRef` + `useEffect` 做程序化聚焦；`autoFocus` 慎用，只在用户明确预期焦点移动时用
- 客户端导航后把焦点移到新页 `<h1>` 或主内容
- 优先用把无障碍做对的 headless 库：

| 库 | 方式 |
|---------|----------|
| Radix UI | 无样式原语，完整键盘 + ARIA |
| React Aria (Adobe) | 基于 hooks，覆盖全面 |
| Ark UI | headless，状态机驱动 |

**规则：** 不要从零重写模态焦点陷阱、combobox 或标签面板。

- 用视觉隐藏的 `aria-live` 区域播报 toast、表单结果、加载完成与客户端路由变化
- 每个 React 项目加 `eslint-plugin-jsx-a11y`，在构建期捕获缺失 `alt`、非法 ARIA 等

## 按影响分级的常见违规

```
Critical（阻断）:
├── 功能性图片缺 alt
├── 交互元素无法键盘访问
├── 表单缺标签
└── 自动播放媒体无控制

Serious:
├── 对比度不足
├── 缺少跳转链接
├── 自定义控件不可访问
└── 缺少页面标题

Moderate:
├── 缺少 lang 属性
├── 链接文字不明
├── 缺少 landmark
└── 标题层级不当
```

## 验证方法

| 方法 | 能抓到 |
|--------|-------|
| 纯键盘操作 | 焦点陷阱、交互缺失 |
| 屏幕阅读器（VoiceOver/NVDA） | 标签缺失、播报错误 |
| 浏览器 DevTools a11y 审计 | 对比度、缺 alt、ARIA 错误 |
| `eslint-plugin-jsx-a11y` | 构建期静态 JSX 问题 |
| 缩放到 200% | 溢出、布局破损 |
| `prefers-reduced-motion` 开关 | 前庭敏感问题 |
| 强制高对比 / Windows 高对比 | 配色依赖假设 |

自动化只覆盖 30–50% 的问题，人工测试不可省略。也不要过度依赖自动化结论。

## 审计原则

- **尽早开始** — 从设计阶段就考虑无障碍
- **自动化能做的事先做** — 30–50% 的问题可自动发现
- **语义 HTML 优先** — 减少 ARIA 需求
- **记录模式** — 建立可访问组件库
- 不只用自动化测试；不把 ARIA 当第一方案；不隐藏焦点轮廓；不禁用缩放；不只靠颜色

## 自动化工具

```javascript
// axe-core 集成
const axe = require('axe-core');

async function runAccessibilityAudit(page) {
  await page.addScriptTag({ path: require.resolve('axe-core') });
  return await page.evaluate(async () => {
    const results = await axe.run(document, {
      runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa'] }
    });
    return { violations: results.violations, passes: results.passes, incomplete: results.incomplete };
  });
}

// Playwright 测试
test('should have no accessibility violations', async ({ page }) => {
  await page.goto('/');
  const results = await runAccessibilityAudit(page);
  expect(results.violations).toHaveLength(0);
});
```

```bash
npx @axe-core/cli https://example.com
npx pa11y https://example.com
lighthouse https://example.com --only-categories=accessibility
```

注意：自动化检查把"无法判定"的项归入 `incomplete`，必须人工复核，不能当成通过。

## 常见修复模式

**缺表单标签**：

```html
<!-- 之前 -->
<input type="email" placeholder="Email" />

<!-- 之后：可见标签 -->
<label for="email">Email address</label>
<input id="email" type="email" />

<!-- 或 aria-label -->
<input type="email" aria-label="Email address" />

<!-- 或 aria-labelledby -->
<span id="email-label">Email</span>
<input type="email" aria-labelledby="email-label" />
```

**对比度不足**：

```css
/* 之前：2.5:1 */
.text { color: #767676; }
/* 之后：4.5:1 */
.text { color: #595959; }
/* 或加背景 */
.text { color: #767676; background: #000; }
```

**键盘不可达的自定义控件**：

```javascript
class AccessibleDropdown extends HTMLElement {
  connectedCallback() {
    this.setAttribute("tabindex", "0");
    this.setAttribute("role", "combobox");
    this.setAttribute("aria-expanded", "false");
    this.addEventListener("keydown", (e) => {
      switch (e.key) {
        case "Enter": case " ":
          this.toggle(); e.preventDefault(); break;
        case "Escape":
          this.close(); break;
        case "ArrowDown":
          this.focusNext(); e.preventDefault(); break;
        case "ArrowUp":
          this.focusPrevious(); e.preventDefault(); break;
      }
    });
  }
}
```

**缩放与缩放后溢出**：在 200% 与 400% 缩放、320px 宽度下确认无横向滚动、内容不丢失、不动用二维滚动。

## 参考

- WCAG 快速参考：<https://www.w3.org/WAI/WCAG22/quickref/>
- 对比度工具：WebAIM Contrast Checker、axe DevTools
