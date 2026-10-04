# WORKING.md — 工作状态与交接

> 更新：2026-10-05（里程碑推进中）。
> 本文件是"干到哪、下一步是什么"的单一来源；每个里程碑节点更新一次。

## 里程碑（当前目标）

**工作文档先行 → 骨架 → 样本入仓（配置不丢）→ 清单对账 → 步骤实现 → VM 预览验收。**

| # | 事项 | 状态 |
|---|---|---|
| 1 | 仓库建立 + 工作文档（README + 本文件），首个提交 | ✅ a0ca616 |
| 2 | 骨架：`bootstrap.sh` / `install.sh`（含预览）/ `lib/` / `steps/01…12` / 工具 | ✅ 4c4510c |
| 3 | VM 样本导出 → `payload/` + `manifests/files.tsv`（191 文件逐字节一致，0 失配） | ✅ 0979c21 |
| 4 | `manifests/packages.tsv`（167，含 repo/module）/ `aur.tsv`（12）生成 + 对账（0 未解释、0 遗漏） | ✅ 5f31bcb |
| 5 | steps 主体复核 + `tests/`（回归测试驱动真实入口，全部通过） | ✅ |
| 6 | VM 预览 ×2 验收（输出一致、系统零改动）+ 证据落盘 + 全部提交 | ⬜ 进行中 |

## 关键设计（已定）

- **数据驱动**：`manifests/packages.tsv`（官方/archlinuxcn，含 repo + module）、`manifests/aur.tsv`（外来/AUR，含 channel + role）、`manifests/files.tsv`（repo 路径 ↔ 目标绝对路径、权限、md5）、`manifests/bin-links.tsv`（`~/bin` 软链层）、`manifests/excluded.tsv`（排除项 + 理由，样本与对账共用）。
- **纯逻辑与落盘分离**：清单解析、环境检测、阶段计划渲染在 `lib/`；预览与实装共用同一份"将要发生什么"。
- **获取方式**仅 `git clone`／`curl`；无离线缓存、无多桌面矩阵（就 niri + Noctalia）。
- **默认动作 = 只读预览**（`./install.sh`）；实装用 `./install.sh --run`（可 `--yes`）。
- **目标用户名固定 `pang`**；payload 内路径按 `/home/pang` 写入。
- **凭据零入库**：fish 的 `*-env.fish`、`gh/hosts.yml` 等一律排除并记录；入库前密钥扫描。
- **工具**：`tools/capture-from-vm.sh`（VM → payload + 清单，幂等）、`tools/verify-payload.sh`（逐字节复核）、`tools/reconcile.sh`（包清单生成 + 对账）、`tools/selfcheck.sh`（语法/映射/密钥三合一自检，含"payload 必须全部 tracked"检查——样本自带 .gitignore，被屏蔽文件需 `git add -f`）。
- **测试**：`tests/run-all.sh` 驱动真实入口（预览确定性/无落盘、环境识别单行回归、bootstrap 本地克隆交接、清单本地一致性、selfcheck 通过）。

## 样本与清单现状（2026-10-05 导出）

- **191 个文件 / 130M payload**（字体 123M、壁纸 4M、脚本 83 个、插件 6 个、配置若干）；VM ↔ payload 全量 md5：0 失配。
- 包清单：原生显式 167（core 12 / extra 145 / archlinuxcn 8 / multilib 2；模块 drivers 17、desktop 17、audio 2、vmware-guest 1）；外来 12（全 AUR 通道，含 1 个依赖）。
- `~/bin` 软链 16 条；cursor-track 二进制不入仓（由 09 步重建）。

## 后续目标（本里程碑之外）

- 干净 VM 端到端实装验证（跑完安装器得到成品桌面，与样本逐项对比）——含 04–12 步骤的完整实现。
- 物理机实装（用户点名后）。
- GitHub 推送与 `curl` 全链路（用户逐次点名）。

## 下一步

第 6 项：VM 预览 ×2 验收（输出一致、系统零改动）与全部证据落盘。
