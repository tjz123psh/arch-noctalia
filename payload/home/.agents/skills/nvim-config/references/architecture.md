# Neovim 当前架构参考

本参考只保存当前规则；完整结构见[用户架构](</home/pang/md/nvim/nvim配置架构.md>)，接口以实际源码为准。不要把历史章节中的旧代码当作当前实现。

## 加载与归属

根入口：core → languages.setup() → core.lazy → core.ui.neovide（仅 GUI）。

- [核心入口](</home/pang/.config/nvim/lua/core/init.lua>)加载通用选项、诊断、键位、命令、自动保存和中文标点。
- [移动行](</home/pang/.config/nvim/lua/core/movement.lua>)只负责 J/K 与选区语义，键位文件保持入口可读。
- [项目目录](</home/pang/.config/nvim/lua/core/projects/>)分接线、历史、选择器；公开 setup 接口不变，picker 按需加载。
- [共享 UI](</home/pang/.config/nvim/lua/core/ui/>)包含皮肤、输入几何、速查绘制/数据和 Neovide；速查数据不在启动时加载。
- [语言目录](</home/pang/.config/nvim/lua/languages/>)有 12 个独立语言入口，声明合同见[语言指南](</home/pang/.config/nvim/lua/languages/README.md>)。普通 LSP/DAP/Conform/Mason/Treesitter 只消费这些声明；Java 与 Spring 自管，不交给普通 LSP 重复启动。
- 小插件保持单文件；复杂目录靠 lazy 原生 init.lua 接入，不增加第二套插件注册框架。

## 修改约定

1. 先读当前文件并保留未提交状态；备份当前工作树，不只导出 HEAD。
2. opts 用于配置，config 只处理必要接线。按键直接写带回调的 keys，不与 config 内的映射双重维护；require 留在实际回调中。
3. 功能命令就近注册：诊断命令在 diagnostics，项目命令在 projects，语言命令在语言声明。速查只展示，不充当新的映射框架。
4. 新语言在自身目录声明能力并加入 names，运行语言结构测试；不要在公共消费者里塞语言条件。
5. 保留短的边界理由；历史、失败尝试和版本考据放排障历史，不粘贴回运行配置。

## 不可误删的边界

- 自动保存：原生 Ex 解析、退出队列、WinClosed/SafeState、ZQ 同步丢弃保护；禁止简单替换成 QuitPre writeall。
- J/K：数字前缀、modifiable、列/子模式、Select 恢复及无缩进来源时不调用 =。
- 诊断：virtual_lines 自行折行、箭头原样、12 行上限、数字 code 过滤、Ctrl-C 后 ModeChanged 补绘、日志轮转。
- 项目：只追加副本 + 三源并集 + append 回填 + 写守卫；不赋值 recent_projects，不截断用户历史；两份标记列表不擅自并成一份。
- Snacks：默认键表必须完整；grep 不能深合并 select 数字节点。Noice 负责命令行/消息，Snacks 负责选择/输入，两者不互相替换。
- 输入取消：选择器 Esc 一次取消；Snacks 输入框沿用 Esc 先退出插入，再 Esc 取消。不要把两种行为当相同契约。
- 终端：通用 1/2/3 独立；Java 按项目/用途/主类隔离。Sidekick 不用 mux，toggle 不终止进程，close 才清理直连会话。
- DAP：空条件/日志取消不建断点，Java 局部 F5 优先。当前 virtual-text 请求监听器仍需 session,err,response 的参数适配；升级后先跑协议与真实调试回归。
- Java：当前 client/root 固定、超时/失效回调、workspace 复用、Lombok，以及客户端命令成功 nil→vim.NIL、reloadBundles→空表、失败→nil,error。
- 启动：Mason 不自动刷新/安装，lazy 不自动检查更新；Treesitter 缺解析器仍有 6 小时节流。残缺 lazy 先改名保留，克隆失败不继续假装加载成功。

## 文档同步

- 快捷键：所属模块 → [速查数据](</home/pang/.config/nvim/lua/core/ui/reference.lua>) → 必要的 Which-key 分组和用户说明。
- 命令：所属模块 → [命令表](</home/pang/md/nvim/nvim命令.md>)与[自定义命令](</home/pang/md/nvim/nvim自定义命令.md>)。
- 插件/结构：[插件介绍](</home/pang/md/nvim/nvim插件介绍.md>)与[架构](</home/pang/md/nvim/nvim配置架构.md>)。
- 故障根因：[排障历史](</home/pang/.agents/skills/nvim-troubleshooting/references/nvim-troubleshooting-history.md>)；不重新创建已删除的快捷键/依赖清单/Spring 实操文档。

## 验收

纯/隔离回归见[清单](</home/pang/.agents/skills/nvim-config/references/local-checklist.md>)；完整配置测试必须隔离 XDG，真实 UI 必须用 PTY，不把 headless 结果当作窗口验收。退出码 0 也检查 stderr 中的异步错误。Neovide 当前 144 Hz 和持久化不透明度属于用户设置，改目录不能改值。
