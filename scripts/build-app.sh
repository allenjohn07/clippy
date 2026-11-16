#!/usr/bin/env bash
# Builds build/Clippy.app (and build/Clippy.zip with --zip).
#   UNIVERSAL=1  build for both Apple Silicon and Intel (needs full Xcode)
#   VERSION=1.2.3  override the version (defaults to the latest git tag)
#   CODESIGN_IDENTITY="My Cert"  sign with a real/self-signed identity instead of ad-hoc
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="io.github.allenjohn07.clippy"
APP="build/Clippy.app"

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null || echo 0.0.0)}"
VERSION="${VERSION#v}"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || VERSION="0.0.0"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi

echo "==> Building clippy $VERSION"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/clippy" "$APP/Contents/MacOS/clippy"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # regenerate: swift scripts/make-icon.swift

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>Clippy</string>
    <key>CFBundleDisplayName</key>          <string>Clippy</string>
    <key>CFBundleIdentifier</key>           <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>           <string>clippy</string>
    <key>CFBundleIconFile</key>             <string>AppIcon</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleShortVersionString</key>   <string>${VERSION}</string>
    <key>CFBundleVersion</key>              <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>       <string>13.0</string>
    <key>LSUIElement</key>                  <true/>
    <key>NSHumanReadableCopyright</key>     <string>MIT License</string>
</dict>
</plist>
PLIST

IDENTITY="${CODESIGN_IDENTITY:--}"
echo "==> Signing (identity: ${IDENTITY/#-/ad-hoc})"
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"

if [[ "${1:-}" == "--zip" ]]; then
    rm -f build/Clippy.zip
    ditto -c -k --keepParent "$APP" build/Clippy.zip
    echo "==> build/Clippy.zip"
fi
echo "==> Done: $APP"
