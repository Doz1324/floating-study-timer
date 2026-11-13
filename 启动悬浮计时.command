#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
if [ ! -x "$project_dir/dist/悬浮计时.app/Contents/MacOS/FloatingStudyTimer" ]; then
  /bin/bash "$project_dir/scripts/build.sh"
fi
open "$project_dir/dist/悬浮计时.app"
