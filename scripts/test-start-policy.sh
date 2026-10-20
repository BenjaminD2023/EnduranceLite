#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BUILD="$(mktemp -d "${TMPDIR:-/tmp}/endurancelite-start-policy-tests.XXXXXX")"
trap 'rm -rf "$TEST_BUILD"' EXIT

xcrun swiftc \
  "$ROOT/EnduranceLite/Engine/PowerStartPolicy.swift" \
  "$ROOT/EnduranceLite/Models/AppSettings.swift" \
  "$ROOT/EnduranceLite/Models/PowerFeature.swift" \
  "$ROOT/tests/PowerStartPolicyTests.swift" \
  -o "$TEST_BUILD/PowerStartPolicyTests"

"$TEST_BUILD/PowerStartPolicyTests"
