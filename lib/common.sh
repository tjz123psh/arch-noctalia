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
