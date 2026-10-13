#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

# Builds the Mac App Store variant of SA-Sur: the same sources and the same
# icon/mark pipeline as build.sh, but assembled sandboxed (SASur.entitlements),
# with the privacy manifest embedded (PrivacyInfo.xcprivacy), signed with an
# Apple Distribution identity and wrapped in a Mac Installer Distribution-signed
# .pkg ready for Transporter.
#
# This is a second pipeline, not an extension of the direct-download one: the
# direct download keeps building exactly as it does today (build.sh) and its
# notarized zip is a different artifact. See docs/APPSTORE.md.
#
# usage: tools/store-build.sh            # full store build + signed .pkg
#        tools/store-build.sh --smoke    # local sandbox smoke build: ad-hoc
#                                        # signed, no profile, no package
#
# The full build needs, on this Mac:
#   - "Apple Distribution: Sudeep Audio.com LLP (E37W7LU474)"     (login keychain)
#   - "Mac Installer Distribution: Sudeep Audio.com LLP (E37W7LU474)"
#   - the Mac App Store provisioning profile for the App ID, saved at the path
#     in STORE_PROFILE (default: build/embedded.provisionprofile)
# The smoke build needs none of these.
#
# Override via environment: STORE_APP_IDENTITY, STORE_PKG_IDENTITY, STORE_PROFILE.
#
# Note: an unattended run can hang on a keychain approval dialog if the signing
# key's access control has no allow-list entry (see docs/RELEASE.md).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --show-sdk-path)"
BUILD="$ROOT/build/store"
APP="$BUILD/SA-Sur.app"
TEAM_ID="E37W7LU474"
MIN_MACOS="13.0"
ARCHS="arm64 x86_64"
SOURCES=("$ROOT/src/NoteMath.swift" "$ROOT/src/SineOscillator.swift" "$ROOT/src/ToneGenerator.swift" "$ROOT/src/Views.swift" "$ROOT/src/App.swift")
ENTITLEMENTS="$ROOT/SASur.entitlements"
MANIFEST="$ROOT/PrivacyInfo.xcprivacy"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$ROOT/Info.plist")"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$ROOT/Info.plist")"

MODE="store"
if [ "${1:-}" = "--smoke" ]; then
    MODE="smoke"
elif [ -n "${1:-}" ]; then
    echo "usage: tools/store-build.sh [--smoke]" >&2
    exit 1
fi

STORE_APP_IDENTITY="${STORE_APP_IDENTITY:-Apple Distribution: Sudeep Audio.com LLP ($TEAM_ID)}"
# Apple keeps the legacy common name for the Mac installer certificate type
# ("Mac Installer Distribution" in the portal, "3rd Party Mac Developer
# Installer" in the issued certificate), so accept either label.
STORE_PKG_IDENTITY="${STORE_PKG_IDENTITY:-Mac Installer Distribution: Sudeep Audio.com LLP ($TEAM_ID)}"
STORE_PKG_IDENTITIES=("$STORE_PKG_IDENTITY" "3rd Party Mac Developer Installer: Sudeep Audio.com LLP ($TEAM_ID)")
PROFILE="${STORE_PROFILE:-$ROOT/build/embedded.provisionprofile}"
PKG="$BUILD/SA-Sur-$VERSION-store.pkg"

echo "==> SA-Sur $VERSION (build $BUILD_NUMBER), mode: $MODE"

if [ "$MODE" = "store" ]; then
    echo "==> checking certificates and profile"
    IDENTITIES_APP="$(security find-identity -v -p codesigning 2>&1 || true)"
    if [[ "$IDENTITIES_APP" != *"$STORE_APP_IDENTITY"* ]]; then
        echo "FAIL: app identity not in the keychain: $STORE_APP_IDENTITY" >&2
        printf '%s\n' "$IDENTITIES_APP" >&2
        exit 2
    fi
    # Mac installer identities: the portal calls the type "Mac Installer
    # Distribution" but Apple issues the legacy common name, so try both.
    IDENTITIES_ALL="$(security find-identity -v 2>&1 || true)"
    PKG_IDENTITY=""
    for candidate in "${STORE_PKG_IDENTITIES[@]}"; do
        if [[ "$IDENTITIES_ALL" == *"$candidate"* ]]; then
            PKG_IDENTITY="$candidate"
            break
        fi
    done
    if [ -z "$PKG_IDENTITY" ]; then
        echo "FAIL: installer identity not in the keychain (tried: ${STORE_PKG_IDENTITIES[*]})" >&2
        printf '%s\n' "$IDENTITIES_ALL" >&2
        exit 2
    fi
    if [ ! -f "$PROFILE" ]; then
        echo "FAIL: provisioning profile not found: $PROFILE" >&2
        echo "Download the Mac App Store profile (Certificates, Identifiers & Profiles," >&2
        echo "Distribution > Mac App Store Connect) and save it there, or set STORE_PROFILE." >&2
        exit 2
    fi
    # The signature and the profile must agree on the application identifier
    # (Transporter error 90886). The entitlements file carries it explicitly
    # because this project signs by hand; keep it in step with Info.plist.
    ENT_APP_ID="$(/usr/libexec/PlistBuddy -c "Print :com.apple.application-identifier" "$ENTITLEMENTS" 2>/dev/null || true)"
    if [ "$ENT_APP_ID" != "$TEAM_ID.$BUNDLE_ID" ]; then
        echo "FAIL: $ENTITLEMENTS declares application-identifier '$ENT_APP_ID'," >&2
        echo "      but the bundle is $TEAM_ID.$BUNDLE_ID - App Store validation would reject it." >&2
        exit 2
    fi
    echo "    application-identifier $ENT_APP_ID (entitlements, profile and bundle agree)"
fi

rm -rf "$BUILD"
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
# The artwork arrives finished (see build.sh): MakeIcon takes the silhouette from
# its alpha channel and fits it to Apple's icon grid. CleanIcon was retired with
# the previous artwork.
"$BUILD/icon/MakeIcon" "$ROOT/logos/SA-Sur app logo.png" "$BUILD/icon/master-1024.png" 1024 grid > /dev/null
ICONSET="$BUILD/AppIcon.iconset"
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

echo "==> logos"
"$ROOT/tools/stage-logos.sh" "$BUILD/logos" > /dev/null

echo "==> assembling bundle"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/SA-Sur" "$APP/Contents/MacOS/SA-Sur"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$BUILD/logos/sudeep-audio.png" "$BUILD/logos/hafod-mastering.png" "$APP/Contents/Resources/"
cp "$MANIFEST" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"

echo "==> manual"
# docs/MANUAL.md -> docs/SA-Sur-User-Manual.pdf is rendered by tools/manual.sh,
# which also checks the PDF. The manual is a resource, so it has to be here before
# the signing step: a signed bundle cannot gain one afterwards, and the Help item
# in the app opens it by name.
if [ ! -f "$ROOT/docs/SA-Sur-User-Manual.pdf" ]; then
    echo "FAIL: no docs/SA-Sur-User-Manual.pdf - run tools/manual.sh" >&2
    exit 1
fi
cp "$ROOT/docs/SA-Sur-User-Manual.pdf" "$APP/Contents/Resources/SA-Sur-Manual.pdf"
printf 'APPL????' > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"

if [ "$MODE" = "store" ]; then
    echo "==> embedding provisioning profile"
    PROFILE_PLIST="$BUILD/profile.plist"
    if ! security cms -D -i "$PROFILE" > "$PROFILE_PLIST" 2>/dev/null; then
        echo "FAIL: could not decode $PROFILE as a provisioning profile" >&2
        exit 3
    fi
    PROFILE_NAME="$(/usr/libexec/PlistBuddy -c "Print :Name" "$PROFILE_PLIST" 2>/dev/null || echo '?')"
    PROFILE_EXPIRES="$(/usr/libexec/PlistBuddy -c "Print :ExpirationDate" "$PROFILE_PLIST" 2>/dev/null || echo '?')"
    echo "    $PROFILE_NAME (expires $PROFILE_EXPIRES)"
    if ! grep -q "$TEAM_ID" "$PROFILE_PLIST" || ! grep -q "$BUNDLE_ID" "$PROFILE_PLIST"; then
        echo "FAIL: profile does not cover $BUNDLE_ID for team $TEAM_ID" >&2
        exit 3
    fi
    cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
fi

echo "==> signing ($MODE)"
SIGN_ENTITLEMENTS="$BUILD/SA-Sur-$MODE.entitlements"
cp "$ENTITLEMENTS" "$SIGN_ENTITLEMENTS"
if [ "$MODE" = "smoke" ]; then
    # com.apple.application-identifier and the team identifier are restricted
    # entitlements: they are only valid with a provisioning profile, so an
    # ad-hoc smoke build must not carry them or it will not launch.
    /usr/libexec/PlistBuddy -c "Delete :com.apple.application-identifier" "$SIGN_ENTITLEMENTS" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.team-identifier" "$SIGN_ENTITLEMENTS" 2>/dev/null || true
fi
if [ "$MODE" = "store" ]; then
    codesign --force --options runtime --timestamp \
        --entitlements "$SIGN_ENTITLEMENTS" --sign "$STORE_APP_IDENTITY" "$APP"
else
    codesign --force --options runtime --timestamp=none \
        --entitlements "$SIGN_ENTITLEMENTS" --sign - "$APP"
fi
codesign --verify --strict --verbose=2 "$APP" 2>&1 | tail -3

echo "==> checking entitlements"
APP_ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
if [[ "$APP_ENTITLEMENTS" != *"com.apple.security.app-sandbox"* ]]; then
    echo "FAIL: app-sandbox entitlement missing from $APP" >&2
    exit 4
fi
echo "  OK  app-sandbox entitlement present"
if [ "$MODE" = "store" ]; then
    # App Store validation (Transporter error 90886) wants the application
    # identifier in the *signature*, not just in the embedded profile. Check the
    # signed result, not the input, so a signing change cannot slip past.
    if [[ "$APP_ENTITLEMENTS" == *"$TEAM_ID.$BUNDLE_ID"* ]]; then
        echo "  OK  application-identifier $TEAM_ID.$BUNDLE_ID is in the signature"
    else
        echo "FAIL: the signature carries no application-identifier for $TEAM_ID.$BUNDLE_ID." >&2
        echo "      App Store Connect rejects this build (Transporter error 90886)." >&2
        printf '%s\n' "$APP_ENTITLEMENTS" >&2
        exit 4
    fi
fi
# Capture the signature description once instead of piping it into `grep -q`:
# grep -q exits at the first match, codesign dies of SIGPIPE and `pipefail`
# would then report a perfectly good signature as a failure.
SIGN_INFO="$(codesign -dvvv "$APP" 2>&1 || true)"
printf '%s\n' "$SIGN_INFO" | grep -E "Identifier|Authority|TeamIdentifier|Signature" || true
if [ "$MODE" = "store" ] && [[ "$SIGN_INFO" != *"Apple Distribution"* ]]; then
    echo "FAIL: app not signed with an Apple Distribution certificate" >&2
    exit 4
fi

echo "==> checking bundle contents resolve"
swiftc -O -target "$(uname -m)-apple-macos$MIN_MACOS" -sdk "$SDK" "$ROOT/tools/CheckBundle.swift" -o "$BUILD/CheckBundle"
"$BUILD/CheckBundle" "$APP"

echo "==> checking privacy manifest declarations"
TRACKING="$(plutil -extract NSPrivacyTracking raw -o - "$APP/Contents/Resources/PrivacyInfo.xcprivacy")"
API_TYPE="$(plutil -extract NSPrivacyAccessedAPITypes.0.NSPrivacyAccessedAPIType raw -o - "$APP/Contents/Resources/PrivacyInfo.xcprivacy")"
API_REASON="$(plutil -extract NSPrivacyAccessedAPITypes.0.NSPrivacyAccessedAPITypeReasons.0 raw -o - "$APP/Contents/Resources/PrivacyInfo.xcprivacy")"
if [ "$TRACKING" = "false" ] && [ "$API_TYPE" = "NSPrivacyAccessedAPICategoryUserDefaults" ] && [ "$API_REASON" = "CA92.1" ]; then
    echo "  OK  no tracking; UserDefaults declared with reason CA92.1"
else
    echo "FAIL: manifest values unexpected (tracking=$TRACKING type=$API_TYPE reason=$API_REASON)" >&2
    exit 4
fi

echo "==> verifying architecture and deployment target"
lipo -info "$APP/Contents/MacOS/SA-Sur"
vtool -show-build "$APP/Contents/MacOS/SA-Sur" | grep -E "platform|minos|sdk"

if [ "$MODE" = "store" ]; then
    echo "==> stripping quarantine attributes (Apple upload requirement)"
    xattr -cr "$APP"
    if xattr -r "$APP" | grep -q "com.apple.quarantine"; then
        echo "FAIL: quarantine attributes remain under $APP" >&2
        exit 5
    fi

    echo "==> packaging with $PKG_IDENTITY"
    rm -f "$PKG"
    productbuild --sign "$PKG_IDENTITY" --component "$APP" /Applications "$PKG"

    echo "==> verifying package"
    pkgutil --check-signature "$PKG"
    pkgutil --payload-files "$PKG" | head -8
    ls -lh "$PKG"
    echo "==> done: upload $PKG with Transporter (store builds are not notarized or stapled)"
else
    echo "==> done: $APP"
    echo "    ad-hoc signed and sandboxed - first launch should create"
    echo "    ~/Library/Containers/$BUNDLE_ID (proof the sandbox is active)"
fi
