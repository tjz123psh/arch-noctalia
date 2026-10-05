# arch-noctalia

一键把 Arch 装成 niri + Noctalia 桌面：驱动、字体、软件、配置、脚本、插件一次到位。

## 怎么用

重装系统时，先手动装好基础 Arch、能联网、装好 `git`（教程 §9.1 的基础部分；archlinuxcn 源和 `paru` 现在由安装器自动配置，不用手填了）。然后就一行：

```bash
curl -fsSL https://raw.githubusercontent.com/tjz123psh/arch-noctalia/main/bootstrap.sh | bash
```

它会拉下仓库并**直接开始安装**（无人值守；在终端里有 TTY 时 sudo 密码照常提示）。只想先看一眼计划、不动系统：

```bash
curl -fsSL https://raw.githubusercontent.com/tjz123psh/arch-noctalia/main/bootstrap.sh | bash -s -- --preview
```

如果重装当天外网（GitHub/AUR）不稳，可以**先跳过 AUR**——AUR 是唯一需要外网的环节，其余全部走国内镜像：

```bash
curl -fsSL https://raw.githubusercontent.com/tjz123psh/arch-noctalia/main/bootstrap.sh | bash -s -- --no-aur
```

这样 12 步里只跳过第 05 步（AUR），其余照装、装完直接进桌面；AUR 留到桌面里网络从容时再补：

```bash
cd ~/arch-noctalia && ./install.sh --run --yes   # 只补第 05 步（其余阶段自动跳过）
```

也可以老办法来（先看再装）：

```bash
git clone https://github.com/tjz123psh/arch-noctalia.git ~/arch-noctalia
cd ~/arch-noctalia
./install.sh --preview   # 先看一眼要干什么，不动系统
./install.sh --run       # 开始安装
```

装完重启，就是完整的桌面。

## 说明

- 目标机用户名是 `pang`，路径按 `/home/pang` 写死。
- 只从 git / curl 拉取，没有离线包。
- 分 12 步装：源 → 系统更新 → 软件 → 驱动 → AUR → 桌面 → 配置 → 脚本 → Noctalia → 服务 → 登录界面 → 自检。
- 第 01 步会把 archlinuxcn 源**一律写成安装器标准块**（缺失追加／已有整段覆盖；先备份为 `.pre-arch-noctalia`），随后按实测速度重排镜像；**官方仓库镜像表**（`/etc/pacman.d/mirrorlist`）也会写成标准列表（tuna 打头，先备份）。之后装好 `archlinuxcn-keyring` 与 `paru`。
- 配置步（07）铺完文件后还会：建标准用户目录（Desktop/Documents/Downloads/…/Templates、Pictures/Screenshots）、生成 zh_CN locale、把登录 shell 设为 fish、重建带主题的 GRUB 菜单。
- `--no-aur` 跳过第 05 步（AUR）且**不标记完成**；之后任何时候 `./install.sh --run --yes` 都会只补这一步（其余阶段自动识别为已完成）。
- 中断了没关系，重跑 `./install.sh --run` 会接着来，装过的不会重复装。**要强制重跑某段（重跑修复）**：`./install.sh --run --redo NN` —— 从 NN 起清掉完成记录并重新执行（如 `--redo 07` 重铺配置）。
- **个人数据不会被覆盖**：两份便签和 `Templates/` 是"种子"——只在缺失时初始化，你在机器上写的内容安装器绝不碰；其余文件若与仓库版本不同会被覆盖，但覆盖前会把旧内容备份到 `.state/overwritten/<时间戳>/`（该目录在克隆的仓库里，可随手恢复）。
- **权限与 vfat**：GRUB 主题等目标若落在 vfat（ESP）上，权限位由挂载选项（fmask/dmask）统一决定——安装器在 FAT 系文件系统上跳过权限位校验、系统文件读不到时自动改用 root 读，**不改动你的挂载设置**；ESP 怎么挂都不影响部署与自检。
- 第 12 步自检范围：文件清单、软件包、`~/bin` 软链（存在且可执行）、服务启用状态；"启用但当前未运行"只提示不算失败（可能待重启 / 无对应硬件）。
- 想自己检查一下（可选）：`tools/selfcheck.sh`、`tests/run-all.sh`。

## 目录

- `install.sh` / `bootstrap.sh` —— 入口（bootstrap = clone + 直接转 install；不带参数时按 `--run --yes` 一键实装）
- `steps/` —— 12 个安装步骤
- `manifests/` —— 软件和文件的清单
- `payload/` —— 要装到机器上的配置、脚本、字体、插件
- `lib/` —— 公共代码；`tests/`、`tools/` —— 自检
