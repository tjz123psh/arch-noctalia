# WORKING.md — 工作状态与交接

> 更新：2026-10-05（起步里程碑开始时）。
> 本文件是"干到哪、下一步是什么"的单一来源；每个里程碑节点更新一次。
> 首个提交只有本文件与 README——遵用户要求"工作彻底开始前，先写好工作文档"。

## 里程碑（当前目标）

**工作文档先行 → 骨架 → 样本入仓（配置不丢）→ 清单对账 → 步骤实现 → VM 预览验收。**

| # | 事项 | 状态 |
|---|---|---|
| 1 | 仓库建立 + 工作文档（README + 本文件），首个提交 | ✅ |
| 2 | 骨架：`bootstrap.sh` / `install.sh`（含预览）/ `lib/` / `steps/01…12` / `manifests/` / `payload/` | ⬜ |
| 3 | VM 样本导出 → `payload/` + `manifests/files.tsv`（全量 md5 比对 0 失配；密钥排除） | ⬜ |
| 4 | `manifests/packages.tsv` / `aur.tsv` 生成 + 对账（0 未解释）+ 密钥扫描 | ⬜ |
| 5 | steps 01–12 实现（01-sources / 02-system / 03-packages 为可安全实跑版本） | ⬜ |
| 6 | VM 预览 ×2 验收（输出一致、系统零改动）+ 证据落盘 + 全部提交 | ⬜ |

## 关键设计（已定）

- **数据驱动**：`manifests/packages.tsv`（官方/archlinuxcn）、`manifests/aur.tsv`（外来/AUR）、`manifests/files.tsv`（repo 路径 ↔ 目标绝对路径、权限、md5）、`manifests/excluded.tsv`（排除项 + 理由）。
- **纯逻辑与落盘分离**：清单解析、环境检测、阶段计划渲染在 `lib/`；预览与实装共用同一份"将要发生什么"（单一来源）。
- **获取方式**仅 `git clone`／`curl`；无离线缓存、无多桌面矩阵（就 niri + Noctalia）。
- **目标用户名固定 `pang`**；payload 内路径按 `/home/pang` 写入。
- **凭据零入库**：fish 的 `*-env.fish`、`gh/hosts.yml` 等一律排除并记录；入库前密钥扫描。

## 样本来源（VM，只读）

niri 配置（config.kdl + conf.d）、Noctalia 设置（settings.toml / hooks.toml）、两个自制插件源（含 cursor-track 源码）、`~/scripts` + `~/bin` 软链目标、三个手工字体、greeter 资产（/etc/greetd、/etc/nwg-hello、头像）、壁纸。逐文件清单 = `manifests/files.tsv`（由 `tools/capture-from-vm.sh` 生成/刷新）。

## 后续目标（本里程碑之外）

- 干净 VM 端到端实装验证（跑完安装器得到成品桌面，与样本逐项对比）。
- 物理机实装（用户点名后）。
- GitHub 推送与 `curl` 全链路（用户逐次点名）。

## 下一步

按里程碑表第 2 项开始：搭骨架。
