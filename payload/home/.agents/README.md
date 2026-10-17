# 共享技能库（Agent Skills）

**位置**：`~/.agents/skills/` —— 这是 [Agent Skills 规范](https://agentskills.io/specification) 的"用户级"标准位置。

**谁读这里**（两边都原生支持，无需软链）：
- **DSH**：搜索根 `<agentsHome>/skills`（完整顺序：`<项目>/.dsh/skills` → `<项目>/.agents/skills` → `Config.customSkillDirs` → `~/.dsh/skills` → `~/.agents/skills`）；**发现深度只有一层**：`<name>/SKILL.md`（嵌套技能树会被忽略）
- **pi**：`docs/skills.md` 明确支持 `~/.agents/skills/` 与项目级 `.agents/skills/`；支持递归，但本库保持扁平

## 目录约定

```
skills/
├── <skill-name>/SKILL.md     每个技能一个目录，frontmatter 必填 name + description
├── <skill-name>/references/  可选：引用资料
├── <skill-name>/scripts/     可选：技能自带脚本
└── _shared/scripts/          非技能目录（无 SKILL.md → 不会被当成技能）；放多个技能共用的脚本
```

- 技能名 = 目录名，kebab-case（小写字母/数字/连字符）
- **不要**嵌套分类目录（DSH 只认一层深度）
- 工具专属技能不放这里：DSH 专属在 `~/.dsh/skills/`，pi 专属在 `~/.pi/agent/skills/`

## 加一个技能

```bash
mkdir -p ~/.agents/skills/my-skill
cat > ~/.agents/skills/my-skill/SKILL.md <<'MD'
---
name: my-skill
description: 一句话说明什么时候用它（这是给 agent 看的路由信息，要写清触发场景）。
---
# 正文…
MD
# 然后同步进安装器仓库（这些文件由 arch-noctalia 纳管）：
#   cp 到 payload/home/.agents/skills/my-skill/ 并更新 manifests/files.tsv 的 md5 —— 可以让 agent 代劳
#   本地 ~/.agents/.git 只是历史壳子（不入仓），装不装 git 提交都不影响两边 agent 读取
```

两边 agent 下次启动（DSH 是热更新，本会话内就会出现在技能清单里）就能看到它。

## 历史

- 2026-10-16 建立：从 `~/.dsh/skills` 与 `~/.pi/agent/skills` 迁入共用技能（DSH 专属的 dsh-upgrade / dsh-plugin-management 留在 `~/.dsh/skills`）
- 冲突处理：`deep-diagnosis` 取 pi 侧更新版 + 合并 DSH 侧独有文件；`grill-me` 取 pi 侧完整版（DSH 侧是 7 行占位）+ 保留 DSH 的 `agents/openai.yaml`
- 路径收敛（同日完成）：三端共用脚本从 pi 的 category 目录移到 `_shared/scripts/`；全库其余旧路径（`~/.pi/agent/skills/分类/` 15 处、`~/.dsh/skills/nvim-*` 9 处）也一并改为 `~/.agents/skills/…`，并逐条 stat 验证目标存在（0 残留）
- 2026-10-17 纳入安装器：`~/.agents` 全部文件（124 个）进 arch-noctalia 的 `payload/home/.agents/` + `manifests/files.tsv`（保留 `~/.agents/.git` 本地历史，不入仓）；机器上权限统一为 644（目录 755、6 个脚本 755）
