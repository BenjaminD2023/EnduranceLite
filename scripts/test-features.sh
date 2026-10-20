#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BUILD="$(mktemp -d "${TMPDIR:-/tmp}/endurancelite-feature-tests.XXXXXX")"
trap 'rm -rf "$TEST_BUILD"' EXIT

xcrun swiftc \
  "$ROOT/EnduranceLite/Engine/EnergyMonitor.swift" \
  "$ROOT/EnduranceLite/Engine/BackgroundHider.swift" \
  "$ROOT/EnduranceLite/Models/BatterySnapshot.swift" \
  "$ROOT/tests/FeatureBehaviorTests.swift" \
  -o "$TEST_BUILD/FeatureBehaviorTests"

"$TEST_BUILD/FeatureBehaviorTests"
