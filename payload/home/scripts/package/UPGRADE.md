# package 升级方案

> 起于 2026-10-04。基线 commit `f0689d1`，升级前快照 `~/scripts/.backups/package-2026-10-04`。
> 本文是这次升级的唯一主文档：分期、任务、验收、决策、回退都记在这里。
> 进度看最后一节的勾选框；每完成一项就更新本文。

## 一、为什么要升

现在这 5 个脚本能干活，但三个地方会真出事或真难受：

| 脚本 | 现状 | 问题 |
|---|---|---|
| `pac` | 装 pacman/AUR，带 AI 审查 | 无论什么情况都传 `--skipreview`：opencode 不在或提示词丢失时，AI 审查和 paru 自带复核**同时消失**，AUR 包等于裸装 |
| `pac` | AI 审查由模型自己定级 | 提示词 341 行、四十多条阈值全交给模型数；上游实测正常包约 1/4 被判高风险（一屏警告 = 用户学会一路按 y） |
| `pacr` / `pacrrr` | 卸载、追踪残留是两条命令 | 卸载侧 pacr 早就同时管 pacman/AUR/Flatpak，但清残留要另敲 pacrrr 且必须重新跑一遍应用；两边候选逻辑各写一份 |
| `pak` | Flatpak 安装 TUI，独立脚本 | 装的一端要分两个命令（pac / pak），而卸的一端早已统一；243 行 fzf/字典/预览代码与 pac 重复 |
| 全部 | 无打包、无测试、不在 PATH | `~/scripts/package` 不在 PATH，只能手敲绝对路径；改完没有任何可复跑的验收 |

## 二、目标与非目标

**目标**
1. 装：一条命令覆盖 pacman / AUR / Flatpak，AUR 走审查门禁，审查没跑成时**不**跳过 paru 自带复核。
2. 卸：一条命令覆盖 pacman / AUR / Flatpak，卸载后能顺手清干净家目录残留（永久删除，按用户习惯）。
3. 审查质量：模型只报"看到了什么"并附原文，风险等级由脚本按固定规则算，且核实证据出处。
4. 每个阶段都留下可复跑的验收脚本，改动可单期回退。

**非目标**
- 不再改动命令名与脚本路径：安装入口固定为 `pac`（`~/scripts/package/pac`），卸载入口固定为 `pacr`；fish 的 `paru` 包装与 `~/.local/bin` 链接都指向这些名字。
- 不改 `pacrrr` 的删除行为（保持 `rm -rf` 永久删除，用户 2026-10-04 明确要求）。
- 不引入 API key 配置文件；不抽共享库；不打包 AUR 包（那是另一条路线）。
- 不动 `pak` 之外的既有安装逻辑；不动 `pacd` 的代码。

## 三、分期

| 期 | 内容 | 主要文件 | 验收 | 状态 |
|---|---|---|---|---|
| 一期 | pac 复核兜底：审查没跑成就不传 `--skipreview`；加 `--no-ai`、`PARU_UI_DRY_RUN` | `pac` | `tests/phase1-review-gate.sh` | **已完成**（10 条断言全绿） |
| 二期 | pacr + pacrrr 合并：pacr 成唯一实现，pacrrr 变壳；移植上游候选枚举与豁免名单；保留 strace 档 | `pacr`、`pacrrr` | `tests/phase2-leftover.sh` | **已完成**（32 条断言全绿） |
| 三期 | pak 并入 pac：一条列表三种来源；pak 变壳 | `pac`、`pak` | `tests/phase3-flatpak.sh` | **已完成**（19 条断言全绿 + 真机验证） |
| 四期 | pac AI 审查改造：证据包 + 本地定级 + 证据核实 + 不给模型工具 | `pac`、`~/scripts/share/prompts/aur-review.md` | `tests/phase4-review-score.sh` | **已完成**（17 条断言全绿） |
| 五期 | AI 后端改为直连 HTTP（URL + 模型名 + key）；缓存目录与环境变量改名 | `pac`、`~/.config/pac/ai.conf` | `tests/phase5-ai-http.sh` | **已完成**（31 条断言全绿） |
| 六期 | AI 接进 pacr 判残留置信度；AI 模块抽共享库；pacd 补文档 | `pacr`、`lib/pac-ai.sh`、`share/prompts/leftover-scan.md` | `tests/phase6-ai-leftover.sh` | **已完成**（17 条断言全绿） |

排序理由：先修"会出事"的（一期）；再做天天用的卸载侧（二期）；三期是体验统一，本机已安装 Flatpak 应用为 0，不急；四期行为变化最大，放最后以便单独回退。

## 四、各期任务明细

### 一期：pac 复核兜底

- **T1-1** 加状态量：本批 AUR 包总数 / 真正跑出审查结论的个数（`AUR_REF_TOTAL`、`AUR_REF_REVIEWED`）。
- **T1-2** 安装参数单点组装：`paru_install()` —— 只有当本批每个 AUR 包都跑出过审查结论时才追加 `--skipreview`。审查没跑（`--no-ai`、用户跳过、无 opencode/提示词）或审查失败时，一律保留 paru 自带复核。
- **T1-3** 新增 `--no-ai`：本次不审查、不逐包追问，直接普通安装（自然走"不传 `--skipreview`"这条路）。
- **T1-4** `--check` 与 `--no-ai` 互斥，同时给直接报错退出（`--check` 是"只审查"，和"关掉审查"自相矛盾）。
- **T1-5** 新增 `PARU_UI_DRY_RUN=1`：只打印将执行的 paru 命令，不真装。用于验收和排查。
- **T1-6** usage 同步，并说明"AI 审查没跑成时保留 paru 自带复核"。

验收（`tests/phase1-review-gate.sh`，全部在临时目录跑，假 paru 只记录参数）：
1. 没有 opencode → 收到 `-S -- <pkg>`，无 `--skipreview`。
2. 有 opencode、审查跑完、用户继续 → `-S --skipreview -- <pkg>`。
3. 有 opencode、用户跳过审查 → 无 `--skipreview`。
4. `--no-ai` → 不出现追问，无 `--skipreview`。
5. `PARU_UI_DRY_RUN=1` → 打印命令且不真的调用 paru。

### 二期：pacr + pacrrr 合并

流程顺序被两条硬约束钉死：**追踪必须在卸载前**（应用还装着才能跑），**删残留必须在卸载成功后**（卸载失败时配置还在）。包元数据也要在卸载前抓（`pacman -Qi` 卸载后就查不到）。

- **T2-1** `pacr` 成唯一实现，`pacrrr` 变三行壳（`exec pacr --trace-command "$@"`），保留原输入形式（任意命令 / AppImage）。
- **T2-2** 移植上游 `bin/pacr` 的候选枚举：包元数据（描述 / URL / 二进制名 / desktop 的 Name 与 StartupWMClass / Flatpak app-id）派生名字片段；家目录 `~/.config`、`~/.cache`、`~/.local/share`、`~/.local/state`、`~/.var/app`、根级点目录按"每个应用一条"枚举；外加限深关键词搜索覆盖偏门位置（如 `~/Documents/Tencent Files`）。
- **T2-3** 豁免名单函数化（`.ssh`、`.gnupg`、密钥环、shell rc/history、`user-dirs.*`、共享 mime/icons/fonts/themes、`~/.local/share/applications` 整体、`~/.wine` 整体、包管理器缓存），**枚举与删除前各校验一次**。
- **T2-4** 保留 pacrrr 的 strace 档（追踪真实读写路径），作为 `pacr --trace` 的候选来源，标记为"追踪到的"。
- **T2-5** 删除仍是永久 `rm -rf`；清单显示体积与来源；保留"输入确认词才删"的闸门。
- **T2-6** 参数：`--no-clean`（只卸载）、`--scan`（只列不删）、`--trace`、`--dry-run`。

### 三期：pak 并入 pac

- **T3-1** 索引增加 Flatpak 行：来源列写 origin（如 `flathub`），ref 写 `<origin>/<app-id>`。**必须走 `flatpak remote-ls --app --cached`**（本机实测：走缓存 0.9s，实时 >30s），并纳入索引缓存与失效判定；没有 flatpak 时静默跳过。
- **T3-2** 预览传参改为 `{1}` + `{2}`（ref + 来源），Flatpak 行走 `flatpak remote-info`（pak 现有代码搬过来）。
- **T3-3** 安装分发：`aur/*` 走审查门禁后 `paru_install`；Flatpak 行走 `flatpak install`；其余走 `paru_install`。混选时分两条命令。
- **T3-4** `--check` 下 Flatpak 行按现有非 AUR 规则提示跳过。
- **T3-5** `pak` 变三行壳（`exec pac --flatpak`），可随时删除。

### 四期：pac AI 审查改造

- **T4-1** 提示词换成上游 84 行版本（`~/scripts/share/prompts/aur-review.md`），旧版改名 `aur-review.legacy.md` 备份；要求模型用中文写结论。
- **T4-2** 证据包：AUR 元数据（`paru -Si --aur` + AUR RPC）、git 历史、**最近 3 次提交的 diff**、构建目录全部文本文件内容、包信誉（上架 <90 天或最新提交者为近 60 天新面孔 → 低）、`.SRCINFO` 与 PKGBUILD 的源主机比对（脚本自己做）。
- **T4-3** 审查期间**不给模型任何工具**。
- **T4-4** 定级收回脚本：照搬上游 jq 规则（恶意一条即高；可疑一处中、两处以上高；证据找不到出处则降级/丢弃），**不改阈值**。
- **T4-5** 输出改造：丢掉 `PAC_DECISION` 解析，改为解析 JSON + 校验字段 + 分类着色，末尾补"原因 / 包的情况"两行。
- **T4-6** 后端：opencode → agy 自动探测，加 `--ai <后端>`；保留 `--ai-model`。

## 五、决策记录

| # | 决策 | 结论 | 状态 |
|---|---|---|---|
| D1 | pacrrr 的删除方式 | 保持永久 `rm -rf`，不改进回收站 | **已定**（用户 2026-10-04 明确） |
| D2 | pacr 与 pacrrr 是否合并 | 合，pacr 为唯一实现，pacrrr 留壳 | **已定** |
| D3 | pak 是否并入 pac | 合 | **已定**（用户 2026-10-04） |
| D4 | 卸载后是否默认清残留 | 问一句、默认 Y；`--no-clean` 跳过 | 默认执行，可否决 |
| D5 | strace 追踪档的触发 | 被动用（`pacr --trace`），不默认追问 | 默认执行，可否决 |
| D6 | `pak` 命令名 | 保留三行壳，不直接删 | 默认执行，可否决 |
| D7 | AI 后端范围 | opencode + agy 自动探测；不引入 API key 配置 | 默认执行，可否决 |
| D8 | 定级规则数值 | 照搬上游，不自调阈值（他做过 58+14 样本校准） | 默认执行，可否决 |
| D9 | 是否建分支 | 不建，直接在主线用小步提交 + 快照备份 | 默认执行，可否决 |
| D10 | 命令命名 | 安装入口 `paru-ui` → `pac`；`pacr` / `pacd` / `pacrrr` / `pak` 名字保留；五个命令在 `~/.local/bin` 建链接 | **已定**（用户 2026-10-04） |
| D11 | 缓存目录与 `PARU_UI_*` 环境变量 | 已改名：`~/.cache/paru-ui` → `~/.cache/pac`（旧目录自动搬一次），`PARU_UI_*` → `PAC_*`（旧变量仍兼容） | **已定**（用户 2026-10-04） |
| D12 | AI 审查后端 | 不用第三方 CLI，直连 HTTP：url + 模型名 + key 写在 `~/.config/pac/ai.conf`（600 权限） | **已定**（用户 2026-10-04） |

## 六、工程约定

- **备份**：每期开工前 `cp -a package .backups/package-<日期>`。
- **提交**：每期一个 commit，只 `git add package`（`~/scripts` 仓库里还有其它未完成的改动，不碰）。
- **验收脚本**：放 `package/tests/`，可重复执行、只依赖临时目录、不碰系统状态。
- **提示词**：新版本落 `~/scripts/share/prompts/aur-review.md`，旧版改名备份，不删。
- **缓存路径不变**：`~/.cache/pac`；新增缓存也只能加子目录。
- **中文注释**：与现有脚本风格一致，说明"为什么"而不只是"做什么"。

## 七、回退

1. 单期回退：`git -C ~/scripts revert <该期 commit>`。
2. 整包回退：`rsync -a --delete ~/scripts/.backups/package-2026-10-04/ ~/scripts/package/` 后再核对 md5。
3. 四期（AI 改造）是行为变化最大的一期，若判定规则不合适，优先把提示词与 jq 规则整段退回，其余保留。

## 八、进度

- [x] T0 备份 `.backups/package-2026-10-04` + 记录基线 `f0689d1`
- [x] T0-2 写本文档 + 一期验收脚本
- [x] 一期 pac 复核兜底（T1-1 ~ T1-6）—— 验收脚本 10/10 通过，回归项全过
- [x] 一期收尾：命令改名 `paru-ui` → `pac`，建 `~/.local/bin` 五个入口，fish 包装改指向 —— 五个命令均可直接调用
- [x] 二期 pacr + pacrrr 合并（T2-1 ~ T2-6）—— 卸载后清残留、豁免名单、永久删除、strace 档，32/32 通过
- [x] 三期 pak 并入 pac（T3-1 ~ T3-5）—— Flatpak 走缓存、预览/安装按来源分派、pak 变壳，19/19 通过
- [x] 四期 AI 审查改造（T4-1 ~ T4-6）—— 提示词换新、证据包、脚本定级、证据核实、关工具，17/17 通过
- [x] 五期 AI 后端改为直连 HTTP + 缓存目录/环境变量改名 —— 五套验收共 117 条断言全绿
- [x] 六期 AI 接进 pacr + 共享库 + pacd 文档 —— 六套验收共 134 条断言全绿

---

## 九、一期完成记录（2026-10-04）

改动 `pac`（原 `paru-ui`，+105 / -43，722 → 784 行）：

### 命名与入口

| 命令 | 作用 | 备注 |
|---|---|---|
| `pac` | 安装 pacman / AUR（三期后含 Flatpak） | 原 `paru-ui`；fish 里敲 `paru <关键词>` 也走它 |
| `pacr` | 卸载（二期后含家目录残留清理） | |
| `pacd` | 降级 | 代码不动 |
| `pacrrr` | strace 残留追踪 | 二期后变成 `pacr` 的壳 |
| `pak` | Flatpak 安装 | 三期后变成 `pac` 的壳，可随时删 |

五个命令都在 `~/.local/bin` 有符号链接（该目录在 PATH 首位），所以现在可以直接敲 `pac 关键词`。
改名只动了脚本自身：文件、消息前缀、usage、`tests/` 默认路径、fish 包装。
**未动**：缓存目录仍是 `~/.cache/paru-ui`，环境变量仍是 `PARU_UI_*`（见 D11）。

### 代码改动

- 新增 `aur_review_complete()` 与 `paru_install()`：只有本批 AUR 包**全部**跑出审查结论时才传 `--skipreview`。
- `confirm_aur_install_after_review` 加计数与 `--no-ai` 早退；审查失败（返回值非 0/3）不计入"审过"。
- 选项解析从"只看第一个参数"改成循环，`--no-ai` 才能与 `--install`/`--check` 组合；`--check` + `--no-ai` 直接报错退出 2。
- 新增 `PARU_UI_DRY_RUN=1`：只打印将执行的命令。
- 新增 `tests/phase1-review-gate.sh`。

验收证据（`tests/phase1-review-gate.sh` 实测，全部在临时目录、假 paru 只记参数）：

| 用例 | paru 实际收到的参数 | 结果 |
|---|---|---|
| 没有 opencode | `-S -- testpkg` | PASS |
| 审查跑完 + 用户继续 | `-S --skipreview -- testpkg` | PASS |
| 用户选 n 跳过审查 | `-S -- testpkg` | PASS |
| `--no-ai` | `-S -- testpkg`，且没有审查追问 | PASS |
| `PARU_UI_DRY_RUN=1` | 打印命令、未真的调用 paru | PASS |

回归：`--help` / `--preview core/bash` / `--index` / `--ai-model` 正常；`shellcheck -S warning` 无告警；`bash -n` 通过。

---

## 十、二期完成记录（2026-10-04）

改动：`pacr`（266 → 1043 行）重写为合并版；`pacrrr`（347 行）变成 15 行转发壳；新增 `tests/phase2-leftover.sh`。

### pacr 现在的两条流程

| 流程 | 触发 | 顺序 |
|---|---|---|
| 包模式 | `pacr [关键词]` | 选包 → 收集元数据（**卸载前**，`pacman -Qi/-Qlq` 卸载后就查不到）→ `--trace` 时先追踪 → 卸载 → 问一句"是否清理家目录残留? [Y/n]" → 勾选 → 输入 `delete` → 永久删除 |
| 命令模式 | `pacr --trace-command <命令>`（`pacrrr` 走这里） | 保留原顺序：追踪 → 勾选 → 永久删除 → 问是否用包管理器卸载（AppImage 走原分支） |

选项：`--no-clean`（只卸载）、`--scan`（只列候选）、`--trace`、`--trace-timeout N`、`--dry-run`（只打印，且**不启动**被追踪的程序）。

### 候选从哪来

1. **元数据关键词**：包名、`/usr/bin` 下的二进制名、desktop 的 Name/StartupWMClass、URL 的二级域名与路径段、描述里的专有名词，去通用词后成关键词。
2. **枚举**：`~/.config`、`~/.cache`、`~/.local/share`、`~/.local/state`、`~/.var/app` 按"每个应用一条"；共享目录只列应用专属文件；根级点目录/点文件；再对可见目录做限深关键词搜索（覆盖 `~/Documents/Tencent Files` 这类偏门位置）。
3. **追踪**：`--trace` 或命令模式下 strace 抓到的真实读写路径，标记为"追踪到的"，排序优先级最高（名字完全同名的预选次之）。

### 安全边界

- 只动 `$HOME` 内路径；豁免名单（`.ssh`/`.gnupg`/密钥环/shell rc/共享的 mime-icons-fonts-themes/`user-dirs.*`/顶层标准目录整体/包管理器缓存）在**枚举前与删除前各校验一次**。
- 删除是 `rm -rf` 永久删除（按你的要求，不进回收站）；必须输入确认词 `delete`；软链一律跳过；路径不存在则跳过并计数。
- 卸载失败时不进清理流程（避免"配置删了、软件还在"）。
- dry-run 只打印卸载命令与候选清单，不启动被追踪程序、不删任何文件。

### 验收证据（`tests/phase2-leftover.sh`，假 HOME + 假 pacman/paru/fzf）

| 用例 | 断言要点 | 结果 |
|---|---|---|
| 1 `--scan` | 列出 `.config/.cache/.local/share` 与可见目录候选；豁免项不出现；不删任何文件 | 7/7 |
| 2 卸载后清理 | 真调用 `paru -Rns`；四个候选全被删；`.ssh` 与 `gtk-3.0` 完好 | 7/7 |
| 3 确认词不对 | 提示已取消，一条都不删 | 2/2 |
| 4 `--no-clean` | 不追问、不删除，但仍完成卸载 | 3/3 |
| 5 `--dry-run` | 打印 DRY_RUN，不删除，也不调用 paru | 3/3 |
| 6 `pacrrr` 壳 | 追踪目标确实运行过（marker 断言，防假通过）；追踪到的路径被删；答 n 则不卸载 | 3/3 |
| 7 `--trace --dry-run` | 不启动被追踪的程序、不删除 | 3/3 |
| 8 `--help` | 四个新选项都在 | 4/4 |

回归：`tests/phase1-review-gate.sh` 仍 10/10；`bash -n` 与 `shellcheck -S warning` 无告警。

### 两个踩到的坑（留给以后）

1. 本机 bash 5.3 里 `${x/#pattern/repl}` 的锚定形式对**含斜杠**的 pattern 不生效（`${x//pattern/repl}` 才生效），所以路径缩写统一走 `short_path()` 函数（内部用 `${p#"$HOME"/}`）。
2. `run_trace` 的等待循环里有 `read -r -t 1`，非交互喂 stdin 时会立刻返回并把被追踪程序杀掉 —— 测试用延时管道绕开了，真实交互不受影响。

### 尚未真机验证的部分

真实系统上的交互式 fzf 选择、真实 `paru -Rns` 卸载、`--trace` 跑真实 GUI 程序这三条没法在假环境里验，需要你自己跑一次：建议先 `pacr --scan <某个不在乎的包>` 看清单合不合理，再真卸一个小包。

### 许可提示

候选枚举与豁免名单的写法移植自 [shorin-pac](https://github.com/SHORiN-KiWATA/shorin-pac)（GPL-3.0-or-later），`pacr` 头部已注明出处。本仓库目前没有 LICENSE 文件；将来若要对外分发需处理 GPL 兼容问题。

---

## 十一、三期完成记录（2026-10-04）

改动：`pac`（784 → 941 行）并入 Flatpak 支持；`pak`（243 行）变成 18 行转发壳；新增 `tests/phase3-flatpak.sh`。

### 一条列表三种来源

| 来源 | ref 形式 | 预览 | 安装 |
|---|---|---|---|
| 官方源 / AUR | `extra/firefox`、`aur/foo` | `pacman -Si` / `paru -Si --aur` | `paru -S`（AUR 先过审查门禁） |
| Flatpak | `flathub/org.example.App` | `flatpak remote-info` | `flatpak install` |

- Flatpak 列表**必须走 `remote-ls --cached`**：本机实测缓存 0.9s、实时 >30s（会卡死界面），只有缓存为空时才兜底实时拉。
- 预览要传来源列（`--preview {1} {2}`），否则分不清 `flathub/xxx` 是 Flatpak 还是某个仓库名。
- 新增 `--flatpak`（只列 Flatpak，用独立索引缓存），`pak` 壳走它。
- 没有 flatpak 时静默退回纯 pacman/AUR。

### 真机测试揪出来的一个真缺陷（已修）

拿 `kimi-code-bin`（本机真装着的 AUR 包）做只读扫描时，候选有 **28 条**，其中大部分是噪音：拆出来的片段 `code` 靠"包含"匹配命中了 `~/.config/opencode`（53 MB，别人的配置）、`~/Projects/punycode.js`、`~/Documents/leetcode` 等。真删一下就是事故。

修法：关键词分两档。

| 档 | 来源 | 匹配规则 | 命中分数 |
|---|---|---|---|
| 强 | 包名、二进制名、desktop 名、URL 路径段 | 整名相同，或长度 ≥3 的包含匹配 | 100 / 60 |
| 弱 | 名字按 `._-` 拆出来的片段、描述里的大写词 | **只认整名相同** | 40（不预选） |

另外补了"弱升强"：`kimi-code-bin` 会先拆出片段 `kimi`，之后二进制名 `kimi` 必须把它升级为强关键词，否则 `~/.kimi` 会漏（这个是修完第一版才发现的）。

修复后同一个包的候选从 28 条降到 3 条。

### 验收证据

`tests/phase3-flatpak.sh`（假 flatpak/pacman/paru/fzf）：索引三种来源同屏、预览分派、安装分派、dry-run 不安装、pak 壳只列 Flatpak、没有 flatpak 时静默退回 —— **19/19 通过**。
`tests/phase2-leftover.sh` 新增用例 9 钉死关键词规则（弱关键词不得命中 opencode/punycode/leetcode）—— **40/40 通过**。

### 真机验证（用 kimi-code-bin 实跑，测完已还原）

1. 只读扫描 `pacr --scan kimi-code-bin`：候选 3 条（`~/.kimi`、`~/.cache/kimi-code`、备份 tar 包），豁免项不出现。
2. 真卸载 + 真清理：`paru -Rns` 移走 181.94 MiB → 列出候选 → 输入确认词 `delete` → 永久删除两条 → `.ssh`/`.config/fish`/`Projects` 完好。
3. 中途还验证了另一道闸门：sudo 拿不到密码、卸载失败时，脚本打印"卸载命令返回失败，跳过残留清理"，**一条都没删**。
4. 测完还原：`~/.kimi` 从备份解回（8 个文件一致）、`paru -S kimi-code-bin` 重装（2.1.1-2）、测试用的密码垫片删除。

### 注意

- 真机测试用了一个临时的 fzf 替身来做选择（真 fzf 需要终端），并且为了在无终端环境跑 paru 的 sudo，用了一个 askpass 垫片（已删除）。**真实交互式操作还没被人手点过**，建议你自己跑一次 `pac`（装）和 `pacr`（卸）确认手感。
- kimi-code 的测试是用户明确授权的；删除前已备份。

---

## 十二、四期完成记录（2026-10-04）

改动：`pac`（941 → 1370 行）审查链路重写；提示词换成上游 84 行版（旧版 341 行改名 `aur-review.legacy.md` 保留）；新增 `tests/phase4-review-score.sh`。

### 分工变了：模型只报信号，级别由脚本算

| | 以前 | 现在 |
|---|---|---|
| 提示词 | 341 行，四十多条阈值全交给模型 | 88 行，只要求"报出看到了什么 + 附原文" |
| 谁定级 | 模型自己数规则，最后吐 `PAC_DECISION` | `pac` 用固定 jq 规则算，模型无权定级 |
| 证据核实 | 无 | 引用的原文要在证据包里找得到（或它引用的 URL 主机都出现过），否则"恶意"降为可疑、其余不计 |
| 模型手里的工具 | 有（能自己跑命令） | **没有任何工具**（`OPENCODE_CONFIG_CONTENT` 里 edit/webfetch/bash 全拒） |
| 证据来源 | 模型自己去查 | `pac` 备齐：AUR RPC 元数据、`paru -Si`、git 历史、**最近 3 次提交的 diff**、构建目录里每个文件的原文、`.SRCINFO` 与 PKGBUILD 的下载源比对 |

定级规则（照搬上游冻结版本，未改数值）：恶意一条即高；可疑按类别计数，≥2 类为高、1 类且包信誉弱为高、1 类为中；只有"没法完全检查"的地方且信誉弱为中；构建期拉取未锁定依赖且信誉不强为中；其余为低。包信誉由 `pac` 从 RPC 与 git 历史算（上架 <90 天，或最新提交者是近 60 天才出现的新人 → 弱；满一年且 ≥50 票 → 强）。

### 兼容性上的取舍

本机 opencode 是 1.18.31：上游用的 `--standalone` 是 2.x 才有的开关，这里改用 1.x 也支持的 `--pure`（不加载插件）；证据包用 `-f` 作为附件传（避免把几百 KB 塞进命令行参数），提示词同样走 `-f`。

### 验收证据（`tests/phase4-review-score.sh`，假 opencode 喂不同输出）

| 用例 | 断言要点 | 结果 |
|---|---|---|
| 1 干净包 | 结论低风险；包的情况有内容；真的执行了安装 | 3/3 |
| 2 可核实的恶意信号 | 结论高风险；标"已核实"；默认不装 | 3/3 |
| 3 引用不到原文的恶意信号 | 降为可疑 → 中风险（不是高）；标"出处不明，未计入定级"；默认不装 | 3/3 |
| 4 卫生项 + 新包（上架 10 天） | 中风险；报告写明包龄；默认不装 | 3/3 |
| 5 模型输出不是合法 JSON | 提示审查失败；默认不装 | 2/2 |
| 6 `.SRCINFO` 里有 PKGBUILD 没有的下载地址 | 报告列出该不一致并标明是 pac 自己发现的；一条可疑 = 中风险 | 3/3 |

回归：一/二/三期验收脚本仍全绿；`bash -n` 与 `shellcheck -S warning` 无告警。

### 真机试跑（pac --check kimi-code-bin）发现并修掉的问题

1. **tab 切分写法是错的**：`${entry%%*$'\t'}` 这种写法在 bash 里根本不切分（要写成 `${entry%%$'\t'*}` 或用变量装 tab）。后果是包名带着 `\tAUR` 尾巴传给 `paru -G`，真机上直接报"不在 AUR 中的软件包"。这条路径（界面多选后的 ref 解析）以前的测试从没覆盖过，已改用 `tab=$'\t'` 的写法。
2. **默认模型 id 过期**：zen 免费档把 `opencode/deepseek-v4-flash-free` 改名成了 `opencode/deepseek-v4-flash`，真机上报 "Model not found"。已更新默认值，并在模型不可用时打印换模型的提示（`pac --ai-model` 或追问时按 m）。
3. **证据包对空输入不够健壮**：RPC 拿不到内容时 `--argjson` 会报错、整条审查失败。现在三处输入（RPC/信誉/文件清单）都先校验再兜底。

顺带把一期的验收夹具也更新成新协议（假 opencode 输出 JSON 而不是旧的 `PAC_DECISION`），并给它加了假 curl 避免联网。

### 真机链路已通，但 AI 后端暂时不可用

`pac --check kimi-code-bin` 在真机上已经能走完全部前置步骤：拉取 PKGBUILD、构建证据包（2 个文件 / 14787 字节 / 含最近 3 次提交的 diff）、把提示词与证据包交给 opencode。卡在模型这一步：

- 旧默认模型 `opencode/deepseek-v4-flash-free` 已被 zen 改名 → 报 Model not found（已改成 `opencode/deepseek-v4-flash`，并加了换模型的提示）
- 换成 `opencode/deepseek-v4-flash` 与 `opencode/deepseek-v4.1-flash` 都返回 **Upstream request failed: Insufficient account funds**

也就是说这台机器上 zen 免费档已经不能用了，需要挑一个能用的后端：

1. 临时换模型：`pac --ai-model <模型>`，或在审查追问里按 m 从 `opencode models` 里选（前提是那个后端有额度/Key）。
2. 计划里的 T4-6（opencode → agy 自动探测）还没做；本机装着 `agy`，接上它就能不依赖 zen。

**当前的兜底是对的**：审查失败 → 不跳过 paru 自带的 PKGBUILD 复核 → 默认不装（有额度之前，AI 审查这条线相当于关闭状态，装包仍然受 paru 自己的复核保护）。

### 尚未真机验证的部分

真实模型在真实包上的判定质量（误报率、能否抓住恶意）需要后端可用后再跑几次 `pac --check <包名>` 才能下结论。

---

## 十三、五期完成记录（2026-10-04）

改动：`pac`（1370 → 1550 行）AI 后端从"调 opencode CLI"换成"直连 HTTP"；新增 `~/.config/pac/ai.conf`；缓存目录与环境变量改名；新增 `tests/phase5-ai-http.sh`。

### 为什么换

opencode 那条路把三件事绑在第三方工具上：模型 id（zen 一改名就报 Model not found）、额度（免费档说没就没）、插件与工具行为（还得额外配置去关）。换成直连 HTTP 后只剩三样：**url、模型名、key**，而且 HTTP 调用天然没有工具可给模型用。

### 配置

`~/.config/pac/ai.conf`（权限 600）：

    url         = https://api.deepseek.com     # 三种写法都行，会自动补 /v1/chat/completions
    model       = deepseek-chat
    key         = sk-xxxx
    protocol    = openai                       # 可选；anthropic 则走 /v1/messages + x-api-key
    timeout     = 600                          # 可选
    max_tokens  = 4096                         # 可选
    temperature = 0                            # 可选

一次性覆盖：`PAC_AI_URL` / `PAC_AI_MODEL` / `PAC_AI_KEY`。
安全上：只解析「键 = 值」，**不 source 配置文件**（配置里塞命令也不会被执行）；权限不是 600 会警告；报错只打状态码与截断的响应体，**不回显 key**。

### 命令

| 命令 | 作用 |
|---|---|
| `pac ai init` / `--ai-init` | 生成配置模板（600） |
| `pac ai show` / `--ai-show` | 显示配置，key 打码成 `…1234` |
| `pac ai model <名字>` / `--ai-model` | 改模型（只改这一行，注释与其它字段都留着） |
| `pac ai models` / `--ai-models` | 从 {url}/models 拉列表，fzf 选一个写回配置 |

`pac --help` 里新增了 `Commands: ai [init|show|model <名字>|models]` 一节。

### 顺带改名（D11）

- 缓存目录 `~/.cache/paru-ui` → `~/.cache/pac`；启动时若旧目录在、新目录不在，自动 `mv` 一次，已下好的包索引与预览不浪费。
- 环境变量 `PARU_UI_*` → `PAC_*`（`PAC_DRY_RUN`、`PAC_INDEX_MAX_AGE`、`PAC_AUR_INDEX_MAX_AGE`、`PAC_SESSION_CACHE_DIR`），旧名字仍然认。
- 旧的 `~/.cache/pac/opencode_model` 已无人读取，可以删。

### 验收证据（`tests/phase5-ai-http.sh`，假 curl 会记录每次调用）

| 用例 | 断言要点 | 结果 |
|---|---|---|
| 1 `ai init` | 生成模板、权限 600、url/model/key 三行都在 | 6/6 |
| 2 `ai show` | 显示 url 与模型；**完整 key 不出现**，只显示 `…后四位` | 4/4 |
| 3 url 归一化 | 裸域名 / `/v1` / 完整路径三种写法都打到 `/v1/chat/completions` | 3/3 |
| 4 鉴权 | 请求带 `Authorization: Bearer <key>` | 1/1 |
| 5 HTTP 401 | 报 401、提示 key 问题、**报错里没有 key**、默认不装 | 4/4 |
| 6 anthropic 协议 | 打到 `/v1/messages`，用 `x-api-key` | 2/2 |
| 7 `ai model` | 改模型，url/key/注释原样 | 5/5 |
| 8 `ai models` | 请求 `/models`，fzf 选中后写回配置 | 3/3 |
| 9 权限 644 | 打印「建议 chmod 600」 | 1/1 |
| 10 没配置 | 提示后端没配好，**不阻塞安装**（paru -S 不带 --skipreview） | 2/2 |

回归：一~四期四套脚本全绿（10 + 40 + 19 + 17）；`bash -n` 与 `shellcheck -S warning` 无告警。

### 你要做的两步

    pac ai init                      # 生成 ~/.config/pac/ai.conf
    $EDITOR ~/.config/pac/ai.conf    # 填 url / model / key
    pac ai show                      # 确认（key 打码）
    pac ai models                    # 可选：从端点拉列表挑模型

填好之后 `pac --check <AUR 包>` 走的就是四期那套「模型只报信号、pac 定级」；没填之前 AI 审查这条线是关的，装包仍然受 paru 自带 PKGBUILD 复核保护。

---

## 十四、六期完成记录（2026-10-04）

改动：AI 模块从 `pac` 抽成 `lib/pac-ai.sh`（302 行）供两个脚本共用；`pacr` 接上 AI 判残留；新增 `share/prompts/leftover-scan.md`；新增 `tests/phase6-ai-leftover.sh`；README 补 `pacd` 一节。

### 决策变更：抽了共享库

一期时把「不抽共享库」列为非目标，因为那时只有一个消费者。现在 `pacr` 也要发 AI 请求，再复制一份 300 行的模块没有意义，所以抽成 `lib/pac-ai.sh`：`pac` 与 `pacr` 各自 source 它，找不到就退回「没有 AI」的行为（不报错、不阻塞）。配置、协议、鉴权、错误处理全部复用，两个脚本的 AI 行为天然一致。

### pacr 的 AI 残留判定

流程：按名字预筛出候选 → **交给模型判置信度** → 结果并进候选清单 → fzf 里显示「来源 · 置信度」和一句话理由 → 用户勾选 → 输入确认词 → 永久删除。

硬边界（模型说什么都不好使）：

- 模型给的路径必须**存在**、**在 $HOME 内**、**不是软链**、**不在豁免名单**，四条全过才会出现在清单里；`~/.ssh/...`、`/etc/passwd`、不存在的路径在验收里都被丢掉了。
- 模型额外想到的路径（不在预筛列表里的）经同样校验后以 `AI 判定的` 来源列出，**不预选**。
- 只有高置信度（追踪到的 / 名字完全同名的 / AI 判高的）才默认预选，其余要用户自己勾。
- `--no-ai` 完全不发请求；没配 AI 就只按名字匹配；AI 返回坏 JSON 会打印「AI 判定失败」再退回名字匹配 —— 三种情况都不影响主流程。

证据包：@@BT@${home, tokens[], packages[{name,kind,description,url,binaries,data_dir}], candidates[{score,src,bytes,path,matched,location}]}`。为此把 `PKG_META_FILE` 从「一行一个包名」升级成真正的 JSON 记录（描述、URL、`/usr/bin` 下的命令名都写进去）。

### 验收证据（`tests/phase6-ai-leftover.sh`）

| 用例 | 断言要点 | 结果 |
|---|---|---|
| 1 配好 AI | 候选带「AI 判定的」来源、置信度标签与理由；豁免路径（`~/.ssh`）、家目录外路径（`/etc/passwd`）、不存在的路径**全部被丢掉**；AI 额外想到的合法路径被采纳 | 7/7 |
| 2 请求地址 | 打到配置的 `/v1/chat/completions` | 1/1 |
| 3 `--no-ai` | 完全不发请求，仍按名字列出，且没有 AI 的理由 | 3/3 |
| 4 没配 AI | 提示「AI 未配置」，仍列出候选，不发请求 | 3/3 |
| 5 坏 JSON | 提示「AI 判定失败」，仍列出候选 | 2/2 |

另外二期测试加了 AI 配置隔离（`XDG_CONFIG_HOME` 指向空目录），免得测试去读用户真配置、真发请求。

### 真机试跑（pacr --scan kimi-code-bin，只读）

    >> AI 判定残留置信度： cn:deepseek-v4.1-flash @ 127.0.0.1:7863
       候选数量： 2

       [按名字匹配 · 同名] 25KB     ~/.kimi
         家目录下的 .kimi 目录，正是 kimi 命令（kimi-code-bin）存放配置与登录凭证的默认位置。
       [按名字匹配 · 疑似] 9.3KB    ~/scripts/.backups/kimi-home-2026-10-04-1658.tar.gz
         名字含 kimi，是你自己打的 ~/.kimi 备份快照，并非程序自动生成的数据。

模型把「真正的配置目录」和「我自己打的备份包」分得清清楚楚，还主动说明了后者不是程序数据 —— 这正是名字匹配做不到、而 AI 能补上的那一层。

### 补记：两个转发壳已删除（2026-10-04）

`pak`（`exec pac --flatpak`）与 `pacrrr`（`exec pacr --trace-command`）原本是为了不破坏老命令名而留的转发壳，用户要求清掉，于是：

- 删掉这两个文件与 `~/.local/bin` 里的同名链接；对应功能改用 `pac --flatpak` 与 `pacr --trace-command <命令>`。
- 同步更新：`pac` / `pacr` 的帮助文案、二期验收（追踪用例改走 `pacr --trace-command`）、`maintenance/recommend-check` 里对 strace 的描述。
- D6「保留三行壳」随之作废，决策表见下。

### 补记：目录与缓存整理（2026-10-04）

- 审查产物从缓存根目录收进 `~/.cache/pac/review/`：`review-<包>.report` 这类散落文件改成 `review/<包>.report`，`pac --clear-cache` 现在能一次清干净（以前只清索引和预览，散落的报告会一直留着）。
- `pacr` 与 `pacd` 的缓存从 `~/.cache/pacr_tui` / `pacd_tui` 归到 `~/.cache/pac/` 下（pacr 的老目录已自动搬过去，源列表不用重下）。
- 清掉的历史垃圾：`opencode_model`（改成 HTTP 后已无人读）、旧的散落 `review-*` 文件、14 个陈旧 `session.*` 预览缓存（脚本的 trap 正常会清，这些是崩溃/被 Ctrl-C 留下的）。
- 文件权限规范化：命令与验收脚本 755，文档与共享库 644。
- 新增 `tests/run-all.sh`：一把跑完六套并汇总，改完东西跑它就行。

### pacd 文档

`pacd` 代码不动（它比上游 shorin-pac 还多了软件源列表缓存），只在 README 里补了一节：依赖 `downgrade`、两种版本来源（本地缓存 / A.L.A）、走 `pacman` 的依赖拦截、以及「高危依赖警告」是怎么回事。

---

## 附：与上游 shorin-pac 的关系

本套脚本与 [SHORiN-KiWATA/shorin-pac](https://github.com/SHORiN-KiWATA/shorin-pac) 同源（本套更早，2026-06-28~07-01 一代）。上游把 5 个脚本重构成 `bin/pac` + `bin/pacr` + `lib/shorin-pac.sh` + AUR 打包。本次升级**不走整体替换**，只选择性移植上游已验证的部分（候选枚举、证据核实的思路、定级规则、暴露过的坑），保留本套"每个脚本自包含 + strace 追踪 + pacd 降级"的差异。
