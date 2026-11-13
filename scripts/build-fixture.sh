#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
fixture_dir="$project_dir/build/全屏覆盖验证.app"
mkdir -p "$fixture_dir/Contents/MacOS" "$project_dir/build/module-cache"
swiftc -module-cache-path "$project_dir/build/module-cache" -parse-as-library \
  "$project_dir/Tests/FullScreenFixture.swift" -framework AppKit -o "$fixture_dir/Contents/MacOS/FullScreenFixture"
cat > "$fixture_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FullScreenFixture</string>
<key>CFBundleIdentifier</key><string>local.ztx.FullScreenFixture</string>
<key>CFBundleName</key><string>全屏覆盖验证</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
codesign --force --sign - "$fixture_dir"
printf '测试窗口：%s\n' "$fixture_dir"
