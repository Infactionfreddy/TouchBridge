#!/bin/zsh
# Copies dist/TouchBridge.app to ~/Applications and launches it.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d dist/TouchBridge.app ] || Scripts/build-app.sh release
mkdir -p "$HOME/Applications"
pkill -x TouchBridge || true
# Wait up to ~5 s for the old instance to exit, so it does not still hold the device when the new one starts.
for _ in $(seq 1 50); do pgrep -x TouchBridge >/dev/null || break; sleep 0.1; done
rm -rf "$HOME/Applications/TouchBridge.app"
cp -R dist/TouchBridge.app "$HOME/Applications/TouchBridge.app"
# Launch Services may still consider the killed instance running for a moment and answer -600 (procNotFound).
sleep 1
open "$HOME/Applications/TouchBridge.app" || { sleep 2; open "$HOME/Applications/TouchBridge.app"; }
echo "installed and launched ~/Applications/TouchBridge.app"
