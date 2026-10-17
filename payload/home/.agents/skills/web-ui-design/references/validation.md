# 验收：矩阵、证据与执行方法

用真实内容、真实视口、真实浏览器验收；不要凭一张桌面宽屏截图判断完成。本文件是 SKILL.md 第 3 段验收证据表的展开：档位选择、完整矩阵、各维度细节、执行方法与报告格式。

## 门禁纪律

- "完成"指通过所选风险档的矩阵，而不是页面能打开；一张桌面 hero 截图不算验收
- 工具报错（例如调整视口失败）不是跳过该维度的理由——换手段（`--viewport`、CDP、新会话）验证，或明确标注"未验证"并列入残余风险。绝不静默跳过然后宣称完成
- 每个"通过"都对应证据：截图、控制台日志、DOM 断言或自动化测试

## 风险档位

| 档位 | 何时 |
|---|---|
| Smoke | 纯非可见逻辑改动之外的最低要求 |
| Standard | 新建完整 Web 界面或改版的**默认档** |
| Release | 上线前、共享组件/设计系统、支付/认证/多语言，或高风险改动 |

### Smoke

- 构建/启动，关键页面与主流程
- 一个窄视口 + 一个宽视口，控制台无相关错误，无横向溢出

### Standard（新建/改版默认）

- 375 / 768 / 1440 视口；键盘走主流程；一个适用的失败/空/加载态
- 真实截图 → 视觉评审 → 修正 → 新截图；主流程与控制台证据
- 产品支持时覆盖相关主题；用真实长内容或 CJK 检查主操作与布局

### Release

- 含 Standard 全部内容，另加 1024、超宽、主题/高对比、200% 缩放与大字号
- 适用的触摸/输入法、CJK/RTL、加载/错误/离线/无权限/空结果、bfcache 与慢网
- `prefers-reduced-motion`、性能、CLS、路由卸载与监听器清理，以及产品承诺的安装/缓存行为

## 完整矩阵

| 维度 | 代表取值 |
|---|---|
| 视口 | 375（手机）、768（平板）、1024、1440、超宽（≥1920） |
| 主题 | 明色、暗色（`prefers-color-scheme`）、强制高对比 |
| 文本 | 默认、浏览器缩放 200%、用户大字号覆盖、长翻译、CJK、RTL |
| 输入 | 纯键盘、鼠标/触控板、触摸、输入法组合 |
| 状态 | 首次加载、刷新、bfcache、空、忙碌、失败、离线、空结果 |
| 网络 | 快、限速/慢、离线 |
| 动效 | 默认、`prefers-reduced-motion: reduce` |

## 视觉与布局

- 无横向溢出：任何视口下 `documentElement.scrollWidth` 不超过视口宽。逐个检查图片、表格、`<pre>`/代码块、长 URL、不换行的标题
- 窄视口有真实的构图变化，不是桌面布局被压扁；宽视口不出现大片死区或失控行长
- 断点切换处无内容跳动、遮挡或重叠；sticky/fixed 元素不遮内容、不互相堆叠
- resize、字体缩放、明暗主题切换后布局不破；主操作始终可见可点
- 长翻译、CJK、RTL、大字号下不溢出容器、不截断主操作

```javascript
// 每个视口都跑
await page.evaluate(() =>
  document.documentElement.scrollWidth > document.documentElement.clientWidth
);
```

## 无障碍

- 所有交互元素键盘可到达；Tab 序符合视觉序；焦点可见
- 模态/抽屉/菜单打开：焦点锁在内部；关闭：焦点回到触发元素；`Esc` 关闭
- 图标按钮有可读名称；状态不只靠颜色；文字对比达标
- 尊重 `prefers-reduced-motion`：入场与氛围动效在该设置下冻结或降级
- 语义标签、标题层级、表单标签与错误关联正确

细则与 WCAG 条目见 `accessibility.md`。

## 状态与行为

- 产品适用的数据、异步、权限或网络状态都有清晰 UI，不是白屏或卡死；没有相应语义的静态控件不要编造状态
- 表单校验时机、错误位置与恢复路径清晰；提交有反馈且防重复提交
- 图片/字体/异步内容到达前有占位；无大布局偏移（CLS）
- 控制台无未处理错误或警告（favicon 之类已知无害项可标注豁免）

## 性能

- 首屏可交互时间合理；关键资源不阻塞渲染
- 滚动、动画、长列表、输入不掉帧、不阻塞主线程
- 无内存/监听器泄漏：路由切换或组件卸载后已清理
- 动画只动 transform/opacity，不触发持续 layout/paint；空闲时不持续吃 CPU

## 执行方法

新建/改版且有视觉变化时：先完成一轮**真实截图 → 视觉评审 → 修正 → 再截图**，然后跑这里的浏览器行为验收。构建成功、控制台无错、无溢出都不能替代这一步。

视觉判断与行为证据分开：视觉断言、构图选择、品牌判断属于 `critique.md`；本文件只收集可观察的浏览器证据，不要把同一条美学意见写两遍。

- 用 `playwright` MCP 起服务、切视口、截图、读控制台、做 DOM 断言（优先真实浏览器证据）
- 对比度与 WCAG 合规审计按 `accessibility.md` 的清单与工具执行
- 按 UI/UX 最佳实践审查代码时读 `guidelines.md`（固定基线）

## Playwright 执行循环

默认用已配置的 Playwright MCP。MCP 提供隔离的无头浏览器与统一权限边界；CLI 只是 MCP 确实不具备能力时的兜底，不是绕过确认的捷径。

| 用途 | 工具 |
|---|---|
| 打开或切换页面 | `playwright_browser_navigate`、`playwright_browser_tabs` |
| 获取可操作结构 | `playwright_browser_snapshot`、`playwright_browser_find` |
| 表单与交互 | `playwright_browser_click`、`playwright_browser_fill_form`、`playwright_browser_type`、`playwright_browser_press_key` |
| 响应式检查 | `playwright_browser_resize` 后重新 snapshot |
| 运行时诊断 | `playwright_browser_console_messages`、`playwright_browser_network_requests` |
| 视觉证据 | `playwright_browser_take_screenshot` |

执行顺序：

1. 导航到真实页面，先 snapshot 拿到当前结构与稳定 ref。
2. 用最新 ref 交互；导航、对话框、切换标签或 DOM 大改之后必须重新 snapshot。
3. 覆盖主路径与一个错误/空状态；检查控制台与失败网络请求。
4. 按任务风险切换代表性的窄/中/宽视口；不要把单张桌面截图当成验收。
5. 用 DOM/无障碍树证明行为，用截图证明视觉；未验证项显式标注。

优先用具体交互工具。`playwright_browser_evaluate` 与 `playwright_browser_run_code_unsafe` 只用于已有工具无法表达的检查，代码保持只读、范围最小。

ref 失效时先重新 snapshot，不要用任意脚本暴力定位。截图输出放到任务约定的目录或 `/tmp/pi/`，不要落在项目根。任务结束后关闭临时页面、服务与 CLI 会话，不要关闭用户已有的浏览器会话。

**CLI 兜底**（仅在 MCP 连不上且重试无效、任务明确需要 MCP 未暴露的能力、或用户明确要求复现 CLI 流程时使用；先说明理由，不得把 MCP 需要确认的操作改走 CLI 绕过权限）：

```bash
export PWCLI="$HOME/.agents/skills/web-ui-design/scripts/playwright_cli.sh"
"$PWCLI" open https://example.com
"$PWCLI" snapshot
"$PWCLI" click e3
"$PWCLI" snapshot
```

不要全局安装 Playwright CLI。命令细节见 `playwright-cli.md`；trace、多标签与排障见 `playwright-workflows.md`。

## 平台注意点

- **SPA / 路由应用**：测路由切换、bfcache、卸载时的监听器与内存清理，不只测首屏
- **SSR / 静态页**：测禁用 JS 或慢 hydration，确认字体/图片到达时不产生布局偏移
- **组件库 / 设计系统**：逐个组件验证其**适用**的空、加载、错误与长内容状态，不只顺路径；没有数据或异步语义的组件不需要编造状态
- **嵌入 / iframe / 扩展 UI**：在真实宿主里测，而不是只在独立 dev 模式

## 报告格式

列出：视口、主题、字号、输入方式、状态、步骤、证据、期望、实际、残余风险。

未验证的维度必须显式写出；空白不等于通过。
