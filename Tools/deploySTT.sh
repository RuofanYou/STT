#!/usr/bin/env bash
set -euo pipefail

# 用法：
#   ./Tools/deploySTT.sh          # 默认同步到正式服
#   ./Tools/deploySTT.sh beta     # 同步到测试服
#   ./Tools/deploySTT.sh retail   # 同步到正式服

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$ROOT_DIR/ShengTangTools"

TARGET=${1:-retail}

if [[ "$TARGET" == "beta" ]]; then
  DEST_BASE="/Applications/World of Warcraft/_beta_/Interface/AddOns"
elif [[ "$TARGET" == "retail" ]]; then
  DEST_BASE="/Applications/World of Warcraft/_retail_/Interface/AddOns"
else
  echo "未知目标：$TARGET (应为 beta 或 retail)" >&2
  exit 1
fi

DEST="$DEST_BASE/ShengTangTools"

# —— 版本号自动进位并同步窗口标题（联网校验日期） ——
# 规则：
# - 从网络获取当前时间（HTTP Date 头，GMT），转换为本地时区的 YYMMDD；
# - 读取 toc 中的版本号（形如 251205.3）；
#   - 若日期部分 != 今日，则改为 今日.1；
#   - 若日期部分 == 今日，则小数点后一位 +1。
# - 若无法联网或解析失败，直接中止部署（仓库约束：日期必须联网核对）。

TOC_SRC="$SRC_DIR/ShengTangTools.toc"
if [[ ! -f "$TOC_SRC" ]]; then
  echo "未找到 TOC 文件：$TOC_SRC" >&2
  exit 1
fi

# 仅允许一条 Version 行（单一权威）
VER_LINE_COUNT=$(grep -n "^## Version:" "$TOC_SRC" | wc -l | tr -d ' ')
if [[ "$VER_LINE_COUNT" != "1" ]]; then
  echo "TOC 中的 \"## Version:\" 行应当唯一，当前为 $VER_LINE_COUNT 条" >&2
  exit 1
fi

# 获取网络时间（HTTP Date 头），例如：Fri, 05 Dec 2025 08:10:00 GMT
get_http_date() {
  local url="$1"
  (curl -sI --max-time 5 "$url" || true) \
    | awk 'tolower($0) ~ /^date:/ {sub(/^[Dd][Aa][Tt][Ee]:[[:space:]]*/, ""); print}' \
    | tr -d '\r' \
    | tail -n1
}

HTTP_DATE="$(get_http_date https://www.cloudflare.com)"
if [[ -z "$HTTP_DATE" ]]; then
  HTTP_DATE="$(get_http_date https://www.google.com)"
fi

if [[ -z "$HTTP_DATE" ]]; then
  echo "无法从网络获取当前时间（HTTP Date 头），请检查网络后重试。" >&2
  exit 1
fi

# 将 HTTP GMT 时间转换为本地时区的 YYMMDD
# 优先 python3（email.utils 更健壮）→ gdate → BSD date
CURRENT_YYMMDD=""
if command -v python3 >/dev/null 2>&1; then
  CURRENT_YYMMDD="$(
python3 - "$HTTP_DATE" 2>/dev/null <<'PY' || true
import sys, datetime, email.utils
s = sys.argv[1]
dt = email.utils.parsedate_to_datetime(s)
if dt.tzinfo is None:
    dt = dt.replace(tzinfo=datetime.timezone.utc)
print(dt.astimezone().strftime('%y%m%d'))
PY
  )"
fi

if [[ -z "$CURRENT_YYMMDD" ]] && command -v gdate >/dev/null 2>&1; then
  CURRENT_YYMMDD=$(gdate -d "$HTTP_DATE" +%y%m%d 2>/dev/null || true)
fi

if [[ -z "$CURRENT_YYMMDD" ]]; then
  LC_ALL=C CURRENT_YYMMDD=$(date -j -f "%a, %d %b %Y %T %Z" "$HTTP_DATE" +%y%m%d 2>/dev/null || true)
fi

if [[ -z "${CURRENT_YYMMDD:-}" ]]; then
  echo "解析网络时间失败：$HTTP_DATE" >&2
  exit 1
fi

if [[ "${DEBUG:-0}" != "0" ]]; then
  echo "[DEBUG] HTTP_DATE: $HTTP_DATE"
  echo "[DEBUG] CURRENT_YYMMDD: $CURRENT_YYMMDD"
fi

# 读取并解析旧版本
OLD_VER=$(sed -n 's/^## Version:[[:space:]]*//p' "$TOC_SRC" | head -n1)
if [[ ! "$OLD_VER" =~ ^[0-9]{6}(\.[0-9]+)?$ ]]; then
  echo "TOC 版本号格式非法：$OLD_VER（期望形如 YYMMDD.N）" >&2
  exit 1
fi

OLD_DATE_PART="${OLD_VER%%.*}"
OLD_PATCH_PART="0"
if [[ "$OLD_VER" == *.* ]]; then
  OLD_PATCH_PART="${OLD_VER#*.}"
fi

if [[ "$OLD_DATE_PART" == "$CURRENT_YYMMDD" ]]; then
  NEW_VER="$CURRENT_YYMMDD.$((OLD_PATCH_PART + 1))"
else
  NEW_VER="$CURRENT_YYMMDD.1"
fi

if [[ "$NEW_VER" != "$OLD_VER" ]]; then
  TITLE_TEXT="|cff00ff00STT - $NEW_VER|r"
  # 原地同步修改 toc 的版本与标题
  perl -0777 -i -pe \
    "s/^## Version:.*$/## Version: $NEW_VER/m; \
     s/^## Title:.*\$/## Title: $TITLE_TEXT/m; \
     s/^## Title-enUS:.*\$/## Title-enUS: $TITLE_TEXT/m; \
     s/^## Title-zhTW:.*\$/## Title-zhTW: $TITLE_TEXT/m" \
    "$TOC_SRC"
  echo "版本号与标题已更新：$OLD_VER -> $NEW_VER (基于网络日期 $CURRENT_YYMMDD)"
else
  echo "版本号无需变更：仍为 $OLD_VER (基于网络日期 $CURRENT_YYMMDD)"
fi

# 注意：更新日志的版本号「冻结」不在 deploy 做，而在 releaseSTT.sh 做。
# 原因：deploy 一天会跑几十次（每次都 bump 版本），但真正发给用户的 release 包很少；
# 只有在打 release 包时把 changelog 顶部的 PENDING 冻结为「本 release 包的版本号」，
# 才能保证「游戏内更新日志最新条目 == 用户拿到的包版本」。详见 releaseSTT.sh。

# 在部署前自动补齐缺失本地化键（不阻断部署）
echo "运行本地化缺失检查并自动填充占位..."
FILL=1 bash "$ROOT_DIR/Tools/check_locale.sh" || true

echo "部署 ShengTangTools 到: $DEST"
mkdir -p "$DEST_BASE"

# 使用 rsync 以保持文件时间并删除目的端多余文件
# --filter 'protect' 保留目标端 .git 与 .zip；--delete-excluded 清除 LibDeflate 开发文件
rsync -a --delete --delete-excluded \
  --filter "protect .git" \
  --filter "protect *.zip" \
  --exclude "libs/LibDeflate/tests" \
  --exclude "libs/LibDeflate/tools" \
  --exclude "libs/LibDeflate/docs" \
  --exclude "libs/LibDeflate/dev_docs" \
  --exclude "libs/LibDeflate/examples" \
  --exclude "libs/LibDeflate/rockspecs" \
  --exclude "libs/LibDeflate/.github" \
  --exclude "libs/LibDeflate/CONTRIBUTING.md" \
  --exclude "libs/LibDeflate/README.md" \
  --exclude "libs/LibDeflate/changelog.md" \
  "$SRC_DIR/" "$DEST/"

# 显示 TOC 版本校验（单一权威）
TOC_FILE="$DEST/ShengTangTools.toc"
if [[ -f "$TOC_FILE" ]]; then
  VER=$(grep -E "^## Version:" "$TOC_FILE" | sed 's/^[^:]*: *//')
  echo "部署完成。TOC版本: $VER"
else
  echo "部署完成。但未找到 $TOC_FILE 进行版本确认" >&2
fi
