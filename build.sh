#!/bin/bash
# 构建「小工具侧边栏」App 并安装到 ~/Applications
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/小工具侧边栏.app"
BUILD="$ROOT/build"

rm -rf "$BUILD"
mkdir -p "$BUILD"
cp "$ROOT/ToolSidebar.swift" "$BUILD/main.swift"

echo "== 编译 =="
xcrun swiftc -O -swift-version 5 \
  "$BUILD/main.swift" \
  -o "$BUILD/ToolSidebar" \
  -framework AppKit

echo "== 打包 =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/ToolSidebar" "$APP/Contents/MacOS/ToolSidebar"
mkdir -p "$APP/Contents/Resources/agent"
cp "$ROOT/agent/toolagent.py" "$APP/Contents/Resources/agent/toolagent.py"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>小工具侧边栏</string>
  <key>CFBundleDisplayName</key><string>小工具侧边栏</string>
  <key>CFBundleExecutable</key><string>ToolSidebar</string>
  <key>CFBundleIdentifier</key><string>com.a1.toolsidebar</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" 2>/dev/null
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "== 已安装 =="
echo "$APP"
