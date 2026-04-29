#!/usr/bin/env bash
# Assemble an unsigned Focus.app bundle around the release binary.
# The binary itself is dual-mode (CLI + menu bar app); the bundle only affects
# how macOS presents it (LSUIElement hides the Dock icon, Launch Services
# rules kick in, etc.).

set -euo pipefail

cd "$(dirname "$0")/.."

# Single source of truth for CFBundleShortVersionString. Override via env when
# building from a tag (e.g. release.yml passes FOCUS_VERSION=$(git describe)).
VERSION="${FOCUS_VERSION:-$(cat VERSION)}"

# `--show-bin-path` resolves the path without compiling, so we can look it up
# first and only invoke `swift build` once.
BIN_DIR="$(swift build -c release --show-bin-path)"
swift build -c release
BIN="$BIN_DIR/focus"

if [[ ! -x "$BIN" ]]; then
  echo "error: expected $BIN not found after build" >&2
  exit 1
fi

APP="./Focus.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/focus"

# Bundle.module resolves to this, alongside the binary.
if [[ -d "$BIN_DIR/Focus_Focus.bundle" ]]; then
  cp -R "$BIN_DIR/Focus_Focus.bundle" "$APP/Contents/MacOS/"
fi

# Generate AppIcon.icns from the inline Swift renderer. Building a real
# iconset (multiple sizes + @2x) so Finder, Dock, Launchpad, etc. all look
# crisp instead of relying on sips' single-size icns output.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
SRC_PNG="$ICONSET/icon-source.png"
swift Scripts/render-icon.swift "$SRC_PNG"
for s in 16 32 64 128 256 512 1024; do
  sips -z "$s" "$s" "$SRC_PNG" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
done
cp "$ICONSET/icon_32x32.png"     "$ICONSET/icon_16x16@2x.png"
cp "$ICONSET/icon_64x64.png"     "$ICONSET/icon_32x32@2x.png"
cp "$ICONSET/icon_256x256.png"   "$ICONSET/icon_128x128@2x.png"
cp "$ICONSET/icon_512x512.png"   "$ICONSET/icon_256x256@2x.png"
cp "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"
rm "$SRC_PNG"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"
rm -rf "$(dirname "$ICONSET")"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                <string>Focus</string>
    <key>CFBundleDisplayName</key>         <string>Focus</string>
    <key>CFBundleIdentifier</key>          <string>com.nchourrout.focus</string>
    <key>CFBundleExecutable</key>          <string>focus</string>
    <key>CFBundleIconFile</key>            <string>AppIcon</string>
    <key>CFBundleVersion</key>             <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>  <string>${VERSION}</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key>      <string>13.0</string>
    <key>LSUIElement</key>                 <true/>
    <key>NSPrincipalClass</key>            <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>    <string>Copyright © 2026 Nicolas Chourrout.</string>
</dict>
</plist>
EOF

echo "Built $APP (version $VERSION)"
