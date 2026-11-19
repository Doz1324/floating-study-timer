#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
fixture="${1:?请使用 bash scripts/test-wake-ui.sh 运行临时窗口测试}"
mkdir -p "$project_dir/build/module-cache"
swiftc -module-cache-path "$project_dir/build/module-cache" -parse-as-library \
  "$project_dir/Tests/FullScreenFixture.swift" -framework AppKit -o "$fixture"
