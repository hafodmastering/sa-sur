#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Hafod Mastering Limited and Sudeep Audio.com LLP

# The manual: one markdown source, one HTML render, one PDF.
#
#   docs/MANUAL.md                      the copy - the only file to edit
#   docs/SA-Sur-User-Manual.pdf         the artifact: ships in the app bundle
#                                       (Help menu), and goes to the release page
#   tools/mdtohtml.py                   markdown -> HTML, plus Figure 1's callouts
#                                       and Appendix A, generated from
#                                       docs/note-table.csv so the 108
#                                       frequencies are never retyped
#   tools/CheckManual.swift             reads the PDF back and checks it
#
# usage: tools/manual.sh            # regenerate the HTML, then check the PDF
#        tools/manual.sh --html     # regenerate the HTML only
#
# RENDER STEP, and why it is not in this script. The PDF is made by printing the
# HTML to PDF at A4 in a browser, from the document's own @page rule. Two
# in-repo renderers were tried and both fail on the current OS, so the render is
# an operator step and this script checks its output instead:
#
#   - WKWebView.createPDF() ignores pagination entirely: it renders the whole
#     document as one page 6,487 pt tall.
#   - WKWebView.printOperation(with:) blocks the main thread indefinitely when
#     run from a script, with or without a visible window (45 s watchdog).
#   - A fresh `--headless` Chromium launch hung on its first run, before it wrote
#     anything. Retried on 20 Oct with the installed Google Chrome and
#     --headless=new: it wrote the PDF in about four seconds. See below.
#
# So: print the HTML to PDF at A4 and save it to docs/SA-Sur-User-Manual.pdf.
# This script fails if that PDF is older than the markdown, which is what stops a
# stale manual shipping in a signed app.
#
# WHAT WORKS (20 Oct 2026): Chrome headless, which renders the document's own
# @page rule and needs no window:
#
#   TMPD=$(mktemp -d)
#   "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
#       --headless=new --disable-gpu --no-first-run --no-default-browser-check \
#       --user-data-dir="$TMPD" --no-pdf-header-footer \
#       --print-to-pdf="$PWD/docs/SA-Sur-User-Manual.pdf" \
#       "file://$PWD/build/manual/SA-Sur-Manual.html"
#
# It prints a few harmless CVDisplayLink/task_policy errors on macOS and still
# writes the file. The page count is asserted by tools/CheckManual.swift: adding
# or removing a page is a layout decision, so update that number deliberately.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
MANUAL="$ROOT/docs/MANUAL.md"
PDF="$ROOT/docs/SA-Sur-User-Manual.pdf"
HTML="$ROOT/build/manual/SA-Sur-Manual.html"
MODE="${1:-check}"

case "$MODE" in
    check|--html) ;;
    *) echo "usage: tools/manual.sh [--html]" >&2; exit 2 ;;
esac

mkdir -p "$ROOT/build/manual"

echo "==> markdown -> HTML"
python3 "$ROOT/tools/mdtohtml.py" "$MANUAL" "$HTML" \
    --figure "$ROOT/docs/screenshots/ui-snapshot-light.png"

if [ "$MODE" = "--html" ]; then
    echo "==> html only; not checking the PDF"
    exit 0
fi

if [ ! -f "$PDF" ]; then
    echo "FAIL: no PDF at $PDF" >&2
    echo "      Render $HTML to PDF at A4 and save it there. See the header." >&2
    exit 1
fi

SOURCES=("$ROOT/docs/MANUAL.md" "$ROOT/docs/note-table.csv"
         "$ROOT/docs/screenshots/ui-snapshot-light.png" "$ROOT/tools/mdtohtml.py")
for source in "${SOURCES[@]}"; do
    if [ "$PDF" -ot "$source" ]; then
        echo "FAIL: the PDF is older than ${source#$ROOT/} - the manual changed and" >&2
        echo "      the PDF was not re-rendered. Render $HTML to $PDF. See the header." >&2
        exit 1
    fi
done

echo "==> reading the PDF back (tools/CheckManual)"
swiftc -O -target "$ARCH-apple-macos13.0" -sdk "$SDK" \
    "$ROOT/tools/CheckManual.swift" -o "$ROOT/build/manual/CheckManual"
"$ROOT/build/manual/CheckManual" "$PDF"

echo
echo "MANUAL: ok ($PDF)"
