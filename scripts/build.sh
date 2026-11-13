#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="${1:-$project_dir/dist/悬浮计时.app}"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$project_dir/build/module-cache"
swiftc -O -whole-module-optimization -target "$(uname -m)-apple-macos13.0" \
  -module-cache-path "$project_dir/build/module-cache" \
  "$project_dir"/Sources/*.swift -framework AppKit \
  -o "$app_dir/Contents/MacOS/FloatingStudyTimer"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
bash "$project_dir/scripts/build-icon.sh"
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app_dir"
codesign --verify --strict "$app_dir"
printf '已生成：%s\n' "$app_dir"
