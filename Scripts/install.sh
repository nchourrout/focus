#!/usr/bin/env bash
# Build Focus.app, copy it to /Applications, and symlink the inner binary to
# /usr/local/bin/focus. Privileged steps go through `osascript ... with
# administrator privileges`, which surfaces the standard macOS password dialog
# and works equally well from a regular terminal or from a non-TTY shell.

set -euo pipefail

cd "$(dirname "$0")/.."

./Scripts/build-app.sh

APP_SRC="$(pwd)/Focus.app"
APP_DEST="/Applications/Focus.app"
BIN_INSIDE="$APP_DEST/Contents/MacOS/focus"
CLI_LINK="/usr/local/bin/focus"
# Root-owned copy the sudoers rule trusts (see SudoersInstaller.swift). Only
# refreshed when a previous grant created it; the first grant happens in-app.
HELPER_DIR="/Library/PrivilegedHelperTools/com.nchourrout.focus"

INSTALL_CMD="/bin/rm -rf '$APP_DEST' && \
/bin/cp -R '$APP_SRC' '$APP_DEST' && \
( /usr/bin/xattr -dr com.apple.quarantine '$APP_DEST' || true ) && \
/bin/mkdir -p '$(dirname "$CLI_LINK")' && \
/bin/ln -sf '$BIN_INSIDE' '$CLI_LINK' && \
if [ -d '$HELPER_DIR' ]; then \
  /bin/rm -rf '$HELPER_DIR' && /bin/mkdir -m 755 '$HELPER_DIR' && \
  /bin/cp -R '$APP_DEST/Contents/MacOS/' '$HELPER_DIR/' && \
  /usr/sbin/chown -R root:wheel '$HELPER_DIR' && /bin/chmod -R go-w '$HELPER_DIR'; \
fi"

echo "==> installing $APP_DEST (admin password dialog will appear)"
osascript -e "do shell script \"$INSTALL_CMD\" with administrator privileges" >/dev/null

echo
echo "Installed. Next:"
echo "  open /Applications/Focus.app   # launch the menu bar app"
echo
echo "First time you toggle the block, Focus will prompt for your"
echo "admin password again to install /etc/sudoers.d/focus. After that,"
echo "all toggles and pomodoro auto-blocks run without prompting."
