#!/bin/zsh
# Builds dist/TouchBridge.app from the SPM product and signs it.
# Usage: Scripts/build-app.sh [debug|release]   (SIGN_IDENTITY env var overrides the identity)
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
IDENTITY="${SIGN_IDENTITY:-Apple Development: Frederic Garsolke (LLLQH7PQW7)}"
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
