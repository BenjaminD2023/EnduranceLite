#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BUILD="$(mktemp -d "${TMPDIR:-/tmp}/endurancelite-settings-tests.XXXXXX")"
# Foundation derives a command-line program's defaults domain from its name.
# A fresh executable name isolates these tests from the installed app and all
# earlier runs, including the cross-process persistence check.
TEST_BINARY="$TEST_BUILD/EnduranceLiteSettingsTests-$(uuidgen)"
cleanup() {
  if [[ -x "$TEST_BINARY" ]]; then
    "$TEST_BINARY" --cleanup >/dev/null 2>&1 || true
  fi
  rm -rf "$TEST_BUILD"
}
trap cleanup EXIT

xcrun swiftc \
  "$ROOT/EnduranceLite/Models/AppSettings.swift" \
  "$ROOT/EnduranceLite/Models/PowerFeature.swift" \
  "$ROOT/EnduranceLite/Engine/SessionStore.swift" \
  "$ROOT/EnduranceLite/Engine/NativeLowPower.swift" \
  "$ROOT/EnduranceLite/Engine/PrivilegedShell.swift" \
  "$ROOT/tests/SettingsTests.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY"
"$TEST_BINARY" --verify-persistence
