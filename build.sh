#!/bin/bash
# 构建「小工具侧边栏」：universal（arm64 + x86_64）、deployment target macOS 13、带图标
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/小工具侧边栏.app"
BUILD="$ROOT/build"
VERSION="1.3.0"
SDK="$(xcrun --show-sdk-path)"

rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "== 编译 arm64 =="
xcrun swiftc -O -swift-version 5 \
  -target arm64-apple-macosx13.0 \
  "$ROOT/main.swift" "$ROOT/ToolSidebar.swift" "$ROOT/Agent.swift" \
  -framework AppKit -framework Carbon -sdk "$SDK" \
  -o "$BUILD/ToolSidebar-arm64"

echo "== 编译 x86_64 =="
xcrun swiftc -O -swift-version 5 \
  -target x86_64-apple-macosx13.0 \
  "$ROOT/main.swift" "$ROOT/ToolSidebar.swift" "$ROOT/Agent.swift" \
  -framework AppKit -framework Carbon -sdk "$SDK" \
  -o "$BUILD/ToolSidebar-x86_64"

echo "== 合并 universal =="
lipo -create "$BUILD/ToolSidebar-arm64" "$BUILD/ToolSidebar-x86_64" -output "$BUILD/ToolSidebar"
lipo -info "$BUILD/ToolSidebar"

echo "== 打包 =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/ToolSidebar" "$APP/Contents/MacOS/ToolSidebar"
if [ -f "$ROOT/assets/AppIcon.icns" ]; then
  cp "$ROOT/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
if [ -f "$ROOT/featured.json" ]; then
  cp "$ROOT/featured.json" "$APP/Contents/Resources/featured.json"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>小工具侧边栏</string>
  <key>CFBundleDisplayName</key><string>小工具侧边栏</string>
  <key>CFBundleExecutable</key><string>ToolSidebar</string>
  <key>CFBundleIdentifier</key><string>com.a1.toolsidebar</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" 2>/dev/null
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "== 已安装 =="
echo "$APP  (v$VERSION)"
