#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

# Signs SA-Sur with a Developer ID certificate, has Apple notarize it, and
# staples the ticket to the app, so it opens on anyone's Mac without the
# "Apple could not verify" block. That block is Gatekeeper refusing a
# quarantined app whose signature is not a Developer ID and which carries no
# notarization ticket; nothing in the source code affects it.
#
# ONE-OFF PREPARATION, IN YOUR OWN TERMINAL. Never paste these secrets anywhere
# else, including into a chat:
#
#   1. A paid Apple Developer Program membership, and a "Developer ID Application"
#      certificate in your login keychain (developer.apple.com, or Xcode >
#      Settings > Accounts > Manage Certificates > +). Check what you have:
#        security find-identity -v -p codesigning
#      If the identity is listed but there are 0 *valid* identities, the chain is
#      broken: import Apple's "Developer ID - G2" intermediate from
#      apple.com/certificateauthority into the login keychain.
#
#   2. Notarization credentials in the keychain (it prompts for the password, so
#      nothing sensitive is ever written into a file). Use an app-specific
#      password from appleid.apple.com > Sign-In and Security:
#        xcrun notarytool store-credentials "notefrequency" \
#            --apple-id "you@example.com" --team-id "ABCDE12345"
#
# usage: tools/notarize.sh "Developer ID Application: Your Name (ABCDE12345)"
#        (run ./build.sh first; this re-signs the app it produced)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/SA-Sur.app"
PROFILE="${NOTARY_PROFILE:-notefrequency}"
IDENTITY="${1:-}"

if [ ! -d "$APP" ]; then
    echo "No app at $APP - run ./build.sh first." >&2
    exit 1
fi

if [ -z "$IDENTITY" ]; then
    echo "usage: tools/notarize.sh \"Developer ID Application: Your Name (TEAMID)\"" >&2
    echo
    echo "Signing identities available on this Mac:" >&2
    security find-identity -v -p codesigning >&2 || true
    echo
    echo "No Developer ID certificate is a hard blocker: notarization requires one," >&2
    echo "and it requires a paid Apple Developer Program membership." >&2
    exit 2
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/Info.plist")"
STAGE="$ROOT/build/notarize-upload.zip"
OUT="$ROOT/build/SA-Sur-$VERSION-notarized.zip"

echo "==> re-signing with hardened runtime (required for notarization) and a secure timestamp"
codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign -dvvv "$APP" 2>&1 | grep -E "Identifier|Authority|TeamIdentifier|flags" || true

echo "==> checking the keychain profile '$PROFILE' exists"
if ! xcrun notarytool history --keychain-profile "$PROFILE" > /dev/null 2>&1; then
    echo "Notarization credentials for profile '$PROFILE' are missing or invalid." >&2
    echo "Create them once with: xcrun notarytool store-credentials \"$PROFILE\" --apple-id ... --team-id ..." >&2
    exit 3
fi

echo "==> submitting to Apple (this waits for the result; typically a few minutes)"
rm -f "$STAGE"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGE"
xcrun notarytool submit "$STAGE" --keychain-profile "$PROFILE" --wait

echo "==> stapling the ticket into the app so it validates offline"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Gatekeeper verdict (want: accepted, source=Notarized Developer ID)"
spctl -a -vvv -t exec "$APP"

echo "==> repackaging - the zip must be rebuilt AFTER stapling to include the ticket"
rm -f "$OUT"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"
ls -lh "$OUT"
echo "==> done: send $OUT"
