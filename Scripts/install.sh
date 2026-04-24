#!/usr/bin/env bash
# Build Focus.app, copy it to /Applications, and symlink the binary
# inside it to /usr/local/bin/focus so the CLI works from the shell.

set -euo pipefail

cd "$(dirname "$0")/.."

./Scripts/build-app.sh

APP_SRC="./Focus.app"
APP_DEST="/Applications/Focus.app"
BIN_INSIDE="$APP_DEST/Contents/MacOS/focus"
CLI_LINK="/usr/local/bin/focus"

echo "==> installing $APP_DEST"
sudo rm -rf "$APP_DEST"
sudo cp -R "$APP_SRC" "$APP_DEST"

# Local builds are unsigned; strip the quarantine flag so Gatekeeper doesn't
# block the first open. (Not a no-op for apps downloaded from the web.)
sudo xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true

echo "==> symlinking $CLI_LINK -> $BIN_INSIDE"
sudo mkdir -p "$(dirname "$CLI_LINK")"
sudo ln -sf "$BIN_INSIDE" "$CLI_LINK"

echo
echo "Installed. Next:"
echo "  open /Applications/Focus.app   # launch the menu bar app"
echo
echo "The first time you toggle the block, Focus will prompt for your"
echo "admin password to install /etc/sudoers.d/focus. After that, all"
echo "Hyper+B toggles and pomodoro auto-blocks run without prompting."
