#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/tc002-dial-test.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/mac-app/Sources/DialAdjustment.swift" \
  "$ROOT/mac-app/Sources/NavigationPosition.swift" \
  "$ROOT/mac-app/Tests/DialAdjustmentTests.swift" \
  -o "$TEST_DIR/dial-tests"
"$TEST_DIR/dial-tests"
