#!/usr/bin/env bash
# lib/common.sh — 公共工具：输出、守卫、确认、清单读取辅助。
# 说明：输出刻意保持英文与确定性（无时间戳、无随机），保证裸 TTY 可读、预览输出可复现。
# shellcheck disable=SC1091

[[ -n "${_AN_COMMON_LOADED:-}" ]] && return 0
_AN_COMMON_LOADED=1

AN_ROOT_DIR="${AN_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck disable=SC2034  # AN_STATE_DIR 供 install.sh（source 本文件）使用
AN_STATE_DIR="${AN_ROOT_DIR}/.state"

# --- 输出 ---
info()  { printf '[info]  %s\n' "$*"; }
warn()  { printf '[warn]  %s\n' "$*" >&2; }
error() { printf '[error] %s\n' "$*" >&2; }
ok()    { printf '[ok]    %s\n' "$*"; }
die()   { error "$@"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# --- root 操作（目标机已按 §9.1 装好 sudo） ---
as_root() { sudo "$@"; }

# --- 确认（--yes / AN_ASSUME_YES=1 时自动通过） ---
confirm() {
  local prompt="$1"
  if [[ "${AN_ASSUME_YES:-0}" == "1" ]]; then
    info "auto-confirmed: ${prompt}"
    return 0
  fi
  local reply=""
  read -r -p "${prompt} [y/N] " reply </dev/tty 2>/dev/null || return 1
  [[ "${reply}" =~ ^[Yy]$ ]]
}

# --- 步骤守卫：步骤脚本只允许经 install.sh 运行（防手滑直跑） ---
require_orchestrator() {
  if [[ "${AN_RUN:-0}" != "1" ]]; then
    error "This step must run via install.sh (safety guard)."
    error "Standalone execution requires: AN_RUN=1"
    exit 64
  fi
}

# --- 清单读取：去掉注释与空行 ---
manifest_rows() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  grep -vE '^[[:space:]]*(#|$)' "$f" || true
}

# --- 清单数据行计数（用于预览输出；确定性） ---
count_rows() {
  local f="$1"
  if [[ -f "$f" ]]; then
    manifest_rows "$f" | wc -l | tr -d ' '
  else
    echo 0
  fi
}

# --- 部署校验：目标属性读取（普通用户 → root 回退） ---
# 系统文件（$HOME 之外）归 root：普通用户读不到时用 root 重试一次。
# 场景：ESP 以 fmask/dmask=0077 挂载时 /boot 对普通用户不可进入（见 README 要点）。
# 用法：t_type FILE（-L 跟随软链的文件类型）/ t_perms FILE（权限位）/ t_md5 FILE（内容 md5）。
_target_probe() { # $1=type|perms|md5  $2=target
  local kind="$1" t="$2" asroot=0 out=""
  while :; do
    case "$kind" in
      type)
        # %F 输出是本地化文本（zh_CN 下为"普通文件"）——强制 C locale，纯用户侧/root 侧一致。
        # root 侧用 env 显式传 LC_ALL，不依赖 sudo 的 env_keep 配置。
        if (( asroot == 0 )); then
          out="$(LC_ALL=C stat -L -c '%F' -- "$t" 2>/dev/null)"
        else
          out="$(as_root env LC_ALL=C stat -L -c '%F' -- "$t" 2>/dev/null)"
        fi
        # coreutils 把空文件报为 "regular empty file"——归一为 "regular file"（调用方只关心是否常规文件）。
        if [[ "$out" == "regular empty file" ]]; then
          out="regular file"
        fi
        ;;
      perms)
        if (( asroot == 0 )); then
          out="$(stat -c '%a' -- "$t" 2>/dev/null)"
        else
          out="$(as_root stat -c '%a' -- "$t" 2>/dev/null)"
        fi
        ;;
      md5)
        if (( asroot == 0 )); then
          out="$(md5sum -- "$t" 2>/dev/null | awk '{print $1}')"
        else
          out="$(as_root md5sum -- "$t" 2>/dev/null | awk '{print $1}')"
        fi
        ;;
    esac
    if [[ -n "$out" ]]; then
      break
    fi
    if (( asroot == 1 )); then
      break
    fi
    if [[ "$t" == "${HOME}"/* ]]; then
      break
    fi
    asroot=1
  done
  printf '%s' "$out"
}
t_type()  { _target_probe type "$1"; }
t_perms() { _target_probe perms "$1"; }
t_md5()   { _target_probe md5 "$1"; }

# 目标所在文件系统的类型（沿路径向上找到第一个对当前用户可见的位置）。
fs_of_target() {
  local p="$1"
  while [[ ! -e "$p" && "$p" != "/" ]]; do
    p="$(dirname -- "$p")"
  done
  stat -f -c '%T' -- "$p" 2>/dev/null || printf ''
}

# FAT 系文件系统没有 Unix 权限位——权限由挂载选项（fmask/dmask）统一决定，不能逐文件校验/设置。
fs_has_unix_perms() { # $1=fs type（如 vfat/exfat/btrfs）
  case "${1:-}" in
    vfat|msdos|exfat) return 1 ;;
    *) return 0 ;;
  esac
}

# --- seed 清单（个人数据种子：只在缺失时初始化，绝不覆盖已有内容；见 manifests/seed.tsv） ---
# shellcheck disable=SC2034  # AN_SEED 供 source 本文件的步骤脚本消费；此处只负责填充
load_seed_targets() { # 填充全局关联数组 AN_SEED[]（键 = files.tsv 的 repo 路径列）
  declare -gA AN_SEED=()
  local p _note
  [[ -f "${AN_ROOT_DIR}/manifests/seed.tsv" ]] || return 0
  while IFS=$'\t' read -r p _note; do
    if [[ -z "$p" || "$p" == "#"* ]]; then
      continue
    fi
    AN_SEED["$p"]=1
  done < "${AN_ROOT_DIR}/manifests/seed.tsv"
}
