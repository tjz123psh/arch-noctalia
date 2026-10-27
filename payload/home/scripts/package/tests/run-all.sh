#!/usr/bin/env bash
# 一把跑完 package 下所有验收套件
#
# 用法: tests/run-all.sh

set -uo pipefail

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
total_pass=0
total_fail=0
failed=()

for t in "$DIR"/phase*.sh; do
    name="$(basename -- "$t")"
    printf '%-34s ' "$name"
    out="$(bash "$t" 2>&1)"
    line="$(grep -o 'PASS=[0-9]* FAIL=[0-9]*' <<<"$out" | tail -n 1)"

    if [[ -z "$line" ]]; then
        printf '没有结果（脚本异常）\n'
        failed+=("$name")
        continue
    fi

    printf '%s\n' "$line"
    p="${line#PASS=}"; p="${p%% *}"
    f="${line##*FAIL=}"
    total_pass=$((total_pass + p))
    total_fail=$((total_fail + f))
    (( f == 0 )) || failed+=("$name")
done

echo
echo "合计：PASS=$total_pass FAIL=$total_fail"
if (( ${#failed[@]} > 0 )); then
    echo "失败套件：${failed[*]}"
    exit 1
fi
