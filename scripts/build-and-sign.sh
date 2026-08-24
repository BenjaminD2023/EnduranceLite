#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TEAM_ID="${DEVELOPMENT_TEAM:-45PVRUCTSQ}"
IDENTITY="${CODE_SIGN_IDENTITY:-Apple Development: appleid202325@outlook.com (FR8NBQWMH7)}"
DERIVED="$ROOT/build"

echo "→ Building EnduranceLite (Release)"
xcodebuild \
  -project EnduranceLite.xcodeproj \
  -scheme EnduranceLite \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  -destination "platform=macOS,arch=arm64" \
  build

APP="$DERIVED/Build/Products/Release/EnduranceLite.app"

echo "→ Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" | sed -n '1,20p'

echo "→ Installing to /Applications"
rm -rf /Applications/EnduranceLite.app
cp -R "$APP" /Applications/EnduranceLite.app
xattr -cr /Applications/EnduranceLite.app || true

echo "Installed /Applications/EnduranceLite.app"
spctl --assess --type execute -v /Applications/EnduranceLite.app || true
