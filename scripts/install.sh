#!/bin/bash
# Builds Swapling and installs it to ~/Applications, then restarts it from there.
# Running the app from dist/ means running it from inside ~/Documents, a folder macOS guards:
# the app and its CodexBar helper read their bundled resources there, and because each build is
# ad-hoc signed with a new code hash, macOS forgets the grant and asks for "Documents" again.
# ~/Applications is not guarded, so the installed copy never asks.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/bundle.sh

DEST="$HOME/Applications/Swapling.app"
osascript -e 'quit app id "dev.swapling.app"' >/dev/null 2>&1 || true
# Also stop a copy started straight from its binary (e.g. with --demo), which ignores quit.
pkill -x Swapling >/dev/null 2>&1 || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto dist/Swapling.app "$DEST"
codesign --verify --strict "$DEST"
open "$DEST"
echo "Installed and opened $DEST"
