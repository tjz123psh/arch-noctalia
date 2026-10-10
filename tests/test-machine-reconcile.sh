#!/usr/bin/env bash
# tests/test-machine-reconcile.sh — 「本机现状 vs 清单」对账（只读，不需要 root）。
# 这台物理机就是采集样本机，所以清单里的 target 可以直接和磁盘对账；这是唯一能抓
# 「target_path 列写错 / 清单过期 / 内容漂移」的测试。
#
# 语义（刻意区分「结构性错误」与「用户自己的编辑」）：
#   * 目标缺失、目标不是绝对路径  → 失败（结构性错误）；
#   * 内容与清单 md5 不一致        → 默认只报告（用户改过自己的配置是正常的），
#                                   加 AN_RECONCILE_STRICT=1 才判失败（当门禁用）。
#   * seed 行只核对存在性（内容本来就可能被用户编辑）；
#   * 豁免：/boot/*（ESP 未挂载时）、由 hook/ACL 管理的 /etc/nwg-hello/background.png。
# 默认只在样本机（当前用户 == 清单里的目标用户）运行；其它机器打印 [skip] 通过，
# 需要强制跑时用 AN_RECONCILE=1。
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_USER="pang"   # 与 install.sh 的 AN_TARGET_USER 一致
strict="${AN_RECONCILE_STRICT:-0}"

if [[ "$(id -un)" != "$TARGET_USER" && "${AN_RECONCILE:-0}" != 1 ]]; then
  echo "[skip] not the sample machine (user $(id -un) != ${TARGET_USER}); set AN_RECONCILE=1 to force"
  exit 0
fi

declare -A SEED=()
while IFS=$'\t' read -r p _n; do
  if [[ -z "$p" || "$p" == "#"* ]]; then continue; fi
  SEED["$p"]=1
done < <(grep -vE '^[[:space:]]*(#|$)' "$ROOT_DIR/manifests/seed.tsv")

exempt() { # $1=target → 0=豁免（不计入对账）
  case "$1" in
    /etc/nwg-hello/background.png) return 0 ;;   # 壁纸同步 hook 通过 ACL 持续改写（守卫见 11-greeter.sh）
    /boot/*) [[ -d /boot/grub ]] || return 0 ;;  # ESP 未挂载时 /boot 内容不在场
  esac
  return 1
}

errs="$(mktemp)"; notes="$(mktemp)"
trap 'rm -f "$errs" "$notes"' EXIT
ok=0; drifted=0; missing=0; skipped=0; unreadable=0; mode_drift=0
while IFS=$'\t' read -r rp tp mode md5; do
  if [[ -z "$rp" || "$rp" == "#"* ]]; then continue; fi
  if exempt "$tp"; then skipped=$((skipped + 1)); continue; fi
  if [[ "$tp" != /* ]]; then printf 'not an absolute target: %s\n' "$tp" >> "$errs"; continue; fi
  if [[ ! -e "$tp" ]]; then printf 'missing target: %s\n' "$tp" >> "$errs"; missing=$((missing + 1)); continue; fi
  if [[ -n "${SEED[$rp]:-}" ]]; then ok=$((ok + 1)); continue; fi
  cur="$(md5sum -- "$tp" 2>/dev/null | awk '{print $1}')"
  if [[ -z "$cur" ]]; then unreadable=$((unreadable + 1)); printf 'unreadable (skipped): %s\n' "$tp" >> "$notes"; continue; fi
  if [[ "$cur" == "$md5" ]]; then
    ok=$((ok + 1))
  else
    drifted=$((drifted + 1))
    printf 'content differs from the manifest: %s\n' "$tp" >> "$notes"
  fi
  am="$(stat -c '%a' -- "$tp" 2>/dev/null || true)"
  if [[ -n "$am" && "$am" != "$mode" ]]; then
    mode_drift=$((mode_drift + 1))
    printf 'mode differs from the manifest (disk %s, manifest %s): %s\n' "$am" "$mode" "$tp" >> "$notes"
  fi
done < <(grep -vE '^[[:space:]]*(#|$)' "$ROOT_DIR/manifests/files.tsv")

printf '[info]  reconcile: %d ok, %d content-drift, %d mode-drift, %d missing, %d exempt, %d unreadable\n' \
  "$ok" "$drifted" "$mode_drift" "$missing" "$skipped" "$unreadable"
if [[ -s "$notes" ]]; then
  printf '%s\n' '--- 只报告（用户自己的编辑属正常；AN_RECONCILE_STRICT=1 时才算失败）---'
  head -20 "$notes"
fi

rc=0
if [[ -s "$errs" ]]; then
  printf '%s\n' '--- 结构性错误（目标缺失/非绝对路径）---'
  head -20 "$errs"
  rc=1
fi
if [[ "$strict" == 1 && "$drifted" -gt 0 ]]; then
  echo "reconcile: $drifted file(s) drift from the manifest (strict mode)"
  rc=1
fi
(( rc == 0 )) || { echo "test-machine-reconcile: FAIL"; exit 1; }
echo "ok: machine vs manifests reconciled (structure ok; content drift is reported, not gated by default)"
