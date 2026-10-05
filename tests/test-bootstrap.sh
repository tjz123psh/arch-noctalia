#!/usr/bin/env bash
# test-bootstrap.sh — bootstrap 冒烟：
#   1) 本地路径源 → git clone → 显式参数透传（install.sh --preview）
#   2) 不带 install 参数 → 默认以 --run --yes 交接（stub 仓库验证，不跑真安装）
#   3) 脚本从管道喂入（等效 `curl | bash`）→ 必须不挂起且交接正确
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

# 场景 3：脚本从管道喂入（等效 curl | bash），必须不挂起。
# 回归背景（2026-10-05 实测事故）：bootstrap 曾在中途 `exec </dev/tty`，把 bash 自己的
# 脚本流截断——bash 读完缓冲后转去从终端读“下一行脚本”，等不到输入 → 静默挂死。
# 守卫 1（静态）：脚本任何时刻都不得对自身 exec 换 stdin。
if grep -qE '^[[:space:]]*exec[[:space:]]*<' "$ROOT/bootstrap.sh"; then
  echo "guard FAIL: bootstrap 不得修改本进程 stdin（会挂死 'curl | bash'）"
  exit 1
fi
# 守卫 2（动态）：管道喂脚本 + 超时兜底，交接必须正常完成。
set +e
out3="$(cat "$ROOT/bootstrap.sh" | timeout 10 bash -s -- --src "$stub" --dest "$dest/repo3" 2>&1)"
rc3=$?
set -e
printf '%s\n' "$out3"
[ "$rc3" -eq 0 ] || { echo "stdin-script scenario rc=${rc3} (hang?)"; exit 1; }
printf '%s\n' "$out3" | grep -q 'stub-install got: --run --yes' || { echo "stdin-script handover wrong"; exit 1; }

echo "ok: bootstrap (1) preview passthrough OK, (2) default handover = --run --yes OK, (3) stdin-script no-hang OK"
