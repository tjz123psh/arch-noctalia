---
name: testing-strategy-patterns
description: 内部参考，不单独触发。
---

# Testing Patterns

按遇到的具体形态读取对应章节，不要整份加载。

## 可测性重构

被测代码难测时，先看是不是这三种耦合：

1. **副作用与决策混在一起。** 把「算出该做什么」和「去做」分开：前者返回描述（枚举、结构体、命令列表），可直接断言；后者薄到不值得测。
   SystemMaintenance-tui 的 `app/operation.rs`、`app/task.rs` 是这个形态。

2. **外部依赖硬编码。** 时钟、路径、命令执行器、网络客户端通过参数或 trait 注入。Rust 用 trait + 泛型或 `Box<dyn>`；Python 用参数默认值 + `unittest.mock.patch`；Node 用依赖注入或 `--experimental-test-module-mocks`。

3. **构造成本过高。** 需要完整 GTK app 或数据库才能测一个纯计算，说明该计算应该被提出来。

## 特权与系统操作

rjsupplicant-gui 的 `privileged.rs`、pngshot 的 systemd 交互属于此类。

- 把「构造命令」和「执行命令」分离，测试只断言构造结果（参数顺序、转义、路径），不真的提权。
- 权限失败、二进制缺失、超时各写一条测试，用注入的假执行器返回对应错误。
- 绝不在测试里真的写系统目录、改认证或调用 `sudo`。

## GTK / 图形应用

- 业务逻辑（配置解析、状态推导、文本格式化）放纯模块，正常单元测试覆盖。
- widget 层只做 smoke：能否构造、能否启动、能否关闭。MD Reader 的 `tests/smoke_app.py` 是这个模式，配 `is_parallel: false` 和显式 timeout。
- 无图形会话时用 `xvfb-run` 或跳过并明确标注跳过原因，不要静默通过。

## TUI

- 事件循环拆成 `update(state, event) -> state`，对状态转换做表驱动测试。
- 渲染层测缓冲区内容而不是截图：Ratatui 用 `TestBackend` + `Buffer` 断言。
- 必测 resize 到极小尺寸不 panic。

## 表驱动测试

同一逻辑多组输入时用表，失败信息里必须能看出是哪一行：

```rust
#[test]
fn parses_sizes() {
    let cases = [
        ("0", Some(0)),
        ("1K", Some(1024)),
        ("", None),
        ("abc", None),
    ];
    for (input, want) in cases {
        assert_eq!(parse_size(input), want, "input={input:?}");
    }
}
```

Python 用 `subTest(input=...)`，Node 用 `t.test()` 子测试。

## 异步与并发

- 固定并发顺序不可行时，断言不变量（总数守恒、无重复、状态最终一致），不断言具体交错。
- 超时、取消、重复提交各写一条。
- 不用 `sleep` 等待结果；用通道、事件或轮询带上限。
- 资源释放用 drop/finally 断言，或在测试末尾检查句柄计数。

## Mock 的边界

只 mock 这些：网络、时钟、随机数、文件系统、子进程、提权、外部 API。

不要 mock 正在被验证的分支、同模块内的纯函数、或整个被测对象。如果测试里 mock 的行数超过被测逻辑，说明测试写错了层。

## 覆盖率

覆盖率是发现盲区的工具，不是目标：

- 用它找「一行都没跑过」的错误处理分支。
- 不追百分比，不为提高数字给 getter 写测试。
- Rust `cargo llvm-cov`，Python `coverage run -m unittest discover`。两者都未预装，需要时先确认再用。

## 失败信息质量

测试失败时应该不看源码就知道哪里坏了：

- 断言带上输入值和上下文（`assert_eq!(got, want, "input={input:?}")`）。
- 测试名描述行为而非函数名：`rejects_empty_ssid` 优于 `test_config_2`。
- 一个测试验证一件事；需要三个不相关断言时拆开。
