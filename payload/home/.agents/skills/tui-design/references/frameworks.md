# TUI 框架选择参考

需要选择 TUI 框架时参考此表。

## 框架对比

| 框架 | 语言 | 模式 | 哲学 | 适用场景 |
|---|---|---|---|---|
| **Ratatui** | Rust | Immediate-mode | 每帧从零绘制，高性能 | 系统工具、Git、监控、文件管理 |
| **Bubble Tea** | Go | Elm Architecture (MVU) | Model → Update → View 单向数据流 | 管理面板、Shell 组件、SSH 应用 |
| **Textual** | Python | 声明式 + CSS | CSS-like 样式、事件驱动、async-first | 数据工具、SQL/HTTP 客户端、快速原型 |
| **Ink** | Node/TS | React 渲染终端 | JSX + Flexbox + Hooks | AI 工具、流式 UI、CLI 向导 |

## 生态工具

| 框架 | 辅助库 | 用途 |
|---|---|---|
| Ratatui | Crossterm (后端), color-eyre (panic安全) | 终端后端、错误恢复 |
| Bubble Tea | Lipgloss (样式), Bubbles (组件库), gum (CLI工具) | 样式、预制组件、Shell脚本 |
| Textual | Rich (富文本), Textual-web (Web远程) | 终端输出美化、Web 访问 |
| Ink | ink-router, ink-form, ink-text-input | 路由、表单、输入 |

## 选择决策树

1. 需要极端性能或单二进制部署？ → **Ratatui**
2. 项目已经是 Go/Rust/Python/Node？ → 对应语言的主流框架
3. 快速原型、内部工具？ → **Textual**（最少样板代码）
4. 需要流式渲染（AI/日志）？ → **Ink**（React Suspense 天然支持）
5. 多用户 SSH 远程 TUI？ → **Bubble Tea + Wish**
6. 只需富 CLI 输出，不是全屏 TUI？ → **Rich** (Python) / **Lipgloss** (Go)

## 测试钩子

选型时一并确认框架的测试能力，验收阶段要用：

| 框架 | 测试手段 |
|---|---|
| Ratatui | `TestBackend` + `Buffer` 断言 |
| Textual | Pilot + snapshot 测试 |
| Bubble Tea | 纯 `Update`/`View` 测试 + 伪终端冒烟 |
| Ink / OpenTUI | 依框架自身文档的测试与帧捕获指引 |

本环境当前**没有**框架专用 skill：确定框架后按项目自身约定实现，不要引用不存在的 skill。
