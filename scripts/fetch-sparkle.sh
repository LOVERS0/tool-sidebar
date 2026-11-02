#!/bin/bash
# 下载 Sparkle 2.x 框架（本地构建 / CI 用），已存在则跳过
set -euo pipefail
DEST="${1:-$(cd "$(dirname "$0")/.." && pwd)/vendor}"
mkdir -p "$DEST"
cd "$DEST"
if [ -d "Sparkle.framework" ]; then
  echo "Sparkle.framework 已存在"
  exit 0
fi
VERSION="2.10.1"
URL="https://github.com/sparkle-project/Sparkle/releases/download/${VERSION}/Sparkle-${VERSION}.tar.xz"
echo "下载 Sparkle ${VERSION}…"
if ! curl -L --fail --http1.1 -m 300 -sS -o sparkle.tar.xz "$URL"; then
  echo "直连失败，改用镜像"
  curl -L --fail --http1.1 -m 300 -sS -o sparkle.tar.xz "https://ghproxy.net/$URL"
fi
tar -xf sparkle.tar.xz
rm -f sparkle.tar.xz
