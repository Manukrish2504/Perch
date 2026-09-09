#!/bin/bash
# Builds Perch.app.
#
# Deliberately not SwiftPM: the Command Line Tools ship a PackageDescription whose
# interface and dylib disagree, so `swift build` cannot parse any manifest. A direct
# swiftc invocation has fewer moving parts, and the .app bundle is hand-assembled
# either way because there is no Xcode on this machine.
set -euo pipefail

cd "$(dirname "$0")"
APP="${1:-build/Perch.app}"
SDK="$(xcrun --show-sdk-path)"
CONFIG="${CONFIG:-release}"
[ "$CONFIG" = "debug" ] && OPT="-Onone -g" || OPT="-O"

echo "→ compiling ($CONFIG)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# shellcheck disable=SC2086
swiftc $OPT \
  -target arm64-apple-macos14.0 \
  -sdk "$SDK" \
  $(find Sources/Perch -name '*.swift' | sort) \
  -framework AppKit -framework SwiftUI -framework Charts \
  -lsqlite3 \
  -o "$APP/Contents/MacOS/Perch"

echo "→ writing Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Perch</string>
    <key>CFBundleDisplayName</key><string>Perch</string>
    <key>CFBundleIdentifier</key><string>dev.local.perch</string>
    <key>CFBundleExecutable</key><string>Perch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <!-- Accessory app: the notch shelf is the whole presence, so no Dock icon. -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# An ad-hoc signature is enough for a local build and keeps macOS from
# re-prompting for file access on every rebuild.
echo "→ signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"

echo "✓ built $APP"
