#!/usr/bin/env bash
# lib/detect.sh — 环境识别：机型（physical / vm / unknown）、当前用户。
# 只读；识别失败返回 unknown，不做猜测。
# shellcheck disable=SC1091

[[ -n "${_AN_DETECT_LOADED:-}" ]] && return 0
_AN_DETECT_LOADED=1

detect_virt() {
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    # 裸机时 systemd-detect-virt 输出 "none" 且退出码为 1 —— 只看 stdout，别被 rc 带偏
    local out=""
    out="$(systemd-detect-virt 2>/dev/null || true)"
    if [[ -n "$out" ]]; then echo "$out"; else echo unknown; fi
  else
    echo unknown
  fi
}

detect_dmi_product() {
  cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown
}

# 机型判定：
#   systemd-detect-virt=vmware            → vm（VMware 客户机；测试场地）
#   none 且 DMI 含 ASUS / FA507           → physical（目标笔记本 ASUS TUF A15）
#   其他                                   → unknown（实装时需 --machine 显式指定）
detect_machine() {
  local virt dmi
  virt="$(detect_virt)"
  case "$virt" in
    vmware) echo "vm" ;;
    none)
      dmi="$(detect_dmi_product)"
      if [[ "$dmi" == *ASUS* || "$dmi" == *FA507* ]]; then
        echo "physical"
      else
        echo "unknown"
      fi
      ;;
    *) echo "unknown" ;;
  esac
}

current_user() { id -un; }
