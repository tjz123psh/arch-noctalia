#!/usr/bin/env bash
# test-bootstrap.sh — bootstrap 冒烟：
#   1) 本地路径源 → git clone → 显式参数透传（install.sh --preview）
#   2) 不带 install 参数 → 默认以 --run --yes 交接（用 stub 仓库验证，不跑真安装）
# 说明：clone 取的是 git HEAD（未提交的工作树改动不在克隆内）——干净工作树上最有意义。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$(mktemp -d)"
trap 'rm -rf "$dest"' EXIT

if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
  echo "[warn] working tree is dirty — the clone tests committed HEAD only"
fi

set +e
out="$(bash "$ROOT/bootstrap.sh" --src "$ROOT" --dest "$dest/repo" -- --preview 2>&1)"
rc=$?
set -e
printf '%s\n' "$out"
[ "$rc" -eq 0 ] || { echo "bootstrap rc=${rc}"; exit 1; }
printf '%s\n' "$out" | grep -q 'preview OK' || { echo "handover did not reach 'preview OK'"; exit 1; }
[ -d "$dest/repo/.git" ] || { echo "clone did not produce a git repo"; exit 1; }

# 场景 2：不带参数 → 默认 --run --yes（stub 仓库只回显收到的参数，不真装）
stub="$dest/stub-src"
mkdir -p "$stub"
cat > "$stub/install.sh" <<'STUB'
#!/usr/bin/env bash
echo "stub-install got: $*"
STUB
chmod +x "$stub/install.sh"
git -C "$stub" init -q
git -C "$stub" add -A
git -C "$stub" -c user.email=t@example.invalid -c user.name=t commit -qm init

set +e
out2="$(bash "$ROOT/bootstrap.sh" --src "$stub" --dest "$dest/repo2" 2>&1)"
rc2=$?
set -e
printf '%s\n' "$out2"
[ "$rc2" -eq 0 ] || { echo "bootstrap(default) rc=${rc2}"; exit 1; }
printf '%s\n' "$out2" | grep -q 'stub-install got: --run --yes' || { echo "default handover is not '--run --yes'"; exit 1; }

echo "ok: bootstrap (1) preview passthrough OK, (2) default handover = --run --yes OK"
