#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

"""Independently recompute the note table and diff it against the Swift output.

The expected values here are produced through exp/ln rather than the app's
pow(2, x), so a bug in the Swift implementation has to reproduce itself in a
second, differently-written calculation to slip through.
"""
import math
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "build/test-output.txt"

with open(path, "r", encoding="utf-8") as handle:
    log = handle.read()

# --- print everything worth reading, collapse the PASS wall --------------
passes = 0
for line in log.splitlines():
    if line.startswith("PASS"):
        passes += 1
        continue
    print(line)
print(f"(+ {passes} PASS lines suppressed)")

# --- the table ----------------------------------------------------------
match = re.search(r"@@TABLE@@\n(.*?)\n@@END@@", log, re.S)
if not match:
    print("DIFF: FAIL - no table found in test output")
    sys.exit(1)

rows = [line.split(",") for line in match.group(1).splitlines() if line.strip()]
if len(rows) != 108:
    print(f"DIFF: FAIL - expected 108 rows, got {len(rows)}")
    sys.exit(1)

NAMES = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B"]
mismatches = []
worst = (0.0, "")
for label, value in rows:
    name = re.match(r"([A-G][#b]?)(\d+)", label)
    semitone = NAMES.index(name.group(1))
    octave = int(name.group(2))
    midi = (octave + 1) * 12 + semitone
    expected = 440.0 * math.exp(math.log(2.0) * (midi - 69) / 12.0)
    got = float(value)
    delta = abs(got - expected)
    if delta > worst[0]:
        worst = (delta, label)
    if delta > 1e-6:
        mismatches.append((label, got, expected))

print(f"\nDIFF: compared {len(rows)} notes against an independent calculation")
print(f"DIFF: largest absolute difference {worst[0]:.3e} Hz (at {worst[1]})")
if mismatches:
    print(f"DIFF: FAIL - {len(mismatches)} mismatch(es)")
    for label, got, expected in mismatches[:10]:
        print(f"  {label}: swift {got} vs independent {expected}")
    sys.exit(1)

print("DIFF: PASS - all 108 note frequencies agree to <1e-6 Hz")
