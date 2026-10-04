#!/usr/bin/env bash
# lib/plan.sh — 阶段计划的唯一来源（预览与实装共用同一份"将要发生什么"）。
# 输出保持确定性：无时间戳、无随机、顺序固定。
# shellcheck disable=SC1091

[[ -n "${_AN_PLAN_LOADED:-}" ]] && return 0
_AN_PLAN_LOADED=1

# 阶段表：id|name|一句话描述（渲染供预览；步骤脚本按 id 执行）
AN_STAGES=(
  "01|sources|verify/repair archlinuxcn keyring; multilib; mirrors health check"
  "02|system|first full system upgrade (pacman -Syu)"
  "03|packages|install official/archlinuxcn packages (manifests/packages.tsv)"
  "04|drivers|install hardware drivers from package list (physical only)"
  "05|aur|install AUR/foreign packages (manifests/aur.tsv, via paru)"
  "06|desktop|install niri + Noctalia desktop packages"
  "07|config|deploy dotfiles (payload -> target paths, per manifests/files.tsv)"
  "08|scripts|deploy scripts and create the ~/bin symlink layer"
  "09|noctalia|Noctalia settings + plugin source + cursor-track build + enable"
  "10|services|enable services (docker/bluetooth/snapper/scrub/rice-dnd...)"
  "11|greeter|greetd + nwg-hello + wallpaper/avatar/login background"
  "12|verify|post-install self check against manifests/files.tsv"
)

stage_ids() {
  local s
  for s in "${AN_STAGES[@]}"; do echo "${s%%|*}"; done
}

stage_name() { # $1=id
  local s
  for s in "${AN_STAGES[@]}"; do
    if [[ "${s%%|*}" == "$1" ]]; then
      echo "$s" | cut -d'|' -f2
      return 0
    fi
  done
  return 1
}

stage_desc() { # $1=id
  local s
  for s in "${AN_STAGES[@]}"; do
    if [[ "${s%%|*}" == "$1" ]]; then
      echo "$s" | cut -d'|' -f3
      return 0
    fi
  done
  return 1
}

# 渲染完整计划。（$1=mode preview|run；$2=machine；$3=virt；$4=user）
# 注意：只读操作——不得创建/修改任何文件（预览的验收要求）。
render_plan() {
  local mode="$1" machine="$2" virt="$3" user="$4"
  local id name desc payload_count

  printf '== arch-noctalia installer ==\n'
  printf 'mode:    %s\n' "$mode"
  printf 'machine: %s (systemd-detect-virt=%s)\n' "$machine" "$virt"
  printf 'user:    %s\n' "$user"
  printf 'repo:    %s\n' "$AN_ROOT_DIR"
  printf '\nstages (%d):\n' "${#AN_STAGES[@]}"
  for id in $(stage_ids); do
    name="$(stage_name "$id")"
    desc="$(stage_desc "$id")"
    printf '  [%s] %-9s %s\n' "$id" "$name" "$desc"
  done

  payload_count="$(find "$AN_ROOT_DIR/payload" -type f ! -name '.gitkeep' 2>/dev/null | wc -l | tr -d ' ')"
  printf '\nmanifests:\n'
  printf '  packages.tsv: %s rows\n' "$(count_rows "$AN_ROOT_DIR/manifests/packages.tsv")"
  printf '  aur.tsv:      %s rows\n' "$(count_rows "$AN_ROOT_DIR/manifests/aur.tsv")"
  printf '  files.tsv:    %s rows\n' "$(count_rows "$AN_ROOT_DIR/manifests/files.tsv")"
  printf '  excluded.tsv: %s rows\n' "$(count_rows "$AN_ROOT_DIR/manifests/excluded.tsv")"
  printf 'payload files:  %s\n' "$payload_count"

  if [[ "$mode" == "preview" ]]; then
    printf '\npreview OK — nothing was changed.\n'
  fi
}
