# WORKING.md — 工作状态与交接

> 更新：2026-10-05（里程碑推进中）。
> 本文件是"干到哪、下一步是什么"的单一来源；每个里程碑节点更新一次。

## 里程碑（当前目标）

**工作文档先行 → 骨架 → 样本入仓（配置不丢）→ 清单对账 → 步骤实现 → VM 预览验收。**

| # | 事项 | 状态 |
|---|---|---|
| 1 | 仓库建立 + 工作文档（README + 本文件），首个提交 | ✅ a0ca616 |
| 2 | 骨架：`bootstrap.sh` / `install.sh`（含预览）/ `lib/` / `steps/01…12` / 工具 | ✅ 4c4510c |
| 3 | VM 样本导出 → `payload/` + `manifests/files.tsv`（193 文件逐字节一致，0 失配；密钥排除扫描通过） | ✅ |
| 4 | `manifests/packages.tsv` / `aur.tsv` 生成 + 对账（0 未解释） | ⬜ 进行中 |
| 5 | steps 01–12 实现（01-sources / 02-system / 03-packages 为可安全实跑版本） | ⬜ |
| 6 | VM 预览 ×2 验收（输出一致、系统零改动）+ 证据落盘 + 全部提交 | ⬜ |

## 关键设计（已定）

- **数据驱动**：`manifests/packages.tsv`（官方/archlinuxcn）、`manifests/aur.tsv`（外来/AUR）、`manifests/files.tsv`（repo 路径 ↔ 目标绝对路径、权限、md5）、`manifests/bin-links.tsv`（`~/bin` 软链层）、`manifests/excluded.tsv`（排除项 + 理由，样本与对账共用）。
- **纯逻辑与落盘分离**：清单解析、环境检测、阶段计划渲染在 `lib/`；预览与实装共用同一份"将要发生什么"。
- **获取方式**仅 `git clone`／`curl`；无离线缓存、无多桌面矩阵（就 niri + Noctalia）。
- **目标用户名固定 `pang`**；payload 内路径按 `/home/pang` 写入。
- **凭据零入库**：fish 的 `*-env.fish`、`gh/hosts.yml` 等一律排除并记录；入库前密钥扫描。
- **样本刷新工具**：`tools/capture-from-vm.sh`（VM → payload + 清单，幂等）+ `tools/verify-payload.sh`（逐字节复核）。

## 样本现状（2026-10-05 导出）

- 193 个文件 / 130M payload（字体 123M、壁纸 4M、脚本 83 个、插件 6 个、配置若干）。
- VM 原件 ↔ payload 全量 md5 比对：0 失配。
- `~/bin` 软链 16 条（12× `scripts/desktop`、4× `.config/niri/scripts`）；cursor-track 二进制不入仓（由 09 步重建）。

## 后续目标（本里程碑之外）

- 干净 VM 端到端实装验证（跑完安装器得到成品桌面，与样本逐项对比）。
- 物理机实装（用户点名后）。
- GitHub 推送与 `curl` 全链路（用户逐次点名）。

## 下一步

第 4 项：生成并核对 `manifests/packages.tsv` / `aur.tsv`（对账脚本 + 0 未解释 + 密钥扫描）。
