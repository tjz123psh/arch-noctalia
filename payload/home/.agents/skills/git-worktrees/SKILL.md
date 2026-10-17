---
name: git-worktrees
description: "Create and manage Git worktrees for isolated branches or parallel workspaces. Use for worktree lifecycle and parallel branch requests."
when-to-use: >
  Use when the user explicitly asks for worktree/parallel branches, or when the current
  checkout has important uncommitted changes and a separate independent task must begin.
  Do not use for ordinary edits or merely because the worktree is dirty.
---

# Git Worktrees

目标：在确实需要隔离时创建 git worktree，避免污染当前工作区。

## 触发条件

只在这些情况使用：

- 用户明确说 `worktree`、隔离工作区、并行分支。
- 当前工作区有重要未提交改动，但用户要开始另一条独立任务。
- 风险较高的实验性改动，不应碰当前 checkout。

普通小修、小配置改动、单分支开发，不使用 worktree。

## 最小流程

1. 检查当前目录是否是 git 仓库。
2. 检查 `git status --short`，说明当前工作区是否干净。
3. 选择位置：
   - 已有 `.worktrees/` 优先。
   - 其次已有 `worktrees/`。
   - 都没有且用户未指定时，使用 `~/worktrees/<project-name>/` 并说明选择。
4. 如果用项目内 `.worktrees/` 或 `worktrees/`，必须先确认它们被 `.gitignore` 忽略。
5. 创建新分支 worktree：

```bash
git worktree add <path> -b <branch-name>
```

6. 进入新 worktree 后再次运行 `git status --short`。
7. 不自动删除 worktree 或分支；清理属于独立的破坏性步骤。

## 需要细节时读取

完整 playbook 在：

```text
~/.agents/skills/git-worktrees/references/worktree-playbook.md
```

遇到目录选择、`.gitignore` 合并、已有分支、同名目录或清理 worktree 时读取对应章节。

## 完成输出

说明：

- worktree 路径。
- 分支名。
- 是否修改了 `.gitignore`。
- 后续命令应在哪个目录运行。
