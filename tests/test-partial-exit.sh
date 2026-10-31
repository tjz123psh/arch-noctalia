#!/usr/bin/env bash
# test-partial-exit.sh — 结尾状态必须能当退出码用（全 stub、零系统副作用）：
#   漏了阶段却 exit 0，会让脚本/自动化误以为装完了（审计 F2：--from 07 跳过 01-06 后仍退 0）。
#   规则：全齐 → 0；只差 05（AUR 已知可后补，含 --no-aur）→ 0 并写明；其它缺阶段 → 非零。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/repo/steps" "$sandbox/stub-bin"

cp "$ROOT/install.sh" "$sandbox/repo/install.sh"
ln -s "$ROOT/lib" "$sandbox/repo/lib"
ln -s "$ROOT/manifests" "$sandbox/repo/manifests"
ln -s "$ROOT/payload" "$sandbox/repo/payload"
for f in "$ROOT"/steps/*.sh; do
  b="$(basename "$f")"
  printf '#!/usr/bin/env bash\necho "STUB %s"\n' "$b" > "$sandbox/repo/steps/$b"
done
for c in sudo pacman git; do
  printf '#!/bin/sh\nexit 0\n' > "$sandbox/stub-bin/$c"
  chmod +x "$sandbox/stub-bin/$c"
done

export HOME="$sandbox/home"
mkdir -p "$HOME"
DONE="$HOME/.local/state/arch-noctalia/steps.done"
run() { PATH="$sandbox/stub-bin:$PATH" bash "$sandbox/repo/install.sh" --run --yes --machine vm "$@" 2>&1; }

# 1) --from 03 跳过了 01-02：跑完剩下的阶段也必须非零退出。
set +e
out1="$(run --from 03)"
rc1=$?
set -e
printf '%s\n' "$out1"
[ "$rc1" -ne 0 ] || { echo "[FAIL] a run that skipped stages 01-02 exited 0"; exit 1; }
grep -q 'stages not completed: 01 02' <<<"$out1" || { echo "[FAIL] missing 'stages not completed' line"; exit 1; }
grep -q 'STUB 03-packages.sh' <<<"$out1" || { echo "[FAIL] stage 03 should still run"; exit 1; }
if grep -q 'STUB 01-sources.sh' <<<"$out1"; then
  echo "[FAIL] stage 01 must not re-run under --from 03"
  exit 1
fi

# 2) 同一套已记账的 03-12 之后再普通跑：01-02 补齐 → 0。
if ! out2="$(run --from 01)"; then
  printf '%s\n' "$out2"
  echo "[FAIL] completing the skipped stages should exit 0"
  exit 1
fi
grep -q 'all stages complete\.' <<<"$out2" || { echo "[FAIL] expected 'all stages complete.' after finishing"; exit 1; }
[ "$(wc -l < "$DONE")" -eq 12 ] || { echo "[FAIL] done file should list all 12 stages"; exit 1; }

echo "ok: missing stages make the run exit non-zero; completing them exits 0"
