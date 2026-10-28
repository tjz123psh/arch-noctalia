#!/usr/bin/env bash
# tests/test-manifest-schema.sh — 七份清单的「形状与规模」回归（只读、无副作用）。
# 目的：清单是安装器的唯一事实来源，形状错了（列错位、TAB 变空格、md5 截断、目标路径写歪）
# 在部署前就该红。这里逐列做格式校验，并对规模做**精确锁定**：
#   规模数字 = 刻意加的锁。清单增减条目时必须同步改这里（防止「删一行 + 删文件」式的静默缩表）。
# 校验项：列数 / 每列正则 / 唯一性 / 目标路径在白名单前缀内 / seed ⊆ files / 各类枚举值域。
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
M="$ROOT_DIR/manifests"
errs="$(mktemp)"
trap 'rm -f "$errs"' EXIT
note() { printf '%s\n' "$*" >> "$errs"; }
data() { grep -vE '^[[:space:]]*(#|$)' "$1"; }
cnt() { data "$1" | wc -l | tr -d ' '; }

# --- 规模锁 ---
count_lock() { # $1=file $2=expected $3=label
  local n; n="$(cnt "$1")"
  [[ "$n" == "$2" ]] || note "$3 row count: $n (locked at $2) — intentional changes must update this test"
}
count_lock "$M/files.tsv" 538 "files.tsv"
count_lock "$M/packages.tsv" 176 "packages.tsv"
count_lock "$M/aur.tsv" 17 "aur.tsv"
count_lock "$M/bin-links.tsv" 19 "bin-links.tsv"
count_lock "$M/seed.tsv" 34 "seed.tsv"
count_lock "$M/excluded.tsv" 154 "excluded.tsv"
count_lock "$M/runtime-regenerated.tsv" 26 "runtime-regenerated.tsv"

# --- 末行换行：所有步骤都用 while read 逐行读清单，末行没换行会静默漏掉最后一条 ---
for f in "$M"/*.tsv; do
  [[ -s "$f" ]] || continue
  if [[ -n "$(tail -c 1 -- "$f")" ]]; then
    note "missing trailing newline: $(basename "$f")"
  fi
done

# --- 通用逐列规则 ---
nf_rule() { # $1=file $2=fields $3=label
  awk -F'\t' -v n="$2" -v lab="$3" '!/^[[:space:]]*#/ && NF && NF != n { printf "%s: line %d has %d fields (want %d)\n", lab, NR, NF, n }' "$1" >> "$errs"
}
col_rule() { # $1=file $2=col $3=regex $4=label
  awk -F'\t' -v c="$2" -v re="$3" -v lab="$4" '!/^[[:space:]]*#/ && NF && $c !~ re { printf "%s: line %d col %d = [%s]\n", lab, NR, c, $c }' "$1" >> "$errs"
}
uniq_rule() { # $1=file $2=col $3=label
  awk -F'\t' -v c="$2" -v lab="$3" '!/^[[:space:]]*#/ && NF { n[$c]++; line[$c]=NR } END { for (k in n) if (n[k] > 1) printf "%s: duplicate value [%s] (%d times)\n", lab, k, n[k] }' "$1" >> "$errs"
}

# --- files.tsv ---
nf_rule "$M/files.tsv" 4 "files.tsv"
col_rule "$M/files.tsv" 1 '^payload/' "files.tsv col1 must be a repo-relative payload path"
col_rule "$M/files.tsv" 2 '^/(home|etc|usr/share|usr/local|var/lib|var/cache|boot|opt)/' "files.tsv col2 must be under an allowed top-level dir"
col_rule "$M/files.tsv" 3 '^[0-7]{3,4}$' "files.tsv col3 must be an octal mode"
col_rule "$M/files.tsv" 4 '^[0-9a-f]{32}$' "files.tsv col4 must be an md5"
uniq_rule "$M/files.tsv" 1 "files.tsv col1"
uniq_rule "$M/files.tsv" 2 "files.tsv col2"

# --- packages.tsv ---
nf_rule "$M/packages.tsv" 4 "packages.tsv"
col_rule "$M/packages.tsv" 1 '^[a-z0-9@._+-]+$' "packages.tsv col1 must be a package name"
col_rule "$M/packages.tsv" 2 '^(core|extra|multilib|archlinuxcn)$' "packages.tsv col2 must be a known repo"
col_rule "$M/packages.tsv" 3 '^(|drivers|desktop|audio|vmware-guest)$' "packages.tsv col3 must be a known module"
uniq_rule "$M/packages.tsv" 1 "packages.tsv col1"

# --- aur.tsv ---
nf_rule "$M/aur.tsv" 4 "aur.tsv"
col_rule "$M/aur.tsv" 1 '^[a-z0-9@._+-]+$' "aur.tsv col1 must be a package name"
col_rule "$M/aur.tsv" 2 '^(aur|archlinuxcn)$' "aur.tsv col2 must be a known channel"
col_rule "$M/aur.tsv" 3 '^(explicit|dependency)$' "aur.tsv col3 must be explicit|dependency"
uniq_rule "$M/aur.tsv" 1 "aur.tsv col1"

# --- bin-links.tsv ---
nf_rule "$M/bin-links.tsv" 2 "bin-links.tsv"
col_rule "$M/bin-links.tsv" 1 '^[A-Za-z0-9._+-]+$' "bin-links.tsv col1 must be a link name"
col_rule "$M/bin-links.tsv" 2 '^[^/]' "bin-links.tsv col2 must be relative to \$HOME"
uniq_rule "$M/bin-links.tsv" 1 "bin-links.tsv col1"

# --- seed.tsv：每一行都必须是 files.tsv 第 1 列里存在的 repo 路径 ---
nf_rule "$M/seed.tsv" 2 "seed.tsv"
awk -F'\t' 'NR == FNR { if ($1 !~ /^[[:space:]]*#/ && NF) have[$1] = 1; next }
           !/^[[:space:]]*#/ && NF && !($1 in have) { printf "seed.tsv: line %d path not in files.tsv: [%s]\n", FNR, $1 }' \
  "$M/files.tsv" "$M/seed.tsv" >> "$errs"
uniq_rule "$M/seed.tsv" 1 "seed.tsv col1"

# --- runtime-regenerated.tsv：2 列，且每行必须引用 files.tsv 里存在的 repo 路径 ---
nf_rule "$M/runtime-regenerated.tsv" 2 "runtime-regenerated.tsv"
awk -F'\t' 'NR == FNR { if ($1 !~ /^[[:space:]]*#/ && NF) have[$1] = 1; next }
           !/^[[:space:]]*#/ && NF && !($1 in have) { printf "runtime-regenerated.tsv: line %d path not in files.tsv: [%s]\n", FNR, $1 }' \
  "$M/files.tsv" "$M/runtime-regenerated.tsv" >> "$errs"
uniq_rule "$M/runtime-regenerated.tsv" 1 "runtime-regenerated.tsv col1"

# --- excluded.tsv ---
nf_rule "$M/excluded.tsv" 3 "excluded.tsv"
col_rule "$M/excluded.tsv" 1 '^(dir|file|package|pattern)$' "excluded.tsv col1 must be dir|file|package|pattern"

# --- terminal-tools 的 Git 键表：07 步与工具本体各存一份，两处必须一字不差 ---
# 07 结尾把 Git 半边补进 ~/.gitconfig（键表写在步骤里），而真正写入/回退的是 payload 里的
# terminal-tools（GIT_KEYS/GIT_VALUES）。两处一旦分叉（改了一个忘了另一个），自检与工具就会
# 一个说已就位、一个说缺——用测试把“只能有一处口径”钉住。
pairs_of() { # $1=file $2=keys-array-name $3=values-array-name
  # 用 substr 比较而不是正则：把 "^NAME=\\(" 传给 awk -v 时，未识别的转义会被吃掉，变成裸括号报
  # "invalid regexp"。数组名里没有特殊字符，前缀比较就够了。
  awk -v ka="$2=(" -v va="$3=(" '
    substr($0, 1, length(ka)) == ka { k = 1; v = 0; next }
    substr($0, 1, length(va)) == va { k = 0; v = 1; next }
    k && /^\)/ { k = 0; next }
    v && /^\)/ { v = 0; next }
    k { gsub(/^[ \t]+|[ \t]+$/, ""); if ($0 != "") keys[++n] = $0 }
    v { gsub(/^[ \t]+|[ \t]+$/, ""); gsub(/^'\''|'\''$/, ""); if ($0 != "") vals[++m] = $0 }
    END {
      if (n == 0 || n != m) { print "EXTRACT-FAILED(n=" n ",m=" m ")"; exit }
      for (i = 1; i <= n; i++) print keys[i] "=" vals[i]
    }
  ' "$1"
}
tt_tool="$ROOT_DIR/payload/home/scripts/maintenance/terminal-tools"
tt_step="$ROOT_DIR/steps/07-config.sh"
if [[ -f "$tt_tool" ]]; then
  tt_tool_pairs="$(pairs_of "$tt_tool" GIT_KEYS GIT_VALUES)"
  tt_step_pairs="$(pairs_of "$tt_step" tt_keys tt_values)"
  case "$tt_tool_pairs$tt_step_pairs" in
    *EXTRACT-FAILED*) note "terminal-tools: 键表提取失败（工具本体或 07 的数组形状变了）" ;;
  esac
  [[ "$tt_tool_pairs" == "$tt_step_pairs" ]] \
    || note "terminal-tools: 07-config.sh 的 tt_keys/tt_values 与工具本体的 GIT_KEYS/GIT_VALUES 不一致"
fi

if [[ -s "$errs" ]]; then
  head -40 "$errs"
  echo "test-manifest-schema: FAIL ($(wc -l < "$errs") problem(s))"
  exit 1
fi
echo "ok: 7 manifests (538/176/17/19/34/154/26 rows) match the column/format/value/whitelist rules"
