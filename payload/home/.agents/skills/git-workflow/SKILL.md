---
name: git-workflow
description: "Plan commit scope, Conventional Commits, branch names, staging, and PR content. Use for local Git/PR preparation; use git-push for remote writes or releases."
when-to-use: >
  Use when the user asks to commit code, split commits, name branches, or prepare a PR.
  For actual push, tag, or GitHub Release, use `git-push`. Skip for read-only status checks.
---

# Git Workflow（个人规范）

## 提交规范（Conventional Commits）

格式：`<type>(<scope>): <description>`

| type | 场景 |
|------|------|
| `feat` | 新功能 |
| `fix` | 修 bug |
| `docs` | 文档 |
| `refactor` | 重构（不改功能） |
| `perf` | 性能优化 |
| `test` | 加测试 |
| `chore` | 构建/工具变动 |

scope 可选（如 `feat(auth): ...`），description 用英文祈使句，首字母小写。

## 分支命名

```
<type>/<short-description>
```

示例：`feat/oauth-login`、`fix/null-pointer`、`refactor/extract-utils`

## 提交粒度

- 一个提交 = 一个逻辑变更，不大不小
- 需要说明 why 时在 body 写，不写废话
- 一天多次提交正常，推之前可以 squash

## Tag / Release

```
git tag -a v<major>.<minor>.<patch> -m "简短说明"
git push origin v<major>.<minor>.<patch>
```

只推送本次明确创建的 tag，避免 `--tags` 把本地其他标签一起发布。实际执行发布时加载 `git-push`。

## PR

需要 PR 时按 `references/pull-request.template.md` 组织目标、改动、验证和风险；内容必须来自实际 diff 与测试。

## 参考

- [Conventional Commits](https://www.conventionalcommits.org/)
