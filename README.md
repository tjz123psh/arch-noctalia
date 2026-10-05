# arch-noctalia

一键把 Arch 装成 niri + Noctalia 桌面：驱动、字体、软件、配置、脚本、插件一次到位。

## 怎么用

重装系统时，先手动装好基础 Arch、能联网（就是我安装教程里 §9.1 那步：`pacman.conf` 加上 archlinuxcn 源，装好 `paru` 和 `git`）。然后：

```bash
git clone https://github.com/tjz123psh/arch-noctalia.git ~/arch-noctalia
cd ~/arch-noctalia
./install.sh --preview   # 先看一眼要干什么，不动系统
./install.sh --run       # 开始安装
```

也可以一行把仓库拉下来（拉完先预览）：

```bash
curl -fsSL https://raw.githubusercontent.com/tjz123psh/arch-noctalia/main/bootstrap.sh | bash
```

装完重启，就是完整的桌面。

## 说明

- 目标机用户名是 `pang`，路径按 `/home/pang` 写死。
- 只从 git / curl 拉取，没有离线包。
- 分 12 步装：源 → 系统更新 → 软件 → 驱动 → AUR → 桌面 → 配置 → 脚本 → Noctalia → 服务 → 登录界面 → 自检。
- 配置步（07）铺完文件后还会：建标准用户目录（Desktop/Documents/Downloads/…/Templates、Pictures/Screenshots）、生成 zh_CN locale、把登录 shell 设为 fish、重建带主题的 GRUB 菜单。
- 中断了没关系，重跑 `./install.sh --run` 会接着来，装过的不会重复装。
- 想自己检查一下（可选）：`tools/selfcheck.sh`、`tests/run-all.sh`。

## 目录

- `install.sh` / `bootstrap.sh` —— 入口（bootstrap 就是 clone 再转 install）
- `steps/` —— 12 个安装步骤
- `manifests/` —— 软件和文件的清单
- `payload/` —— 要装到机器上的配置、脚本、字体、插件
- `lib/` —— 公共代码；`tests/`、`tools/` —— 自检
