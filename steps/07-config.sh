#!/usr/bin/env bash
# steps/07-config.sh — Stage 07: 部署配置与资产（dotfiles / 字体 / greeter 等）。
# 按 manifests/files.tsv（repo_path<TAB>target_path<TAB>mode<TAB>md5）逐行部署：
#   1) 预检：payload 文件存在且 md5 与清单一致，否则 die（仓库拷贝不完整）；
#   2) 部署：install -D -m <mode> —— $HOME 内用当前用户，其余（/etc、/usr/share、/var/lib）走 sudo；
#   3) 每行部署后立即复核 md5（+ 权限位）；不一致 → warn + 计数，继续后续行，不中断；
#   4) 幂等：常规文件且 md5（+ 权限位）一致 → 跳过（unchanged）；
#   5) seed（manifests/seed.tsv，个人数据种子如便签/模板）：已存在一律保持现状，只在缺失时初始化；
#   6) 覆盖"内容不同"的文件前，先把旧内容备份到 .state/overwritten/<时间戳>/；
#   7) 两种环境适配（不改挂载设置）：FAT 系（vfat/exfat，如 ESP）没有 Unix 权限位——权限由挂载选项
#      决定，这类文件系统跳过权限位校验；系统文件普通用户读不到时，校验改用 root 读；
#   8) 部署后收尾：建标准用户目录、locale-gen、登录 shell（fish）、GRUB 菜单重建。
set -Eeuo pipefail
AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "${AN_ROOT_DIR}/lib/common.sh"

require_orchestrator

MANIFEST="${AN_ROOT_DIR}/manifests/files.tsv"
[[ -f "$MANIFEST" ]] || die "missing manifest: ${MANIFEST}"

md5_of() { local f="$1"; md5sum "$f" 2>/dev/null | awk '{print $1}'; }

# --- 1) 预检：payload 完整性（存在 + md5） ---
rows=0
payload_bad=0
while IFS=$'\t' read -r repo_path _target _mode md5; do
  if [[ -z "$repo_path" || "$repo_path" == "#"* ]]; then
    continue
  fi
  rows=$((rows + 1))
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
info "Stage 07 config: ${rows} files to deploy; payload verified"

# --- 2) 部署 + 3) 逐行复核 ---
load_seed_targets

# 覆盖前备份：把将被覆盖文件的旧内容存到 ${AN_STATE_DIR}/overwritten/<时间戳>/（用户可读、可恢复）。
# 尽力而为：备份失败只 warn，不中断部署（会留下明确日志）。
RUN_TS=""
backup_overwritten() { # $1=target  $2=ftype
  local t="$1" ftype="$2" rel base
  [[ "$ftype" == "regular file" ]] || return 0
  [[ -n "$RUN_TS" ]] || RUN_TS="$(date +%Y%m%d-%H%M%S)"
  rel="${t#/}"
  base="${AN_STATE_DIR}/overwritten/${RUN_TS}/${rel}"
  if ! mkdir -p -- "$(dirname -- "$base")"; then
    warn "backup dir not writable: $(dirname -- "$base")"
    return 0
  fi
  if [[ "$t" == "$HOME"/* ]]; then
    if ! cp -- "$t" "$base" 2>/dev/null; then
      warn "backup failed: ${t}"
      return 0
    fi
  else
    # 系统文件由 root 读、重定向由当前用户执行（备份文件归用户所有，可自行恢复）。
    if ! as_root cat -- "$t" > "$base" 2>/dev/null; then
      rm -f -- "$base"
      warn "backup failed: ${t}"
      return 0
    fi
  fi
  info "backed up: ${t} -> ${base}"
}

checked=0
deployed=0
unchanged=0
kept=0
failed=0
mode_skipped=0
while IFS=$'\t' read -r repo_path target mode md5; do
  if [[ -z "$repo_path" || "$repo_path" == "#"* ]]; then
    continue
  fi
  checked=$((checked + 1))
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

  # 幂等跳过：常规文件（非软链）且内容一致；支持权限位的文件系统上还要求权限位一致。
  if [[ "$ftype" == "regular file" && ! -L "$target" && -n "$actual_md5" && "$actual_md5" == "$md5" ]]; then
    if (( mode_enforced == 0 )) || [[ "$(t_perms "$target")" == "$mode" ]]; then
      unchanged=$((unchanged + 1))
      continue
    fi
  fi

  if (( exists == 1 )); then
    if [[ "$actual_md5" == "$md5" ]]; then
      info "re-installing (mode or type differs): ${target}"
    else
      info "overwriting changed file: ${target}"
      backup_overwritten "$target" "$ftype"
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

printf '[info]  files: %d checked, %d deployed, %d unchanged, %d kept (seed), %d failed\n' "$checked" "$deployed" "$unchanged" "$kept" "$failed"
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
if have grub-mkconfig && [[ -d /boot/grub ]]; then
  as_root grub-mkconfig -o /boot/grub/grub.cfg >/dev/null || die "grub-mkconfig failed"
  ok "GRUB menu regenerated (theme applied)"
fi

ok "Stage 07 config: done"
