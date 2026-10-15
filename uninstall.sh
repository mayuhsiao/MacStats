#!/bin/bash
# 結束程式、移除登入自動啟動與 App
set -euo pipefail

APP_NAME="MacStats"
pkill -x "$APP_NAME" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.maxhsiao.MacStats.plist"
rm -rf "$HOME/Applications/${APP_NAME}.app"
defaults delete com.maxhsiao.MacStats 2>/dev/null || true

echo "🗑  已移除 ${APP_NAME}"
