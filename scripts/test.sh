#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$project_dir/build/module-cache"
swiftc -module-cache-path "$project_dir/build/module-cache" \
  "$project_dir/Sources/TimerCore.swift" "$project_dir/Sources/StateStore.swift" \
  "$project_dir/Sources/WakeRound.swift" "$project_dir/Tests/WakeTests.swift" "$project_dir/Tests/TimerTests.swift" -o "$project_dir/build/TimerTests"
"$project_dir/build/TimerTests"
