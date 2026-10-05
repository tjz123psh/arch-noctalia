#!/usr/bin/env bash
# lib/mirrors.sh — archlinuxcn 镜像工具：解析 / 实探 / 降级排序 / 就地改写。
# 说明：纯函数、不依赖 lib/common.sh（可单独测试）；"降级链" = 快的排前、不通的沉底，
#       配合 pacman 逐文件按 Server 顺序取用的原生行为（前不行，后顶上）。

# 解析 [archlinuxcn] 段的 Server URL（按出现顺序）。
cn_servers_in_conf() {
  awk '
    /^[[:space:]]*\[archlinuxcn\][[:space:]]*$/ { f=1; next }
    f && /^[[:space:]]*\[/ { f=0 }
    f && /^[[:space:]]*Server[[:space:]]*=/ {
      sub(/^[[:space:]]*Server[[:space:]]*=[[:space:]]*/, "")
      sub(/[[:space:]]*$/, "")
      print
    }
  ' "$1"
}

# 从 URL 提取主机名（日志用）。
cn_host() {
  local h="${1#*://}"
  printf '%s' "${h%%/*}"
}

# 并行实探各镜像（stdin = URL，每行一条）：输出 "速度B/s 序号 URL"；失败/超时 = 0。
# 指标 = 限时 8s 抓 archlinuxcn.files 前 16MB 的吞吐：能识破"瞬间快、持续慢"的镜像
# （8s 内抓不完 16MB ≈ 持续 <2MB/s，直接沉底；实测 aliyun 就属这类：起步 16~26MB/s、持续仅 ~2MB/s）。
cn_probe_servers() {
  local tmp s probe t idx=0
  tmp="$(mktemp)"
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    idx=$((idx + 1))
    probe="${s/\$arch/x86_64}/archlinuxcn.files"
    (
      t="$(curl -fsS -o /dev/null --connect-timeout 3 --max-time 8 --range 0-16777215 \
            -w '%{speed_download}' "$probe" 2>/dev/null)" || t=""
      printf '%s %s %s\n' "${t:-0}" "$idx" "$s"
    ) >> "$tmp" &
  done
  wait || true
  cat "$tmp"
  rm -f "$tmp"
}

# stdin = "速度 序号 URL" 行 → 输出排序后的 URL（快→慢；同分按原序；不通的最后）。
cn_order_servers() {
  sort -s -k1,1gr -k2,2n | awk 'NF >= 3 { print $3 }'
}

# 就地改写：$1 = conf 路径；stdin = 新的 Server URL 列表。输出改写后的整个 conf。
# 仅替换 [archlinuxcn] 段内的 Server 行（SigLevel 等其它行保留）；找不到段则原样输出。
cn_rewrite_conf() {
  local conf="$1" line in_cn=0 u
  local -a new_servers=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && new_servers+=("$line")
  done
  while IFS= read -r line; do
    if (( in_cn == 0 )) && [[ "$line" =~ ^[[:space:]]*\[archlinuxcn\][[:space:]]*$ ]]; then
      in_cn=1
      printf '%s\n' "$line"
      for u in "${new_servers[@]}"; do
        printf 'Server = %s\n' "$u"
      done
      continue
    fi
    if (( in_cn == 1 )); then
      if [[ "$line" =~ ^[[:space:]]*\[ ]]; then
        in_cn=0
      elif [[ "$line" =~ ^[[:space:]]*Server[[:space:]]*= ]]; then
        continue
      fi
    fi
    printf '%s\n' "$line"
  done < "$conf"
}

# 整段替换：$1 = conf 路径；stdin = 新块（含段头行）。[archlinuxcn] 段（段头到下一个 [ 之前）
# 整体替换为新块；无该段则追加到文件尾。用于安装器写入标准块（用户 2026-10-05 确认可覆盖）。
# 区别：cn_rewrite_conf 只改 Server 行、保留其它行（用于按实测重排）；本函数连其它行一起换掉。
cn_replace_section() {
  local conf="$1" line found=0 in_cn=0
  local -a block=()
  while IFS= read -r line; do
    block+=("$line")
  done
  while IFS= read -r line; do
    if (( in_cn == 0 )) && [[ "$line" =~ ^[[:space:]]*\[archlinuxcn\][[:space:]]*$ ]]; then
      in_cn=1
      found=1
      printf '%s\n' "${block[@]}"
      continue
    fi
    if (( in_cn == 1 )); then
      if [[ "$line" =~ ^[[:space:]]*\[ ]]; then
        in_cn=0
      else
        continue
      fi
    fi
    printf '%s\n' "$line"
  done < "$conf"
  if (( found == 0 )); then
    printf '\n%s\n' "${block[@]}"
  fi
}
