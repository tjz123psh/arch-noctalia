# 来源与更新（mattpocock 技能组：grilling + grill-me）

`grilling`（**本文件所在目录**）与 `grill-me` 是从上游仓库**原样复制**的第三方技能，请勿手改正文——
改动会与上游分叉，下次更新即被覆盖。要调整行为，请在上游提 issue/PR，或另建一个本地技能包一层。
本文件是本地补的来源记录，**不属于上游正文**。

| 项 | 值 |
|---|---|
| 上游仓库 | https://github.com/mattpocock/skills |
| 固定 commit | `c55ee46073ed923f86ce59a5eb3b6d895095d1b7` |
| 安装日期 | 2026-09-26 |
| 上游技能桶 | `skills/productivity/` |

## 装了哪两个，为什么是两个

| 本地 | 上游路径 | 调用策略 |
|---|---|---|
| `grill-me/` | `skills/productivity/grill-me/` | `disable-model-invocation: true` —— **仅用户可调用**（GUI 里 `/grill-me`） |
| `grilling/` | `skills/productivity/grilling/` | 模型可调用（正文真身） |

`grill-me` 只是**前门指针**，正文仅一行 `Call the Skill tool with "grilling".`；
真正的访谈逻辑全在 `grilling`。**两个必须同时存在**，只装 `grill-me` 会指向空处。

上游还有两个相关技能（本机暂未安装）：`skills/engineering/grill-with-docs/`（需要 `domain-modeling`）、
以及 `wayfinder`。需要时按同样方式加装。

## 如何被 DSH 发现

DSH 的 skill 发现只认 `skills/<名>/SKILL.md` **一层**（或 `skills/<名>.md`），分类目录不会被扫描。
⇒ 两个技能各自是 `skills/` 下的**顶层真目录**，与别的技能并列，**不再用软链**：

```
~/.agents/skills/grilling/SKILL.md     # 正文真身（模型可调用）
~/.agents/skills/grill-me/SKILL.md     # 前门指针（仅用户可调用）
```

> 2026-10-16：grilling / grill-me 连同其余通用技能一起迁到共享库 `~/.agents/skills/`（DSH 与 pi 共用），上面的路径已按新位置更新。
> 2026-10-07 之前是「`mattpocock/` 分类文件夹 + 顶层相对软链」，当天已拍平成上面的样子。
> 软链方案的坑：还原/清理流程一旦漏掉真身，顶层只剩**悬空软链** ⇒ 技能静默消失（本组 10-06、10-07 各中一次）。

## 更新到上游最新

```bash
SHA=$(curl -fsS https://api.github.com/repos/mattpocock/skills/commits/main | python3 -c 'import sys,json;print(json.load(sys.stdin)["sha"])')
ROOT="$HOME/.agents/skills"   # 2026-10-16 迁移到共享库后，两个技能都在顶层，路径即 skills/<名>/
for f in grill-me/SKILL.md grill-me/agents/openai.yaml grilling/SKILL.md grilling/agents/openai.yaml; do
  curl -fsS -H "Accept: application/vnd.github.raw" \
    "https://api.github.com/repos/mattpocock/skills/contents/skills/productivity/$f?ref=$SHA" -o "$ROOT/$f"
done
```

更新后把上面的「固定 commit」改成新的 SHA，并核对 frontmatter 里的 `name`/`description`
（`grilling` 的 description 是它的触发词来源，DSH 靠它决定是否自动加载）。

> 本机 `raw.githubusercontent.com` 经常超时；上面的写法走 `api.github.com`，实测更稳。

## 本机修复记录

- **2026-10-06**：`grill-me` 被改成顶层真目录，但 `mattpocock/grilling` 没跟着建
  ⇒ 顶层软链 `grilling` 悬空、**正文真身丢失**（`grill-me` 里的 "Call the Skill tool with \"grilling\"" 指向空处）。
- **2026-10-07 15:32（清理轮）**：从 09-26 退役快照把正文抢救回来并**装回 live** ——
  `grilling/{SKILL.md,agents/openai.yaml}` 就位、`readlink -f` 可解析、frontmatter 正常
  （`name: grilling` + description 齐全，模型可自动加载）。正文与固定 commit `c55ee460…` 逐字节一致；
  另存一份在 `~/.dsh/backup/profile-snapshots/skills-home-layer-20261007-152337/skills-extra/mattpocock/grilling/`。
- **2026-10-07 17:2x（拍平，用户拍板「不搞软链这种形式了，按官方的样子正常放置」）**：
  两个技能都搬到 `~/.dsh/skills/<名>/` **顶层真目录**；`mattpocock/` 分类目录与两条顶层软链一并退役，
  本文件随之搬进 `grilling/`。正文逐字节未改（`grilling/SKILL.md` sha256 `10ff989e…`）；
  拍平前整棵树有 tar 退路 `~/.dsh/backup/misc/skills-flatten-20261007-172258/skills-before-flatten.tar.gz`。
