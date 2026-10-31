#!/usr/bin/env bash
# test-terminal-tools-gate.sh — 07 结尾的 terminal-tools 补齐必须与 12 步同向（审计 F15）：
#   12 把「管理块在、6 个 git 键一个没设」判为失败，而 07 以前只 warn —— 结果是
#   「12 红、--redo 12 又修不了」的死局。现在 07 当场 die，重跑 07 即可重试。
# 做法：沙箱 HOME + 一个会失败的 fake terminal-tools；其余（pacman/locale/grub...）全是 no-op。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
case "$sandbox" in /tmp/*|/var/tmp/*) ;; *) echo "[FAIL] sandbox is not under /tmp: $sandbox"; exit 1;; esac

repo="$sandbox/repo"
home="$sandbox/home"
stub="$sandbox/stub-bin"
mkdir -p "$repo/manifests" "$repo/steps" "$repo/payload" "$home/.config/fish" \
         "$home/scripts/maintenance" "$stub"
ln -sfn "$ROOT/lib" "$repo/lib"
cp "$ROOT/steps/07-config.sh" "$repo/steps/"
printf '# schema=1\n' > "$repo/manifests/files.tsv"
printf '# schema=1\n' > "$repo/manifests/seed.tsv"
printf '# schema=1\n' > "$repo/manifests/runtime-regenerated.tsv"

# Fish 半边在位（管理块标记），Git 半边一个都没设。
cat > "$home/.config/fish/config.fish" <<'CONF'
# >>> maintenance terminal-tools >>>
zoxide init fish | source
# <<< maintenance terminal-tools <<<
CONF
tool="$home/scripts/maintenance/terminal-tools"
cat > "$tool" <<'TOOL'
#!/usr/bin/env bash
echo "fake terminal-tools: refusing to enable" >&2
exit 1
TOOL
chmod +x "$tool"

for c in pacman paru systemctl usermod locale-gen grub-mkconfig glib-compile-schemas \
         setfacl getfacl fc-cache update-desktop-database gsettings fish bat zoxide delta; do
  printf '#!/bin/sh\nexit 0\n' > "$stub/$c"
  chmod +x "$stub/$c"
done
printf '#!/bin/sh\necho btrfs\n' > "$stub/findmnt"; chmod +x "$stub/findmnt"
printf '#!/bin/sh\nexec "$@"\n' > "$stub/sudo"; chmod +x "$stub/sudo"

run07() {
  env HOME="$home" PATH="$stub:$PATH" AN_RUN=1 AN_MACHINE=physical AN_ROOT_DIR="$repo" \
      bash "$repo/steps/07-config.sh" 2>&1
}

rc=0
out="$(run07)" || rc=$?
printf '%s\n' "$out" | tail -5
(( rc != 0 )) || { echo "[FAIL] a failing terminal-tools --enable must fail stage 07 (12 would go red and --redo 12 cannot fix it)"; exit 1; }
grep -q 'terminal-tools --enable failed' <<<"$out" || { echo "[FAIL] missing terminal-tools failure message"; exit 1; }
grep -q 'fake terminal-tools: refusing to enable' <<<"$out" || { echo "[FAIL] the tool's own output is not surfaced"; exit 1; }

# 反向：工具成功时 07 必须照常走完（失败门只在真的失败时生效）。
printf '#!/usr/bin/env bash\nexit 0\n' > "$tool"
chmod +x "$tool"
rc=0
out2="$(run07)" || rc=$?
(( rc == 0 )) || { printf '%s\n' "$out2" | tail -10; echo "[FAIL] stage 07 must succeed when terminal-tools --enable works"; exit 1; }
grep -q 'Stage 07 config: done' <<<"$out2" || { echo "[FAIL] stage 07 did not finish"; exit 1; }

echo "ok: failing terminal-tools --enable aborts stage 07 (same direction as stage 12); success path unchanged"
