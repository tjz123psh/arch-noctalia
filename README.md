# arch-noctalia

把干净的 Arch Linux 一键装成 **niri + Noctalia** 桌面（Wayland）：驱动、字体、配置、脚本、插件一次到位，装完重启就能用。

## 要求

- 刚装好的 Arch：能登录 TTY、能联网（archinstall 装完的状态就够）
- 用户名 `pang`（路径按 `/home/pang` 写死）
- 用普通用户跑，过程中会让你输 sudo 密码

## 安装

```bash
git clone https://github.com/tjz123psh/arch-noctalia.git ~/arch-noctalia
cd ~/arch-noctalia
./install.sh
```

装完 `sudo reboot`。

## 装完之后

- 桌面：niri 平铺窗口管理器 + Noctalia（状态栏 / 侧边栏 / 插件）
- 登录界面：greetd + nwg-hello，壁纸与桌面同步
- 常用软件：kitty、fish、nvim、yazi、mpv、fuzzel、fcitx5、Docker、snapper 快照、ASUS 显卡切换
- 自制脚本都在 `~/bin`，配置在 `~/.config`，全部由本仓库部署

## 常用命令

| 命令 | 作用 |
|------|------|
| `./install.sh` | 安装；中断了再跑会接着装 |
| `./install.sh --preview` | 只看计划，不动系统 |
| `./install.sh --redo 07` | 从第 7 步起重跑（改完配置想让它生效） |
| `./install.sh --no-aur` | 先跳过 AUR 包，进桌面后再补 |

## 结构

`install.sh` 入口 · `steps/` 12 个步骤 · `manifests/` 清单（要装什么） · `payload/` 实际文件 · `lib/` 公共函数 · `tests/` 回归测试。

## 更多

设计取舍、每条配置为什么这么写、已知限制：见 [docs/DETAILS.md](docs/DETAILS.md)。
