# ui-checks 审查报告 — 菜单交互 / 检查类脚本 / 测试套件

- **任务**：task-4（term-menu、hw-doctor、storage-health、gpu-check、check-battery、boot-check、pacnew-check、log-check、terminal-tools、tests/run）
- **方法**：只读静态审查（逐文件通读 + 关键路径 grep）+ /tmp 沙箱带桩实测 + 真实只读运行 + time/子进程计数定量。
- **环境**：Arch Linux / Btrfs / Snapper，uid 1000，非交互 TTY；/boot 为 drwx------ root，故无 sudo 时 boot-check 走"无法检查"分支；fzf/shellcheck/所有依赖工具均在位。
- **合规**：未修改工作区任何文件；未访问 review/；未执行 clean/cache-clean apply、scrub start、quicksave/quickload、sysup、备份/恢复 apply、systemctl 写操作、btrfs 写操作。所有实测均在 /tmp 沙箱内用桩命令完成（terminal-tools 用 HOME/XDG_CONFIG_HOME/XDG_STATE_HOME/GIT_CONFIG_GLOBAL 全部指向 /tmp）。bash -n 10 个在范围内文件全部通过。
- **基线声明**：本范围未发现 P0。tests/run 只做只读评估，**未运行整套**（含一条会写真实 HOME 的用例，见 P2-9）。

## 统计

| 级别 | 条数 | 已确认 | 高度可疑 |
|---|---|---|---|
| P0 | 0 | 0 | 0 |
| P1 | 3 | 3 | 0 |
| P2 | 12 | 11 | 1 |
| P3 | 12 | 11 | 1 |
| 合计 | 27 | 25 | 2 |

按文件：terminal-tools 6、term-menu 9、storage-health 3、gpu-check 2、check-battery 1、pacnew-check 2、log-check 3、boot-check 0（无独立发现，计入退出码一致性对比）、hw-doctor 1（性能）、tests/run 4、lib/ui.sh 1（共享缺陷）。

## 快速索引

| 级别 | 位置 | 一句话 |
|---|---|---|
| P1 | terminal-tools:241-247 | ! cmd 后取 $? 恒为 0，--disable 遇到已消失的托管键就报"退出码 0"失败，Git 配置半恢复且无法自愈 |
| P1 | terminal-tools:149-154,200,226 | 用户没有全局 gitconfig（新装机常态）时 --enable 恒定失败，功能完全不可用 |
| P1 | terminal-tools:89,130 | config.fish 是符号链接时，stat 取到 777，mv 把软链替换成 0777 常规文件 |
| P2 | hw-doctor:435 / boot-check:290 / pacnew-check:117 vs storage-health:264 / gpu-check:275 | "查询失败"在两派检查脚本里退出码语义相反，同一菜单里表现不一致 |
| P2 | gpu-check:232-233 | lspci 查询失败时仍断言"未检测到 NVIDIA 显卡，本节不适用" |
| P2 | log-check:170-172 | 只读检查默认往 $HOME/log-check-*.md 写文件；HOME 不可写时裸报错；tests 的 PTY 用例每次都会写真实 HOME |
| P2 | check-battery:48,55 | upower 查询失败在 set -e 下静默退出，退出码透传 1/3，与"无电池"无法区分 |
| P2 | pacnew-check:60-64 | 缺 pacdiff 返回 1（文档契约为 127），且用 exit 跳过面板收尾 |
| P2 | log-check:163-168 | 缺 systemctl/journalctl 返回 1（应为 127） |
| P2 | storage-health:176-181,205-213 | 目标路径含空格时：df 解析截断挂载点；findmnt -r 返回 \x20 转义路径被原样传给 btrfs/systemd-escape → 全部"查询失败" |
| P2 | term-menu:40-42 | 叶子子工具运行中按 Ctrl+C，父菜单 INT trap 直接 exit 130 关掉整个菜单，"子工具 130=返回父菜单"契约被抢跑 |
| P2 | term-menu:894-905,909-916 | view-snapshots 每行 4 次 $(ui_pad)，长描述再逐字符 $(ui_dwidth)：300 行实测 6.6s / 1.9s |
| P2 | term-menu:1089-1097 | warn_batch_pairs 对每个选中 ID 重查一遍所有配置：20 个 ID = 41 次 snapper |
| P2 | tests/run:298-316 | PTY 端到端用例没有隔离 HOME，会在真实 $HOME 留下 log-check-*.md；还有 sleep 时序脆弱 |
| P2 | tests/run:1403-1410,1652-1669,2853-2926,2929-2978 | 覆盖缺口：只测 --strict 路径、只在"已有 gitconfig"下测 terminal-tools，正好放过 P1-1/P1-2 与退出码不一致 |
| P3 | pacnew-check:67-71,93-111 | 两个 mktemp 文件没有登记/ trap，Ctrl+C 会残留 /tmp 文件 |
| P3 | term-menu:665,706 | choose_menu 内 set +e/set -e 状态泄漏（目前唯一因所有调用点都在 $( ) 里而未爆） |
| P3 | term-menu:714,716 | 无 fzf 回退分支用 %-12s/%-18s 字节填充对齐 CJK（违反 HANDOFF 规则 2） |
| P3 | term-menu:1009,1038 | 临时文件登记了却用 rm -f 删除，未 ui_tmp_discard |
| P3 | term-menu:1429-1433 | 蓝牙工具后台启动后无条件打印"已启动"，启动失败无提示 |
| P3 | lib/ui.sh:619 | ui_panel_stat err 记入 UI_N_MISS，汇总把"错误"并进"缺失" |
| P3 | terminal-tools:92 | 中断会在 ~/.config/fish/ 留下 .config.fish.terminal-tools.XXXXXX 临时文件（无 trap） |
| P3 | hw-doctor:222-345 | 一次检查 86 个子进程（17 次 tput、7 次 expand、11 次 systemctl），其中 tput 只为每张卡片取一次终端宽度 |
| P3 | storage-health:68-119 | 单个 smartctl JSON 已拿到内存，却按字段 fork jq：2 块盘 = 15 次 jq |
| P3 | log-check:141 | 已经捕获过 systemctl --failed，又重复查一次 |
| P3 | tests/run:29 / 15-18 / 7-8 / 3089 | test_syntax 的 find 会下钻 review/；fail() 立即退出不输出 TAP plan；无单项过滤/超时 |

---

## 详细发现

### P0
本范围内没有会直接丢数据/毁系统的路径：term-menu 的删除/恢复都经关键词确认并复用 quicksave/quickload 的锁与保护；只读检查脚本不写系统配置。**唯一需要点名的是 log-check 的默认写文件（P2-3）和 terminal-tools 的写路径（P1-1..3）**，它们不构成数据丢失，但属于"只读脚本其实会写"和"配置恢复失败"。

---

### P1-1 terminal-tools --disable：$? 取在 ! 之后恒为 0，导致误报失败 + Git 配置半恢复

**文件**：terminal-tools:241-247

```bash
241	    if ! git config --global --unset-all "$key" >/dev/null 2>&1; then
242	      # 退出码 5 代表该键原本不存在；其它错误才算失败。
243	      rc=$?
244	      if [[ "$rc" -ne 5 ]]; then
245	        ui_err "无法清除 Git 配置项 %s（退出码 %s）。" "$key" "$rc"
246	        return 1
```

**触发条件**（任一即可）：
1. terminal-tools --enable 后，用户手动删掉 6 个托管键中的任意一个（git config --global --unset delta.navigate），再 --disable。
2. --enable 在 apply_git_settings（224-232）中途失败——脚本自己在 330 行提示"请运行 terminal-tools --disable 尝试回退"——此时尚未写入的键在状态文件里记为"原本不存在"，--disable 会对不存在的键调用 --unset-all。

**证据**：
- 语义实测（bash 本身）：bash -c 'if ! (exit 5); then echo "rc_in_then=$?"; fi' → rc_in_then=0；git config --global --unset-all <不存在的键> → git_unset_rc=5。即第 243 行拿到的是 ! cmd 的结果 0，永远不等于 5 → 永远进 244 分支报错。
- 沙箱复现（HOME/XDG_STATE_HOME/GIT_CONFIG_GLOBAL 全在 /tmp）：
```
enable rc=0
keys after enable: core.pager delta / delta.navigate true / merge.conflictstyle zdiff3
--- 手动 git config --global --unset delta.navigate 后 ---
[错误] 无法清除 Git 配置项 delta.navigate（退出码 0）。   (stderr)
disable rc=1
state file still exists? terminal-tools-git-before.tsv
keys after failed disable: delta.side-by-side true / diff.colormoved default / merge.conflictstyle zdiff3
```
即：core.pager / interactive.diffFilter / delta.navigate 已被删除、旧值未恢复，循环在故障键处 return 1，**状态文件保留**（255 行的 rm -f 走不到）。因为状态文件还在、而故障键在 Git 里永不出现，重跑 --disable **每次都在同一处失败**，用户无法用脚本完成回退，只能手工把键补回去。

**影响**：功能错误 + 用户 Git 显示配置处于半恢复状态；脚本的恢复保证（README 306-307 行"准确恢复这些旧值"）不成立。
**建议修法**（只描述）：local rc=0; git config --global --unset-all "$key" >/dev/null 2>&1 || rc=$? 再比较 5；或先 git config --global --get-all "$key" 判存在再删。补一条"托管键被人为删除后 --disable 仍能完整恢复"的回归。
**确认度**：已确认（bash 语义实测 + 沙箱端到端复现）。

---

### P1-2 terminal-tools --enable 在用户没有全局 gitconfig 时恒定失败

**文件**：terminal-tools:149-154（git_global_readable），调用点 200（capture_git_state）、226（apply_git_settings）、238（restore_git_state）

```bash
149	git_global_readable() {
150	  if ! git config --global --list >/dev/null 2>&1; then
151	    ui_err "无法读取当前用户的 Git 全局配置；未修改 Git 设置。"
152	    return 1
```

**触发条件**：~/.gitconfig 与 $XDG_CONFIG_HOME/git/config 都不存在时运行 terminal-tools --enable（全新安装、只用仓库级配置、或 HOME 换过的用户）。

**证据**：
```
$ HOME=/tmp/uihome git config --global --list        # 无 .gitconfig
致命错误: 无法读取配置文件 '/tmp/uihome/.gitconfig': 没有那个文件或目录   rc=128
# 沙箱里 enable 的输出：
[成功] 已找到: fish/bat/zoxide/git/delta/base64
[错误] 无法读取当前用户的 Git 全局配置；未修改 Git 设置。   rc=1
```
（git 2.55.0；--get-all 在同类情况下返回 1，所以 --status 只是显示"尚未由本工具配置"，不报错——问题只在 --list。）仓库测试在 2939-2940 行先执行了 git config --global core.pager less，文件因此存在，**永远覆盖不到这条路径**。

**影响**：--enable 在"没有全局 gitconfig"的机器上 100% 不可用（Fish 块也不会写），而 README/HANDOFF 把它列为可选但可用的功能。
**建议修法**：把"文件不存在"视为空配置（例如 --list 失败时改用 git config --global --get-regexp 或直接接受"没有旧值"继续），或捕获 128 并区分"无文件"与"不可读"；补对应回归。
**确认度**：已确认（实测 git 行为 + 沙箱端到端）。

---

### P1-3 terminal-tools 会把符号链接的 Fish 配置替换成 0777 常规文件

**文件**：terminal-tools:89（stat -c '%a'）、92（在配置目录 mktemp）、129（chmod "$old_mode" "$tmp"）、130（mv -f "$tmp" "$FISH_CONFIG"）

```bash
87	  if [[ -e "$FISH_CONFIG" ]]; then
89	    old_mode="$(stat -c '%a' "$FISH_CONFIG")"
...
129	  chmod "$old_mode" "$tmp"
130	  mv -f "$tmp" "$FISH_CONFIG"
```

**触发条件**：用户用 dotfiles 管理 Fish 配置（~/.config/fish/config.fish 是指向仓库的符号链接），然后 terminal-tools --enable（--disable 同样会重写，只要走到 rewrite）。

**证据**：沙箱复现（ln -s $SB2/dotfiles/fish-config.fish $SB2/config/fish/config.fish）：
```
enable rc=0
-rwxrwxrwx 1 pang pang 551 .../config/fish/config.fish     # ← 已是常规文件，软链没了，且 0777
（dotfiles 里的目标文件保持原样，不再接收后续改动）
```
原因：GNU stat 不加 -L 用 lstat，软链权限恒为 777；mv -f 替换的是链接本身而不是目标。内容没有丢（awk 是透过软链读的），但软链被破坏、新文件 world-writable（Fish 会执行该文件内容）。

**影响**：dotfiles 工作流被静默破坏；一个可被其他本地用户改写的 shell 配置被创建。
**建议修法**：先 [[ -L "$FISH_CONFIG" ]] 检测，拒绝或在写入前用 readlink -f 落到真实目标上，并用 stat -Lc '%a' 取目标权限；补符号链接回归。
**确认度**：已确认（沙箱端到端）。

---

### P2-1 检查脚本"查询失败"的退出码语义分两派，同一菜单内表现不一致

**文件**：hw-doctor:435、boot-check:290、pacnew-check:117（查询失败 → 非零，与 --strict 无关）
对比 storage-health:264、gpu-check:275（查询失败只记 warn，ui_tally_status "$STRICT" 决定）

```bash
# hw-doctor
435	  [[ "$HW_QUERY_FAILED" -eq 0 ]] || return 1
436	  ui_tally_status "$strict"
# boot-check / pacnew-check 同型（290 行、117 行）
# storage-health
62	    ui_panel_stat warn "SMART 查询失败（退出码 $rc）"
264	ui_tally_status "$STRICT"        # ← 没有 query_failed 判断
# gpu-check
275	  ui_tally_status "$strict"
```

**触发条件**：无 sudo/无权限/工具桩失败时分别运行两类脚本。
**证据**（沙箱桩：lsblk/smartctl/df/findmnt/btrfs/systemctl 全部 exit 5；lspci/lsmod/glxinfo/vulkaninfo 全部 exit 5）：
```
storage-health 无 --strict  →  输出 3 条"[注意] 查询失败"  exit=0
storage-health --strict     →  exit=1
gpu-check 无 --strict       →  4 条"[注意] 查询失败"        exit=0
gpu-check --strict          →  exit=1
（对照真实机器：pacnew-check 无 --strict exit=1；boot-check 无 --strict exit=1）
```
term-menu 的 leaf_is_check/run_leaf_and_pause（1442-1476）按"非零 = 有需要人工处理或无法检查"统一措辞；于是同一"系统检查"菜单里，boot/pacnew 失败会提示"部分项目无法检查"，storage-health/gpu-check 失败**什么都不提示**（退出 0），用户看到的是"检查结束"。HANDOFF 规则 6 与 README 316-324 的措辞也无法同时覆盖这两派。

**影响**：自动化（按退出码）与交互用户都会得到不一致结论；SMART/Btrfs 读不到时 storage-health 不给非零信号。
**建议修法**：给这两支也加 *_QUERY_FAILED 并像 hw-doctor 一样返回非零（或反过来统一为"仅 --strict 生效"，但必须全项目一致并同步 README/HANDOFF）；补"无 --strict 下查询失败必须非零"的回归。
**确认度**：已确认（沙箱实测 5 组退出码）。

---

### P2-2 gpu-check：lspci 查询失败时仍断言"NVIDIA 不存在"

**文件**：gpu-check:142,145-147,179,231-235

```bash
145	    pci_output="$(LC_ALL=C lspci -k 2>&1)" || pci_rc=$?
147	      ui_panel_stat warn "lspci 查询失败（退出码 $pci_rc）"
...
179	        [[ "$model" == *NVIDIA* ]] && has_nvidia=1
...
232	  if ((has_nvidia == 0)); then
233	    ui_panel_stat info "未检测到 NVIDIA 显卡，本节不适用"
```

**触发条件**：lspci 失败（无 pciutils 权限/桩失败/命令异常）时运行 gpu-check。
**证据**：沙箱桩实测输出：
```
│  [注意] lspci 查询失败（退出码 5）
│  [消息] 未检测到 NVIDIA 显卡，本节不适用
```
同一个失败还可能连带跳过 prime-run 验证，用户因此以为"没有独显/不需要检查"。
**影响**：把"无法检查"写成"没有"，正违反 HANDOFF 规则 6；混合显卡场景下会漏掉独显问题。
**建议修法**：lspci 失败时把 NVIDIA/prime-run 段显示为"无法判断（PCI 查询失败）"，并把该段计入查询失败状态。
**确认度**：已确认（沙箱实测）。

---

### P2-3 log-check 是"只读检查"但默认写 $HOME，且 HOME 不可写时裸报错

**文件**：log-check:170-172

```bash
170	  report="${LOG_CHECK_REPORT:-$HOME/log-check-$(date '+%Y%m%d-%H%M%S').md}"
171	  ui_working "正在读取本次启动的系统和用户日志"
172	  generate_report > "$report"
```

**触发条件**：任何一次 log-check（含 term-menu → 系统检查 → 日志检查）。默认路径带时间戳，**每次运行产生一个新文件**，长期使用会在 HOME 累积；HOME 只读/不存在时直接失败。
**证据**（沙箱 HOME）：
```
路径  /tmp/uisb12/home/log-check-20260910-195413.md      rc=1（因为桩 systemctl/journalctl 失败）
$ ls /tmp/uisb12/home → log-check-20260910-195413.md
$ HOME=/tmp/uisb12/nonexistent log-check
log-check: 行 172: /tmp/uisb12/nonexistent/log-check-...md: 没有那个文件或目录   rc=1   （没有任何解释）
```
term-menu 的 preview（387-393 行）确实写了默认路径，README 未提；但作为"检查类脚本"它会在只读审查语境下产生副作用（而且 tests 的 PTY 用例会写真实 HOME，见 P2-9）。
**建议修法**：改为按需输出（--report FILE），默认写 stdout 或 $XDG_STATE_HOME/maintenance/logs/ 并在写入前检查目录可写、失败时给出中文错误。
**确认度**：已确认（实测）。

---

### P2-4 check-battery：查询失败静默退出，退出码透传，与"无电池"混淆

**文件**：check-battery:48、55（以及 set -euo pipefail 第 5 行）

```bash
48	BAT_PATH="$(upower -e | awk '/battery/ {print; exit}')"
50	if [[ -z "$BAT_PATH" ]]; then
51	  ui_err "未检测到电池设备（虚拟机 / 台式机属正常）"
52	  exit 1
55	INFO="$(upower -i "$BAT_PATH")"
```

**触发条件**：upower 已安装但 daemon 不可达（容器/无 D-Bus/服务未起）。
**证据**（沙箱桩 upower）：
```
$ PATH=<stub>:... check-battery        # upower -e exit 1
upower daemon unreachable              ← 只有 upower 自己的 stderr
rc=1                                    ← 脚本没有任何自己的输出，且与"未检测到电池"同一码
$ ... check-battery                     # upower -e 正常、upower -i exit 3
device query failed
rc=3                                    ← 未文档化的退出码直接泄漏
```
文档化契约是 0/1/2/127（README 316-324），3 不在其中；同时"无法检查"与"没有电池"无法区分。
**影响**：批量巡检时无法判断是"没电池"还是"upower 坏了"；term-menu 会把它当"检查完成（有人工项）"。
**建议修法**：两处命令替换改为 if ! out=$(upower ...); then ui_err "upower 查询失败…"; exit 1; fi，并把检查失败与无设备用不同文案/退出码区分。
**确认度**：已确认（桩实测）。

---

### P2-5 pacnew-check / log-check 缺依赖返回 1，而非文档约定的 127

**文件**：pacnew-check:60-64、log-check:163-168

```bash
# pacnew-check
60	  if ! have pacdiff; then
61	    ui_panel_stat miss "缺少 pacdiff；请安装 pacman-contrib"
62	    panel_end
63	    exit 1
64	  fi
# log-check
163	  if ! have systemctl || ! have journalctl; then
165	    ui_panel_stat miss "缺少 systemctl 或 journalctl"
167	    exit 1
```
（check-battery:43-46 在同样场景正确返回 127，说明契约本意是 127。）

**触发条件**：pacdiff（pacman-contrib）未安装；或 systemd 工具缺失。
**证据**：受限 PATH（无 pacdiff，非 TTY）实测 pacnew-check --strict → 输出"[缺失] 缺少 pacdiff；请安装 pacman-contrib"，**rc=1**。
**影响**：README 的退出码契约（127=缺少命令）对自动化失效；另外 pacnew-check 用 exit 而非 return，跳过 ui_tally_summary 与卡片闭合。
**建议修法**：两处改 return 127（并保留 panel_end），main 的返回值由脚本尾部透传。
**确认度**：已确认（实测 + 代码）。

---

### P2-6 含空格的挂载路径：storage-health 解析截断 / 转义路径被原样传给 btrfs

**文件**：storage-health:175-181（df 解析）、199-213、229、241（findmnt -r 路径）

```bash
175	if DF_OUT="$(df -P -x tmpfs -x devtmpfs 2>&1)"; then
176	  while read -r percent mountpoint; do
181	  done < <(awk 'NR > 1 {gsub(/%/, "", $5); print $5, $6}' <<< "$DF_OUT")
...
199	  if ! BTRFS_MOUNTS="$(findmnt -rn -t btrfs -o TARGET,SOURCE 2>&1)"; then
...
213	      stats="$(LC_ALL=C btrfs device stats -c "$target" 2>&1)" || stats_rc=$?
229	      scrub="$(LC_ALL=C "${SUDO[@]}" btrfs scrub status -R "$target" 2>&1)" || scrub_rc=$?
241	        instance="$(systemd-escape --path "$target")"
```

**触发条件**：任何挂载点含空格（/run/media/$USER/My Passport 这类外置盘、NAS 挂载），或 Btrfs 挂载点含空格。
**证据**：
```
# df 桩输出 "/dev/sdb1 100000 50000 50000 50% /run/media/pang/My Passport"
│  [成功] /run/media/pang/My 已使用 50%        ← "Passport" 被丢掉（awk 只打印 $6）
# findmnt -r 对含空格挂载点的真实行为（-F 假 fstab，只读）：
$ findmnt -F /tmp/fstab -r -o TARGET,SOURCE
/run/media/pang/My\x20Disk /dev/sdb1          ← raw 模式把空格转义成 \x20
```
read -r target source 拿到的是带字面 \x20 的路径，它被原样传给 btrfs device stats -c、btrfs scrub status -R、systemd-escape --path → 在真实系统上必然 "No such file or directory"，于是该文件系统整段显示"[注意] 查询失败"，且卡片标题也带 \x20。df 那条则是把两段路径都算错（可能把用量归到错误名字下）。
**影响**：外置盘/NAS 场景下 Btrfs 检查整段失效（误报查询失败）；空间表显示错误挂载点。
**建议修法**：df 用 df -P --output=pcent,target（或 findmnt）解析；findmnt 去掉 -r，或用 findmnt -P（键值对）/ --json 解析，避免把 raw 转义串当路径。
**确认度**：已确认（df 桩实测 + findmnt 真实行为实测；后者与代码路径组合推理，结论对 btrfs 工具链成立）。

---

### P2-7 term-menu：叶子子工具运行中按 Ctrl+C 会关掉整个菜单，"130=返回父菜单"契约被父级 INT trap 抢跑

**文件**：term-menu:40-42（trap 定义）、1455-1480（run_leaf_and_pause 的 130/10 处理）

```bash
40	trap 'show_cursor; ui_tmp_cleanup' EXIT
41	trap 'exit 130' INT
42	trap 'exit 143' TERM
...
1463	  if [ "$status" -eq 130 ] || [ "$status" -eq 10 ]; then
1464	    return 0                     # ← 子工具"请求回父菜单"
```

**触发条件**：菜单里执行任一叶子工具时按 Ctrl+C（例如 log-check、quicksave、migration-pack 这些自己 catch INT 并返回 130 的脚本）。
**证据**：进程组级 SIGINT 复现（父 bash 带 trap 'exit 130' INT + EXIT trap，前台子 bash 带 trap "exit 130" INT，对整个进程组发 SIGINT）：
```
menu drawn
CHILD-INT          ← 子工具按契约退出 130
PARENT-INT-TRAP    ← 父菜单的 INT trap 同时触发
PARENT-EXIT-TRAP
script exit code: 130   ← 没有任何 "menu would redraw here"
```
即 1463 行的"回父菜单"分支在 Ctrl+C 场景永远不会执行：结果页与菜单一起消失（Esc 场景不受影响，因为 Esc 只让 fzf/子工具返回 130，父进程收不到信号）。
**影响**：与 term-menu 头部注释（3-4 行"叶子脚本返回非 0 时必须保留现场并回到菜单"）和 HANDOFF 规则 9 相冲突；长时间工具中途取消会把用户直接扔回 shell。
**建议修法**：子工具执行期间临时 trap '' INT（或 trap 'LEAF_INTERRUPTED=1' INT），等子进程返回后再决定是否退出菜单；或明确把"Ctrl+C 退出整个菜单"写进 README 并去掉子工具的 130 回退约定。
**确认度**：已确认（进程组 SIGINT 语义实测 + 代码路径）。

---

### P2-8 性能：view-snapshots 的"每格一次命令替换"让 300 行快照列表要 6.6 秒

**文件**：term-menu:890-916（compact_text 逐字符 $(ui_dwidth)、_snap_row 每行 4 次 $(ui_pad)）

```bash
899	    for ((i = 0; i < ${#text}; i++)); do
900	      ch="${text:i:1}"
901	      w=$((w + $(ui_dwidth "$ch")))     # ← 每个字符一个子 shell
...
910	    printf "%*s%s %s %s %s %s\n" "$W_IND" "" \
911	      "$(ui_pad "$1" "$W_ID")" "$(ui_pad "$2" "$W_TIME")" \
912	      "$(ui_pad "$3" "$W_USER")" "$(ui_pad "$4" "$W_CLEAN")" "$5"
```

**证据**（桩 snapper：150 条/配置 × 2 配置 = 300 行，全部走 print_snapshot_list）：
```
长中文描述（60 显示列，走 compact_text 逐字符循环）: real 0m6.606s
短 ASCII 描述（quicksave-sysup，只走 _snap_row）      : real 0m1.900s
对照：_snap_row 100 行 = 0.366s（约 3.7ms/行）
对照：逐字符 $(ui_dwidth) 33 字符 = 0.036s，改成直接调 _ui_dwidth_calc = 0.008s（4.5×，约 1.1ms/字符）
```
ui_dwidth 本身有缓存且不 fork，但每个 $( ) 仍会 fork；描述越长、快照越多，代价线性放大（48 列上限 × N 行 ≈ N×48 个子 shell）。
**影响**：用户直接感知的"读取/刷新慢"——快照多、描述长时 view-snapshots 会卡 5 秒以上（term-menu 会显得像挂死）。
**建议修法**：把 ui_pad/ui_dwidth 改为"值版本"写全局变量（UI_DWIDTH_RESULT 已存在）并用 printf -v 组装行，彻底去掉命令替换；compact_text 直接调 _ui_dwidth_calc 读 UI_DWIDTH_RESULT，或预先 ui_wrap 一次。
**确认度**：已确认（计时实测）。

---

### P2-9 tests/run 的 PTY 端到端用例会在真实 $HOME 留下 log-check 报告

**文件**：tests/run:298-316（drive 脚本与按键序列）

```bash
298	  cat > "$drive" <<EOF
299	stty rows 45 cols 130 2>/dev/null
300	export PATH="$bin:\$PATH"
301	export MAINTENANCE_NO_NOTIFY=1
302	cd "$ROOT"
303	./term-menu
304	EOF
...
311	    printf '0'; sleep 0.4; printf '4'; sleep 0.8; printf '\r'; sleep 2.5
312	    printf '1'; sleep 0.4; printf '0'; sleep 0.8; printf '\r'; sleep 4
```

**触发条件**：任何一次完整 tests/run（只要 script 存在）。按键序列是主菜单 "04 系统检查" → 子菜单 "10 日志检查"，于是真正执行了 log-check，而 drive 脚本**没有覆盖 HOME**（其它用例都显式 HOME="$home"）。
**影响**：每跑一次测试套件就在用户 HOME 多一个 log-check-YYYYmmdd-HHMMSS.md（与 P2-3 叠加）；测试污染真实环境，违背 HANDOFF"用临时目录和命令桩、不依赖真实系统状态"。另外该用例纯靠 sleep 2.5/0.4/0.8/4 定时（308 行注释自己承认按键连打会误选），负载高时容易 flaky，timeout 60s 也会把失败吞成"没有输出"而非明确失败。
**建议修法**：drive 脚本里 export HOME="$TMP_DIR/pty-home"（并 mkdir），或把该用例的按键序列换成只读动作（硬件检查/GPU 检查）；断言按键间隔改成轮询捕获内容而不是固定 sleep。
**确认度**：已确认（代码铁证：无 HOME 隔离 + 按键→日志检查映射 + log-check 默认写 $HOME；未实际运行该用例）。

---

### P2-10 tests/run 覆盖缺口（正好漏掉本次 P1/P2）

**文件**：tests/run:2981-3009（CLI 契约）、1403-1410（strict 单测）、1588-1669（gpu-check）、2853-2926（storage-health）、2929-2978（terminal-tools）

- test_cli_argument_contracts 只验证 --help 返回 0、未知参数非零、多余参数非零；**没有任何"缺命令 = 127"断言**，所以 P2-5 不会被发现。
- test_storage_health_strict_status / test_gpu_compact_health_summary 全部带 --strict（2905、2910、2916、2921、1652、1662），**无 --strict 的查询失败路径无覆盖**，所以 P2-1 不会被发现。
- test_terminal_tools_lifecycle 在 2939-2940 先 git config --global core.pager less 造出 gitconfig，**"没有全局 gitconfig"路径无覆盖**（P1-2）；恢复场景只测"enable 写入过的键"（2961-2973），**"托管键中途消失"无覆盖**（P1-1）；config.fish 始终是常规文件，**符号链接路径无覆盖**（P1-3）。
- check-battery 在整个套件里只有 CLI 契约引用（grep -c check-battery tests/run = 2），**没有 upower 缺失/查询失败/无电池的行为测试**（P2-4）。
- log-check 只测 generate_report 的内存路径（813-827，用 TMP 报告），**默认 $HOME 写路径、HOME 不可写、缺依赖退出码都没有覆盖**（P2-3/P2-5）。
- term-menu 的**无 fzf 回退分支**（choose_menu 708-723）无覆盖；view-snapshots 长描述渲染无性能/正确性回归（P2-8）；warn_batch_pairs 只测 1 个 ID（1038-1075），IO 放大无覆盖（P2-11）。
**建议修法**：按上表逐条补最小回归；CLI 契约测试增加"PATH 中移除某命令后退出码 = 127"的通用断言。
**确认度**：已确认（读代码 + 计数）。

---

### P2-11 性能：warn_batch_pairs 对每个选中快照重查所有配置（N+1）

**文件**：term-menu:1077-1097

```bash
1085	  for id in "$@"; do
1086	    batch="${id_batch[$id]:-}"
1088	    peers=""
1089	    while IFS="$sep" read -r other _; do
1090	      ...
1093	      if snapper --csvout --separator "$sep" -c "$other" list --columns number,userdata 2>/dev/null |
1094	        grep -Fq "maintenance_batch=$batch"; then
```

**触发条件**：删除多个快照（Tab 多选）且它们带 maintenance_batch。每个 ID 都要重新 snapper list-configs + 对每个配置 snapper list。
**证据**（桩 snapper 记录调用）：20 个带 batch 的 ID → **41 次 snapper 调用**；本机 snapper list-configs 实测 8-40ms，snapper list 11ms 量级（冷启动更高），即确认框出现前多等约 0.5-1.5s，且随 ID 数线性增长。
**建议修法**：先把每个配置的 number,userdata 取一次到关联数组（配置数很小），再在内存里做批次配对；list-configs 只调用一次。
**确认度**：已确认（桩计数实测）。

---

### P3 列表（细节从简）

1. **pacnew-check 临时文件泄漏**：67-71 与 93-111 两个 mktemp 文件既没 ui_tmp_register 也没有 trap；在 pacdiff/find 运行期间 Ctrl+C 会在 /tmp 留下文件（log-check 用 45-49/9-11 做了正确示范）。确认度：已确认（代码）。
2. **term-menu set -e 状态泄漏**：665 set +e / 706 set -e 在 choose_menu 内切换全局 shell 选项。当前所有调用点都是 $(choose_menu ...)（子 shell），所以没爆；一旦有人在当前 shell 直接调用（测试里就有这种用法，tests/run:354、1052）就会给调用者打开 errexit。确认度：已确认（代码 + 调用点全量核对）。
3. **无 fzf 回退分支用字节填充**：714/716 的 %-12s %-18s 对 CJK 标签按字节补齐，违反 HANDOFF 规则 2（同理 721 行用 awk 匹配输入，输入非法时静默返回 1）。因为当前所有标签都是 4 个汉字才碰巧对齐；换标签即错位。确认度：已确认（代码 + 回退分支实测输出）。
4. **show_snapshots 临时文件未销账**：1009-1010 登记后 1038 用 rm -f，UI_TMP_PATHS 里留下死条目（退出时 rm -rf 一个不存在的路径，无害但不干净）；应改 ui_tmp_discard "$tmp"。确认度：已确认（代码）。
5. **蓝牙工具后台启动无失败检测**：1429-1433 "$act" & 后无条件打印"已启动"并 sleep 1；命令不存在/立即崩溃也会显示成功。确认度：已确认（代码）。
6. **lib/ui.sh 汇总把"错误"算作"缺失"**：619 行 err) … UI_N_MISS=$((…+1))，ui_tally_summary（636-639）只打印"正常/注意/缺失"，因此 SMART 失败（err）在汇总里显示为"缺失"。strict 判据不受影响。确认度：已确认（代码 + 输出观察）。
7. **terminal-tools 临时文件残留**：92 行在 ~/.config/fish/ 里 mktemp，103-107 只在"解析失败"时 rm；--enable/--disable 被 Ctrl+C 打断会留下 .config.fish.terminal-tools.XXXXXX。确认度：已确认（代码）。
8. **hw-doctor 每张卡片都要 fork 一次 tput**：_ui_rule_width → ui_cols → tput cols（lib/ui.sh:280-287）被 banner/每次 panel/ui_section 调用。strace 计数：一次 hw-doctor 共 86 个子进程，其中 **17 次 tput、7 次 expand、11 次 systemctl、11 次 grep、9 次 awk**；暖机后总耗时 0.44-0.57s（首次冷跑曾达 2.4s，属环境抖动，不作为结论）。建议在 ui.sh 里缓存 tput cols（可加 TTL/COLUMNS 优先）。确认度：已确认（strace 计数 + 计时）。
9. **storage-health 对同一份 JSON 逐字段 fork jq**：68-76、84、111、119 行，smart_value 每次一个 jq；本机 2 块盘实测 **15 次 jq**，总耗时 0.20-0.21s（绝对开销不大，但按盘数线性增长）。建议一次 jq -r '[...]|@tsv' 取全部字段。确认度：已确认（计数实测）。
10. **log-check 重复查询**：141 行又跑一次 systemctl --failed，而 136 行已经通过 capture_command 拿到同样数据。确认度：已确认（代码）。
11. **tests/run 结构问题**：29 行 find "$ROOT" -maxdepth 2 … ! -path '*/.git/*' 会下钻到 review/（depth 2 的 *.sh/可执行文件全部 bash -n），仓库里任何别人的临时文件都会让 test_syntax 失败（环境耦合）；15-18 行 fail() 立即 exit 1，不打印 1..N TAP plan，失败后没有汇总；3089 行 plan 用的是"通过数"而不是用例总数；套件没有单项过滤参数、没有 per-test 超时，想跑"安全子集"只能复制改文件。确认度：已确认（代码）。
12. **tests/run 跳过也计通过**：284-288 行在缺 script 时 pass 'pty menu drive skipped…'，与真正执行共用同一个 pass，套件输出无法区分"跑了"和"跳过了"；同理 1543-1546。确认度：已确认（代码）。

---

## 性能专项小结（"读取/刷新慢"）

| 路径 | 量化 | 结论 |
|---|---|---|
| term-menu view-snapshots | 300 行：长中文描述 **6.6s**，短描述 **1.9s**；_snap_row 3.7ms/行；逐字符 $(ui_dwidth) 1.1ms/字符 | **主因**，P2-8，建议去命令替换 |
| term-menu warn_batch_pairs | 20 个 ID = **41 次 snapper** | P2-11，建议缓存配置快照列表 |
| term-menu choose_menu 每次重绘 | ui_status_line = 14.7ms/次（约 8 个 fork：awk×2/df/tail/tr/ip/awk/date） | 可接受；若菜单重绘频繁可把 footer 改为定时更新 |
| term-menu --preview | 24ms/次（重新 source ui.sh + awk 换行） | 可接受（每次光标移动一次） |
| hw-doctor | 86 子进程/次，0.44-0.57s 暖机 | 每卡片一次 tput 可省 17 fork |
| gpu-check | 0.79-0.82s（glxinfo/vulkaninfo 自身占大头；gl_field 每字段一个 awk） | 可合并 awk，收益中等 |
| storage-health | 0.20-0.21s，其中 15 次 jq | 可合并成 1 次 jq |
| pacnew-check / boot-check / log-check / check-battery / terminal-tools | 64-490ms | 无显著瓶颈 |

---

## tests/run 评估与"安全子集"建议（**默认不要跑**）

**总体判断**：套件工程质量不错——set -euo pipefail、TMP_DIR="$(mktemp -d)" + EXIT trap（已实测 Ctrl+C 也会执行 cleanup）、每个用例自带 PATH 桩、写操作脚本（quicksave/quickload/clean/sysup/offsite/migration/mirror）基本都配了 snapper/btrfs/pkexec/systemctl/findmnt 桩。59 个 test_ 函数，3029-3088 行顺序执行。

**已知不安全/不建议直接跑的**：
- test_menu_end_to_end_in_pty（284-325）：**会写真实 $HOME**（P2-9）+ 固定 sleep 时序 + 真实 fzf。
- test_offsite_rejects_same_disk（1672-1680）：**没有 PATH 桩、没有 HOME 隔离**，直接对 /var/tmp 跑真实 offsite-backup --check，依赖真实磁盘枚举；只有在"同盘拒绝"逻辑正确时才安全。
- test_privileged_read_prompts（1542-1586）：需要 script 且非 root，会在 PTY 里用 sudo 桩执行真实 pacdiff/find /etc（只读，但触及真实系统）。
- 其余 quicksave/quickload/offsite/migration/clean/scrub/sysup/restore 用例：都靠桩，但一旦桩不完整（例如某命令没设桩）就可能落到真实系统命令；在未逐行确认前按"需要复核"对待。

**可作为只读/纯临时目录子集安全运行**（仅使用 TMP_DIR 与桩，或纯函数/纯文本断言；仍然建议先复制 tests/run 到 /tmp、删掉第 3029-3088 行的执行列表再按需调用）：
test_syntax（⚠ 会扫描整棵树含 review/）、test_config_parser、test_strict_check_status、test_ui_display_width_and_tmp_registry、test_long_operations_report_progress、test_rich_new_feature_previews、test_menu_tools_resolve_from_script_dir、test_update_escape_contract、test_menu_navigation_contract、test_all_fzf_selectors_cycle、test_all_child_menus_retain_last_item、test_log_query_failure、test_manual_snapshot_ids、test_term_snapshot_delete_guards、test_term_snapshot_delete_releases_lock、test_term_snapshot_query_failures、test_terminal_tools_lifecycle（沙箱 HOME）、test_maintenance_lock*（用 TMP 锁文件）。

其余（update/clean/quicksave/quickload/offsite/migration/mirror/sysup/scrub/restore/schedule）属于"有桩但会驱动真实脚本的写路径"，按 HANDOFF 第四节的要求应在确认桩覆盖后运行，不建议在未准备的环境里整套跑。

---

## 附：本次实测命令与依据（可复现）

- bash -n 全部 10 个在范围内文件（含 tests/run）→ 通过。
- bash -c 'if ! (exit 5); then echo "rc_in_then=$?"; fi' → rc_in_then=0；git config --global --unset-all <缺失键> → 5。（P1-1 根因）
- HOME=<空目录> git config --global --list → 致命错误、rc=128。（P1-2）
- 沙箱 terminal-tools：fresh --disable 创建 config/fish/config.fish；--enable→删键→--disable rc=1 且状态文件保留；软链被替换为 -rwxrwxrwx。（P1-1/1-3 + P3-7）
- 桩（lsblk/smartctl/df/findmnt/btrfs/systemctl 全 exit 5）：storage-health 无 --strict → 0、--strict → 1。（P2-1）
- 桩（lspci/lsmod/glxinfo/vulkaninfo 全 exit 5）：gpu-check 无 --strict → 0，且输出"未检测到 NVIDIA 显卡"。（P2-1/P2-2）
- 桩 upower：-e exit 1 → rc=1 无脚本消息；-i exit 3 → rc=3。（P2-4）
- 受限 PATH 无 pacdiff：pacnew-check --strict → rc=1（缺命令）。（P2-5）
- 沙箱 HOME 运行 log-check → 生成 $HOME/log-check-<ts>.md；HOME 不存在 → 行 172 裸报错。（P2-3）
- df 桩含空格挂载点 → 输出 /run/media/pang/My 已使用 50%；findmnt -F <假 fstab> -r → /run/media/pang/My\x20Disk。（P2-6）
- 进程组 SIGINT（父 trap exit 130 + 前台子 trap exit 130）→ 父 INT trap 抢先执行，脚本 exit 130，菜单不会重绘。（P2-7）
- 桩 snapper 300 行：长描述 6.606s / 短描述 1.900s；_snap_row×100=0.366s；逐字符 $(ui_dwidth) 33 字符=0.036s vs 直接调用 0.008s。（P2-8）
- 桩 snapper 20 个带 batch 的 ID → warn_batch_pairs 共 41 次 snapper。（P2-11）
- strace/xtrace 计数 hw-doctor 一次 86 个子进程（tput 17 / expand 7 / systemctl 11）；暖机 0.44-0.57s。（P3-8）
- 真实只读运行（暖机）：check-battery 74-80ms、terminal-tools --status 64-70ms、storage-health 198-213ms、pacnew-check 231-376ms、boot-check 470-490ms、gpu-check 792-820ms、hw-doctor 440-570ms、log-check 79ms。

## 未覆盖 / 无法在本环境验证

- boot-check / pacnew-check 的 TTY sudo 交互路径：本会话无 TTY，request_read_access（boot-check:18-31、pacnew-check:12-25）直接返回 0，只验证了"无权限时按查询失败处理"的分支；TTY 下的提示与只读 sudo 复用依赖 tests/run 的 PTY 用例（我未运行）。
- term-menu 真 fzf 交互（按键契约）：本范围只做了静态核对；仓库自带的 PTY 用例覆盖了 --cycle 与 load:pos()，我未重复运行。
- btrfs 挂载点含空格的真实 btrfs device stats 失败：无法在不写系统状态的前提下创建此类挂载；结论基于 findmnt raw 行为的实测 + 代码路径推理（标注为"已确认的行为链"）。
- quickload/quicksave/offsite/migration 等破坏性路径不在本任务范围，未执行。
