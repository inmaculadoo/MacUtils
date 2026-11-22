#!/usr/bin/env bash
# Builds build/Ligero.app from the SwiftPM executable and signs it.
#
#   SIGN_ID="Ligero Dev" scripts/bundle.sh   # stable signature: TCC permissions survive rebuilds
#   scripts/bundle.sh                        # ad-hoc signature: permissions are lost on every build
set -euo pipefail

cd "$(dirname "$0")/.."

ARCH="arm64"
APP="build/Ligero.app"
SIGN_ID="${SIGN_ID:--}"

echo "==> Checking localizations"
for strings in Resources/*.lproj/*.strings; do
    plutil -lint "$strings"
done
plutil -lint Resources/Info.plist

echo "==> Building (release, $ARCH)"
swift build -c release --arch "$ARCH" --product Ligero
BIN_DIR="$(swift build -c release --arch "$ARCH" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Ligero" "$APP/Contents/MacOS/Ligero"
cp Resources/Info.plist "$APP/Contents/Info.plist"
for lproj in Resources/*.lproj; do
    cp -R "$lproj" "$APP/Contents/Resources/"
done
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing with identity: $SIGN_ID"
codesign --force --sign "$SIGN_ID" --identifier app.allinone --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"

lipo -archs "$APP/Contents/MacOS/Ligero"
echo "==> Done: $APP"
