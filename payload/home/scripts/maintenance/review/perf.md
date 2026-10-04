# 读取慢 / 刷新慢 —— 实测性能报告（term-menu / checkallupdates / quickload / storage-health / hw-doctor）

- 审计对象：`/home/pang/scripts/maintenance`（~12.2k 行 Bash，git HEAD `10a0cdb`）
- 本机环境（实测）：Arch Linux，kernel `7.2.4-zen2-1-zen`，bash `5.3.15`，jq `1.8.2`，strace `7.0`，fzf `/usr/bin/fzf`；`/` 与 `/home` 为同一 btrfs 设备 `/dev/nvme0n1p7`，物理盘 1 块
- **全部数字都来自本机真实执行的命令**；没有修改仓库任何文件（`git status --porcelain` 为空）；没有执行任何写状态命令（无 pacman -Syu/-Sy、无 flatpak update、无 snapper/btrfs 变更、无 systemctl 变更，`systemctl` 一律用 stub 顶替）
- 全部 shim / stub / 日志在 `/tmp/maintenance-review/perf/`；一键复现：`bash /tmp/maintenance-review/perf/measure.sh`（原始输出 `/tmp/maintenance-review/perf/measure.log`）
- 标注：**[实测]** = 本机真实跑出来的；**[估算]** = 由实测单次成本 × 代码中的调用次数推算，已注明

---

## (a) 排名表：路径 → 实测成本 → 进程/exec 数 → 根因 → 具体修法

| # | 路径（file:line） | 实测成本 | 进程 / exec 计数 | 根因 | 具体修法 |
|---|---|---|---|---|---|
| 1 | `term-menu` 快照查看 `show_snapshots` → `print_snapshot_list`（`term-menu:867`，热点 `term-menu:890-959`） | **[实测]** 10 条/配置 364 ms；200 条/配置 **3155 ms**；500 条/配置 **7454 ms** → 线性 **≈7.3 ms/行**（2 个配置）。单行复制基准：短描述 **5.89 ms/行**，长描述（触发逐字截断）**30.33 ms/行**（n=300） | **[实测]** 200 条/配置一次渲染：`clone` **2942**、`wait4` **5867**、`execve` 133（成功 52）；`wait4` 占 syscall 时间 **79.9 %**（2.97 s / 3.72 s）。约 **7.4 次 fork / 行** | 每行用命令替换取字段：`desc_display="$(compact_text …)"`（949）、`entries+="$(_snap_row …)"`（952），`_snap_row` 内 5 个 `$(ui_pad …)`（911-915）→ 6 个 subshell/行；`compact_text:890` 宽度检查 `$(ui_dwidth "$text")` 再来 1 个，**截断时逐字符 `$(ui_dwidth "$ch")`（第 901 行）每字 1 个 fork**，故长描述 ~31 ms/行 | 行渲染去 fork：宽度用 `_ui_dwidth_calc`（`lib/ui.sh:414`，纯 bash）直接取 `$UI_DWIDTH_RESULT`，用 `printf -v` 拼行而不是 `$( )`；`compact_text` 的逐字符循环改为按字节/前缀一次算宽。**[实测]** 复制基准里 fork-free 版 **0.09 ms/行（短）0.14 ms/行（长）**，即 **≈65×/≈215×** |
| 2 | `term-menu` 快照路径的 snapper 串行单次查询（`show_snapshots` 里 `term-menu:1012` 的 `for conf in "${ordered_configs[@]}"` → `snapper … list` @ `term-menu:926`；开头 `list-configs` @ `term-menu:990`） | **[实测]** 2 个配置共 **3 次串行 snapper**：延迟 0 s→333 ms，0.1 s→657 ms，0.3 s→1264 ms，0.6 s→2166 ms ⇒ **墙面时间 = 3 × 单次延迟 + ~330 ms**（斜率 3.05） | **[实测]** 每次调用 1 个 `snapper` 子进程；串行 `wait`（无并行） | 每条配置一次 `snapper list`，循环里逐个等待；本机 `snapper list-configs` 8 ms、真实 `snapper list` 在大快照表下通常 100-400 ms | 拿到 `list-configs` 后**并行**发起每个配置的 `snapper list`（后台 `&` + `wait`，与 `checkallupdates` 的做法一致），或对支持 `--root` 的场景合并一次调用；墙面时间从 N×延迟降到 1×延迟 |
| 3 | `quickload --list` / `--list-all`（`quickload:332` list-configs → `quickload:396-460`；行渲染 `quickload:455`） | **[实测]** `--list` **673 ms**（2 次串行 snapper @0.3 s）；`--list-all` **1015 ms**（3 次串行）；snapper 零延迟 + 200 条/配置时仍 **1183 ms**（3 次 1163-1266 ms）→ 行渲染同样 ≈3 ms/行 | **[实测]** 每次 `snapper`=1 进程；零延迟 200 条/配置下有 **400 行 × 3 个 `$(ui_pad …)`** 子 shell | 与 #1 同类：`printf "$MSG_LIST_FMT" "$(ui_pad …)"` ×3/行；查询本身也是每个配置一次串行 `get_snapper_list_output`（378-394） | 同 #1 去 fork；`--list-all` 的多配置查询并行化 |
| 4 | `cache-clean --list` 预览（`cache-clean:72` `dir_bytes` → `du -sb \| awk`，被 `cache-clean:118 cache_row` 每行调用；`show_list` 12 行） | **[实测]** `--list` 717 / 701 / 679 / 689 ms；单路径 `du -sb`：`.rustup` **1043 ms**、`.npm` 293、`mason` 288、`.cargo` 275、chrome 63、go-build 59、`/var/cache/pacman/pkg` 53、thumbnails 5 ms | **[实测]** 12 行 × 2 个子进程（`du`+`awk`）= 24；但 **13 次独立 `du\|awk` = 602 ms，单次 `du` 传 13 个路径 = 580 ms** → 进程开销只占 **~22 ms（3.6 %）** | 成本几乎全是 `du` 真实遍历（**本身是对的**，不是 fork 问题）；问题是"预览"被这 ~0.6-0.7 s 阻塞、且 `--all-*` 清理前后各再算一次（`cache-clean:369`+`375`） | 预览不需要精确字节数：可先渲染、大小后台异步填充（或对"保留不动"行干脆不 `du`）；`du` 合并成一次调用只能省 ~22 ms。**真要省的是感知延迟，不是 CPU** |
| 5 | `storage-health` SMART 每字段一个 `jq`（`storage-health:44 smart_value`，调用点 `storage-health:68-76`，另 77-99 有 3 处 jq） | **[实测]** 真实（本机 1 盘 1 btrfs）：**224 ms** rc=0；stub 3 盘 + 3 btrfs：**474 ms**。**12 次 jq/盘**（同一份 JSON 反复解析）：12 次独立 jq = **56 ms**，同一份 5 KB JSON 单次 jq = **3.4 ms** → **≈16×** | **[实测]** stub 3 盘 + 3 挂载点：**126 次 execve**，其中 `jq` **38**、`tput` **20**、`bash` 15、`date` 12、`awk` 7、`btrfs` 6、`systemd-escape` 3、`systemctl` 3、`smartctl` 3 | `smart_value` 每个字段起一个 `jq` 重新解析整份 smartctl JSON（多盘时线性放大） | 一台设备一次 `jq -r '[.model_name,.serial_number,…]|@tsv'` 取全部字段（**[实测]** 单次解析 3.4 ms vs 12 次 56 ms）；`df`/`awk` 已是单次调用（`storage-health:175-190`），无需改 |
| 6 | `checkallupdates --refresh` / `--refresh-stale` 记账开销（`checkallupdates:373-507`） | **[实测]** 三个来源各 0 s（纯记账）**71 ms**；`--refresh-stale` 全新鲜 **75 ms**（0 次来源查询）；只 AUR 过期 **1089 ms**（1 s 是 paru stub 的 sleep，记账 ≈89 ms） | **[实测]** 纯记账 `--refresh` **59 次 execve**（`mktemp` **10**、`find` **6**、`date` 6、`touch` 4、`mv` 4、`bash` 4、`timeout` 3、`basename` 3、`awk` 3、`mkdir` 2、`flock` 2…）；`--refresh-stale` 全新鲜仍 **37 次 execve**（`mktemp` 10、`find` 6、`awk` 6、`stat` 3） | 每次刷新无论是否需要查询都：建 **10 个 mktemp**（415-424）、`_cau_reclaim_orphans` 跑 **6 次 `find -mmin +60`**（222-229）、合并/落盘 status、`touch`/`rm` 时间戳 | 完全跳过时（stale 且全新鲜，`checkallupdates:392-396`）应直接 `print_cached_updates_or_empty` 返回，不建临时文件、不跑 orphan 回收；`find` 回收改为一次 `find` 多 `-name`（`-o`）调用。**[实测]** 6 次 find=9 ms、10 次 mktemp=13 ms，记账地板 ~40-75 ms |
| 7 | 交互渲染小成本：`ui_status_line`（`lib/ui.sh:774-811`）每次 fzf footer；`checkallupdates --load-actions` 每次 fzf load；`term-menu --preview` 每次光标移动 | **[实测]** `ui_status_line` **17-21 ms**（`df`+`tail`+`tr`+`ip`+`awk`×2+`date`）；`checkallupdates --load-actions` **15-17 ms**（每次列表渲染都会 fork 一个完整 bash + 重新 source `lib/ui.sh`+`lib/config.sh`）；`term-menu --preview __update_menu` **25 ms**、`clean` **22 ms**（每按一次方向键） | **[实测]** 冷启动交互打开 `checkallupdates`（缓存冷/热都）**48 ms**，**18 次 execve**；`term-menu` 启动到退出 **61-69 ms**，**24 次 execve** | `ui_status_line` 每行 1 个子进程链（`ip route \| awk` 6 ms 最贵）；`--load-actions` 与 preview 都是"整脚本重跑"模式 | `ui_status_line` 每项缓存 2-5 s（或纯 bash 读 `/proc/net/route`）；preview 用 `term-menu` 内部函数直接调用（`BASH_SOURCE` 已支持 `--preview`，但仍在 fork 新 bash）→ 至少把 `lib/ui.sh` 的 source 改成按需 |
| 8 | `hw-doctor`（`hw-doctor:386` 4 次串行 `findmnt`） | **[实测]** 冷启动 **2461 ms**（首次），热 **435-446 ms**；`lspci` stub 掉后 **323 ms** → `lspci -k` ≈ **123 ms** | **[实测]** 115 次 execve：`tput` 17、`bash` 17、`expand` 15、`systemctl`(stub) 11、`grep` 11、`awk` 9、`findmnt` 3 | `for mountpoint in / /home /boot /efi` 逐个 `findmnt`（每个 ~3 ms，可忽略）；19 个 panel 各 1 次 `tput cols`（`_ui_rule_width`）+ `expand` | 4 次 `findmnt --target` 可合并为一次 `findmnt -rn`；`tput cols` 每次 panel 重开（`lib/ui.sh:280`）可缓存到变量 |
| 9 | `term-menu` 删除快照的批量配对检查（`term-menu:1070 warn_batch_pairs`） | **[实测]** snapper stub 8 ms/次；真实 snapper 100-300 ms/次 **[估算]** | **[实测]** 代码在 `for id in "$@"` 里对每个选中 id 重跑 `snapper … list --columns number,userdata`（1093）和 `snapper … list-configs`（1097）⇒ **O(选中数 × 配置数)** 次相同查询 | 同一份"userdata/批次"数据被每个 id 重复查询 | 循环外查一次、建 id→batch 映射（现在 `id_batch` 已在循环外，但"其它配置"部分在循环内） |

### 关键量化证据（不是估算）

- **单次 fork/子进程成本（本机实测，进程内 1000-3000 次循环）**：`$(printf %s hi)` **0.526 ms**；`$(ui_pad abc 8)` **0.832 ms**；`$(ui_dwidth abc)` **0.854 ms**；`ui_pad` 直接函数调用 **0.084 ms**；`_snap_row` 等价（1+5 子 shell）**5.118 ms**；`date +%s` **1.076 ms**；`stat -c %Y` **1.063 ms**；`basename` **1.021 ms**；`awk` **2.382 ms**；`jq` **3.302 ms**；空循环 **0.006 ms**
- **`checkallupdates` 三来源确实是并行**（详见"假警报"节）
- **`--refresh-stale` 确实只查过期来源**（详见"假警报"节）

---

## (b) 用到的确切命令

所有产物在 `/tmp/maintenance-review/perf/`；`P=/tmp/maintenance-review/perf`，`R=/home/pang/scripts/maintenance`。

**0. 环境**
```bash
git -C "$R" rev-parse --short HEAD; git -C "$R" status --porcelain
bash --version | head -1; jq --version; strace -V | head -1; fzf --version
```

**1. term-menu 冷启动（fake fzf 立即以 130 取消）**
```bash
# $P/bin/fzf: 记录 argv、读干 stdin、exit 130（或按 FZF_SHIM_PICK 返回指定行）
export PATH=$P/bin:$P/stub:/usr/bin:/bin FZF_SHIM_LOG=$P/logs/fzf.log FZF_SHIM_COUNT=$P/logs/fzf.count
export FZF_SHIM_RC=130
for i in 1 2 3 4 5; do s=$(date +%s%N); "$R/term-menu" </dev/null >/dev/null 2>&1; e=$(date +%s%N); echo $(( (e-s)/1000000 )); done   # → 61..69 ms
strace -f -e trace=execve -o "$P/logs/tm-execve.txt" "$R/term-menu" </dev/null >/dev/null 2>&1
grep 'execve(' "$P/logs/tm-execve.txt" | grep -v ENOENT | sed -E 's/.*execve\("([^"]+)".*/\1/' | sort | uniq -c | sort -rn   # → 24 execve
strace -f -o "$P/logs/tm-syscalls.txt" -c "$R/term-menu" </dev/null >/dev/null 2>/dev/null
```

**2. term-menu 快照路径（确定性 fzf + snapper stub）**
```bash
export SNAPPER_LOG=$P/logs/snapper.log STUB_SNAP_COUNT=10 STUB_DELAY_SNAPPER=0
FZF_SHIM_PICK="1:__snapshot_menu;2:view-snapshots" "$R/term-menu" </dev/null >/dev/null 2>&1
# 延迟扫描 0/0.1/0.3/0.6 s → 333/657/1264/2166 ms；STUB_SNAP_COUNT=200 → 3155 ms；=500 → 7454 ms
export STUB_SNAP_COUNT=200
FZF_SHIM_PICK="1:__snapshot_menu;2:view-snapshots" strace -f -c -o "$P/logs/tm-snap200-c.txt" "$R/term-menu" </dev/null >/dev/null 2>/dev/null
grep -E 'clone|execve|wait4|% time' "$P/logs/tm-snap200-c.txt"   # clone 2942, wait4 5867, wait4 79.87%
```

**3. 行渲染复制基准（不改仓库，复制 `term-menu:890-959` 的函数到 /tmp）**
```bash
bash $P/rowbench.sh 300
# current impl short 5.89 ms/row / LONG 30.33 ms/row ; fork-free 0.09 / 0.14 ms/row
bash $P/bench2.sh 2>/dev/null
```

**4. checkallupdates 刷新（stub PATH + HOME 重定向，缓存写进 /tmp）**
```bash
export HOME=$P/home PATH=$P/stub:$P/bin:/usr/bin:/bin STUB_LOG=$P/logs/stub.log
export STUB_DELAY_CHECKUPDATES=1 STUB_DELAY_PARU=1 STUB_DELAY_FLATPAK=1
rm -rf "$HOME/.cache/checkallupdates"
s=$(date +%s%N); "$R/checkallupdates" --refresh >/dev/null 2>&1; e=$(date +%s%N); echo $(( (e-s)/1000000 ))   # → 1069 ms（并行：3×1 s）
export STUB_DELAY_CHECKUPDATES=3 STUB_DELAY_PARU=1 STUB_DELAY_FLATPAK=1   # → 3072 ms（=max，不是 5000）
export STUB_DELAY_CHECKUPDATES=0 STUB_DELAY_PARU=0 STUB_DELAY_FLATPAK=0   # → 71 ms 纯记账
strace -f -e trace=execve -o "$P/logs/cau-execve.txt" "$R/checkallupdates" --refresh >/dev/null 2>&1   # → 59 execve, mktemp 10, find 6
# 全新鲜时 --refresh-stale：
strace -f -e trace=execve -o "$P/logs/cau-stale-execve.txt" "$R/checkallupdates" --refresh-stale >/dev/null 2>&1  # → 75 ms, 37 execve, 0 次来源查询
# 只让 AUR 过期：
touch "$HOME/.cache/checkallupdates/last-refresh-pacman" "$HOME/.cache/checkallupdates/last-refresh-flatpak"
touch -d '2 hours ago' "$HOME/.cache/checkallupdates/last-refresh-aur"
"$R/checkallupdates" --refresh-stale   # → 1089 ms，stub 日志里只有 paru 被调用
# fzf load 事件成本：
for i in 1 2 3 4 5; do s=$(date +%s%N); "$R/checkallupdates" --load-actions >/dev/null; e=$(date +%s%N); echo $(( (e-s)/1000000 )); done  # → 15..17 ms
# 交互打开（fake fzf）：
CHECKALLUPDATES_ALLOW_NONINTERACTIVE_UI=1 FZF_SHIM_RC=130 "$R/checkallupdates" </dev/null   # → 48 ms, 18 execve
```

**5. quickload**
```bash
export SNAPPER_LOG=$P/logs/snapper-ql.log STUB_DELAY_SNAPPER=0.3 STUB_SNAP_COUNT=10
"$R/quickload" --list       # → 673 ms, snapper 2 次
"$R/quickload" --list-all   # → 1015 ms, snapper 3 次
STUB_DELAY_SNAPPER=0 STUB_SNAP_COUNT=200 "$R/quickload" --list-all   # → 1183 ms
```

**6. cache-clean（只跑 `--list`，只读）**
```bash
"$R/cache-clean" --list    # → 717 / 701 / 679 / 689 ms（4 次）
for p in "$HOME/.rustup" "$HOME/.npm" "$HOME/.local/share/nvim/mason" "$HOME/.cargo" \
         "$HOME/.cache/google-chrome" "$HOME/.cache/go-build" /var/cache/pacman/pkg "$HOME/.cache/thumbnails"; do
  s=$(date +%s%N); du -sb -- "$p" 2>/dev/null | awk '{print $1}'; e=$(date +%s%N); echo "$p $(( (e-s)/1000000 )) ms"; done
# 13 次独立 du|awk=602 ms vs 1 次 du 传 13 参数=580 ms
```

**7. storage-health（真实只读 + stub 放大）**
```bash
env PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/bin "$R/storage-health"    # 真实 → 224 ms rc=0
export PATH=$P/stub:/usr/bin:/bin SMART_LOG=$P/logs/smart.log
strace -f -e trace=execve -o "$P/logs/sh-execve.txt" "$R/storage-health" >/dev/null 2>&1   # → 126 execve, jq 38
grep 'execve("/usr/bin/jq"' "$P/logs/sh-execve.txt" | sed -E 's/.*\[([^]]*)\].*/\1/' | sort | uniq -c | sort -rn
# 同一 5 KB JSON：12 次独立 jq = 56 ms；单次多字段 jq = 3.4 ms
```

**8. hw-doctor**
```bash
for i in 1 2 3; do s=$(date +%s%N); PATH=$P/stub:/usr/bin:/bin "$R/hw-doctor" >/dev/null 2>&1; e=$(date +%s%N); echo $(( (e-s)/1000000 )); done  # → 435..446 ms（首次冷 2461 ms）
PATH=$P/stub2:$P/stub:/usr/bin:/bin "$R/hw-doctor"   # lspci 打桩 → 322-324 ms ⇒ lspci ≈120 ms
PATH=$P/stub:/usr/bin:/bin strace -f -e trace=execve -o "$P/logs/hw-execve.txt" "$R/hw-doctor" >/dev/null 2>&1  # → 115 execve
```

**9. 微基准**
```bash
bash $P/bench2.sh        # ui_pad 直调 0.084 ms vs $(ui_pad) 0.832 ms vs $(ui_dwidth) 0.854 ms vs 1+5 子 shell 5.118 ms
# 外部命令：date 1.076 ms / stat 1.063 ms / basename 1.021 ms / awk 2.382 ms / jq 3.302 ms（n=1000）
```

**10. 静态定位（只读 grep，行号已核对）**
```bash
grep -rn 'sleep [0-9]' "$R" | grep -v '^.*tests/'
grep -rn '\bfind \|\bdu -' "$R" | grep -v '^.*tests/'
python3 $P/loopscan.py "$R"     # 扫描"循环体内含外部命令"的位置
grep -n 'compact_text()\|_snap_row()\|desc_display="\$(compact_text\|entries+="\$(_snap_row' "$R/term-menu"
```

---

## (c) 假警报 / 其实没问题（明确排除，避免误修）

1. **`checkallupdates --refresh` 的来源查询是真并行，不是串行** **[实测]**
   三个来源各 sleep 1.0 s → 总耗时 **1069 ms**；`pacman=3 s, aur=1 s, flatpak=1 s` → **3072 ms**（串行会是 5 s）。stub 时间线（`$P/logs/stub.log`）显示三个 START 在 0.7 ms 内、三个 END 在 0.4 ms 内。`checkallupdates:429-455` 的 `&` + `wait` 设计有效，**不要"优化"成串行**。
2. **`--refresh-stale` 真的只查过期来源** **[实测]** 全新鲜时 75 ms、**0 次来源查询**（`checkallupdates:392-396`）；只让 AUR 过期时日志里**只有 paru** 被调用，pacman/flatpak 沿用缓存。
3. **刷新是懒加载的，不阻塞首屏** **[实测]** 冷缓存交互打开 `checkallupdates` 只要 **48 ms / 18 次 execve**（缓存热时同样 48 ms）；过期时只挂 `refresh-pending` 标记，由 fzf `load` 事件触发（`checkallupdates:745-754`、`790`）。整轮网络刷新被推迟到 `reload-sync` 之后 —— 这是**设计正确的异步**，用户可感知的"刷新慢"来自真实网络时间 + ~70-90 ms 记账地板（见排名 #6），不是同步阻塞。
4. **`print_tagged_cache` 是单次 `awk`，几百个包不会爆子进程** **[实测]** `checkallupdates:181-182` 明确用一条 `awk` 输出全部行；`--refresh` 全流程 0 s stub 只有 **59 次 execve**，其中 `awk` 仅 3 次。
5. **`cache-clean` 的 `du` 开销是真实遍历，不是 fork 问题** **[实测]** 13 次独立 `du|awk` 602 ms vs 单次 `du` 传 13 个路径 580 ms → 进程开销仅 ~22 ms（3.6 %）。改成"一次 du"最多省 ~22 ms；真正的改法是别让**预览**等它。
6. **`ui_dwidth` / `ui_pad` 本身是纯 bash，不 fork** **[实测]** 直接函数调用 **0.084 ms**；`lib/ui.sh:414` 的 `_ui_dwidth_calc` 无外部命令。**只有 `$( )` 包装才 fork**（0.83 ms/次）。
7. **`pacnew-check` 的 `find /etc` 等不是瓶颈** **[实测]** 4 个路径各 **3-4 ms**（0 匹配），`mktemp`/`awk` 每轮各一次可忽略（`pacnew-check:91-113`）。
8. **`quickload:1043`、`quickload:1131`、`quickload:1343`、`term-menu:1432` 的 `sleep 1-3`** 都在"重启前/启动 GUI 后"的交互确认场景，是刻意的人性化停顿，不是性能缺陷。
9. **`lib/ui.sh:133` 的 `sleep 60`** 是 sudo 保活后台循环（每 60 s 一次 `sudo -n true`），不影响前台；只在需要 sudo 的长任务里启动。
10. **`checkallupdates:727` 的 `sleep 3`** 只在"未安装 fzf"的错误路径上，正常路径不执行。
11. **`storage-health` 在本机只有 224 ms**（1 盘 1 btrfs 设备），单盘用户感觉不到慢；#5 的问题只在多盘/多挂载点机器上线性放大（stub 3 盘 → 474 ms，其中 jq 重解析占 ~150 ms）。
12. **`hw-doctor` 的 2.4 s 只是首次冷启动**（`lspci` 首次枚举）；热启动 435-446 ms。作为一次性诊断可接受。

---

## 覆盖范围与置信度

- **已实测**：`term-menu`（启动/取消、快照查看全路径、`--preview`）、`checkallupdates`（`--refresh`、`--refresh-stale`、`--load-actions`、交互打开）、`quickload`（`--list` / `--list-all`）、`cache-clean --list`、`storage-health`（真实 + stub 放大）、`hw-doctor`（真实 + stub）、`lib/ui.sh` 的 `ui_status_line`/`ui_pad`/`ui_dwidth` 与单次 fork/外部命令成本。全部数字来自本机执行。
- **仅静态分析（未端到端测）**：`sysup`（**未运行**：唯一路径会触发 `pacman -Syu` 等写操作，按规则禁止；只读了 `sysup:43-95`/`sysup:489-537`，其新闻 `curl` 有 `--connect-timeout 10 --max-time 25`，是更新前的串行网络等待，属设计选择）、`clean`、`mirror-update`、`offsite-backup`、`migration-pack`、`backup-restore`、`log-check`（需 `systemctl`/`journalctl` 样本，按规则未跑）。其中的 `clean:451-457`、`quicksave:184-186`、`quicksave:220-231` 的"每配置一次串行 snapper"与 #2 同型，但配置数少（root/home），**[估算]** 影响 ≤ 1-2 次 snapper 延迟。
- **测量噪声**：会话中有其他 teammate 同时使用同一台机器/同一 `/tmp` 目录；关键项取 3-5 次中位数，趋势（线性/并行）不受影响。
- **可复现**：`bash /tmp/maintenance-review/perf/measure.sh`（完整原始日志 `measure.log`）；shim/stub 全在 `/tmp/maintenance-review/perf/{bin,stub}`，仓库零改动（`git status --porcelain` 空）。
