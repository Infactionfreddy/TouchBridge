#!/bin/zsh
# Builds dist/TouchBridge.app from the SPM product and signs it.
# Usage: Scripts/build-app.sh [debug|release]
# Signing identity: SIGN_IDENTITY env var; otherwise the first "Apple Development"
# identity in the keychain; otherwise ad-hoc (permissions then reset on every build).
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$( { security find-identity -v -p codesigning 2>/dev/null || true; } \
    | awk -F'"' '/"Apple Development: /{print $2; exit}')"
fi
if [[ -z "$IDENTITY" ]]; then
  echo "warning: no Apple Development identity found, signing ad-hoc; set SIGN_IDENTITY to keep permissions stable" >&2
  IDENTITY="-"
fi
APP="dist/TouchBridge.app"

swift build -c "$CONFIG" --product TouchBridge
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/TouchBridge" "$APP/Contents/MacOS/TouchBridge"
cp App/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
xattr -cr "$APP"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
codesign --verify --verbose=2 "$APP"
echo "built $APP ($CONFIG, signed as '$IDENTITY')"
