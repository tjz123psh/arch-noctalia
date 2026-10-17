# 当前配置审查与回归清单

先保存当前工作树（含未跟踪文件），不使用 HEAD 替代本轮基线。完整环境准备和隔离示例见[架构](</home/pang/md/nvim/nvim配置架构.md>)。

## 一、静态约束

- 语言实现仅在各语言目录；普通服务与 managed_lsp 不重叠，共享调试器不依赖另一种语言先加载。
- core.ui/core.projects 的目录入口存在，旧同名平铺 Lua 文件不存在，避免 require 优先命中旧文件。
- 速查绘制和数据仅在使用时加载；插件键位只有一份实际声明，不在 config 再绑定。
- Mason 是工具安装器的依赖，不形成反向循环；启动不加载 mason-lspconfig 或刷新/安装工具。
- 拆分、去注释与真正逻辑删减分开统计。纯注释整理可用剥离调试信息后的 LuaJIT 字节码比对。

## 二、可重复回归

在配置根目录执行；这些测试不启动真实语言服务：

~~~bash
nvim -u NONE -i NONE -n --headless -l tests/config_structure.lua
nvim -u NONE -i NONE -n --headless -l tests/autosave.lua
nvim -u NONE -i NONE -n --headless -l tests/core_workflows.lua
nvim -u NONE -i NONE -n --headless -l tests/whichkey_scopes.lua
nvim -u NONE -i NONE -n --headless -l tests/languages.lua
luajit tests/language_definitions.lua
luajit tests/java_declaration.lua
nvim -u NONE -i NONE -n --headless -l tests/java_workflows.lua
nvim -u NONE -i NONE -n --headless -l tests/spring_wizard.lua
nvim -u NONE -i NONE -n --headless -l tests/language_actions.lua
~~~

项目回归必须给出新的临时根 NVIM_CORE_TEST_TMP，并把 XDG_STATE_HOME/XDG_CACHE_HOME 指向该根；[项目测试](</home/pang/.config/nvim/tests/projects.lua>)会写自有夹具并启动两个短命写入进程，不能指向用户数据。

## 三、真实路径

| 改动 | 必须验证 |
|---|---|
| 保存/关闭 | 普通与强制退出、缩写/修饰符/链式命令、ZQ、取消、失败、多个修改缓冲区、BufDelete 保分屏和确认 |
| 编辑 | J/K 的普通/字符/行/块/Select、反向选区、数字前缀、边界、文本缩进、CJK 真实 UTF-8 输入及单地址/范围转换 |
| 项目 | 历史并集、损坏/空文件恢复、并发追加、写失败不截断、最长根、空格路径、树切换、取消不切换 |
| 界面 | 60×18/80×24/120×30/160×50 与 resize；grep 有预览且不残留节点；选择确认/取消一次；输入框按各自契约；速查滚动；皮肤与 ColorScheme |
| 调试 | DAP 空输入取消、Java 局部 F5、实际断点/变量/stdin、正常退出及晚到回调；先运行监听器协议测试 |
| 语言/工具 | 现有语言声明、Java/Spring、Lua API、Markdown；完整安装策略测试确认启动刷新/写包为零 |

真实测试使用独立 Neovim 和新临时工程，仅复用已安装插件/工具。只清理本轮创建的 PID/客户端；不启动真实 AI/tmux 会话验证 Sidekick，使用替身检查 toggle/close 的区别。

## 四、健康与快照

- 使用隔离环境运行 lazy、vim.lsp、vim.deprecated，以及需要的已加载插件 health。
- 缺少未使用生态的可选工具不等于配置故障，不为消除可选警告安装系统包。
- 快照比较实际选项、键位、命令和插件集合；不比较函数地址。自动生成的互斥路由顺序、动态 runtimepath 需单独解释，不假装全部原始 JSON 必须相同。
- 全量 StyLua 检查、相关真实回归与 stderr 检查都通过后再报告完成。仅有退出码 0 不够。
- 性能使用同版本、同插件、相同隔离环境做交错多轮比较，不把删注释宣称成明显加速。

## 五、同步与恢复

更新所属代码、[速查数据](</home/pang/.config/nvim/lua/core/ui/reference.lua>)、必要的 Which-key 提示和现有四份用户文档；新根因写排障历史。不要重新创建用户删除的独立快捷键文档。恢复时仅取备份中需要的文件，不覆盖其它未提交工作。
