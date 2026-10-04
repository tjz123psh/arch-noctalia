# arch-noctalia

> 一键安装器：把 **物理机 Noctalia 安装形态（在 VM 里逐项验证过的这一套）** 装到重装后的 ASUS TUF A15（AMD + NVIDIA）。
> （名字暂拟，可改。）

## 这是什么

物理机重装时，手动做到《Arch 安装教程》**§9.1「配置下载源」（含）**——具体为：

1. LiveCD → `archinstall` 完成基础系统（GPT/UEFI、btrfs、GRUB、用户 `pang`、NetworkManager）；
2. 首启进 TTY → `nmtui` 联网；
3. `pacman.conf` 加入 archlinuxcn 源；
4. `sudo pacman -S --needed paru git`。

**从 §9.2 起（头文件、显卡驱动、字体、32 位源、音视频、桌面、中文、输入法、软件、快照/回滚、登录界面、KVM、ROG、录屏、个人工具——直到 §19）全部由本安装器接管。**

装完得到与"已验证样本"逐项一致的桌面：niri + Noctalia、两个自制插件（侧栏 / 放大镜）、脚本体系、字体、壁纸与登录界面。

## 两种获取方式（仅此两种；无离线缓存）

```bash
# 方式一：git clone
git clone <repo-url> ~/arch-noctalia && cd ~/arch-noctalia && ./install.sh

# 方式二：curl 引导（内部同样是 git clone）
curl -fsSL <bootstrap-raw-url> | bash
```

未推送前用本地路径：`git clone /home/pang/Projects/arch-noctalia ~/arch-noctalia`。

> `./install.sh` 的默认动作是**只读预览**（见下节）；实装用 `./install.sh --run`（可加 `--yes` 免确认）。

## 预览模式（不落盘）

```bash
./install.sh --preview    # 只读：识别环境 → 渲染完整阶段计划 → 退出，不改动任何文件
```

## 阶段

| # | 阶段 | 内容 |
|---|---|---|
| 01 | sources | 校验/补齐 archlinuxcn keyring；源健康检查 |
| 02 | system | 首次全系统更新 |
| 03 | packages | 官方/archlinuxcn 包（manifests/packages.tsv） |
| 04 | drivers | AMD/NVIDIA/固件/asusctl（物理机） |
| 05 | aur | AUR/外来包（manifests/aur.tsv，paru 逐个） |
| 06 | desktop | niri + Noctalia |
| 07 | config | dotfiles 部署（payload → 目标绝对路径） |
| 08 | scripts | ~/scripts + ~/bin 软链体系 |
| 09 | noctalia | Noctalia 设置 + 插件源 + cursor-track 构建 + 启用 |
| 10 | services | docker/蓝牙/snapper/snap-pac/btrfs-scrub/rice-dnd 等 |
| 11 | greeter | greetd + nwg-hello + 壁纸/头像/登录背景 |
| 12 | verify | 装后自检（对照 manifests/files.tsv 逐项核） |

## 数据与原则

- **数据驱动**：包来自 `manifests/*.tsv`；文件来自 `payload/`（映射与 md5 见 `manifests/files.tsv`）；脚本不硬编码清单。
- **配置永不丢失**：样本来自 VM 里已验证的形态；`tools/` 里是可重复运行的"VM → payload"提取与对账工具，任何时候可重刷、可审计。
- **简单可读**：单文件单职责、幂等、能重跑、坏了看得懂；只有 `git`／`curl` 两种获取方式，无离线缓存。
- **凭据零入库**：密钥类文件按排除清单（`manifests/excluded.tsv`）不入仓，入库前跑密钥扫描。

## 手工前置（安装器不代做）

- 按教程做到 §9.1（含）；基础系统为 UEFI + GPT + btrfs + GRUB。
- **目标用户名固定 `pang`**：payload 中路径按 `/home/pang` 写入；换名需自行修正。
- 带凭据的个人项目（如 NapCat 机器人、锐捷客户端）不纳入自动安装，按"手工准备项"处理。

## 当前状态

- 2026-10-05：仓库建立（**文档先行**——首个提交只有本文件与 `WORKING.md`）；随后按里程碑推进：骨架 → 样本入仓 → 清单对账 → 步骤实现 → VM 预览验收。
- 工作状态与交接：见 [`WORKING.md`](WORKING.md)。
