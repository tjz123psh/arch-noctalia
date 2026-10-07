# arch-noctalia

一键把 Arch 装成 niri + Noctalia 桌面：软件、驱动、字体、配置、脚本、插件一次到位。

**前置**：基础 Arch + 联网 + `git`（archlinuxcn 源与 `paru` 由安装器自动配置，不用手填）。

## 用法

```bash
U=https://raw.githubusercontent.com/tjz123psh/arch-noctalia/main/bootstrap.sh

curl -fsSL $U | bash                   # 一键实装：拉下仓库并直接开始
curl -fsSL $U | bash -s -- --preview   # 只看计划，不动系统
curl -fsSL $U | bash -s -- --no-aur    # 外网不稳时先跳过 AUR；进桌面后再补：
#   cd ~/arch-noctalia && ./install.sh --run --yes
```

老办法（clone 后本地跑）：`git clone https://github.com/tjz123psh/arch-noctalia.git ~/arch-noctalia`，然后 `./install.sh --preview` 看计划、`./install.sh --run` 开装。

装完重启，就是完整桌面。

## 要点

- 目标机用户名 `pang`（路径按 `/home/pang` 写死）；只从 git/curl 拉取，无离线包。
- 共 12 步：源 → 系统更新 → 软件 → 驱动 → AUR → 桌面 → 配置 → 脚本 → Noctalia → 服务 → 登录界面 → 自检。
- 01 步自动配好 archlinuxcn 与官方镜像表（先备份，再按实测速度重排）；07 步另建标准用户目录、zh_CN locale、fish 登录 shell、主题化 GRUB。
- 中断可续：`./install.sh --run` 接着装；`--redo NN` 从第 NN 步起强制重跑（修复用）。
- 数据安全：便签与 `Templates/` 只在缺失时初始化，你写的内容不会被覆盖；其余文件更新前旧内容备份到 `.state/overwritten/<时间戳>/`。
- btrfs 机器：snapper 时间线快照**每周一次**（`/etc/systemd/system/snapper-timeline.timer.d/override.conf` 覆盖上游 hourly，随 07 部署；保留策略仍由 snapper 自身配置决定）。
- 环境适配：ESP 等 vfat 挂载不做权限位校验、系统文件读取自动走 root；**不改你的挂载设置**。
- 自检：第 12 步查文件 / 软件包 / `~/bin` 软链 / 服务启用状态（含 snapper timeline 的生效日历=每周）；手动跑 `tools/selfcheck.sh`、`tests/run-all.sh`。

## 结构

`bootstrap.sh`、`install.sh`（入口）· `steps/`（12 步）· `manifests/`（清单）· `payload/`（配置/脚本/字体/插件）· `lib/` · `tests/`、`tools/`（自检）。
