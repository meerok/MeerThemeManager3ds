#!/bin/bash
# Builds "Meer Theme Manager 3ds.app" (MtM3) into ./build
set -e
cd "$(dirname "$0")"

echo "▸ Compiling MtM3 (release)…"
swift build -c release --product MtM3
swift build -c release --product mtm3-cli
BIN="$(swift build -c release --show-bin-path)"

APP="build/Meer Theme Manager 3ds.app"
echo "▸ Packaging $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/MtM3" "$APP/Contents/MacOS/MtM3"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Logo.png "$APP/Contents/Resources/Logo.png"
cp "$BIN/mtm3-cli" build/mtm3-cli

echo "▸ Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "✓ Done: $(pwd)/$APP"
echo "  Drag it into /Applications, or run: open \"$APP\""
