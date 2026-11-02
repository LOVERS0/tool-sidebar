#!/bin/bash
# 构建「小工具侧边栏」：universal（arm64 + x86_64）、deployment target macOS 13、带图标
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/小工具侧边栏.app"
BUILD="$ROOT/build"
VERSION="1.8.1"
SDK="$(xcrun --show-sdk-path)"

echo "== Sparkle 框架 =="
/bin/bash "$ROOT/scripts/fetch-sparkle.sh" "$ROOT/vendor"
SPARKLE="$ROOT/vendor"

rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "== 编译 arm64 =="
xcrun swiftc -O -swift-version 5 \
  -target arm64-apple-macosx13.0 \
  "$ROOT/main.swift" "$ROOT/ToolSidebar.swift" "$ROOT/Agent.swift" "$ROOT/Translator.swift" \
  -framework AppKit -framework Carbon -framework Sparkle \
  -F "$SPARKLE" -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -sdk "$SDK" \
  -o "$BUILD/ToolSidebar-arm64"

echo "== 编译 x86_64 =="
xcrun swiftc -O -swift-version 5 \
  -target x86_64-apple-macosx13.0 \
  "$ROOT/main.swift" "$ROOT/ToolSidebar.swift" "$ROOT/Agent.swift" "$ROOT/Translator.swift" \
  -framework AppKit -framework Carbon -framework Sparkle \
  -F "$SPARKLE" -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -sdk "$SDK" \
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
mkdir -p "$APP/Contents/Frameworks"
ditto "$ROOT/vendor/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

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
  <key>SUFeedURL</key><string>https://lovers0.github.io/tool-sidebar/appcast.xml</string>
  <key>SUPublicEDKey</key><string>jRnhK89c0mENrR/Xh96Pw6JoF0S9P1g4ACaZLJllO68=</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" 2>/dev/null
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "== 已安装 =="
echo "$APP  (v$VERSION)"
