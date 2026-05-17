#!/usr/bin/env bash
# Build and replace common C-Switch.app copies so quit-crash fixes actually run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/dist/C-Switch.app"

"$ROOT/scripts/package_app.sh"

killall C-Switch 2>/dev/null || true
sleep 0.3

install_one() {
  local dest="$1"
  if [[ -d "$dest" ]]; then
    rm -rf "$dest"
    echo "Replaced $dest"
  fi
  ditto "$SRC" "$dest"
}

install_one "$HOME/Desktop/C-Switch.app"
install_one "$HOME/Applications/C-Switch.app"

open "$SRC"
echo "Installed build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SRC/Contents/Info.plist") — use this app, not an older copy."
