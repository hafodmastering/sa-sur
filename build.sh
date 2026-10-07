#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

# Builds SA-Sur.app as a universal binary (arm64 + x86_64), assembles the
# bundle by hand, generates the icon, ad-hoc signs it and zips it for transfer.
# Requires only Command Line Tools - no Xcode, no project file.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="$(xcrun --show-sdk-path)"
BUILD="$ROOT/build"
APP="$BUILD/SA-Sur.app"
VERSION="1.0"
MIN_MACOS="13.0"
ARCHS="arm64 x86_64"
SOURCES=("$ROOT/src/NoteMath.swift" "$ROOT/src/SineOscillator.swift" "$ROOT/src/ToneGenerator.swift" "$ROOT/src/Views.swift" "$ROOT/src/App.swift")

rm -rf "$BUILD/slices" "$APP" "$BUILD/AppIcon.icns" "$BUILD/SA-Sur-$VERSION-universal.zip"
mkdir -p "$BUILD/slices"

for ARCH in $ARCHS; do
    echo "==> compiling $ARCH (minos $MIN_MACOS)"
    swiftc -O -parse-as-library \
        -target "$ARCH-apple-macos$MIN_MACOS" \
        -sdk "$SDK" \
        "${SOURCES[@]}" \
        -o "$BUILD/slices/SA-Sur-$ARCH"
done

echo "==> lipo"
lipo -create -output "$BUILD/SA-Sur" "$BUILD"/slices/SA-Sur-arm64 "$BUILD"/slices/SA-Sur-x86_64
lipo -info "$BUILD/SA-Sur"

echo "==> icon"
mkdir -p "$BUILD/icon"
swiftc -O -target "$(uname -m)-apple-macos$MIN_MACOS" -sdk "$SDK" \
    "$ROOT/tools/MakeIcon.swift" -o "$BUILD/icon/MakeIcon"
# MakeIcon takes the silhouette from the artwork's alpha channel (a black tile on
# transparency has no brightness difference to measure) and fits it to Apple's
# icon grid. It re-reads its own output, so a bad icon fails the build.
"$BUILD/icon/MakeIcon" "$ROOT/logos/SA-Sur app logo.png" "$BUILD/icon/master-1024.png" 1024 grid > /dev/null
ICONSET="$BUILD/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16     "$BUILD/icon/master-1024.png" --out "$ICONSET/icon_16x16.png"      > /dev/null
sips -z 32 32     "$BUILD/icon/master-1024.png" --out "$ICONSET/icon_16x16@2x.png"   > /dev/null
sips -z 32 32     "$BUILD/icon/master-1024.png" --out "$ICONSET/icon_32x32.png"      > /dev/null
sips -z 64 64     "$BUILD/icon/master-1024.png" --out "$ICONSET/icon_32x32@2x.png"   > /dev/null
sips -z 128 128   "$BUILD/icon/master-1024.png" --out "$ICONSET/icon_128x128.png"    > /dev/null
sips -z 256 256   "$BUILD/icon/master-1024.png" --out "$ICONSET/icon_128x128@2x.png" > /dev/null
sips -z 256 256   "$BUILD/icon/master-1024.png" --out "$ICONSET/icon_256x256.png"    > /dev/null
sips -z 512 512   "$BUILD/icon/master-1024.png" --out "$ICONSET/icon_256x256@2x.png" > /dev/null
sips -z 512 512   "$BUILD/icon/master-1024.png" --out "$ICONSET/icon_512x512.png"    > /dev/null
cp "$BUILD/icon/master-1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$BUILD/AppIcon.icns"
cp "$BUILD/icon/master-1024.png" "$BUILD/AppIcon-1024.png"

echo "==> logos"
"$ROOT/tools/stage-logos.sh" > /dev/null

echo "==> assembling bundle"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/SA-Sur" "$APP/Contents/MacOS/SA-Sur"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$BUILD/logos/sudeep-audio.png" "$BUILD/logos/hafod-mastering.png" "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist"

echo "==> bundle resources"
ls -1 "$APP/Contents/Resources"

echo "==> ad-hoc signing"
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP" 2>&1 | tail -3

echo "==> checking bundle contents resolve"
swiftc -O -target "$(uname -m)-apple-macos$MIN_MACOS" -sdk "$SDK" "$ROOT/tools/CheckBundle.swift" -o "$BUILD/icon/CheckBundle"
"$BUILD/icon/CheckBundle" "$APP"

echo "==> verifying architecture and deployment target"
lipo -info "$APP/Contents/MacOS/SA-Sur"
vtool -show-build "$APP/Contents/MacOS/SA-Sur" | grep -E "platform|minos|sdk"

echo "==> zipping for transfer"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$BUILD/SA-Sur-$VERSION-universal.zip"
ls -lh "$BUILD/SA-Sur-$VERSION-universal.zip"
echo "==> done: $APP"
