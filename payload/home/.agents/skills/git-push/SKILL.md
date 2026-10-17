---
name: git-push
description: "Perform GitHub push, first publication, tags, releases, and version updates safely. Use only for explicit push/publish/release requests; remote writes stay explicit."
when-to-use: >
  Use when the user explicitly asks to "push to GitHub", "git push", "publish a version", or
  "create a tag/release". For commit message conventions, branch naming, and PR preparation
  without actual pushing, use `git-workflow`.
---

# Git Push

目标：把当前项目可靠推送到 GitHub，同时避免大文件、密钥、私人内容进入仓库。

## 快速判断

1. 先判断模式：
   - 新项目：无 `.git` 或无 remote。
   - 日常更新：已有 remote，只需要 commit + push。
   - 版本发布：用户明确说 release/tag/发版本。
2. 检查工具：`git`、`gh`、Git 用户信息、GitHub 登录状态。
3. 扫描风险：
   - 新增文件 > 10MB：确认是否确实应进入仓库。
   - 单文件 > 100MB：必须排除。
   - 凭据泄露：用 `gitleaks` 扫描，不只靠文件名匹配。工作区用
     `gitleaks dir . --redact --no-banner`；公开仓库或首次推送再加
     `gitleaks git . --redact --no-banner` 扫历史。`--redact` 必须始终带上，
     否则报告会包含明文密钥。命中时只报告 rule、文件和 commit，不输出密钥值。

## 执行规则

- 首次推送必须先写好 `.gitignore`，再 `git add`。
- 不覆盖用户已有 `.gitignore`，只追加必要规则。
- 远程已存在时，不强推；只有用户明确确认覆盖远程才用 force。
- 日常更新保持轻量：看变更、拦截新增大文件、生成提交信息、push。
- Release/tag 只有用户明确要求时执行，不把普通 push 自动升级为发布。
- 推送前核对目标 remote、当前分支和将要推送的 commit；只推用户要求的分支或 tag。

## 需要细节时读取

完整 playbook 在：

```text
~/.agents/skills/git-push/references/github-push-playbook.md
```

只有在遇到首次推送、release、远程冲突、大文件处理或认证失败时读取对应章节。

## 完成输出

必须说明：

- 仓库 URL 或 remote。
- 提交 hash，以及实际创建时的 tag/release URL。
- 排除了哪些文件。
- 仍需用户处理的认证或权限问题。
