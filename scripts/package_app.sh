#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/C-Switch.app"
BINARY_NAME="C-Switch"
EXEC="$APP/Contents/MacOS/$BINARY_NAME"

cd "$ROOT"
"$ROOT/scripts/build_app_icon.sh"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BIN="$ROOT/.build/arm64-apple-macosx/release/C-Switch"
if [[ ! -f "$BIN" ]]; then
  BIN="$ROOT/.build/release/C-Switch"
fi
if [[ ! -f "$BIN" ]]; then
  echo "error: release binary not found" >&2
  exit 1
fi

cp "$BIN" "$EXEC"
chmod +x "$EXEC"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>C-Switch</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.cswitch.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>C-Switch</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>2</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

xattr -cr "$APP" 2>/dev/null || true
codesign --remove-signature "$EXEC" 2>/dev/null || true
codesign --force --sign - --identifier com.cswitch.app --timestamp=none "$EXEC"
codesign --force --sign - --identifier com.cswitch.app --timestamp=none "$APP"

if ! codesign --verify --deep --strict "$APP" 2>/dev/null; then
  echo "warning: codesign verify reported issues (app may still run locally)" >&2
fi

echo "Built $APP (Dock icon enabled)"
echo "Tip: drag to Applications, or: open \"$APP\""
