#!/bin/bash
# Opens a temporary fullscreen fixture and a second timer with disposable study data.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
run_dir="$(mktemp -d "${TMPDIR:-/tmp}/wake-ui.XXXXXX")"
trap 'rm -rf -- "$run_dir"' EXIT
bash scripts/build-fixture.sh "$run_dir/FullScreenFixture"
swiftc -module-cache-path build/module-cache Sources/{AppDelegate,StateStore,TimerCore,TimerPanel,WakeRound,WakeTargetView}.swift \
    Tests/WakeWindowTests.swift -o "$run_dir/WakeWindowTests"
"$run_dir/WakeWindowTests" --data-file "$run_dir/state.json" "$run_dir/FullScreenFixture"
