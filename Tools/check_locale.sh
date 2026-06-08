#!/usr/bin/env bash
set -euo pipefail

# 用途：扫描源码中使用到的本地化键，与 zhCN / zhTW / enUS 运行时语言键对比，找出缺失项
# 使用：bash Tools/check_locale.sh

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/3] 收集源码中使用到的 L[\"...\"] 键（排除 locale 目录）..."
USED_KEYS=$(rg -oP 'L\["\K[^"\]]+(?="\])' \
  --no-filename --hidden --glob '!ShengTangTools/locale/**' \
  ShengTangTools | sort -u)

if [[ -z "$USED_KEYS" ]]; then
  echo "未在源码中发现 L[\"...\"] 用法。"
  exit 0
fi

echo "[2/3] 读取 zhCN / zhTW / enUS 已定义键（主语言包 + auto 占位）..."

tmpdir=$(mktemp -d)
cleanup_tmpdir() {
  [[ -d "${tmpdir:-}" ]] || return 0
  mkdir -p "$HOME/.Trash"
  mv "$tmpdir" "$HOME/.Trash/stt-check-locale-$(basename "$tmpdir")-$(date +%s)" 2>/dev/null || true
}
trap cleanup_tmpdir EXIT

printf "%s\n" "$USED_KEYS" > "$tmpdir/used.txt"
{
  rg -oP 'L\["\K[^"\]]+(?="\])' --no-filename ShengTangTools/locale/zhCN.lua
} | sort -u > "$tmpdir/zh_main.txt"
{
  cat "$tmpdir/zh_main.txt"
  rg -oP '\["\K[^"\]]+(?="\])' --no-filename ShengTangTools/locale/auto_zhCN.lua 2>/dev/null || true
} | sort -u > "$tmpdir/zh.txt"
{
  rg -oP 'L\["\K[^"\]]+(?="\])' --no-filename ShengTangTools/locale/zhTW.lua
} | sort -u > "$tmpdir/tw_main.txt"
{
  cat "$tmpdir/tw_main.txt"
  rg -oP '\["\K[^"\]]+(?="\])' --no-filename ShengTangTools/locale/auto_zhTW.lua 2>/dev/null || true
} | sort -u > "$tmpdir/tw.txt"
{
  rg -oP 'L\["\K[^"\]]+(?="\])' --no-filename ShengTangTools/locale/enUS.lua
} | sort -u > "$tmpdir/en_main.txt"
{
  cat "$tmpdir/en_main.txt"
  rg -oP '\["\K[^"\]]+(?="\])' --no-filename ShengTangTools/locale/auto_enUS.lua 2>/dev/null || true
} | sort -u > "$tmpdir/en.txt"

echo "[3/3] 对比缺失..."
ZH_MISSING=$(comm -23 "$tmpdir/used.txt" "$tmpdir/zh.txt" || true)
TW_MISSING=$(comm -23 "$tmpdir/used.txt" "$tmpdir/tw.txt" || true)
EN_MISSING=$(comm -23 "$tmpdir/used.txt" "$tmpdir/en.txt" || true)
ZH_AUTO_TARGET=$(comm -23 "$tmpdir/used.txt" "$tmpdir/zh_main.txt" || true)
TW_AUTO_TARGET=$(comm -23 "$tmpdir/used.txt" "$tmpdir/tw_main.txt" || true)
EN_AUTO_TARGET=$(comm -23 "$tmpdir/used.txt" "$tmpdir/en_main.txt" || true)

echo "-- 缺失于 zhCN："; printf "%s\n" "$ZH_MISSING" | sed '/^$/d' || true
echo "-- 缺失于 zhTW："; printf "%s\n" "$TW_MISSING" | sed '/^$/d' || true
echo "-- 缺失于 enUS："; printf "%s\n" "$EN_MISSING" | sed '/^$/d' || true

# 若设置 FILL=1，则自动写入 locale/auto_*.lua 作为占位翻译（值=键名）
if [[ "${FILL:-0}" == "1" ]]; then
  echo "[填充] 更新 locale/auto_zhCN.lua / auto_zhTW.lua / auto_enUS.lua ..."

  # auto 文件只保留当前源码仍使用、但主语言包未覆盖的键；避免旧碎片键长期留存。
  printf "%s\n" "$ZH_AUTO_TARGET" | sed '/^$/d' | sort -u > "$tmpdir/zh_auto_all.txt"
  printf "%s\n" "$TW_AUTO_TARGET" | sed '/^$/d' | sort -u > "$tmpdir/tw_auto_all.txt"
  printf "%s\n" "$EN_AUTO_TARGET" | sed '/^$/d' | sort -u > "$tmpdir/en_auto_all.txt"

  # 生成文件函数：保留旧 auto 文件中的既有翻译值；新缺失键仍用键名占位。
  gen_auto(){
    local infile=$1 ; local outfile=$2 ; local varname=$3 ; local oldfile=$4 ; local locale=$5
    python3 - "$infile" "$outfile" "$varname" "$oldfile" "$locale" <<'PY'
import re
import sys
from pathlib import Path

infile, outfile, varname, oldfile = map(Path, sys.argv[1:5])
locale = sys.argv[5]
old_values = {}
if oldfile.exists():
    pattern = re.compile(r'^\s*t\["((?:[^"\\]|\\.)*)"\]\s*=\s*"((?:[^"\\]|\\.)*)"\s*$')
    for line in oldfile.read_text(encoding="utf-8").splitlines():
        m = pattern.match(line)
        if m:
            old_values[m.group(1)] = m.group(2)

def escape(value):
    return value.replace("\\", "\\\\").replace('"', '\\"')

lines = [
    "-- 本文件由 Tools/check_locale.sh 自动生成/维护",
    "-- 不要手动编辑：如需修改，请在主语言包补齐键后重新部署",
    "",
    f"{varname} = {varname} or {{}}",
    f"do local t = {varname}",
]
for key in infile.read_text(encoding="utf-8").splitlines():
    if not key:
        continue
    value = old_values.get(escape(key), escape(key))
    lines.append(f't["{escape(key)}"] = "{value}"')
lines.append("end")
outfile.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
  }

  gen_auto "$tmpdir/zh_auto_all.txt" ShengTangTools/locale/auto_zhCN.lua STT_LOCALE_AUTO_zhCN ShengTangTools/locale/auto_zhCN.lua zhCN
  gen_auto "$tmpdir/tw_auto_all.txt" ShengTangTools/locale/auto_zhTW.lua STT_LOCALE_AUTO_zhTW ShengTangTools/locale/auto_zhTW.lua zhTW
  gen_auto "$tmpdir/en_auto_all.txt" ShengTangTools/locale/auto_enUS.lua STT_LOCALE_AUTO_enUS ShengTangTools/locale/auto_enUS.lua enUS
fi

echo "完成。缺失键已输出；如启用 FILL=1，自动补齐已写入 auto_*.lua。"
