#!/usr/bin/env bash
# tests/test-manifest-schema.sh — 六份清单的「形状与规模」回归（只读、无副作用）。
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
count_lock "$M/files.tsv" 341 "files.tsv"
count_lock "$M/packages.tsv" 169 "packages.tsv"
count_lock "$M/aur.tsv" 12 "aur.tsv"
count_lock "$M/bin-links.tsv" 17 "bin-links.tsv"
count_lock "$M/seed.tsv" 25 "seed.tsv"
count_lock "$M/excluded.tsv" 120 "excluded.tsv"

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

# --- excluded.tsv ---
nf_rule "$M/excluded.tsv" 3 "excluded.tsv"
col_rule "$M/excluded.tsv" 1 '^(dir|file|package|pattern)$' "excluded.tsv col1 must be dir|file|package|pattern"

if [[ -s "$errs" ]]; then
  head -40 "$errs"
  echo "test-manifest-schema: FAIL ($(wc -l < "$errs") problem(s))"
  exit 1
fi
echo "ok: 6 manifests (341/169/12/17/25/120 rows) match the column/format/value/whitelist rules"
