# 项目上下文与品牌锚色

前端三端（Web / 移动 / 终端）共用三个零依赖脚本，位于 `~/.agents/skills/_shared/scripts/`：`context.mjs`（项目语境扫描）、`palette.mjs`（品牌锚色生成）、`pseudoloc.py`（伪本地化）。前两个用来在动手前把**产品语境**和**品牌锚色**固定下来；它们补的是判断段之前的输入——判断段要求区分已知/推断/未知，这两个脚本负责把"已知"落成可读文件。`pseudoloc.py` 的使用见 `i18n-rtl.md`。

## 项目上下文扫描

```bash
node ~/.agents/skills/_shared/scripts/context.mjs
```

输出 `PRODUCT.md` 与 `DESIGN.md` 的内容；都缺失时输出 `NO_PRODUCT_MD` 提示。

**查找顺序**（首个命中为准）：项目根 → `.agents/context/` → `docs/` → monorepo 根（`pnpm-workspace.yaml` / `turbo.json` / `nx.json` / `lerna.json` 标记，回落到 `apps/`、`packages/`）→ `$WEB_UI_CONTEXT_DIR` 环境变量兜底。

Monorepo 里可指定目标：

```bash
node .../context.mjs --target apps/web
```

**两者的分工**：`DESIGN.md` 在视觉决策上优先（token、字体、圆角、色彩），`PRODUCT.md` 在策略与语气上优先（受众、目标、主张）。两者都缺时不代表"没有品牌"——从 CSS 变量、computed 样式、相邻组件里提取既有身份。**保留既有身份是默认**；只有当 `PRODUCT.md` 的反例或用户明确要求重塑时才偏离。

若项目没有 `PRODUCT.md`：从零开始时先写一份再动手；对既有代码做改动时直接用代码作上下文推进，不阻塞。模板与写法见 `ui-contract.md` 的交接约定。

## 品牌锚色生成

```bash
node ~/.agents/skills/_shared/scripts/palette.mjs
node .../palette.mjs --id seed-021      # 指定种子
node .../palette.mjs --from mybrand     # 按 key 哈希（同 key 同结果）
WEB_UI_PALETTE_SEED=mybrand node .../palette.mjs
```

它给出**一个 OKLCH 品牌锚色 + 一句情绪描述**（例如"smoldering tannery — oxblood leather, cured under low workshop light"），然后由模型围绕它组出五角色调色板（bg / surface / ink / accent / muted）。

**为什么不给整套预设色板**：固定的 4 色预设会漂向安全区（暖白背景 + 邻近无彩），与 brief 无关。单锚色 + 运行时组色让同一个种子能长成暗色爵士酒吧，也能长成明亮酒店品牌——取决于 brief 要什么。这个判断与 `visual.md` 「先选策略，再选值」和反模式清单里的 `cream-palette`、`ai-color-palette` 是同一条原则的具体工具。

**用法**（脚本输出里也含这段）：

1. 先读 brief，写一句具体的场景/情绪短语。要具体："1970s travel poster — sun-baked warmth, considered"；不要泛泛："modern and clean"。
2. 用锚色的色相定位主品牌色，再按 `visual.md` 的色彩策略（Restrained / Committed / Full palette / Drenched）决定它占多少面。
3. 组合其余角色，用 OKLCH 保证对比与色相协调；对比度阈值见 `visual.md`。
4. 已有品牌色时**不要**跑这个脚本，保留既有 token。

## 什么时候用

| 情形 | 用哪个 |
|---|---|
| 新项目、要动手前固定产品语境 | `context.mjs`，必要时写 `PRODUCT.md` |
| 接手既有项目、要搞清既有设计语言 | `context.mjs`，再读代码里的 token |
| 新项目、没有已定的品牌色 | `palette.mjs` 取锚色，再按 `visual.md` 组板 |
| 已有品牌规范 | 都不跑，直接遵循既有 token |

这些脚本都零外部依赖，在任意目录可运行；`palette.mjs` 不需要项目里有任何文件，`pseudoloc.py` 接受任意文本或 JSON 输入。
