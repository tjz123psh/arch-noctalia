---
name: using-git-worktrees
description: Use when the user explicitly asks for git worktree, isolated workspace, parallel branches, or risky feature work that should not touch the current checkout. Do not trigger for ordinary edits.
---

# Git Worktrees 使用指南

Git worktrees 在同一仓库中创建隔离工作区，可同时处理多个分支。

**核心原则**：系统化目录选择 + 安全检查 = 可靠隔离。

开始前确认确实需要隔离 worktree；普通小改动直接在当前工作区完成。

## 目录选择

优先级：已有目录 > 询问用户

### 1. 检查已有目录

```bash
ls -d .worktrees 2>/dev/null     # 优先（隐藏目录）
ls -d worktrees 2>/dev/null      # 备选
```

有 `.worktrees` 用它，没有则用 `worktrees`，两者都有时 `.worktrees` 优先。

### 2. 询问用户

如果不存在 worktree 目录：

```
No worktree directory found. Where should I create worktrees?

1. .worktrees/ (project-local, hidden)
2. ~/worktrees/<project-name>/ (global location)

Which would you prefer?
```

## 安全检查

### 项目本地目录（.worktrees / worktrees）

**创建前必须确认已被 .gitignore 忽略：**

```bash
git check-ignore -q .worktrees 2>/dev/null || git check-ignore -q worktrees 2>/dev/null
```

**如果未被忽略：**
1. 向 `.gitignore` 添加对应规则
2. 展示 `.gitignore` 变更差异
3. 提交前问用户确认
4. 忽略规则到位后再创建 worktree

**原因**：防止误把 worktree 内容提交到仓库。

### 全局目录（~/worktrees）

无需 .gitignore 检查——完全在项目外。

## 创建步骤

### 1. 获取项目名

```bash
project=$(basename "$(git rev-parse --show-toplevel)")
```

### 2. 创建 Worktree

```bash
case $LOCATION in
  .worktrees|worktrees)
    path="$LOCATION/$BRANCH_NAME"
    ;;
  ~/worktrees/*)
    path="$HOME/worktrees/$project/$BRANCH_NAME"
    ;;
esac

git worktree add "$path" -b "$BRANCH_NAME"
cd "$path"
```

### 3. 运行项目初始化

自动检测项目类型并执行对应命令：

```bash
# Node.js
if [ -f package.json ]; then npm install; fi
# Rust
if [ -f Cargo.toml ]; then cargo build; fi
# Python
if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
if [ -f pyproject.toml ]; then poetry install; fi
# Go
if [ -f go.mod ]; then go mod download; fi
```

### 4. 验证基准测试

确保 worktree 从干净状态开始：

```bash
npm test   # 或 cargo test / pytest / go test ./...
```

失败则报告并询问是否继续；通过则报告就绪。

### 5. 报告位置

```
Worktree ready at <完整路径>
Tests passing (N 个测试，0 失败)
Ready to implement <功能名>
```

## 快速参考

| 情况 | 操作 |
|------|------|
| `.worktrees/` 存在 | 用它（确认被 gitignore） |
| `worktrees/` 存在 | 用它（确认被 gitignore） |
| 两者都存在 | 用 `.worktrees/` |
| 目录未被忽略 | 加入 .gitignore，展示差异，提交前确认 |
| 基准测试失败 | 报告 + 询问是否继续 |
| 无配置文件 | 跳过依赖安装 |

## 常见错误

### 跳过忽略检查
- **问题**：worktree 内容被跟踪，污染 git status
- **修复**：创建前始终用 `git check-ignore` 确认

### 假设目录位置
- **问题**：不一致，违反项目约定
- **修复**：优先级：已有 > 询问

### 在测试失败时继续
- **问题**：无法区分新 bug 和已有问题
- **修复**：报告失败，获得明确许可后再继续

### 硬编码初始化命令
- **问题**：不同工具的项目会失败
- **修复**：从项目文件自动检测（package.json 等）

## 示例

```
You: 将创建隔离 worktree，不影响当前工作区。

[检查 .worktrees/ - 存在]
[确认被忽略 - git check-ignore 确认已忽略]
[创建工作区: git worktree add .worktrees/auth -b feature/auth]
[运行 npm install]
[运行 npm test - 47 通过]

Worktree ready at $HOME/myproject/.worktrees/auth
Tests passing (47 tests, 0 failures)
Ready to implement auth feature
```

## 警戒线

**绝不：**
- 不检查 .gitignore 就创建 worktree（项目本地）
- 跳过基准测试验证
- 测试失败不经询问继续
- 目录不明确时擅自假设
- 跳过询问用户目录位置

**始终：**
- 优先级：已有 > 询问
- 项目本地目录确认被忽略
- .gitignore 修改提交前询问
- 自动检测项目类型并安装依赖
- 验证测试通过

