#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BUILD="$(mktemp -d "${TMPDIR:-/tmp}/endurancelite-battery-tests.XXXXXX")"
trap 'rm -rf "$TEST_BUILD"' EXIT

xcrun swiftc \
  "$ROOT/EnduranceLite/Engine/BatteryMonitor.swift" \
  "$ROOT/EnduranceLite/Models/BatterySnapshot.swift" \
  "$ROOT/tests/BatteryMonitorTests.swift" \
  -o "$TEST_BUILD/BatteryMonitorTests"

"$TEST_BUILD/BatteryMonitorTests"
