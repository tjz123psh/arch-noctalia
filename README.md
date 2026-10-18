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
- 数据安全：便签与 `Templates/` 只在缺失时初始化，你写的内容不会被覆盖；其余文件更新前旧内容备份到 `<状态目录>/overwritten/<时间戳>/`（08 步替换 `~/bin` 下已存在的真实文件时同样先备份）。
- 状态目录：续装记录与覆盖备份放在 `~/.local/state/arch-noctalia/`（不再落在 clone 里，删掉/重克隆仓库不会丢备份）。
- btrfs 机器：snapper 时间线快照**每周一次**（`/etc/systemd/system/snapper-timeline.timer.d/override.conf` 覆盖上游 hourly，随 07 部署；保留策略仍由 snapper 自身配置决定）。
- 快照策略：**root 与 home 走同一条逻辑**——只有维护脚本成套打快照（`quicksave`，以及 `sysup` 升级前的 `quicksave-sysup`；两个配置同一批次）＋ snapper 自身的每周 timeline。`/etc/snap-pac.ini` 随 07 部署，把 `[root] snapshot` 显式设为 `False`，关掉 snap-pac 的「每次 pacman 事务自动快照」（它的默认只对 root 生效，会让 root 比 home 多出一堆零碎快照）。注意：维护脚本的深度清理（`clean all`）只保留 `before*` 节点与最近一套成套批次，timeline 快照也会被它删掉。
- Wi-Fi 热点：Noctalia 没有热点 UI，用 `~/bin/rice-hotspot` 兜底（命令行开关、改名/改密码/换频段）。装了 Docker 的机器上 Docker 的 `FORWARD` 策略是 drop、会挡掉热点客户端（连上没网），脚本会通过 root 助手 `/usr/local/bin/rice-hotspot-net` 往 `DOCKER-USER` 链放行——助手与 `/etc/sudoers.d/rice-hotspot`（只放行这一个脚本）随 07 部署，部署前用 `visudo -cf` 预检。另有一个 `rice-hotspot-net-sync.service`（10 步启用、挂在 `docker.service` 上）：Docker 每次启动都会清掉 `DOCKER-USER`，该单元会自动把放行补回来（热点没在跑时什么都不做）。
  5GHz 热点还要管制域：包 `wireless-regdb`（提供 `/lib/firmware/regulatory.db`）＋ `/etc/modprobe.d/cfg80211-regdom.conf`（`ieee80211_regdom=CN`，随 07 部署）。缺了它内核停在 world 域，5GHz 信道禁止主动发射，AP 模式只能回落 2.4GHz 或随机失败；改过之后要重载无线模块栈（或重启）才生效。
- 终端与编辑器：kitty 配色由 Noctalia 模板生成（`themes/noctalia.conf`，列 `runtime-regenerated.tsv`），字体 Maple Mono NF CN，透明/毛玻璃交给 niri；`conf.d/environment.kdl` 给**整个会话**设 `EDITOR`/`VISUAL`/`SUDO_EDITOR`/`SYSTEMD_EDITOR=nvim`（这台机器只装 nvim、没有 vi/vim/nano，不设的话 `git commit` 不带 `-m`、`systemctl edit`、`sudoedit` 这类命令会失败）。热点改由侧边栏插件 `pang/tide-sidebar` 提供 UI，`~/bin/rice-hotspot` 命令保留、fish 的 `completions/rice-hotspot.fish` 补全已于 2026-10-17 删除；代理环境变量片段 `conf.d/proxy.fish` 已纳入安装器（只在 7890 有监听时才设代理，否则静默跳过）。
- Noctalia 的 shell 字体固定为 `Noto Sans CJK SC`（`[shell] font_family`，随 settings 种子副本部署；提供字体的 `noto-fonts-cjk` 本来就在 `packages.tsv`）：宿主 `ui.input` 的**鼠标拖选**在"中文＋英文/符号混排"时会因字体回退在 run 边界卡住（命中测试按 Pango per-run 度量做视觉行分组；上游未修，属宿主限制），把 shell 字体设成同时覆盖中英文的字体即可绕开（键盘选区不受影响）。**以后换字体要保持"拉丁 + 中文同一字体"**，否则该缺陷复发。
- 文件管理器 yazi：包在 `packages.tsv` 里，桌面项在启动器可见（`Exec=kitty --class yazi -e yazi %f`，同时是「打开文件夹」的候选，nautilus 仍是默认）。
  配色与语法高亮交给 Noctalia 的「Yazi」社区模板（`settings.toml` 的 `community_ids` 已含 `yazi`），产物是 `~/.config/yazi/{theme.toml,flavors/noctalia.yazi/*}`，换壁纸自动重渲染——这三个文件列在 `runtime-regenerated.tsv`，自检只核对存在。
  整屏外框：`init.lua` 里一句 `require("full-border"):setup()`，让整个界面套一圈圆角方框、栏位分隔线接到方框上下沿。插件本体随安装器部署在 `plugins/full-border.yazi/`（上游 yazi-rs/plugins 的 MIT 版本，`main.lua` 头标 `@since 26.8.15`，许可证一并纳管），**不走 `ya pkg` 联网安装**；升级 yazi 后这里若报错，从上游拉最新 `main.lua` 覆盖即可。想换成方角外框，把那行改成 `require("full-border"):setup { type = ui.Border.PLAIN }`。
  键位说明整份汉化在 `keymap.toml`（由 yazi v26.9.1 默认键位翻译而来，按键与行为完全一致；升级 yazi 后需要重新生成）；`yazi.toml` 只放行为设置（文本→nvim、视频音频→mpv；写死程序名，因为从启动器拉起时环境里没有 fish 的 `$EDITOR`）。
  `z`（fzf 跳文件）/ `Z`（zoxide 跳目录）**不用额外装插件**——它们是 yazi 26.x 内置的，`plugins/` 里看不到。按下后状态栏出现的 `1 left` 是任务计数（首次要在当前目录跑一遍 `fd`，家目录文件多时几秒），扫完才弹出选择器；`Esc` 取消即可，不是卡死。
  fish 里加了 `y` 包装：在 yazi 里逛完按 `q` 退出，终端自动 `cd` 到那个目录（`Q` 退出则不换目录）。
   压缩包：`Shift+O` 菜单三条 —— 解压到当前目录 / 同名文件夹 / 指定位置（弹出 fuzzel 选择器，预填当前目录；`yazi.toml` 的 `[open] prepend_rules` 让认不出类型的 `.zip` 也能解压）。
- mpv 增强：`aur.tsv` 装了 `mpv-uosc`（现代 UI）、`mpv-thumbfast-git`（进度条悬停缩略图）、`anime4k-git`（画质 shader）。`mpv.conf` 里 `script=` 显式加载 uosc（本体在 `/usr/share/mpv/scripts`，而 mpv 只自动扫 `~/.config/mpv/scripts` 与 `/etc/mpv/scripts`），并设 `osd-fonts-dir`/`sub-fonts-dir` 指向 `/usr/share/mpv/fonts`——**缺这两行 uosc 的图标字体会找不到、控件条会挤成一团**（实测踩过）。uosc 主题在 `script-opts/uosc.conf`（Noctalia 配色 + 圆角 + 半透明 + 顶栏常显 + 菜单打字搜索），列 `seed.tsv`：装完你在机器上改的不会被重跑覆盖。
  界面：右键 = uosc 菜单，`?` = 键位速查；`Ctrl+o` 打开文件/URL、`Ctrl+l` 加载字幕、`Ctrl+j/a/v` 字幕/音轨/视频轨、`Ctrl+p` 播放列表、`Ctrl+i` 章节、`Ctrl+q` 清晰度、`Ctrl+d` 输出设备、`Ctrl+t` 隐藏界面。Anime4K：`Ctrl+1/2/3` = 模式 A/B/C（1080p/720p/480p 动画），`Ctrl+0` 关闭——**默认关**，开了明显吃 GPU。
  B 站弹幕：`scripts/bdanmaku.lua`（第三方 MIT，许可证一并纳管 `bdanmaku.LICENSE.txt`）+ `~/bin/biliass` 包装脚本（弹幕 XML → ASS）；真正的 biliass 在 `~/.local/share/mpv-danmaku/venv`（首用自动创建，机器本地不入仓）。播放 B 站链接时弹幕自动出现，`v` 即弹幕开关。
  在线字幕：`scripts/assrt.lua` 从 assrt.net 搜字幕（按 `a` 触发）——上游没有许可证文件，为免版权问题**不入公开仓库**（见 `excluded.tsv`）；需要在 `script-opts/assrt.conf` 填自己的 API token（assrt.net 注册后免费获取）。
- 显卡模式（supergfxd）：`/etc/supergfxd.conf` 设 `hotplug_type: "Asus"`（上游 / Arch Wiki 建议值）。ASUS 的 `dgpu_disable` 机制下，若该值为 `None`，supergfxd 开机会把「集显」判成状态错乱、强行把 dgpu_disable 写回 0 并回到 Hybrid —— 表现就是「切集显 → 重启 → 又变混合」。该文件列 `files.tsv` + `runtime-regenerated.tsv`（`mode` 字段由 supergfxd 自写，只核存在性）。
- AI agent 技能共享库：`~/.agents/skills/`（Agent Skills 规范的用户级位置，**DSH 与 pi 都原生读取**）；共用技能放这里、工具专属的留在 `~/.dsh/skills` 与 `~/.pi/agent/skills`；库本体是独立 git 仓库（见 `excluded.tsv` 记账）。共用脚本（`context.mjs` / `palette.mjs` / `pseudoloc.py`）在 `~/.agents/skills/_shared/scripts/`。当前分布：共用 18 个、DSH 专属 2 个（`~/.dsh/skills`）、pi 专属 1 个（`~/.pi/agent/skills/batch`）。
- 内屏刷新率：niri 的 `~/.config/niri/conf.d/outputs.kdl` 与登录界面的 `/etc/nwg-hello/niri.kdl` 都**显式钉 `1920x1080@144.063`**，并**给核显（eDP-1）与 MUX 独显（eDP-2）两个接口名各写一段** —— MUX 切到独显后面板接口名会变，而 `mode` 只写「1920x1080」不带刷新率时 niri 用驱动的 preferred 模式（NVIDIA 那边 preferred 只有 60.061Hz，AMD 那边恰是 144Hz，所以以前没暴露）。
- 环境适配：ESP 等 vfat 挂载不做权限位校验、系统文件读取自动走 root；**不改你的挂载设置**。
- 外观：毛玻璃等 GTK 样式以样式类限定作用域（`gtk.css` 追加段，只影响指定程序）；程序的"系统默认值"以 GSettings vendor override 随 07 部署（`/usr/share/glib-2.0/schemas/*.gschema.override`），07 末尾统一 `glib-compile-schemas` 生效——你在程序里改过的值（dconf）优先，不会被覆盖。
- 未纳管项有账可查：`manifests/excluded.tsv` 记录**手动安装项**（需自行安装，安装器带上会出问题，如 AUR 交互构建、按机器定制、需登录/许可）、安全排除项与各类缓存/生成目录的解释；实际纳管的内容见 `files.tsv` / `packages.tsv` / `aur.tsv`。
- 自检：第 12 步查文件 / 软件包 / `~/bin` 软链 / 服务启用状态（含 snapper timeline 的生效日历=每周）；手动跑 `tools/selfcheck.sh`、`tests/run-all.sh`。
- 自检容差：桌面/程序会自行改写的文件（Noctalia 主题产物、WPS 配置、登录背景…）列在 `manifests/runtime-regenerated.tsv`（只核对存在性），你可能编辑的状态文件列在 `manifests/seed.tsv`（存在即保持）——所以机器用过一段时间后 `--redo 12` 也不会误报“安装失败”。真机对账 `tests/test-machine-reconcile.sh` 用同一份名单豁免内容比对，`AN_RECONCILE_STRICT=1` 可当门禁（本机现为 0 漂移）；清单的形状/白名单/取值由 `tools/selfcheck.sh` 与 `tests/test-manifest-schema.sh` 双重把关。
- 登录界面背景：`payload/system/etc/nwg-hello/background.png` 的初始快照**就是种子默认壁纸**（`Pictures/wallpapers/斑斓.png`，两者字节完全相同），所以装完第一次开机，登录界面和桌面壁纸是一致的；之后每次换壁纸由 `~/bin/rice-login-bg`（Noctalia 的 `wallpaper_changed` hook）按**原字节**跟随改写，不做缩放/重编码，写入走第 11 步加的 `u:pang:rw` ACL，所以这条路径的内容不需要安装器再管（`runtime-regenerated.tsv` 只核存在性）。

## 已知限制与取舍

这套东西是**为一台机器写死**的（用户名 `pang`、路径 `/home/pang`、内屏 144Hz 的 eDP-1/eDP-2 双接口名、ASUS 的 `dgpu_disable` 开关），换机器要改 `lib/` 和清单里的机器相关项。下面几条是“知道、但没做或做不到”的，免得以后再翻一遍：

- **没有 CI**：仓库没有 `.github/`，全部验证靠手动跑 —— `tests/run-all.sh`（15 个回归，多数在 mktemp 沙箱里跑）、`tools/selfcheck.sh`（清单/语法/许可证/密钥）、`tests/test-machine-reconcile.sh`（本机对账，`AN_RECONCILE_STRICT=1` 可当门禁）。
- **只在一台真机上验收**：所有结论来自本机（ASUS TUF A15 + btrfs）。`--machine vm` 分支只有检测与沙箱测试覆盖，没有第二台真机的重装记录。
- **yazi 状态栏字段不可配**：26.9.1 的状态栏内容（大小/权限/滚动位置）由版本写死，主题只能改颜色；视频里那套“权限 + 硬链接 + 属主:属组 + 修改时间”得换旧版本才有。
- **`/boot` 不做快照**：ESP 是 vfat，snapper 无法快照，所以 root/home 的快照不含内核与引导文件。
- **`assrt.lua` 不入公开仓库**：上游没有许可证文件且要自填 API token（记账见 `excluded.tsv`）；`bdanmaku` 有 MIT 许可证，已连同 `LICENSE` 一起纳管。
- **字体是仓库体积的大头**：Maple Mono NF CN 四款 + 资源汉圆体三款共约 123MB（工作区 147MB）；这是“没有离线包、全从 git 拉”的代价。
- **破坏性操作只验证到预演**：维护脚本里真会删数据的（`clean`、快照恢复）测试只覆盖沙箱与 dry-run，实际执行仍需人工在终端确认。

## 结构

`bootstrap.sh`、`install.sh`（入口）· `steps/`（12 步）· `manifests/`（清单）· `payload/`（配置/脚本/字体/插件）· `lib/` · `tests/`、`tools/`（自检）。
