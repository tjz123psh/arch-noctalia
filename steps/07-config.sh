#!/usr/bin/env bash
# steps/07-config.sh — Stage 07: 部署配置与资产（dotfiles / 字体 / greeter 等）。
# 按 manifests/files.tsv（repo_path<TAB>target_path<TAB>mode<TAB>md5）逐行部署：
#   1) 预检：payload 文件存在且 md5 与清单一致，否则 die（仓库拷贝不完整）；
#   2) 部署：install -D -m <mode> —— $HOME 内用当前用户，其余（/etc、/usr/share、/var/lib）走 sudo；
#   3) 每行部署后立即复核 md5（+ 权限位）；不一致 → warn + 计数，继续后续行，不中断；
#   4) 幂等：常规文件且 md5（+ 权限位）一致 → 跳过（unchanged）；
#   5) seed（manifests/seed.tsv，个人数据种子如便签/模板）与 runtime（manifests/runtime-regenerated.tsv，
#      装完由桌面自行改写的主题产物/登录背景/supergfxd mode 等）：已存在一律保持现状，只在缺失时初始化；
#   6) 覆盖"内容不同"的文件前，先把旧内容备份到 .state/overwritten/<时间戳>/；
#   7) 两种环境适配（不改挂载设置）：FAT 系（vfat/exfat，如 ESP）没有 Unix 权限位——权限由挂载选项
#      决定，这类文件系统跳过权限位校验；系统文件普通用户读不到时，校验改用 root 读；
#   8) 目标路径护栏：清单第 2 列必须是绝对路径且落在 AN_TARGET_ALLOW 的顶层目录内；
#      AN_TARGET_ROOT 非空时整棵目标树重写到该前缀下（测试/演练用，真实安装留空）。
#   9) 部署后收尾：建标准用户目录、locale-gen、登录 shell（fish）、GRUB 菜单重建、
#      GSettings vendor override 重编译（*.gschema.override → glib-compile-schemas）。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator

MANIFEST="${AN_ROOT_DIR}/manifests/files.tsv"
[[ -f "$MANIFEST" ]] || die "missing manifest: ${MANIFEST}"

md5_of() { local f="$1"; md5sum "$f" 2>/dev/null | awk '{print $1}'; }

# --- 1) 预检：payload 完整性（存在 + md5）+ 目标路径合法性（绝对路径 & 顶层白名单） ---
rows=0
payload_bad=0
target_bad=0
while IFS=$'\t' read -r repo_path raw_target _mode md5; do
  if [[ -z "$repo_path" || "$repo_path" == "#"* ]]; then
    continue
  fi
  rows=$((rows + 1))
  if ! an_resolve_target "$raw_target" >/dev/null; then
    target_bad=$((target_bad + 1))
  fi
  src="${AN_ROOT_DIR}/${repo_path}"
  if [[ ! -f "$src" ]]; then
    payload_bad=$((payload_bad + 1))
    warn "payload missing: ${repo_path}"
    continue
  fi
  actual="$(md5_of "$src")" || actual=""
  if [[ "$actual" != "$md5" ]]; then
    payload_bad=$((payload_bad + 1))
    warn "payload md5 mismatch: ${repo_path}"
  fi
done < "$MANIFEST"

if (( payload_bad > 0 )); then
  die "payload incomplete — the repository copy is broken; re-clone it"
fi
if (( target_bad > 0 )); then
  die "${target_bad} manifest target(s) rejected — they must be absolute and under AN_TARGET_ALLOW"
fi
# sudoers 这类"部署错了会锁死 sudo"的文件，先在预检里验语法（不合格直接中止，不冒险写 /etc）。
if have visudo && [[ -d "${AN_ROOT_DIR}/payload/system/etc/sudoers.d" ]]; then
  for f in "${AN_ROOT_DIR}"/payload/system/etc/sudoers.d/*; do
    [[ -e "$f" ]] || continue
    visudo -cf "$f" >/dev/null 2>&1 || die "invalid sudoers payload: $(basename "$f") — refusing to deploy (a broken sudoers locks out sudo)"
  done
  ok "sudoers payload: syntax verified"
fi

info "Stage 07 config: ${rows} files to deploy; payload verified"
if [[ -n "${AN_TARGET_ROOT:-}" ]]; then
  info "Stage 07 config: SANDBOX — all targets are rewritten under ${AN_TARGET_ROOT} (nothing touches the real system)"
fi

# --- 2) 部署 + 3) 逐行复核 ---
load_seed_targets
load_runtime_targets

# 覆盖前备份：把将被覆盖文件的旧内容存到 ${AN_STATE_DIR}/overwritten/<时间戳>/（用户可读、可恢复）。
# 备份是覆盖的**前置条件**：拿不到副本就返回 1，调用方计 failed 并跳过这个文件。
# 宁可这一次不更新某个文件，也不做「没有副本的覆盖」。
RUN_TS=""
backup_overwritten() { # $1=target  $2=ftype  → 0=有副本或无需副本，1=备份失败
  local t="$1" ftype="$2" rel base base_ts suffix
  [[ "$ftype" == "regular file" ]] || return 0
  if [[ -z "$RUN_TS" ]]; then
    # 同一秒内跑两次要落到不同目录，否则第二次的 cp 会把第一次的备份覆盖掉。
    base_ts="$(date +%Y%m%d-%H%M%S)"
    RUN_TS="$base_ts"
    suffix=1
    while [[ -e "${AN_STATE_DIR}/overwritten/${RUN_TS}" ]]; do
      suffix=$((suffix + 1))
      RUN_TS="${base_ts}-${suffix}"
    done
  fi
  rel="${t#/}"
  base="${AN_STATE_DIR}/overwritten/${RUN_TS}/${rel}"
  if ! mkdir -p -- "$(dirname -- "$base")"; then
    warn "backup dir not writable: $(dirname -- "$base")"
    return 1
  fi
  if [[ "$t" == "$HOME"/* ]]; then
    if ! cp -- "$t" "$base" 2>/dev/null; then
      warn "backup failed: ${t}"
      return 1
    fi
  else
    # 系统文件由 root 读、重定向由当前用户执行（备份文件归用户所有，可自行恢复）。
    if ! as_root cat -- "$t" > "$base" 2>/dev/null; then
      rm -f -- "$base"
      warn "backup failed: ${t}"
      return 1
    fi
  fi
  info "backed up: ${t} -> ${base}"
}

# 软链被替换前，把「它原本指向哪」记下来——cp 只能存内容，存不了链接本身。
backup_symlink() { # $1=target  → 0=已记录，1=失败
  local t="$1" rel base
  [[ -n "$RUN_TS" ]] || RUN_TS="$(date +%Y%m%d-%H%M%S)"
  rel="${t#/}"
  base="${AN_STATE_DIR}/overwritten/${RUN_TS}/${rel}.symlink"
  if ! mkdir -p -- "$(dirname -- "$base")"; then
    warn "backup dir not writable: $(dirname -- "$base")"
    return 1
  fi
  if ! printf "%s\n" "$(readlink -- "$t")" > "$base" 2>/dev/null; then
    warn "backup failed (symlink): ${t}"
    return 1
  fi
  # 能整份复制就再存一份（保留链接形态）；失败不影响上面那份指向记录。
  cp -P -- "$t" "${base%.symlink}" 2>/dev/null || true
  info "backed up symlink: ${t} -> $(readlink -- "$t") (recorded in ${base})"
}

checked=0
deployed=0
unchanged=0
kept=0
failed=0
mode_skipped=0
while IFS=$'\t' read -r repo_path raw_target mode md5; do
  if [[ -z "$repo_path" || "$repo_path" == "#"* ]]; then
    continue
  fi
  checked=$((checked + 1))
  # 清单目标 → 实际路径（白名单校验 + 可选的 AN_TARGET_ROOT 沙箱重写）。
  if ! target="$(an_resolve_target "$raw_target")"; then
    failed=$((failed + 1))
    continue
  fi
  src="${AN_ROOT_DIR}/${repo_path}"

  # 现状读取（读不到且为系统目标时自动回退 root 读，见 lib/common.sh 的 _target_probe）。
  ftype="$(t_type "$target")"          # 空 = 不存在（或 root 也判定不了）
  exists=0
  if [[ -n "$ftype" ]]; then
    exists=1
  fi

  # seed（个人数据种子）：已存在就保持现状，绝不覆盖；缺失才初始化。
  if (( exists == 1 )) && [[ -n "${AN_SEED[$repo_path]:-}" ]]; then
    info "kept (seed — initialized only when missing): ${target}"
    kept=$((kept + 1))
    continue
  fi

  # runtime（装完由桌面/程序自行改写）：同样「存在即保持」。
  # 否则 --redo 07 会把 Noctalia 主题产物、登录背景打回仓库快照，还会连带丢掉 11 步加在
  # /etc/nwg-hello/background.png 上的 u:pang:rw ACL（install 会重建 inode），此后换壁纸就写不进去。
  if (( exists == 1 )) && [[ -n "${AN_RUNTIME[$repo_path]:-}" ]]; then
    # 例外：/etc/supergfxd.conf 里的 hotplug_type=Asus 是安装器必须保证的值（README 的「切集显重启又回混合」坑）。
    # 该键没落上时照常覆盖（先备份），不能因为它是运行时文件就放过。
    if [[ "$raw_target" != "/etc/supergfxd.conf" ]] || grep -q '"hotplug_type": "Asus"' "$target" 2>/dev/null; then
      info "kept (runtime — rewritten by the desktop): ${target}"
      kept=$((kept + 1))
      continue
    fi
  fi

  actual_md5=""
  if (( exists == 1 )); then
    actual_md5="$(t_md5 "$target")"
  fi
  target_fs="$(fs_of_target "$target")"
  mode_enforced=1
  if ! fs_has_unix_perms "$target_fs"; then
    mode_enforced=0
    mode_skipped=$((mode_skipped + 1))
  fi

  # 软链（用户把自己的 dotfile 链过来）：内容一致就保持链接不动。
  # 不这么做的话 install 会 unlink 重建，链接被换成普通文件、而摘要仍显示 0 failed。
  if [[ -L "$target" && -n "$actual_md5" && "$actual_md5" == "$md5" ]]; then
    info "kept (symlink, identical content): ${target} -> $(readlink -- "$target")"
    unchanged=$((unchanged + 1))
    continue
  fi

  # 幂等跳过：常规文件且内容一致；支持权限位的文件系统上还要求权限位一致。
  if [[ "$ftype" == "regular file" && ! -L "$target" && -n "$actual_md5" && "$actual_md5" == "$md5" ]]; then
    if (( mode_enforced == 0 )) || [[ "$(t_perms "$target")" == "$mode" ]]; then
      unchanged=$((unchanged + 1))
      continue
    fi
  fi

  if (( exists == 1 )); then
    if [[ "$actual_md5" == "$md5" ]]; then
      info "re-installing (mode or type differs): ${target}"
    elif [[ -L "$target" ]]; then
      info "replacing symlink (content differs): ${target} -> $(readlink -- "$target")"
      if ! backup_symlink "$target"; then
        warn "skipping ${target}: refusing to replace a symlink without a record of where it pointed"
        failed=$((failed + 1))
        continue
      fi
    else
      info "overwriting changed file: ${target}"
      if ! backup_overwritten "$target" "$ftype"; then
        warn "skipping ${target}: refusing to overwrite without a backup copy"
        failed=$((failed + 1))
        continue
      fi
    fi
  fi

  if [[ "$target" == "$HOME"/* ]]; then
    if ! install -D -m "$mode" "$src" "$target"; then
      warn "install failed: ${target}"
      failed=$((failed + 1))
      continue
    fi
  else
    if ! as_root install -D -m "$mode" "$src" "$target"; then
      warn "install failed (sudo): ${target}"
      failed=$((failed + 1))
      continue
    fi
  fi

  actual_md5="$(t_md5 "$target")"
  if [[ "$actual_md5" != "$md5" ]]; then
    warn "post-install verify failed (md5): ${target}"
    failed=$((failed + 1))
    continue
  fi
  if (( mode_enforced == 1 )); then
    actual_mode="$(t_perms "$target")"
    if [[ "$actual_mode" != "$mode" ]]; then
      warn "post-install verify failed (mode): ${target}"
      failed=$((failed + 1))
      continue
    fi
  fi
  deployed=$((deployed + 1))
done < "$MANIFEST"

printf '[info]  files: %d checked, %d deployed, %d unchanged, %d kept (seed/runtime), %d failed\n' "$checked" "$deployed" "$unchanged" "$kept" "$failed"
if (( mode_skipped > 0 )); then
  info "note: ${mode_skipped} file(s) on a filesystem without Unix permission bits (vfat/msdos/exfat) — permission is governed by the mount options; mode checks skipped"
fi
if (( failed > 0 )); then
  die "Stage 07 config: ${failed} file(s) failed"
fi

# --- 4) 部署后收尾（幂等；对应样本中"配置文件之外"的形态面） ---
# a) 用户目录：user-dirs.dirs 只是映射，目录本体要建（样本另有截图目录）。
for d in Desktop Documents Downloads Music Videos Public Projects Templates Pictures/Screenshots; do
  if [[ ! -d "$HOME/$d" ]]; then
    mkdir -p "$HOME/$d"
    info "created user dir: ~/${d}"
  fi
done

# b) locale：locale.gen / locale.conf 已随文件部署，重建 locale 归档使其对后续会话生效。
if have locale-gen; then
  as_root locale-gen >/dev/null || die "locale-gen failed"
  ok "locale archives regenerated"
fi

# c) 登录 shell：与样本/物理机一致（fish；/etc/shells 已随文件部署）。
if [[ -x /usr/bin/fish ]]; then
  if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "/usr/bin/fish" ]]; then
    as_root usermod -s /usr/bin/fish "$USER" || die "failed to set login shell to fish"
    ok "login shell set to /usr/bin/fish for ${USER}"
  fi
else
  warn "fish not installed — login shell left unchanged"
fi

# d) GRUB：/etc/default/grub 与主题已部署，重建菜单让主题生效（BIOS/UEFI 同一配置路径）。
# /boot 通常是 drwx------ root：普通用户 [[ -d /boot/grub ]] 恒为假，原先这条会被静默跳过，
# 于是 07/12 都报成功而主题从未生效。改用 root 探测，并在探测失败时明确告警。
if have grub-mkconfig; then
  if as_root test -d /boot/grub; then
    as_root grub-mkconfig -o /boot/grub/grub.cfg >/dev/null || die "grub-mkconfig failed"
    ok "GRUB menu regenerated (theme applied)"
  else
    warn "/boot/grub not found or not readable — GRUB menu NOT regenerated; the boot theme will not apply"
  fi
fi

# e) GSettings vendor override：/usr/share/glib-2.0/schemas/*.gschema.override 已随文件部署，
#    重编译 schema 归档让"系统默认值"生效（如 Mission Center 的外观默认值）。
#    需要该 schema 已安装（包由 03/06 步装入），否则跳过——不因一个可选程序中断安装。
if [[ -f /usr/share/glib-2.0/schemas/io.missioncenter.MissionCenter.gschema.xml ]]; then
  if have glib-compile-schemas; then
    as_root glib-compile-schemas /usr/share/glib-2.0/schemas || die "glib-compile-schemas failed"
    ok "GSettings schemas recompiled (vendor overrides applied)"
  else
    warn "glib-compile-schemas not available — gschema overrides not applied"
  fi
else
  warn "mission-center schema not installed — skipped GSettings override compile"
fi

# f) 登录背景的 ACL：11 步会加一次，但 install 覆盖会重建 inode、把 ACL 丢掉（改过壁纸后重跑 07 就会触发）。
#    这里再补一次，保证 rice-login-bg 下一次仍写得进去；沙箱演练跳过（不碰真实 /etc）。
if [[ -z "${AN_TARGET_ROOT:-}" && -e /etc/nwg-hello/background.png ]] && have setfacl; then
  if getfacl -p /etc/nwg-hello/background.png 2>/dev/null | grep -q "^user:${USER}:rw-"; then
    info "ACL already present: u:${USER}:rw on background.png"
  elif as_root setfacl -m "u:${USER}:rw" /etc/nwg-hello/background.png; then
    ok "ACL re-applied: u:${USER}:rw on background.png"
  else
    warn "failed to re-apply the ACL on /etc/nwg-hello/background.png — rice-login-bg will not be able to rewrite it"
  fi
fi

# g) 索引刷新：payload 带了三套字体和三个 .desktop，装完要重建缓存，否则首登可能落回默认字体、
#    yazi 也不出现在「打开方式」候选里（失败只 warn，不影响安装结果）。
if have fc-cache; then
  if as_root fc-cache -f >/dev/null 2>&1; then
    ok "font cache refreshed"
  else
    warn "fc-cache failed — the bundled fonts may not be picked up until the next login"
  fi
else
  warn "fc-cache not found — the bundled fonts may not be picked up until the next login"
fi
if have update-desktop-database; then
  if update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1; then
    ok "desktop database updated (~/.local/share/applications)"
  else
    warn "update-desktop-database failed — yazi may not show up in \"Open with\""
  fi
else
  warn "update-desktop-database not found — .desktop entries may not be picked up"
fi

ok "Stage 07 config: done"
