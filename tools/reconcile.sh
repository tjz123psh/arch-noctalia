#!/usr/bin/env bash
# tools/reconcile.sh — 生成并核对包清单（对照 VM 现况）：
#   manifests/packages.tsv  官方/archlinuxcn 显式包（pacman -Qen）
#   manifests/aur.tsv       外来/AUR 包（pacman -Qm，含依赖）
# 对账：
#   - 全部"显式安装"包 ∈ packages.tsv ∪ aur.tsv ∪ excluded.tsv(kind=package) → 0 未解释
#   - 全部外来包     ∈ aur.tsv ∪ excluded.tsv(kind=package)                → 0 遗漏
# 只读 VM；幂等（重跑 = 按 VM 现况重新生成 + 核对）。
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034  # 由 lib/common.sh（source 时）消费
AN_ROOT_DIR="$ROOT_DIR"
# shellcheck disable=SC1091  # 相对 source；lib 在各检查中以独立目标校验
source "${ROOT_DIR}/lib/common.sh"

VM="${AN_VM_SSH:-vm}"
PACKAGES_TSV="${ROOT_DIR}/manifests/packages.tsv"
AUR_TSV="${ROOT_DIR}/manifests/aur.tsv"
EXCLUDED_TSV="${ROOT_DIR}/manifests/excluded.tsv"

ssh -o BatchMode=yes -o ConnectTimeout=6 "$VM" true 2>/dev/null || die "ssh ${VM} unreachable"

# --- 模块归类（唯一来源；新增包在此登记） ---
classify() {
  case "$1" in
    nvidia-*|lib32-nvidia-*|libva-nvidia-driver|mesa|lib32-mesa|vulkan-radeon|lib32-vulkan-radeon|vulkan-tools|mesa-utils|amd-ucode|linux-firmware|linux-firmware-*|dkms|asusctl|supergfxctl|rog-control-center)
      echo "drivers" ;;
    sof-firmware|alsa-firmware|alsa-ucm-conf)
      echo "audio" ;;
    niri|xwayland-satellite|noctalia|fuzzel|kitty|greetd|nwg-hello|xdg-desktop-portal|xdg-desktop-portal-*|fcitx5|fcitx5-*)
      echo "desktop" ;;
    open-vm-tools)
      echo "vmware-guest" ;;
    *)
      echo "" ;;
  esac
}

# pacman -Si 输出（空行分块）→ "^name<TAB>repo$" 行。
# 注意：-Si 里 Repository 出现在 Name 之前，必须按块配对（不能用流式记忆变量）。
parse_si() {
  awk -v RS='' -F'\n' '
    {
      name=""; repo="";
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^Name[ ]*:/)       { name = $i; sub(/^Name[ ]*:[ ]*/, "", name) }
        if ($i ~ /^Repository[ ]*:/) { repo = $i; sub(/^Repository[ ]*:[ ]*/, "", repo) }
      }
      if (name != "") printf "%s\t%s\n", name, repo
    }'
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

info "fetching live package state from ${VM} ..."
ssh "$VM" pacman -Qen > "$tmpdir/native-explicit.txt"
ssh "$VM" pacman -Qem > "$tmpdir/foreign-explicit.txt"
ssh "$VM" pacman -Qm  > "$tmpdir/foreign-all.txt"

mapfile -t nats < <(awk 'NF{print $1}' "$tmpdir/native-explicit.txt")
mapfile -t fall < <(awk 'NF{print $1}' "$tmpdir/foreign-all.txt")
(( ${#nats[@]} > 0 )) || die "no native explicit packages returned by the VM"

# repo 列：pacman -Qi 不含仓库名 —— 用 pacman -Si 的 Repository 字段（同步库视角）
declare -A repo_of=()
qsi="$(ssh "$VM" env LC_ALL=C pacman -Si -- "${nats[@]}" 2>/dev/null || true)"
while IFS=$'\t' read -r name repo; do
  if [[ -n "$name" ]]; then repo_of["$name"]="$repo"; fi
done < <(printf '%s\n' "$qsi" | parse_si)

# --- packages.tsv ---
{
  echo "# schema=1"
  echo "# package<TAB>repo<TAB>module<TAB>purpose"
  echo "# 由 tools/reconcile.sh 按 VM 现况生成；module 归类见该脚本 classify()"
  for pkg in "${nats[@]}"; do
    printf '%s\t%s\t%s\t\n' "$pkg" "${repo_of[$pkg]:-unknown}" "$(classify "$pkg")"
  done
} > "$PACKAGES_TSV"

# --- aur.tsv（外来：显式 + 依赖；channel 优先同步库二进制） ---
declare -A foreign_explicit=()
while read -r p _v; do
  if [[ -n "$p" ]]; then foreign_explicit["$p"]=1; fi
done < "$tmpdir/foreign-explicit.txt"

declare -A sync_of=()
if (( ${#fall[@]} > 0 )); then
  sinfo="$(ssh "$VM" env LC_ALL=C pacman -Si -- "${fall[@]}" 2>/dev/null || true)"
  while IFS=$'\t' read -r name repo; do
    if [[ -n "$name" ]]; then sync_of["$name"]="$repo"; fi
  done < <(printf '%s\n' "$sinfo" | parse_si)
fi

{
  echo "# schema=1"
  echo "# package<TAB>channel<TAB>role<TAB>purpose"
  echo "# channel: 同步库名（如 archlinuxcn）=有二进制、优先 pacman 装；aur=需 AUR 构建（paru）"
  echo "# role: explicit | dependency"
  for pkg in "${fall[@]}"; do
    role="dependency"
    if [[ -n "${foreign_explicit[$pkg]:-}" ]]; then role="explicit"; fi
    printf '%s\t%s\t%s\t\n' "$pkg" "${sync_of[$pkg]:-aur}" "$role"
  done
} > "$AUR_TSV"

# --- 对账 ---
declare -A pkg_excluded=()
if [[ -f "$EXCLUDED_TSV" ]]; then
  while IFS=$'\t' read -r kind item _reason; do
    if [[ "$kind" == "package" && -n "$item" ]]; then pkg_excluded["$item"]=1; fi
  done < <(manifest_rows "$EXCLUDED_TSV")
fi

declare -A in_pkg=() in_aur=()
while IFS=$'\t' read -r p _1 _2 _3; do
  if [[ -n "$p" ]]; then in_pkg["$p"]=1; fi
done < <(manifest_rows "$PACKAGES_TSV")
while IFS=$'\t' read -r p _1 _2 _3; do
  if [[ -n "$p" ]]; then in_aur["$p"]=1; fi
done < <(manifest_rows "$AUR_TSV")

unexplained=0
missing=0
while read -r p _v; do
  if [[ -z "$p" ]]; then continue; fi
  if [[ -z "${in_pkg[$p]:-}${in_aur[$p]:-}${pkg_excluded[$p]:-}" ]]; then
    printf '[unexplained] %s\n' "$p"
    unexplained=$((unexplained + 1))
  fi
done < "$tmpdir/native-explicit.txt"
while read -r p _v; do
  if [[ -z "$p" ]]; then continue; fi
  if [[ -z "${in_aur[$p]:-}${pkg_excluded[$p]:-}" ]]; then
    printf '[missing-from-aur] %s\n' "$p"
    missing=$((missing + 1))
  fi
done < "$tmpdir/foreign-all.txt"

native_n=${#nats[@]}
fall_n=${#fall[@]}
exp_foreign=$(grep -c . "$tmpdir/foreign-explicit.txt" || true)
pkg_rows=$(manifest_rows "$PACKAGES_TSV" | wc -l | tr -d ' ')
aur_rows=$(manifest_rows "$AUR_TSV" | wc -l | tr -d ' ')

printf '\n===== reconcile summary =====\n'
printf 'vm native explicit (-Qen):  %s\n' "$native_n"
printf 'vm foreign explicit (-Qem): %s\n' "$exp_foreign"
printf 'vm foreign all (-Qm):       %s\n' "$fall_n"
printf 'packages.tsv rows:          %s\n' "$pkg_rows"
printf 'aur.tsv rows:               %s\n' "$aur_rows"
printf 'unexplained explicit:       %s\n' "$unexplained"
printf 'foreign missing from aur:   %s\n' "$missing"

if (( unexplained > 0 || missing > 0 )); then
  error "reconcile: FAIL"
  exit 1
fi
ok "reconcile: 0 unexplained, 0 missing"
