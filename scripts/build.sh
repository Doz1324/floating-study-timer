#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
final_app="$project_dir/dist/悬浮计时.app"
if (( $# != 0 )); then
  echo '用法：bash scripts/build.sh（输出到 dist/悬浮计时.app）' >&2
  exit 2
fi
mkdir -p "$project_dir/dist/.staging.noindex"
stage="$(mktemp -d "$project_dir/dist/.staging.noindex/build.XXXXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
app_dir="$stage/悬浮计时.app"
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
# Swap the verified bundle atomically. The previous version is removed with the staging directory.
if [[ -e "$final_app" ]]; then
  expected_id="$(plutil -extract CFBundleIdentifier raw "$project_dir/Resources/Info.plist")"
  [[ ! -L "$final_app" && "$(plutil -extract CFBundleIdentifier raw "$final_app/Contents/Info.plist")" == "$expected_id" ]]
  swift -module-cache-path "$project_dir/build/module-cache" - "$app_dir" "$final_app" <<'SWIFT'
import Darwin
if renamex_np(CommandLine.arguments[1], CommandLine.arguments[2], UInt32(RENAME_SWAP)) != 0 {
    perror("更新应用失败")
    exit(1)
}
SWIFT
else
  mv "$app_dir" "$final_app"
fi
printf '已生成：%s\n' "$final_app"
