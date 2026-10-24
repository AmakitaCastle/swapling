#!/bin/bash
# Builds Swapling and wraps it into dist/Swapling.app (ad-hoc signed), with the
# CodexBar CLI bundled in Contents/Helpers so users don't need to install CodexBar.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

./scripts/fetch-codexbar-cli.sh
CLI_VERSION="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' scripts/fetch-codexbar-cli.sh)"
CLI_DIR=".cache/codexbar-cli/${CLI_VERSION}/arm64"

# Apple silicon only, matching the bundled CLI.
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Swapling"

APP="dist/Swapling.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Swapling"

# Inside an .app the CLI's Bundle.main is the enclosing app, so it finds its resource bundle
# in Contents/Resources (sealed by the app signature, unlike a bundle next to the helper).
cp "$CLI_DIR/CodexBarCLI" "$APP/Contents/Helpers/CodexBarCLI"
cp -R "$CLI_DIR/CodexBar_CodexBarCore.bundle" "$APP/Contents/Resources/"
cp "$CLI_DIR/THIRD_PARTY_NOTICES" "$APP/Contents/Resources/CodexBarCLI-THIRD_PARTY_NOTICES.txt"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
# Provider icons from CodexBar (monochrome SVGs, loaded as template images).
cp -R Resources/ProviderIcons "$APP/Contents/Resources/ProviderIcons"
cp Resources/Brand/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/Characters "$APP/Contents/Resources/Characters"
# Fusion Pixel Font (OFL-1.1) for the panel, registered at launch; licenses travel with it.
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Swapling</string>
    <key>CFBundleDisplayName</key><string>Swapling</string>
    <key>CFBundleIdentifier</key><string>dev.swapling.app</string>
    <key>CFBundleExecutable</key><string>Swapling</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Nested code first, then the app.
codesign --force --sign - --identifier dev.swapling.codexbar-cli "$APP/Contents/Helpers/CodexBarCLI" >/dev/null
codesign --force --sign - "$APP" >/dev/null
codesign --verify --strict "$APP"
echo "Built $APP"
echo "Run: open $APP"
