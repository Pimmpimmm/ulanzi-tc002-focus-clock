#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

find . -name '*.sh' -type f -not -path './node_modules/*' -print0 | xargs -0 -n1 bash -n
bash companion/verify-runtime-bundle.sh
npm ci
npm test
bash mac-app/test-dial.sh
bash mac-app/build-app.sh

test -x mac-app/dist/TC002FocusCompanion.app/Contents/MacOS/TC002FocusCompanion
test -s mac-app/dist/TC002FocusCompanion.app/Contents/Resources/OakTexture.png
test -f mac-app/dist/TC002FocusCompanion.app/Contents/Resources/tc002-repo/device/TC002_Focus_Probe/TemporaryFocusRelease/lib/libzkgui.so
printf '冷克隆可移植验证通过。\n'
