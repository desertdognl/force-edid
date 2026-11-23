#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Force EDID.app"
MACOS="$APP/Contents/MacOS"
SOURCES=("$ROOT"/Sources/*.swift)
SDK="$(xcrun --show-sdk-path --sdk macosx)"
MINOS="14.0"

echo "Building Force EDID…"
rm -rf "$APP"
mkdir -p "$MACOS"
mkdir -p "$APP/Contents/Resources"

compile() {
  local target="$1"
  local output="$2"
  swiftc \
    -parse-as-library \
    -O \
    -target "$target" \
    -sdk "$SDK" \
    -framework SwiftUI \
    -framework AppKit \
    -framework IOKit \
    -framework CoreGraphics \
    -framework ServiceManagement \
    -framework UniformTypeIdentifiers \
    -o "$output" \
    "${SOURCES[@]}"
}

ARM_BIN="$BUILD/ForceEDID-arm64"
X86_BIN="$BUILD/ForceEDID-x86_64"
compile "arm64-apple-macos${MINOS}" "$ARM_BIN"
compile "x86_64-apple-macos${MINOS}" "$X86_BIN"
lipo -create -output "$MACOS/ForceEDID" "$ARM_BIN" "$X86_BIN"
rm -f "$ARM_BIN" "$X86_BIN"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

APPINFO="$ROOT/Sources/AppInfo.swift"
VERSION="$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' "$APPINFO" | head -1)"
BUILDNUM="$(sed -n 's/.*static let build = "\([^"]*\)".*/\1/p' "$APPINFO" | head -1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILDNUM" "$APP/Contents/Info.plist"
echo "Version $VERSION ($BUILDNUM) universal (arm64 + x86_64)"

# Ad-hoc sign so Gatekeeper treats it as a local app, without sandboxing.
codesign --force --deep --sign - \
  --entitlements "$ROOT/Resources/ForceEDID.entitlements" \
  "$APP" >/dev/null

DIST="$ROOT/dist"
ZIP="$DIST/Force-EDID-${VERSION}-macos-universal.zip"
PKG="$DIST/Force-EDID-${VERSION}-macos-universal.pkg"
mkdir -p "$DIST"

# Drop previous local packages so dist/ only holds the current release.
setopt +o nomatch
rm -f "$DIST"/Force-EDID-*.zip "$DIST"/Force-EDID-*.pkg "$DIST"/Force-EDID-*.dmg
setopt -o nomatch

ditto -c -k --keepParent --norsrc "$APP" "$ZIP"

# Installer package → /Applications/Force EDID.app
pkgbuild \
  --component "$APP" \
  --install-location /Applications \
  --identifier com.fcu.ForceEDID \
  --version "$VERSION" \
  "$PKG" >/dev/null

echo "Built: $APP"
echo "Zip:   $ZIP"
echo "Pkg:   $PKG"
file "$MACOS/ForceEDID"
echo
echo "Open it with:"
echo "  open \"$APP\""
echo
echo "Install with:"
echo "  open \"$PKG\""
echo
echo "CLI:"
echo "  \"$MACOS/ForceEDID\" --help"
