#!/usr/bin/env bash
# Assemble an unsigned Focus.app bundle around the release binary.
# The binary itself is dual-mode (CLI + menu bar app); the bundle only affects
# how macOS presents it (LSUIElement hides the Dock icon, Launch Services
# rules kick in, etc.).

set -euo pipefail

cd "$(dirname "$0")/.."

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

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                <string>Focus</string>
    <key>CFBundleDisplayName</key>         <string>Focus</string>
    <key>CFBundleIdentifier</key>          <string>com.nchourrout.focus</string>
    <key>CFBundleExecutable</key>          <string>focus</string>
    <key>CFBundleVersion</key>             <string>1</string>
    <key>CFBundleShortVersionString</key>  <string>0.2.0</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key>      <string>13.0</string>
    <key>LSUIElement</key>                 <true/>
    <key>NSPrincipalClass</key>            <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>    <string>Copyright © 2026 Nicolas Chourrout.</string>
</dict>
</plist>
EOF

echo "Built $APP"
