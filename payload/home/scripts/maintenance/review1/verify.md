# 对抗性复核报告（verifier · task-5）— 12 条关键结论的独立复现

复核日期：2026-09-10。方法：不采信原报告推理，重新读源码 + 在 /tmp 沙箱用命令桩/合成夹具端到端复现，逐条给出自己的命令与输出。
合规声明：工作区全程只读（未修改任何文件），未访问 review/；未执行 clean/cache-clean apply、scrub start、quicksave 真建快照、quickload、sysup 真升级、备份/恢复 apply、systemctl 写等破坏性操作；所有实测的 HOME、XDG_*、GIT_CONFIG_GLOBAL、PATH、锁文件、mirrorlist、备份目录、staging 目录全部指向 /tmp 夹具。
沙箱：/tmp/vsbx/src（脚本副本 + lib/）、/tmp/vsbx/bin*（桩）、/tmp/vsbx/home*（假 HOME）、/tmp/vsbx/v7|v10|v11（专用夹具）。
环境：Arch/Btrfs，bash 5.3.15，git 2.55.0，GNU coreutils，ncurses clear。

判定汇总：CONFIRMED 12 条（其中 V1 附带两处细节修正；F-01 的一条子结论被证伪并改写为更严重的描述），REFUTED 0 条，UNVERIFIABLE 0 条。

---

## V1（ui-checks P1-1）terminal-tools:241-247，! cmd 之后取 $? 恒为 0

**判定：CONFIRMED（原结论成立；"只能手工把键补回去"一句被证伪）。**

独立复现（沙箱 HOME + git 2.55.0）：

~~~
export HOME=/tmp/vsbx/home_v1 XDG_CONFIG_HOME=/tmp/vsbx/home_v1/.config XDG_STATE_HOME=/tmp/vsbx/home_v1/.local/state
git config --global core.pager less      # 另加 interactive.diffFilter / delta.side-by-side / merge.conflictstyle
/tmp/vsbx/src/terminal-tools --enable    # rc=0，写入 6 个键 + 状态文件
git config --global --unset delta.navigate      # 模拟用户手动删掉一个托管键
/tmp/vsbx/src/terminal-tools --disable          # rc=1
~~~

关键输出：

- bash 语义：bash -c 'if ! (exit 5); then echo rc_inside_then=$?; fi' → rc_inside_then=0；git config --global --unset-all delta.navigate（键不存在）→ 退出码 5。
- --disable 报「[错误] 无法清除 Git 配置项 delta.navigate（退出码 0）。」退出码 1（这里打印的是 ! 的结果 0，不是 git 的 5）。
- 失败后仍在的键：delta.side-by-side=true / merge.conflictstyle=zdiff3 / diff.colormoved=default；已正确恢复的键：core.pager=less / interactive.difffilter=原值。
- 状态文件 terminal-tools-git-before.tsv 保留；重跑 --disable 仍在同一处失败（rc=1），不会自愈。
- 新增验证（原报告未做）：失败后再执行 --enable（会重新写全 6 个键）→ --disable → **rc=0，完全恢复**（core.pager=less、interactive.diffFilter 原值、delta.side-by-side=false、merge.conflictstyle=diff3；delta.navigate 与 diff.colorMoved 原本不存在，被正确清掉），状态文件删除。

与原报告的差异：

1. 原报告写「core.pager / interactive.diffFilter / delta.navigate 已被删除、旧值未恢复」——实测 core.pager 与 interactive.diffFilter **已正确恢复**（它们在故障键之前处理），未恢复的是 delta.navigate 之后的 3 个键。
2. 原报告写「用户无法用脚本完成回退，只能手工把键补回去」**不成立**：先 --enable 再 --disable 是脚本内可行的完整回退路径；只有"反复执行 --disable"不能自愈。

级别建议：原 P1 → **建议 P2**。影响面是用户级 Git 显示配置的半恢复 + 一次误报退出码，无数据丢失，且有脚本内恢复路径；不构成 P1。若项目把"文档承诺的回退操作单次失败"本身定级 P1，可保留 P1，但必须修正上述影响面描述。

---

## V2（ui-checks P1-2）无 ~/.gitconfig 时 --enable 恒定失败

**判定：CONFIRMED。**

独立复现（全新 HOME，无 ~/.gitconfig、无 $XDG_CONFIG_HOME/git/config）：

~~~
HOME=/tmp/vsbx/home_v2 git config --global --list          # 致命错误: 无法读取配置文件 .../.gitconfig: 没有那个文件或目录
echo rc=$?                                                  # 128
HOME=/tmp/vsbx/home_v2 /tmp/vsbx/src/terminal-tools --enable
echo rc=$?                                                  # 1
ls /tmp/vsbx/home_v2/.config/fish /tmp/vsbx/home_v2/.local/state/maintenance   # 都不存在
~~~

- 输出顺序：6 行「[成功] 已找到: fish/bat/zoxide/git/delta/base64」→「[错误] 无法读取当前用户的 Git 全局配置；未修改 Git 设置。」rc=1。
- 失败点在 capture_git_state → git_global_readable，早于 rewrite_fish_config，所以 **Fish 块也没写**（原报告正确）。
- 对照：创建 $XDG_CONFIG_HOME/git/config 后 git config --global --list rc=0。

与原报告的差异：无（128 / rc=1 / 无任何写入，与报告一致）。

级别建议：原 P1 → **建议 P2**。功能在"新装机没有全局 gitconfig"这一常见状态下完全不可用，但失败是干净失败（无写入、有明确中文报错、退出码非 0），无数据风险；按"功能不可用但有明确报错"定 P2 更合适。

---

## V3（ui-checks P1-3）符号链接 config.fish 被换成 0777 常规文件

**判定：CONFIRMED。**

独立复现：

~~~
mkdir -p /tmp/vsbx/home_v3/.config/fish /tmp/vsbx/home_v3/dotfiles
printf 'set -gx EDITOR nvim\n' > /tmp/vsbx/home_v3/dotfiles/config.fish
ln -s /tmp/vsbx/home_v3/dotfiles/config.fish /tmp/vsbx/home_v3/.config/fish/config.fish
stat -c '%a'  .../config.fish      # 777   （脚本第 89 行用的就是不带 -L 的 stat）
stat -Lc '%a' .../config.fish      # 644   （真实目标）
/tmp/vsbx/src/terminal-tools --enable   # rc=0
ls -l .../config.fish              # -rwxrwxrwx ... config.fish
[[ -L .../config.fish ]]           # NO
grep -c 'maintenance terminal-tools' dotfiles/config.fish   # 0（目标文件没被改）
~~~

与原报告的差异：无（连输出形态 -rwxrwxrwx 都一致）。

级别建议：原 P1 → **保持 P1**（不建议降级，也未被夸大）。理由：交互式 Fish 启动时会执行该文件，它是 world-writable 的常规文件，本地其他用户可写入并在该用户开启终端时以该用户身份执行代码，属本地提权面；同时静默破坏 dotfiles 工作流。触发条件是"config.fish 为软链"（dotfiles 用户常见），后果是安全性的，定 P1 合理。

---

## V4（update-chain F-01 / F-02）缓存不可写仍 exit 0 打印旧缓存；状态先写 ok 后 mv 失败被忽略

**判定：CONFIRMED（两条机制都独立复现）。**

F-01 复现（桩 checkupdates/paru/flatpak，先健康刷新，再 chmod 500 缓存目录）：

~~~
HOME=/tmp/vsbx/home_cau PATH=/tmp/vsbx/bin_cau:$PATH /tmp/vsbx/src/checkallupdates --refresh
~~~

关键输出：

- REFRESH_RC=0；桩日志 0 行（**没有任何来源被查询**）；stderr 10 行「mktemp: ... 权限不够」。
- stdout 原样打印上一轮缓存（linux 6.10.1-1 -> 6.10.2-1 …），三个来源文件字节数与内容全部未变。
- CACHE_STAMP（last-refresh）mtime 1789042375 → 1789042377，age=0 → 边框标签会显示「刚刚更新」。

F-02 复现（更干净的做法：让 checkupdates 桩在返回前删掉自己的 repo.XXXXXX 临时文件，模拟 mv 前文件消失）：

~~~
mv: 对 '.../repo.9HJULA' 调用 stat 失败: 没有那个文件或目录
REFRESH_RC=0
source-status.tsv:  pacman ok / aur ok / flatpak ok
last-refresh-pacman: 被 touch（age=0）
updates-repo.txt: 仍是旧内容（6.10.2-1，新结果丢失）
~~~

与原报告的差异：**原报告 F-01 说「边框时间标签也不会更新」是错的**。旧 source-status.tsv 里没有 error 行 → refresh_failed 保持 0 → touch "$CACHE_STAMP" 成功 → 时间标签反而被刷新。即实际是"旧数据 + 新鲜时间戳"，比原报告描述的"旧列表配旧时间"更严重。其余（exit 0、0 次查询、旧缓存当刷新结果、sysup:406 的失败检测失效）全部一致。

级别建议：原 P1 → **保持 P1**。机器可读入口 exit 0 谎报成功、sysup 的"刷新失败不再静默"保证失效、UI 把旧数据标成刚刚更新；属静默正确性失败，P1 合理。

---

## V5（update-chain F-05）mirror-update 回滚用历史旧备份覆盖当前 mirrorlist

**判定：CONFIRMED（端到端复现数据丢失路径）。**

夹具与命令（全部在 /tmp，未触碰真实 /etc）：

~~~
MIRRORLIST_PATH=/tmp/vsbx/mu/etc/pacman.d/mirrorlist
MIRROR_BACKUP_DIR=/tmp/vsbx/mu/backups        # 只有 mirrorlist-20200101-000000-1.bak（39B，2020 年）
MAINTENANCE_LOCK_FILE=/tmp/vsbx/mu/maintenance.lock
reflector 桩：--list-countries 正常，其余三次尝试全部 exit 1；sudo 桩透传
/tmp/vsbx/src/mirror-update -c Japan
~~~

关键输出（CASE A，当前文件只有 Include 行，无 Server 行）：

~~~
before:  # user current config
         Include = /etc/pacman.d/mirrorlist.d/*.conf
EXIT=1
[注意] 当前 mirrorlist 无效，保留历史备份不覆盖：.../mirrorlist-20200101-000000-1.bak
[错误] 所有尝试均失败。
[成功] 已从备份恢复原始镜像源。
after:   Server = https://ancient.example.com/x          ← 2020 年备份覆盖了用户当前配置
备份目录仍只有那 1 份 39B 历史备份（当前文件从未被备份）
~~~

对照（CASE B，当前文件以 Server = 开头）：EXIT=1，回滚后内容仍是用户原来的 Server 行（先备份再回滚，行为正确）。

精确触发条件：当前 mirrorlist 不存在以行首「Server = 」开头的行（Include 式配置 / 全部被注释 / 空文件）+ 本轮 reflector 三次尝试全失败 + 备份目录存在至少一份匹配命名正则的历史备份；第三条不满足时脚本在 369 行提前报错退出（trap 尚未注册，不会覆盖）。

与原报告的差异：无（位置、触发条件、后果一致）。

级别建议：原 P1 → **保持 P1**（静默销毁用户当前配置，且当前文件没有被备份），但必须注明触发面窄：本机 /etc/pacman.d/mirrorlist 是标准 Server 行格式，默认状态不触发；Include/全注释/空文件属少数配置。若项目要求 P1 必须"常见路径可触发"，可标为 P1/P2 之间；我建议保留 P1 并把触发前提写进标题。

---

## V6（update-chain F-06）sysup --yes 在 TERM 未设置/dumb 时因 clear 失败而 set -e 退出

**判定：CONFIRMED。**

最小实验（未跑真实升级）：

~~~
env -u TERM bash -c 'set -e; clear; echo REACHED_AFTER_CLEAR'   # 无输出，退出 1；stderr: TERM environment variable not set.
TERM=dumb bash -c 'set -e; clear; echo REACHED_AFTER_CLEAR'     # 同样退出 1（TERM=dumb 也为真）
TERM=xterm-256color bash -c 'set -e; clear; echo REACHED_AFTER_CLEAR'   # 正常输出 REACHED_AFTER_CLEAR
env -u TERM bash -c 'clear; echo clear_rc=$?'                   # clear_rc=1
~~~

沙箱 sysup（脚本副本 + 15 个命令桩：sudo/curl/quicksave/mirror-update/checkallupdates/post-update-check/pacman/paru/flatpak/grub-mkconfig/findmnt/systemd-inhibit/reflector/python，HOME/锁/桩日志全在 /tmp）：

~~~
env -u TERM /tmp/vsbx/src/sysup --yes </dev/null
→ rc=1, stdout 0 字节, stderr 35 字节（只有 clear 的报错）, 桩日志 0 行
对照：TERM=xterm-256color 同参数 → rc=0, 桩日志 60 行（7 步全部走完）
~~~

与原报告的差异：无（含 TERM=dumb 同为真的细节，已实测确认）。

级别建议：原 P1 → **建议 P2**。文档化的 --yes 非交互入口在 cron/systemd/env -u TERM 下 100% 不可用，但它是安全失败：在第一条输出之前终止，桩日志 0 行，没有发生任何快照/升级/写操作；stderr 有明确报错、退出码 1，自动化可以发现。属"功能不可用"，建议 P2，并按一行修复处理。

---

## V7（data-safety DS-01）clean 深度清理的"保留最近一套批次"会删掉真正的成套回滚点

**判定：CONFIRMED（用 clean 真实源码逐行复现判定与删除结果）。**

方法：把 /home/pang/scripts/maintenance/clean 的 **427-497 行原样 source** 进 harness（仅补 _info/_warn/_item/_success/ui_pad 与 MSG/UI_* 依赖、sudo 透传），用 snapper 桩提供合成数据并记录 delete 调用。

CASE A（root+home 成套批次 B1，home 另有一条更新的单配置批次 B2）：

~~~
root: 185 maintenance_batch=20260905T150150.566936098-3155465 ; 180 无 userdata
home: 186 maintenance_batch=20260905T150150.566936098-3155465
      187 maintenance_batch=20260906T090000.000000000-999   ← 只有 home 有，且字典序最大
      188 无 userdata
输出：keep_batch=[20260906T090000.000000000-999]
      [ITEM] 已删除快照 [root] ID 185 / [root] ID 180 / [home] ID 186 / [home] ID 188
      [ITEM] 保留快照 [home] ID 187（最近回滚点）
      [OK] 快照清理完成       CLEAN_FAILED=0
~~~

结果：B1 的成套对（185+186）被删，只留下 home 单边 187 —— 没有任何成套批次可用于 quickload 的全部还原。

CASE B（对照：最新全局批次在 root/home 都成套）：185 与 186 都被正确保留，只删普通快照 180/188。

与原报告的差异：无。

触发条件与实际常见度：需要"全局最大 maintenance_batch 不是成套批次"。默认 quicksave 会为所有配置建同一批次，所以正常流程不触发；现实可达路径有三条：(a) 用户单配置调用 quicksave -c home；(b) 用 quicksave -del 删掉某成套批次的一半（菜单或 CLI，DS-19）；(c) quicksave 半途失败留下半套（DS-10）。属"少数但完全可达的操作序列"，不是理论极端值。

级别建议：原 P1 → **保持 P1**（护栏失效，删掉的是它明确承诺保留的那一套回滚点；虽然 clean all 本来就要删快照）。

---

## V8（data-safety DS-02）backup-restore --apply-home 把 $HOME 自身权限改成 staging 的 0700

**判定：CONFIRMED（等价命令级 + 代码路径 + 真实 v2 归档证据）。**

独立复现：

~~~
STAGE=$(mktemp -d ...)                  # 700
tar --zstd --no-same-owner -xf v2.tar.zst -C "$STAGE"   # 成员为 d1/ .config/，无 ./ 根条目
HOME_T 预先 chmod 755，mtime 2020-01-01
rsync -a --no-owner --no-group --backup --backup-dir=R -n -i -- "$STAGE/" "$HOME_T/"
  → .d...p..... ./
rsync -a --no-owner --no-group --backup --backup-dir=R -- "$STAGE/" "$HOME_T/"
  → HOME_T mode=700（原 755），mtime=当前时间
对照组：归档用 tar -C payload . 生成（含 ./ 成员）→ 解包后 STAGE 继承 755 → rsync 后 HOME_T 仍 755
~~~

真实证据：/tmp/maintenance-review/sandbox/pack/payload/home-config.tar.zst 共 11 个条目，grep -cx './' = 0；而 migration-pack:344 建包用的正是 tar --zstd -cf archive -C source_root -- rel...，所以 v2 包必然没有 ./ 根条目，STAGE 保持 mktemp 的 0700，rsync -a 的 -p/-t 会把 0700 与当前 mtime 写到 $HOME 自身（backup-restore:518）。

与原报告的差异：无。补充确认 offsite 路径（含 ./ 的归档）会把 STAGE 覆盖成备份里的 HOME 模式（既可收紧也可放松），与报告一致。

级别建议：原 P2 → **保持 P2**。它是"未经声明的 HOME 自身 mode/mtime 变更"（0700 会破坏依赖 o+x 遍历 HOME 的服务/挂载），不是内容丢失；修复成本极低（前后 stat 还原），P2 合适。

---

## V9（core-lib P2-3）ui_confirm 在 EOF/读错误时把空答案当默认值

**判定：CONFIRMED。**

独立复现（source 沙箱副本 /tmp/vsbx/src/lib/ui.sh）：

~~~
bash -c '. ./lib/ui.sh; ui_confirm "是否继续?"; echo rc=$?' </dev/null
  是否继续? [Y/n] rc=0            ← 从未读到答案，默认 y 即"同意"
bash -c '. ./lib/ui.sh; ui_confirm "是否继续?" n; echo rc=$?' </dev/null
  是否继续? [y/N] rc=1            ← 默认 n 行为正确
bash -c '. ./lib/ui.sh; exec 0<&-; ui_confirm "是否继续?"; echo rc=$?'
  是否继续? [Y/n] rc=0 + stderr「read: 0: 读取错误: 错误的文件描述符」
bash -c '. ./lib/ui.sh; ui_confirm_word "输入 yes" yes; echo rc=$?' </dev/null
  rc=1                            ← 关键词确认在 EOF 下拒绝（正确）
~~~

与原报告的差异：无。补充：仓库内默认 y 的调用点确认为 mirror-update:271 与 mirror-update:337（grep 全量核对），当前没有任何默认 y 的调用守高危删除，所以原报告"还不是 P1"的判断成立。

级别建议：原 P2 → **保持 P2**。

---

## V10（ui-checks P2-8）view-snapshots 每格/每字符一次命令替换导致 300 行约 6.6s

**判定：CONFIRMED（量级一致，并用 fork 计数定量证明机制）。**

方法：把 term-menu 副本 source 进 harness，snapper 桩给 root+home 各 150 行（共 300 行）；tput cols=80 → desc_width=29。短 ASCII 描述走 _snap_row；132 显示列中文描述触发 compact_text 逐字符循环。

~~~
bash bench3.sh short   → 2.255s / 2.072s   （报告 1.900s）
bash bench3.sh long    → 7.578s / 7.707s   （报告 6.606s）
strace -f -c -e trace=clone,clone3 bash bench3.sh short → 2138 次 clone
strace -f -c -e trace=clone,clone3 bash bench3.sh long  → 6638 次 clone
  （差值 +4500 = 300 行 × 约 15 次/行，正是 compact_text 的 $(ui_dwidth "$ch")）
微基准：1000× w=$((w+$(ui_dwidth 字))) = 0.992s（约 1.0ms/次命令替换）
        1000× 直接 _ui_dwidth_calc = 0.033s
        100× _snap_row（每行 4 次 $(ui_pad)）= 0.402s（4.0ms/行，报告 3.7ms/行）
~~~

与原报告的差异：机制与量级一致，绝对值有差异——我的长描述 7.6s（比报告 6.6s 慢约 15%），短描述 2.1-2.3s（报告 1.9s），属机器/负载差异；"每格一次命令替换是主因"由 clone 计数直接证实（fork 数与行数×字符数成正比）。另外注意端口宽度会影响耗时：终端的 desc_width 上限 48 时每行约 24 次替换，耗时更高。

级别建议：原 P2 → **保持 P2**（6-8 秒的"像卡死"体验，但不是数据/正确性问题）。

---

## V11（data-safety DS-05）非交互缺确认时 quicksave/clean/cache-clean 返回 0

**判定：CONFIRMED（实测 5 个脚本 + 1 个正向对照）。**

条件：stdin 全为 /dev/null（非 TTY）、不加 --yes/-y；沙箱 HOME + snapper/findmnt/btrfs/du 桩。

| 命令 | 退出码 | 桩中的变更调用 |
| --- | --- | --- |
| quicksave -del 185 | 0 | 0 |
| quicksave -del all | 0 | 0 |
| clean（默认模式） | 0 | 0 |
| clean --all | 0 | 0 |
| cache-clean --safe | 0 | 0 |
| btrfs-scrub --start（对照） | 2 | 0 |
| backup-restore --source <v2 pack> --apply-home（对照） | 2 | 0 |

对照脚本 stderr 明确：「[错误] 非交互操作必须指定 --yes」/「[错误] 非交互恢复必须同时指定 --yes」；README:320 规定非交互高风险操作缺少确认 = 2。

与原报告的差异：无。补充：原报告只举了默认 clean，实测 clean --all 同样是 0，影响面略大；危险操作本身没有误执行（ui_confirm_word 在 EOF 下返回 1，拒绝），问题纯粹是退出码谎报成功。

级别建议：原 P2 → **保持 P2**，但建议把 quicksave -del 单列为最危险的一条（cron 里"删除成功"的谎报会让后续逻辑建立在错误前提上，可议 P1）。

---

## V12（update-chain F-04）来源查询失败用空文件覆盖上一次成功列表

**判定：CONFIRMED。**

独立复现：

~~~
健康刷新后：updates-flatpak.txt = 27 字节（1 行）
把 flatpak 桩改为 rc=1 + stderr 后 --refresh：
  rc=1
  updates-flatpak.txt = 0 字节（flatpak 行数 0）
  source-status.tsv 第 3 行 = flatpak<TAB>error<TAB>flatpak: remote error
  其余来源文件不受影响（updates-repo.txt 27B、updates-aur.txt 20B 保持）
~~~

原报告是 20B → 0B，我用 27B → 0B，机制一致（失败分支先清空 out 文件，再 mv 覆盖缓存文件）。

与原报告的差异：无。

级别建议：原 P2 → **保持 P2**（状态行仍显示查询失败，没有违反"失败≠空"的显示铁律；损失的是离线/重试期间的最后一次已知好数据；修复成本极低）。

---

## 总体校准表

| 编号 | 原级别 | 复核判定 | 建议级别 | 校准说明 |
| --- | --- | --- | --- | --- |
| V1 | P1 | CONFIRMED（细节修正） | P2（降） | 半恢复 + 误报退出码，但无数据丢失，且 --enable→--disable 可脚本内恢复；原报告"只能手工补键"不成立 |
| V2 | P1 | CONFIRMED | P2（降） | 新装无 gitconfig 时功能 100% 不可用，但干净失败、有明确报错、无写入 |
| V3 | P1 | CONFIRMED | P1（保持） | world-writable 的 fish 启动配置 + dotfiles 被静默破坏，安全面 |
| V4 | P1（F-01/F-02） | CONFIRMED | P1（保持） | exit 0 掩盖整轮失败；实测时间戳反而被刷新，比原报告更严重 |
| V5 | P1 | CONFIRMED | P1（保持） | 用户当前 mirrorlist 被历史备份覆盖且从未被备份；触发面窄需注明 |
| V6 | P1 | CONFIRMED | P2（降） | 非交互入口不可用，但安全失败（0 桩调用）、有可见报错 |
| V7 | P1 | CONFIRMED | P1（保持） | 承诺保留的成套回滚点被删；触发需非默认操作序列 |
| V8 | P2 | CONFIRMED | P2（保持） | HOME 自身 mode/mtime 被改，未声明但不丢内容 |
| V9 | P2 | CONFIRMED | P2（保持） | EOF 默认同意；当前无高危调用点 |
| V10 | P2 | CONFIRMED | P2（保持） | 300 行 7.6s（报告 6.6s），clone 计数证实机制 |
| V11 | P2 | CONFIRMED | P2（保持；-del 可议 P1） | 非交互 no-op 返回 0，README 契约是 2 |
| V12 | P2 | CONFIRMED | P2（保持） | 失败清空最后已知好列表，状态行仍如实报错 |

一句话总结：**12 条核心结论全部成立，无整条误报（REFUTED=0）；需要修正的是 V1 的两处细节（"旧值未恢复"的范围、"只能手工修复"不成立）与 V4 的一条子结论（缓存时间戳其实会被刷新，实际更严重）；等级上 V1/V2/V6 三条 P1 偏高（建议降为 P2），其余校准一致。**

## 复现工件位置（全部 /tmp）

- 脚本副本：/tmp/vsbx/src（含 lib/）
- terminal-tools：/tmp/vsbx/t_v1.sh、t_v2.sh、t_v3.sh
- checkallupdates：/tmp/vsbx/bin_cau（桩）、/tmp/vsbx/home_cau（假 HOME）、/tmp/vsbx/t_v4.sh、t_v12.sh
- mirror-update：/tmp/vsbx/mu（夹具 + 桩）、/tmp/vsbx/t_v5.sh
- sysup：/tmp/vsbx/sysup（夹具）、/tmp/vsbx/src/sysup
- clean 批次逻辑：/tmp/vsbx/v7（run.sh + snapper 桩 + 数据夹具）
- view-snapshots 性能：/tmp/vsbx/v10（bench3.sh、micro2.sh、clone_short.txt、clone_long.txt）
- 非交互退出码：/tmp/vsbx/v11（桩 + 夹具）、/tmp/vsbx/t_v11.sh
- HOME 权限等价实验：/tmp/vsbx/ds02
