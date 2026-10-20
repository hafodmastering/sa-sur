#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Hafod Mastering Limited and Sudeep Audio.com LLP

# Renders the Microsoft Store screenshots from the shared view, at the size the
# listing uses.
#
# The images are pictures of the UI at the commit you are packaging, not captures
# of somebody's desktop: that is what makes it possible to say which build a
# screenshot describes, and what lets the listing be refreshed without a Windows
# machine in front of a screen. `pack-msix.ps1 -Screenshots <dir>` refuses a set
# older than the source.
#
# usage: tools/windows-store-screenshots.sh [output-directory]
#
# Default output: build/store-shots/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/store-shots}"

if ! command -v dotnet > /dev/null 2>&1; then
    echo "FAIL: dotnet not found (the .NET SDK 10 is what renders these)" >&2
    exit 2
fi

mkdir -p "$OUT"
dotnet run --project "$ROOT/windows/SaSur.StoreShots" -c Release -- "$OUT"

echo "==> digests (paste these into the release record, not the previous set's)"
for f in "$OUT"/*.png; do
    printf '%s  %s\n' "$(shasum -a 256 "$f" | cut -d' ' -f1)" "$(basename "$f")"
done
