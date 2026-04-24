#!/usr/bin/env bash
# Install /etc/sudoers.d/focus so block/unblock/toggle don't prompt for a password.
# Validates the file with `visudo -cf` before installing — a bad rule is never written.

set -euo pipefail

BIN="${FOCUS_BIN:-/usr/local/bin/focus}"

if [[ ! -x "$BIN" ]]; then
  echo "error: $BIN not found or not executable." >&2
  echo "Point FOCUS_BIN at the focus binary, or run Scripts/install.sh first." >&2
  exit 1
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

cat > "$TMP" <<EOF
$(whoami) ALL=(root) NOPASSWD: \\
    $BIN block, \\
    $BIN unblock, \\
    $BIN toggle, \\
    $BIN toggle --json
EOF

if ! /usr/sbin/visudo -c -f "$TMP" >/dev/null; then
  echo "error: generated sudoers file failed syntax check." >&2
  cat "$TMP" >&2
  exit 1
fi

sudo install -o root -g wheel -m 0440 "$TMP" /etc/sudoers.d/focus
echo "Installed /etc/sudoers.d/focus for $BIN"
