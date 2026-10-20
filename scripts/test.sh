#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for suite in test-process-pauser test-features test-settings test-start-policy test-battery; do
  "$ROOT/scripts/$suite.sh"
done
