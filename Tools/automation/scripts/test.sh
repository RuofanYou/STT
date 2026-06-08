#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT_DIR"

TARGET="${1:-all}"

case "$TARGET" in
  adt)
    bash Tools/automation/scripts/test_adt.sh
    ;;
  stt)
    bash Tools/automation/scripts/test_stt.sh
    ;;
  all)
    bash Tools/automation/scripts/test_adt.sh
    bash Tools/automation/scripts/test_stt.sh
    ;;
  *)
    echo "用法: bash Tools/automation/scripts/test.sh adt|stt|all"
    exit 2
    ;;
esac
