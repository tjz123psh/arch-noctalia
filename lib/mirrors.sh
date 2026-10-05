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
# 指标 = 吞吐量：限时 10s 抓 archlinuxcn.files 前 2MB（range），比"小文件响应时间"更能反映
# 真实装包体验（曾见某镜像小文件 0.08s 但大文件只有 2MB/s，会触发 pacman "too slow"）。
cn_probe_servers() {
  local tmp s probe t idx=0
  tmp="$(mktemp)"
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    idx=$((idx + 1))
    probe="${s/\$arch/x86_64}/archlinuxcn.files"
    (
      t="$(curl -fsS -o /dev/null --connect-timeout 3 --max-time 10 --range 0-2097151 \
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
