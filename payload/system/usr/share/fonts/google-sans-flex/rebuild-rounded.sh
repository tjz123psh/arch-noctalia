#!/bin/bash
# 重新生成 /usr/share/fonts/google-sans-flex/GoogleSansFlex-Rounded.ttf
#
# 作用：把上游 Google Sans Flex 的 6 轴可变字体里，圆润轴 ROND 固定成指定值
#       （默认 100 = 最圆），并补回 18 个具名权重实例，让 fontconfig 能选到真 Bold/Medium。
#
# 依赖：curl + python3 + fonttools（pip install fonttools）
# 用法：bash rebuild-rounded.sh [ROND]        # ROND 取 0..100，默认 100
set -euo pipefail

ROND="${1:-100}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> 下载上游可变字体 (ROND 目标值 = $ROND)"
curl -sSL --max-time 180 -o "$WORK/var.ttf" \
  "https://raw.githubusercontent.com/google/fonts/main/ofl/googlesansflex/GoogleSansFlex%5BGRAD,ROND,opsz,slnt,wdth,wght%5D.ttf"
curl -sSL --max-time 60 -o "$WORK/OFL.txt" \
  "https://raw.githubusercontent.com/google/fonts/main/ofl/googlesansflex/OFL.txt"

echo "==> fontTools: 固定 ROND=$ROND、GRAD=0，重建具名实例"
python3 - "$WORK/var.ttf" "$WORK/out.ttf" "$ROND" <<'PY'
import sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools.ttLib.tables._f_v_a_r import NamedInstance

src, dst, rond = sys.argv[1], sys.argv[2], float(sys.argv[3])
WEIGHTS = [(100, "Thin"), (200, "ExtraLight"), (300, "Light"), (400, "Regular"),
           (500, "Medium"), (600, "SemiBold"), (700, "Bold"), (800, "ExtraBold"),
           (900, "Black")]

f = TTFont(src)
out = instancer.instantiateVariableFont(f, {"ROND": rond, "GRAD": 0.0},
                                        inplace=False, updateFontNames=False)
fv = out["fvar"]
fv.instances = []
for w, nm in WEIGHTS:
    for slnt, suf in ((0.0, ""), (-10.0, " Italic")):
        inst = NamedInstance()
        inst.coordinates = {"opsz": 18.0, "wdth": 100.0, "wght": float(w), "slnt": slnt}
        inst.subfamilyNameID = out["name"].addName(nm + suf)
        inst.postscriptNameID = 0xFFFF
        fv.instances.append(inst)

nm = out["name"]
for nid, val in ((1, "Google Sans Flex"), (2, "Regular"), (4, "Google Sans Flex"),
                 (6, "GoogleSansFlex-Regular"), (16, "Google Sans Flex"), (17, "Regular")):
    nm.setName(val, nid, 3, 1, 0x409)
    nm.setName(val, nid, 1, 0, 0)

# STAT 表里剔除已经固定掉的 GRAD / ROND，避免与 fvar 不一致
stat = out["STAT"].table
axes = stat.DesignAxisRecord.Axis
kept = [a for a in axes if a.AxisTag not in ("GRAD", "ROND")]
tags = [a.AxisTag for a in kept]
remap = {i: tags.index(a.AxisTag) for i, a in enumerate(axes) if a.AxisTag in tags}

def fix(av):
    if av.Format in (1, 2, 3):
        if axes[av.AxisIndex].AxisTag in ("GRAD", "ROND"):
            return None
        av.AxisIndex = remap[av.AxisIndex]
        return av
    if av.Format == 4:
        recs = []
        for r in av.AxisValueRecord:
            if axes[r.AxisIndex].AxisTag in ("GRAD", "ROND"):
                return None
            r.AxisIndex = remap[r.AxisIndex]
            recs.append(r)
        av.AxisValueRecord = recs
        return av
    return av

stat.AxisValueArray.AxisValue = [v for v in (fix(x) for x in stat.AxisValueArray.AxisValue) if v]
stat.DesignAxisRecord.Axis = kept
stat.DesignAxisCount = len(kept)

out.save(dst)
print("    写出:", dst)
PY

echo "==> 安装到 /usr/share/fonts/google-sans-flex/"
sudo install -m644 "$WORK/out.ttf" /usr/share/fonts/google-sans-flex/GoogleSansFlex-Rounded.ttf
sudo install -m644 "$WORK/OFL.txt" /usr/share/fonts/google-sans-flex/OFL.txt
fc-cache -f >/dev/null
echo "==> 完成。验证："
fc-match "Google Sans Flex"
fc-match "sans-serif"
