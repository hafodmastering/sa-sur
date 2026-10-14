#!/usr/bin/env bash
# Regenerates the MSIX tile assets from the composed app icon master.
#
# The master is the same artwork the macOS app ships inside AppIcon.icns, so the Windows tile, the
# Mac icon and the App Store icon cannot drift apart. Generated once and committed: the packaging
# step on Windows then never needs an image tool, and the assets are reviewable in the diff.
#
# Usage: ./make-assets.sh [master.png] [output-dir]
#   default master: the composed 1024px icon from a macOS build (build/AppIcon-1024.png)
#   default out:    Assets/
#
# Only macOS tooling is used (sips, python3): this is a Mac-first estate and these files change
# roughly never.
set -euo pipefail

MASTER="${1:-}"
OUT="${2:-Assets}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

# Default master: the composed icon from a macOS build of this tree, else the one committed for the
# README (256px - big enough for every tile here except the wide and splash, which would be
# upscaled, so prefer a real build if you have one).
if [[ -z "$MASTER" ]]; then
  ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null || echo "$HERE/../..")"
  if [[ -f "$ROOT/build/AppIcon-1024.png" ]]; then
    MASTER="$ROOT/build/AppIcon-1024.png"
  else
    MASTER="$ROOT/docs/screenshots/app-icon.png"
    echo "note: no build/AppIcon-1024.png; falling back to $MASTER" >&2
  fi
fi

if [[ ! -f "$MASTER" ]]; then
  echo "master not found: $MASTER" >&2
  echo "Build the macOS app once (./build.sh) or pass a path to the composed icon." >&2
  exit 2
fi

mkdir -p "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "master  : $MASTER"
sips -g pixelWidth -g pixelHeight "$MASTER" | tail -2

# Square tiles, straight downscale.
for spec in "StoreLogo:50" "Square44x44Logo:44" "Square71x71Logo:71" "Square150x150Logo:150"; do
  name="${spec%%:*}"
  px="${spec##*:}"
  sips -z "$px" "$px" "$MASTER" --out "$OUT/$name.png" >/dev/null
  echo "wrote   : $OUT/$name.png (${px}x${px})"
done

# Wide tile and splash: the square mark centred on the tile colour the manifest declares
# (BackgroundColor #000000). sips pads symmetrically, and padding after the resize is what keeps
# the mark from being stretched.
sips -z 150 150 "$MASTER" --out "$TMP/mark150.png" >/dev/null 2>&1
sips -p 150 310 --padColor 000000 "$TMP/mark150.png" --out "$OUT/Wide310x150Logo.png" >/dev/null 2>&1
echo "wrote   : $OUT/Wide310x150Logo.png (310x150)"

sips -z 300 300 "$MASTER" --out "$TMP/mark300.png" >/dev/null 2>&1
sips -p 300 620 --padColor 000000 "$TMP/mark300.png" --out "$OUT/SplashScreen.png" >/dev/null 2>&1
echo "wrote   : $OUT/SplashScreen.png (620x300)"

# A multi-size .ico for embedding in the executable, so the taskbar and Alt-Tab show the app's own
# icon rather than the generic .NET one. An ICO is a small container of PNGs; python3 writes it so
# nothing has to be installed. It belongs beside the project that embeds it (ApplicationIcon in
# SaSur.App.csproj), not with the packaging assets.
ICO="$HERE/../SA-Sur.App/SA-Sur.ico"
ICO_SIZES=(16 24 32 48 64 128 256)
for px in "${ICO_SIZES[@]}"; do
  sips -z "$px" "$px" "$MASTER" --out "$TMP/ico-$px.png" >/dev/null 2>&1
done
python3 - "$ICO" "$TMP" "${ICO_SIZES[@]}" <<'PY'
import struct, sys, os
out, tmp = sys.argv[1], sys.argv[2]
sizes = [int(s) for s in sys.argv[3:]]
entries = []
for px in sizes:
    with open(os.path.join(tmp, f"ico-{px}.png"), "rb") as fh:
        entries.append((px, fh.read()))
# ICONDIR: reserved, type=1 (icon), count
header = struct.pack("<HHH", 0, 1, len(entries))
offset = len(header) + 16 * len(entries)
directory = b""
payload = b""
for px, data in entries:
    dim = 0 if px >= 256 else px
    directory += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(data), offset)
    payload += data
    offset += len(data)
with open(out, "wb") as fh:
    fh.write(header + directory + payload)
print(f"wrote   : {out} ({len(entries)} sizes: {', '.join(str(s) for s in sizes)})")
PY

echo
echo "result:"
ls -l "$OUT" | tail -n +2
