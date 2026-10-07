#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

# Stages the in-window marks under clean resource names (sudeep-audio.png /
# hafod-mastering.png). Both are the companies' own supplied artwork: MakeMark
# rounds Sudeep's flat red tile at Apple's icon radius and trims the one-pixel
# light edge the JPEG export carries; Hafod's transparent wordmark is resampled
# and otherwise untouched.
#
# usage: stage-logos.sh [destination-dir]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$ROOT/build/logos}"
mkdir -p "$DEST" "$ROOT/build/icon"

# The marks render 44 pt tall, so a 2x display wants 88 px; stage at 176 px for
# headroom. If logoHeight in Views.swift changes, change 176 with it.
swiftc -O -target "$(uname -m)-apple-macos13.0" -sdk "$(xcrun --show-sdk-path)" \
    "$ROOT/tools/MakeMark.swift" -o "$ROOT/build/icon/MakeMark"
"$ROOT/build/icon/MakeMark" "$ROOT/logos/Sudeep Audio logo square.jpg" "$DEST/sudeep-audio.png" 176

cp "$ROOT/logos/hafod_logo-transparent.png" "$DEST/hafod-mastering.png"
sips -Z 176 "$DEST/hafod-mastering.png" > /dev/null

echo "staged marks in $DEST:"
sips -g pixelWidth -g pixelHeight -g profile "$DEST/sudeep-audio.png" "$DEST/hafod-mastering.png" 2>/dev/null | grep -E "png|pixel|profile"
