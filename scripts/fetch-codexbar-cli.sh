#!/bin/bash
# Downloads the pinned CodexBar CLI release for Apple silicon, verifies its checksum, and
# unpacks it for bundle.sh to ship inside the app. Swapling only supports Apple silicon Macs.
# Output: .cache/codexbar-cli/<version>/arm64/{CodexBarCLI,CodexBar_CodexBarCore.bundle,...}
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.77.0"
SHA256="e9e6ac95e358402d488ad3cb4eba4f49ad2967d83ce7c87d82727145f1a95764"
TARBALL="CodexBarCLI-v${VERSION}-macos-arm64.tar.gz"
URL="https://github.com/steipete/CodexBar/releases/download/v${VERSION}/${TARBALL}"

CACHE=".cache/codexbar-cli/${VERSION}"
OUT="$CACHE/arm64"

if [ -x "$OUT/CodexBarCLI" ] && [ "$(cat "$OUT/VERSION" 2>/dev/null)" = "$VERSION" ]; then
    echo "CodexBar CLI ${VERSION} already prepared: $OUT"
    exit 0
fi

mkdir -p "$CACHE"
if [ ! -f "$CACHE/$TARBALL" ]; then
    echo "Downloading $TARBALL"
    curl -fsSL --retry 3 -o "$CACHE/$TARBALL.part" "$URL"
    mv "$CACHE/$TARBALL.part" "$CACHE/$TARBALL"
fi

actual="$(shasum -a 256 "$CACHE/$TARBALL" | awk '{print $1}')"
if [ "$actual" != "$SHA256" ]; then
    echo "Checksum mismatch for $TARBALL" >&2
    echo "  expected $SHA256" >&2
    echo "  actual   $actual" >&2
    rm -f "$CACHE/$TARBALL"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
tar -xzf "$CACHE/$TARBALL" -C "$OUT"
# Upstream's standalone binary has no Developer ID signature (only the linker's ad-hoc one);
# bundle.sh re-signs it ad hoc inside the app.
if [ "$(cat "$OUT/VERSION")" != "$VERSION" ]; then
    echo "Unexpected VERSION in $TARBALL: $(cat "$OUT/VERSION")" >&2
    exit 1
fi

echo "Prepared CodexBar CLI ${VERSION} (arm64): $OUT"
