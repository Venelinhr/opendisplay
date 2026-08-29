#!/bin/zsh
# Build build/AppIcon.icns from the repo's asset-catalogue PNGs.
#
# swiftc cannot compile .xcassets — that is actool's job, and actool only ships
# inside Xcode, which is unusable here (no admin rights to accept the licence).
# iconutil, however, ships with the Command Line Tools, so we assemble a
# classic .iconset by hand and let iconutil do the rest.
set -e
cd "$(dirname "$0")/.."

SRC=Mac/Assets.xcassets/AppIcon.appiconset
OUT=build/AppIcon.iconset
mkdir -p build
rm -rf "$OUT"; mkdir -p "$OUT"

# iconutil expects these exact names. The catalogue stores one PNG per pixel
# size, so several are reused at both 1x and 2x.
cp "$SRC/icon_16.png"   "$OUT/icon_16x16.png"
cp "$SRC/icon_32.png"   "$OUT/icon_16x16@2x.png"
cp "$SRC/icon_32.png"   "$OUT/icon_32x32.png"
cp "$SRC/icon_64.png"   "$OUT/icon_32x32@2x.png"
cp "$SRC/icon_128.png"  "$OUT/icon_128x128.png"
cp "$SRC/icon_256.png"  "$OUT/icon_128x128@2x.png"
cp "$SRC/icon_256.png"  "$OUT/icon_256x256.png"
cp "$SRC/icon_512.png"  "$OUT/icon_256x256@2x.png"
cp "$SRC/icon_512.png"  "$OUT/icon_512x512.png"
cp "$SRC/icon_1024.png" "$OUT/icon_512x512@2x.png"

iconutil -c icns "$OUT" -o build/AppIcon.icns
rm -rf "$OUT"
echo "built build/AppIcon.icns"
