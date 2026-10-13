#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

# Full verification: maths + DSP tests, end-to-end audio graph check, UI render.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="$ARCH-apple-macos13.0"
mkdir -p "$ROOT/build/tools"

echo "############ 1/4  maths + oscillator tests ############"
"$ROOT/test.sh"

echo
echo "############ 2/4  audio graph smoke test ############"
swiftc -O -target "$TARGET" -sdk "$SDK" \
    "$ROOT/src/NoteMath.swift" \
    "$ROOT/src/SineOscillator.swift" \
    "$ROOT/src/ToneGenerator.swift" \
    "$ROOT/tools/audio-smoke/main.swift" \
    -o "$ROOT/build/tools/AudioSmoke"
"$ROOT/build/tools/AudioSmoke"

echo
echo "############ 3/4  UI render ############"
"$ROOT/tools/stage-logos.sh" > /dev/null
swiftc -O -target "$TARGET" -sdk "$SDK" \
    "$ROOT/src/NoteMath.swift" \
    "$ROOT/src/SineOscillator.swift" \
    "$ROOT/src/ToneGenerator.swift" \
    "$ROOT/src/Views.swift" \
    "$ROOT/tools/screenshot/main.swift" \
    -o "$ROOT/build/tools/Snapshot"
SASUR_LOGOS="$ROOT/build/logos" "$ROOT/build/tools/Snapshot" "$ROOT/build/ui-snapshot"

echo
echo "############ 4/4  manual ############"
# Rebuilds the manual's HTML from docs/MANUAL.md and reads the shipped PDF back:
# page count, page size, the sections a reader navigates by, all 108 frequencies
# against docs/note-table.csv, and the house style (no em dashes, no banned words).
"$ROOT/tools/manual.sh"

echo
echo "VERIFY: all stages completed"
