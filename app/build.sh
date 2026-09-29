#!/usr/bin/env bash
# Build Sprout.app and install it to ~/Applications. Pass --open to launch it.
set -euo pipefail

cd "$(dirname "$0")"

swift build -c release --product Sprout
BIN="$(swift build -c release --show-bin-path)/Sprout"

APP="build/Sprout.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Sprout"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

pkill -x Sprout 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Sprout.app"
cp -R "$APP" "$HOME/Applications/"
echo "Installed: $HOME/Applications/Sprout.app"

if [[ "${1:-}" == "--open" ]]; then
  open "$HOME/Applications/Sprout.app"
fi
