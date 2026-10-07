#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

# Builds and runs the verification harness, then diffs the note table against an
# independent calculation. No Xcode required: swiftc from Command Line Tools only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
OUT="$ROOT/build/tests"
LOG="$ROOT/build/test-output.txt"
mkdir -p "$OUT"

echo "==> compiling tests (target $ARCH-apple-macos13.0)"
swiftc -O -target "$ARCH-apple-macos13.0" -sdk "$SDK" \
    "$ROOT/src/NoteMath.swift" \
    "$ROOT/src/SineOscillator.swift" \
    "$ROOT/tests/main.swift" \
    -o "$OUT/SA-SurTests"

echo "==> running tests"
set +e
"$OUT/SA-SurTests" > "$LOG" 2>&1
STATUS=$?
set -e

echo "==> results"
python3 "$ROOT/tools/diff_table.py" "$LOG"
DIFF_STATUS=$?

echo
echo "swift harness exit: $STATUS    diff exit: $DIFF_STATUS"
if [ "$STATUS" -ne 0 ] || [ "$DIFF_STATUS" -ne 0 ]; then
    echo "TESTS FAILED"
    exit 1
fi
echo "TESTS PASSED"
