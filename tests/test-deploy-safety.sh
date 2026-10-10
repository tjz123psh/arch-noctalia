#!/usr/bin/env bash
# test-deploy-safety.sh — 07 步的数据安全行为（沙箱、只碰 $HOME 内目标、sudo 为 stub）：
#   1) seed 已有内容 → 保持不覆盖（kept）；
#   2) 普通文件内容不同 → 覆盖为新内容，且旧内容备份进 .state/overwritten/<时间戳>/；
#   3) seed 缺失 → 用仓库内容初始化；
#   4) 二次运行幂等（unchanged/kept 收敛）。
# 做法：软链真实 lib/，复制真实 steps/07-config.sh，其余（manifests/payload/HOME）全部沙箱化；
# PATH 前置 sudo stub（as_root 全部成 no-op，不进真实系统）。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

repo="$sandbox/repo"
home="$sandbox/home"
stub="$sandbox/stub-bin"
mkdir -p "$repo/steps" "$repo/manifests" "$repo/payload/fixtures" "$home/.cache" "$stub"

cp "$ROOT/steps/07-config.sh" "$repo/steps/"
ln -s "$ROOT/lib" "$repo/lib"
printf 'conf repo content\n' > "$repo/payload/fixtures/conf.txt"
printf 'note repo seed content\n' > "$repo/payload/fixtures/note.md"
printf 'fresh repo seed content\n' > "$repo/payload/fixtures/fresh.md"
m_conf="$(md5sum "$repo/payload/fixtures/conf.txt" | awk '{print $1}')"
m_note="$(md5sum "$repo/payload/fixtures/note.md" | awk '{print $1}')"
m_fresh="$(md5sum "$repo/payload/fixtures/fresh.md" | awk '{print $1}')"

{
  printf 'payload/fixtures/conf.txt\t%s/.cache/an-conf.txt\t644\t%s\n' "$home" "$m_conf"
  printf 'payload/fixtures/note.md\t%s/.cache/an-note.md\t644\t%s\n' "$home" "$m_note"
  printf 'payload/fixtures/fresh.md\t%s/.cache/an-fresh.md\t644\t%s\n' "$home" "$m_fresh"
} > "$repo/manifests/files.tsv"
{
  echo "# schema=1"
  printf 'payload/fixtures/note.md\t个人数据种子\n'
  printf 'payload/fixtures/fresh.md\t个人数据种子\n'
} > "$repo/manifests/seed.tsv"

# 预置：note 已有用户内容；conf 是被改过的内容；fresh 缺失
printf 'USER EDIT\n' > "$home/.cache/an-note.md"
printf 'USER MODIFIED\n' > "$home/.cache/an-conf.txt"

printf '#!/bin/sh\nexit 0\n' > "$stub/sudo"
chmod +x "$stub/sudo"

run07() {
  # AN_TARGET_ALLOW=/：本测试的夹具清单里 target 已经全部写在 $sandbox 内的绝对路径上，
  # 不需要 07 的目标白名单/沙箱重写（那两者由 test-07-deploy-sandbox.sh 专门覆盖）。
  HOME="$home" PATH="$stub:$PATH" AN_RUN=1 AN_ROOT_DIR="$repo" AN_TARGET_ALLOW=/ \
    bash "$repo/steps/07-config.sh"
}

if ! out1="$(run07 2>&1)"; then
  printf '%s\n' "$out1"
  echo "[FAIL] first run exited non-zero"
  exit 1
fi
printf '%s\n' "$out1"

# 1) seed 保留
grep -q 'USER EDIT' "$home/.cache/an-note.md" || { echo "[FAIL] seed note was overwritten"; exit 1; }
printf '%s\n' "$out1" | grep -q 'kept (seed' || { echo "[FAIL] kept message missing"; exit 1; }
# 2) 普通文件覆盖 + 旧内容备份
[[ "$(cat "$home/.cache/an-conf.txt")" == "conf repo content" ]] || { echo "[FAIL] conf not restored to repo content"; exit 1; }
bk="$(find "$home/.local/state/arch-noctalia/overwritten" -name an-conf.txt 2>/dev/null | head -1)"
if [[ -z "$bk" || "$(cat "$bk")" != "USER MODIFIED" ]]; then
  echo "[FAIL] backup missing or does not contain the old content"
  exit 1
fi
# 3) 缺失 seed 初始化
[[ "$(cat "$home/.cache/an-fresh.md")" == "fresh repo seed content" ]] || { echo "[FAIL] missing seed was not initialized"; exit 1; }

# 4) 幂等
if ! out2="$(run07 2>&1)"; then
  printf '%s\n' "$out2"
  echo "[FAIL] second run exited non-zero"
  exit 1
fi
printf '%s\n' "$out2" | grep -q 'files: 3 checked, 0 deployed, 1 unchanged, 2 kept (seed), 0 failed' || {
  echo "[FAIL] second run is not idempotent:"
  printf '%s\n' "$out2" | grep 'files:'
  exit 1
}

echo "ok: seed kept; overwrite backed up (old content preserved); missing seed initialized; re-run idempotent"
