# 反模式检测器（可执行检查）

本 skill 自带一个**可独立运行的检测器**：46 条针对 AI 生成界面典型缺陷的规则，输出带 `file:line` 的客观证据。这是本 skill 里唯一不依赖模型判断的检查手段——其余 reference 是给人读的原则，这一篇是能跑出结果的工具。

实测样例（静态模式，一次典型页面）：

```text
side-tab        L6   border-left: 4px solid #ef4444
overused-font   L3   font-family: Inter
gradient-text   L10  background-clip: text + gradient
dark-glow       L13  Colored glow (rgb(124,58,237)) on dark page
bounce-easing   L14  cubic-bezier(.68, -.55, .27, 1.55)
single-font     L3   only font used is inter
```

## 什么时候跑

| 风险档 | 是否必跑 |
|---|---|
| Smoke | 不必 |
| Standard（新建/改版默认） | **必跑**，把命中项作为验收证据的一部分 |
| Release | **必跑**，并逐条确认或显式豁免 |

新品首次成形、大改视觉、或怀疑"看起来像 AI 拼的"时优先跑。它不能替代视觉评审（第 3 段的截图闭环），也不能替代无障碍与行为验收——它只覆盖**风格类缺陷**。

## 怎么跑

```bash
# 文件或目录（主力模式，无需额外依赖）
node ~/.agents/skills/web-ui-design/scripts/detect.mjs --json src/
node ~/.agents/skills/web-ui-design/scripts/detect.mjs --json index.html

# 常用开关
--json              机器可读输出（推荐，便于筛选与留证）
--no-config         忽略项目配置
--no-design-system  不做设计系统一致性比对
--no-inline-ignores 忽略文件内豁免注释
```

**URL 模式当前不可用。** `detect.mjs <url>` 依赖 `puppeteer`，本机未安装（实测报 `puppeteer is required for URL scanning`）。需要检查已部署页面时，改用**浏览器取证**：用 Playwright MCP 打开页面，取其 DOM/样式交给同一套规则判断，或在本地保存一份渲染后的 HTML 再跑文件模式。不要因为 URL 模式报错就跳过该项检查——换成能用的手段，或明确记为未覆盖。

输出形如：

```json
[{ "antipattern": "side-tab", "name": "Side-tab accent border",
   "description": "...", "severity": "warning",
   "file": "/abs/path/page.html", "line": 2,
   "snippet": "border-left: 4px solid #f00" }]
```

退出码 0 表示**检测执行成功**，不代表没有命中；命中项要读 `--json` 输出。

## 四种豁免方式

检测器设计上允许"有意的例外"，但要留下痕迹：

1. **项目级忽略规则** — `项目/.web-ui/config.json`：

   ```json
   {
     "detector": {
       "ignoreRules": ["overused-font"],
       "ignoreFiles": ["src/legacy/**", "public/**"],
       "ignoreValues": ["color:#fdf6e3"],
       "designSystem": { "enabled": true }
     }
   }
   ```

   `config.json` 建议提交；`config.local.json`（同名同级）用于个人覆盖，应 gitignore。

2. **单文件豁免注释** — 适用于导出文档等不打算修改的文件：

   ```html
   <!-- impeccable-disable overused-font -- 品牌规范文档，字体为既定事实 -->
   ```

   ```css
   .brand { font-family: Inter } /* impeccable-disable-line overused-font */
   ```
   ```js
   // impeccable-disable-next-line bounce-easing: 有意的弹性反馈
   ```

   `impeccable-disable` 作用于整个文件；`-line` / `-next-line` 只作用于当前或下一行。注释语法沿用上游名称，改它会破坏既有项目里的豁免标记。

3. **`--no-config`** — 一次性全量检查，不看项目配置。

4. **显式豁免并记录** — 在验收报告里写"命中 X 条，已确认 Y 条为有意决定，理由……"，而不是静默忽略。**静默忽略等于伪造通过。**

## 设计系统一致性

若项目根有 `DESIGN.md`（或 `Design.md` / `design.md`），检测器会读它的 **YAML frontmatter** 作为设计系统真值，比对代码里出现的字体、颜色、圆角、字号，命中则报 `design-system-font` / `-color` / `-radius` / `-font-size`。

```markdown
---
rounded:
  card: 12px
  pill: 9999px
typography:
  body:
    fontFamily: "Söhne"
    fontSize: 16px
colors:
  ink: "#1a1a1a"
---
```

也可用 `DESIGN.json` 或 `.web-ui/design.json` 作为 sidecar 补充 token。没有 `DESIGN.md` 时该项自动跳过，不会误报。

**这套机制与本 skill 的 `design-system.md` 配套**：那篇讲怎么设计 token 与主题架构，这篇用项目自己的 token 当基准做机器校验。

## 46 条规则清单

严重度为 `warning` 的项应默认修复；标记为 `advisory` 的 10 条是需要结合语境判断的提示，不是硬性禁止。

### 视觉陈词与 AI 味

| 规则 id | 名称 | 说明 |
|---|---|---|
| `side-tab` | Side-tab accent border | Thick colored border on one side of a card — the most recognizable tell of AI-generated UIs. Use a subtler accent or rem |
| `border-accent-on-rounded` | Border accent on rounded element | Thick accent border on a rounded card — the border clashes with the rounded corners. Remove the border or the border-rad |
| `gradient-text` | Gradient text | Gradient text is decorative rather than meaningful — a common AI tell, especially on headings and metrics. Use solid col |
| `cream-palette` | Cream / beige palette | A warm cream or beige page background has become the default "tasteful" AI surface, reached for by reflex. Choose a back |
| `ai-color-palette` | AI color palette | Purple/violet gradients and cyan-on-dark are the most recognizable tells of AI-generated UIs. Choose a distinctive, inte |
| `dark-glow` | Dark mode with glowing accents | Dark backgrounds with colored box-shadow glows are the default "cool" look of AI-generated UIs. Use subtle, purposeful l |
| `icon-tile-stack` | Icon tile stacked above heading | A small rounded-square icon container above a heading is the universal AI feature-card template — every generator output |
| `repeating-stripes-gradient` | Repeating-gradient stripes | Repeating-gradient stripes used as surface decoration are a recurring generated-UI signature. Reach for a deliberate tex |
| `codex-grid-background` | Decorative grid-line background | A two-axis grid drawn with hairline linear-gradient layers ("1px, transparent 1px" on both axes) is a recurring generate |
| `gpt-thin-border-wide-shadow` | Hairline border with wide shadow | A hairline border paired with a wide, diffuse shadow is a recurring generated-UI signature. Commit to one — a defined ed |
| `theater-slop-phrase` | Theater framing copy | Dismissing something as "theater" is a recurring generated-copy tic. Say plainly what the thing does or does not do. |

### 排版

| 规则 id | 名称 | 说明 |
|---|---|---|
| `overused-font` | Overused font | Inter, Roboto, Fraunces, Geist, Plus Jakarta Sans, and Space Grotesk are used on so many sites they no longer feel disti |
| `single-font` | Single font for everything | Only one font family is used for the entire page. Pair a distinctive display font with a refined body font to create typ |
| `flat-type-hierarchy` | Flat type hierarchy | Font sizes are too close together — no clear visual hierarchy. Use fewer sizes with more contrast (aim for at least a 1. |
| `italic-serif-display` | Italic serif display headline | Oversized italic serif (Fraunces, Recoleta, Playfair, Newsreader-italic) as the primary hero headline reads as taste in  |
| `oversized-h1` | Oversized hero headline | A full-sentence headline set at display size ends up dominating the viewport, leaving no room for anything else above th |
| `extreme-negative-tracking` | Crushed letter spacing | Letter-spacing pulled tighter than the point where characters keep their own shapes costs legibility. Tighten display ty |
| `tight-leading` | Tight line height | Line height below 1.3x the font size makes multi-line text hard to read. Use 1.5 to 1.7 for body text so lines have room |
| `wide-tracking` | Wide letter spacing on body text | Letter spacing above 0.05em on body text disrupts natural character groupings and slows reading. Reserve wide tracking f |
| `all-caps-body` | All-caps body text | Long passages in uppercase are hard to read. We recognize words by shape (ascenders and descenders), which all-caps remo |
| `tiny-text` | Tiny body text | Body text below 12px is hard to read, especially on high-DPI screens. Use at least 14px for body content, 16px is ideal. |
| `justified-text` | Justified text | Justified text without hyphenation creates uneven word spacing ("rivers of white"). Use text-align: left for body text,  |
| `line-length` | Line length too long | Text lines wider than ~80 characters are hard to read. The eye loses its place tracking back to the start of the next li |
| `skipped-heading` | Skipped heading level | Heading levels should not skip (e.g. h1 then h3 with no h2). Screen readers use heading hierarchy for navigation. Skippi |

### 脚手架与结构

| 规则 id | 名称 | 说明 |
|---|---|---|
| `hero-eyebrow-chip` | Hero eyebrow / pill chip | A tiny uppercase letter-spaced label sitting immediately above an oversized hero headline — or the same shape rendered a |
| `repeated-section-kickers` | Repeated section kicker labels | Repeating tiny uppercase tracked labels above section headings turns a brand page into AI editorial scaffolding. Replace |
| `numbered-section-markers` | Numbered section markers (01 / 02 / 03) | Numbered display markers as section labels (01, 02, 03) are the AI editorial scaffold one tier deeper than tracked eyebr |
| `nested-cards` | Nested cards | Cards inside cards create visual noise and excessive depth. Flatten the hierarchy — use spacing, typography, and divider |
| `monotonous-spacing` | Monotonous spacing | The same spacing value used everywhere — no rhythm, no variation. Use tight groupings for related items and generous sep |
| `cramped-padding` | Cramped padding | Text is too close to the edge of its container. Two shapes: (1) an element with its own text where the padding is too lo |

### 文案

| 规则 id | 名称 | 说明 |
|---|---|---|
| `em-dash-overuse` | Em-dash overuse | More than two em-dashes (— or --) in body copy is an AI cadence tell. Use commas, colons, periods, or parentheses instea |
| `marketing-buzzword` | Marketing buzzword | Generic SaaS phrases (streamline / empower / supercharge / world-class / enterprise-grade / next-generation / cutting-ed |
| `aphoristic-cadence` | Aphoristic-cadence copy | Three or more sections landing on a short rebuttal sentence ("X. No Y." / "X. Just Y.") or a manufactured-contrast aphor |

### 颜色与对比

| 规则 id | 名称 | 说明 |
|---|---|---|
| `low-contrast` | Low contrast text | Text does not meet WCAG AA contrast requirements (4.5:1 for body, 3:1 for large text). Increase the contrast between tex |
| `gray-on-color` | Gray text on colored background | Gray text looks washed out on colored backgrounds. Use a darker shade of the background color instead, or white/near-whi |
| `broken-image` | Broken or placeholder image | <img> tags with empty src, missing src, or placeholder values ship as broken-image boxes. Use real images, generated ass |

### 布局与溢出

| 规则 id | 名称 | 说明 |
|---|---|---|
| `text-overflow` | Content overflowing its container | Content renders wider than its container, spilling out or forcing a horizontal scrollbar. Let text wrap, constrain width |
| `clipped-overflow-container` | Positioned child clipped by overflow container | A clipping container (overflow hidden or clip) wrapping an absolutely-positioned child cuts off tooltips, menus, and pop |
| `body-text-viewport-edge` | Body text touching viewport edge | Body paragraphs render flush against the left or right viewport edge with no container providing horizontal padding. Wra |

### 动效

| 规则 id | 名称 | 说明 |
|---|---|---|
| `bounce-easing` | Bounce or elastic easing | Bounce and elastic easing feel dated and tacky. Real objects decelerate smoothly — use exponential easing (ease-out-quar |
| `layout-transition` | Layout property animation | Animating width, height, padding, or margin causes layout thrash and janky performance. Use transform and opacity instea |
| `image-hover-transform` | Image hover transform | Scaling or rotating an image on hover is a recurring generated-UI signature. Let imagery sit still, or use a subtler, pu |

### 设计系统一致性

| 规则 id | 名称 | 说明 |
|---|---|---|
| `design-system-font` | Font outside DESIGN.md | A font is used that is not declared in DESIGN.md typography. Use the documented type system or update DESIGN.md if this  |
| `design-system-color` | Color outside DESIGN.md | A literal color is outside the DESIGN.md palette and sidecar tonal ramps. This may be legitimate, but it should be an in |
| `design-system-radius` | Radius outside DESIGN.md | A border-radius value is outside the DESIGN.md rounded scale. Use a documented radius token or update the design system  |
| `design-system-font-size` | Font size outside DESIGN.md | A literal font-size is off the type ramp documented in DESIGN.md typography. Use a documented size step or update the de |

## 命中之后怎么改

1. **先判断是不是真缺陷。** 规则只描述症状，不判断语境。一个 `side-tab` 若确实编码了持久语义（时间轴轴心、严重度系统）且有非颜色线索，就是合法用法——写进豁免并说明。
2. **优先后果最重的**：能让人误读结构的（`nested-cards`、`monotonous-spacing`、`skipped-heading`）> 影响可读性的（`low-contrast`、`line-length`、`tight-leading`）> 纯风格陈词。
3. **修的时候改根因，不要改检测规避。** 把 `border-left: 4px` 换成不可见的等宽占位来躲规则，比原缺陷更糟。
4. **改完重跑**，确认命中数下降且没有引入新命中。

## 边界

- 只覆盖**风格与一致性**；不检查功能、无障碍合规、性能、终端卫生（那些在第 3 段各自的维度里）。
- 规则基于常见生成模式，不是设计法则；**不要把它当作"必须零命中"的门禁**，否则会逼出规避式改写。
- **静态模式与渲染后状态的差别**：文件/目录模式基于 CSS 级联与静态 DOM 计算，能稳定命中字体、颜色、边框、渐变、阴影、动效曲线、设计系统一致性等规则；依赖真实布局结果的规则（如实际换行导致的文字溢出、图片是否真的加载失败）在静态模式下覆盖较弱，需要浏览器取证补齐。
