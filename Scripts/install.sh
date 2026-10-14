#!/bin/zsh
# Copies dist/TouchBridge.app to ~/Applications and launches it.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d dist/TouchBridge.app ] || Scripts/build-app.sh release
mkdir -p "$HOME/Applications"
pkill -x TouchBridge || true
rm -rf "$HOME/Applications/TouchBridge.app"
cp -R dist/TouchBridge.app "$HOME/Applications/TouchBridge.app"
open "$HOME/Applications/TouchBridge.app"
echo "installed and launched ~/Applications/TouchBridge.app"
