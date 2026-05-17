#!/usr/bin/env bash
# Build, sign, and launch C-Switch (menu bar app — look for ⇄ in the top-right).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/C-Switch.app"

"$ROOT/scripts/package_app.sh"
killall C-Switch 2>/dev/null || true
xattr -cr "$APP" 2>/dev/null || true
open -n "$APP"

echo "Launched. Check the menu bar for the ⇄ icon (no Dock icon)."
