#!/usr/bin/env bash
# Build a release binary and symlink it to /usr/local/bin/focus.
#
# Phase 1 only ships a CLI binary. Later phases will assemble a real
# Focus.app bundle and install that; this script stays as a fallback.

set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> swift build -c release"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/focus"
TARGET="/usr/local/bin/focus"

if [[ ! -x "$BIN" ]]; then
  echo "error: expected $BIN not found after build" >&2
  exit 1
fi

echo "==> symlinking $TARGET -> $BIN"
sudo ln -sf "$BIN" "$TARGET"

echo "Installed. Test with: focus status"
echo "Next: Scripts/install-sudoers.sh  (needs FOCUS_BIN=$TARGET by default)"
