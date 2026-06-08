#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT_DIR"

echo "[Automation][ADT] 1/3 locale 检查"
bash Tools/check_locale_ADT.sh

echo "[Automation][ADT] 2/3 执行 unit+replay"
lua Tools/automation/runner/main.lua --plugin adt

echo "[Automation][ADT] 3/3 汇总完成"
