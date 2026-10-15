#!/bin/bash
# 編譯並打包成 build/MacStats.app
# 直接用 swiftc 編譯（不依賴 SwiftPM），並自動挑選與編譯器版本相符的 macOS SDK，
# 避免 Command Line Tools 更新不完整時，預設 SDK 與編譯器不相容。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MacStats"
APP_DIR="build/${APP_NAME}.app"
BIN=".build/release/${APP_NAME}"

SWIFT_VER=$(swiftc --version 2>&1 | sed -nE 's/.*Apple Swift version ([0-9]+\.[0-9]+).*/\1/p' | head -1)
DEFAULT_SDK=$(xcrun --show-sdk-path)
SDK=""
for s in $(ls -d "$(dirname "$DEFAULT_SDK")"/MacOSX[0-9]*.*.sdk 2>/dev/null | sort -rV); do
    iface=$(ls "$s"/usr/lib/swift/Swift.swiftmodule/*.swiftinterface 2>/dev/null | head -1)
    if [ -n "$iface" ] && grep -q "swift-compiler-version: Apple Swift version ${SWIFT_VER}" "$iface"; then
        SDK="$s"
        break
    fi
done
SDK="${SDK:-$DEFAULT_SDK}"
echo "🔧 Swift ${SWIFT_VER}，SDK：$(basename "$SDK")"

mkdir -p "$(dirname "$BIN")"
swiftc -O -sdk "$SDK" -target "$(uname -m)-apple-macos13.0" -module-name "$APP_NAME" \
    $(find Sources/MacStats -name '*.swift' | sort) -o "$BIN"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BIN" "$APP_DIR/Contents/MacOS/"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --sign - "$APP_DIR"

echo "✅ 已打包：$APP_DIR"
