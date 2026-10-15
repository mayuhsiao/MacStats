#!/bin/bash
# 重新編譯 → 結束舊版 → 安裝到 ~/Applications → 啟動新版
# 修改程式碼後，執行這支就能套用
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MacStats"
DEST="$HOME/Applications/${APP_NAME}.app"

./build.sh

if pgrep -x "$APP_NAME" >/dev/null; then
    echo "⏹  結束執行中的 ${APP_NAME}…"
    pkill -x "$APP_NAME" || true
    while pgrep -x "$APP_NAME" >/dev/null; do sleep 0.2; done
fi

mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "build/${APP_NAME}.app" "$DEST"
open "$DEST"

echo "🚀 已安裝並啟動：$DEST"
