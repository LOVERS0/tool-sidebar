#!/bin/bash
# 一键发布：构建 → 签名 → 打 tag → 等待 CI Release → 上传本地包 → 更新 appcast/Homebrew
# 用法：./scripts/release.sh 1.9.0
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "用法: $0 <version>，例如 $0 1.9.0" >&2
  exit 1
fi
TAG="v$VERSION"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$HOME/Applications/小工具侧边栏.app"
REPO="LOVERS0/tool-sidebar"
TAP_DIR="$HOME/Documents/homebrew-tool-sidebar"
cd "$ROOT"

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
command -v gh >/dev/null || { echo "缺少 gh" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "请先 gh auth login" >&2; exit 1; }

echo "== 1/7 构建 v$VERSION =="
VERSION="$VERSION" ./build.sh

echo "== 2/7 打包并签名 =="
ZIP="$ROOT/build/ToolSidebar.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
SIG=$(vendor/bin/sign_update "$ZIP" 2>/dev/null | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
SIZE=$(stat -f%z "$ZIP")
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
[ -n "$SIG" ] || { echo "Sparkle 签名失败" >&2; exit 1; }
echo "sha256=$SHA size=$SIZE"

echo "== 3/7 打 tag $TAG =="
if gh api "repos/$REPO/git/ref/tags/$TAG" >/dev/null 2>&1; then
  echo "tag 已存在，跳过"
else
  HEAD=$(gh api "repos/$REPO/commits/main" --jq .sha)
  gh api --method POST "repos/$REPO/git/refs" \
    -f "ref=refs/tags/$TAG" -f "sha=$HEAD" >/dev/null
  echo "tag $TAG -> ${HEAD:0:7}"
fi

echo "== 4/7 等待 CI 生成 Release（最多 10 分钟） =="
for _ in $(seq 1 60); do
  if gh release view "$TAG" >/dev/null 2>&1; then break; fi
  sleep 10
done
gh release view "$TAG" >/dev/null || { echo "CI 未生成 Release，请检查 Actions" >&2; exit 1; }

echo "== 5/7 上传本地构建并更新 appcast =="
gh release upload "$TAG" "$ZIP" --clobber >/dev/null
python3 - "$VERSION" "$TAG" "$SIZE" "$SIG" <<'PY'
import datetime, re, sys
version, tag, size, sig = sys.argv[1:5]
url = f"https://github.com/LOVERS0/tool-sidebar/releases/download/{tag}/ToolSidebar.zip"
pub = datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
item = f'''    <item>
      <title>Version {version}</title>
      <link>https://github.com/LOVERS0/tool-sidebar/releases/tag/{tag}</link>
      <sparkle:version>{version}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <pubDate>{pub}</pubDate>
      <enclosure url="{url}" length="{size}" type="application/octet-stream" sparkle:edSignature="{sig}" />
    </item>
'''
text = open("appcast.xml", encoding="utf-8").read()
text = re.sub(
    r"    <item>\s*<title>Version " + re.escape(version) + r"</title>.*?</item>\n",
    "", text, flags=re.S)
text = text.replace("    <language>zh-CN</language>\n",
                    "    <language>zh-CN</language>\n" + item, 1)
open("appcast.xml", "w", encoding="utf-8").write(text)
print("appcast entry added")
PY
gh release upload "$TAG" appcast.xml --clobber >/dev/null
BASE64=$(base64 < appcast.xml | tr -d '\n')
FILE_SHA=$(gh api "repos/$REPO/contents/appcast.xml" --jq .sha)
gh api --method PUT "repos/$REPO/contents/appcast.xml" \
  -f message="chore: appcast $TAG" -f content="$BASE64" -f sha="$FILE_SHA" -f branch=main >/dev/null
echo "appcast pushed"

echo "== 6/7 更新 Homebrew cask =="
if [ -f "$TAP_DIR/Casks/tool-sidebar.rb" ]; then
  python3 - "$TAP_DIR/Casks/tool-sidebar.rb" "$VERSION" "$SHA" <<'PY'
import re, sys
path, version, sha = sys.argv[1:4]
text = open(path).read()
text = re.sub(r'version "[^"]+"', f'version "{version}"', text)
text = re.sub(r'sha256 "[^"]+"', f'sha256 "{sha}"', text)
open(path, "w").write(text)
print("cask edited")
PY
  B64=$(base64 < "$TAP_DIR/Casks/tool-sidebar.rb" | tr -d '\n')
  TAP_SHA=$(gh api "repos/LOVERS0/homebrew-tool-sidebar/contents/Casks/tool-sidebar.rb" --jq .sha)
  gh api --method PUT "repos/LOVERS0/homebrew-tool-sidebar/contents/Casks/tool-sidebar.rb" \
    -f message="chore: $VERSION" -f content="$B64" -f sha="$TAP_SHA" -f branch=main >/dev/null
  echo "cask pushed"
else
  echo "未找到 $TAP_DIR，跳过 cask"
fi

echo "== 7/7 完成 =="
gh release edit "$TAG" --notes "## $TAG

- ToolSidebar.zip SHA-256: \`$SHA\`

See [CHANGELOG.md](https://github.com/LOVERS0/tool-sidebar/blob/main/CHANGELOG.md)." >/dev/null
echo "https://github.com/LOVERS0/tool-sidebar/releases/tag/$TAG"
