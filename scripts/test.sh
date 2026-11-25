#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p build/tests
xcrun swiftc -swift-version 5 -module-cache-path "$ROOT/build/module-cache" \
  ToolSidebar.swift Agent.swift L10n.swift Tests/RegressionTests.swift \
  -framework AppKit -framework Carbon -framework Sparkle -F vendor \
  -Xlinker -rpath -Xlinker "$ROOT/vendor" -o build/tests/regression-tests
build/tests/regression-tests
