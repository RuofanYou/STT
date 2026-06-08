#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT_DIR"

echo "[Automation][STT] 1/4 locale 检查"
bash Tools/check_locale.sh

echo "[Automation][STT] 2/4 懒加载 spec 检查"
bash Tools/automation/scripts/check_stt_lazy_spec.sh

echo "[Automation][STT] 3/4 执行 unit+replay"
lua Tools/automation/runner/main.lua --plugin stt

echo "[Automation][STT] 4/4 汇总完成"
