#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BUILD="$(mktemp -d "${TMPDIR:-/tmp}/endurancelite-pauser-tests.XXXXXX")"
trap 'rm -rf "$TEST_BUILD"' EXIT

xcrun swiftc \
  "$ROOT/EnduranceLite/Engine/ProcessPauser.swift" \
  "$ROOT/EnduranceLite/Engine/PidBag.swift" \
  "$ROOT/EnduranceLite/Engine/PrivilegedShell.swift" \
  "$ROOT/EnduranceLite/Models/BatterySnapshot.swift" \
  "$ROOT/tests/ProcessPauserTests.swift" \
  -o "$TEST_BUILD/ProcessPauserTests"

"$TEST_BUILD/ProcessPauserTests"
