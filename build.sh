#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Force EDID.app"
MACOS="$APP/Contents/MacOS"
SOURCES=("$ROOT"/Sources/*.swift)
SDK="$(xcrun --show-sdk-path --sdk macosx)"
TARGET="arm64-apple-macos14.0"

echo "Building Force EDID…"
rm -rf "$APP"
mkdir -p "$MACOS"
mkdir -p "$APP/Contents/Resources"

swiftc \
  -parse-as-library \
  -O \
  -target "$TARGET" \
  -sdk "$SDK" \
  -framework SwiftUI \
  -framework AppKit \
  -framework IOKit \
  -framework CoreGraphics \
  -framework ServiceManagement \
  -framework UniformTypeIdentifiers \
  -o "$MACOS/ForceEDID" \
  "${SOURCES[@]}"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

APPINFO="$ROOT/Sources/AppInfo.swift"
VERSION="$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' "$APPINFO" | head -1)"
BUILD="$(sed -n 's/.*static let build = "\([^"]*\)".*/\1/p' "$APPINFO" | head -1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
echo "Version $VERSION ($BUILD)"

# Ad-hoc sign so Gatekeeper treats it as a local app, without sandboxing.
codesign --force --deep --sign - \
  --entitlements "$ROOT/Resources/ForceEDID.entitlements" \
  "$APP" >/dev/null

DIST="$ROOT/dist"
ZIP="$DIST/Force-EDID-${VERSION}-macos-arm64.zip"
mkdir -p "$DIST"
rm -f "$ZIP"
ditto -c -k --keepParent --norsrc "$APP" "$ZIP"

echo "Built: $APP"
echo "Zip:   $ZIP"
echo
echo "Open it with:"
echo "  open \"$APP\""
echo
echo "CLI:"
echo "  \"$MACOS/ForceEDID\" --help"
