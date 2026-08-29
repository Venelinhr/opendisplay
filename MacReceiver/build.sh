#!/bin/zsh
# Build the macOS receiver WITHOUT Xcode.
#
# Why this exists: this is a managed Mac with no admin rights, so
# `sudo xcodebuild -license` cannot be accepted and `xcodebuild` is unusable.
# DEVELOPER_DIR points the toolchain at the Command Line Tools instead, which
# carry their own already-accepted licence. Verified working: Swift 6.3.3,
# universal binary, minos 13.0, AppKit + Network + VideoToolbox + Metal all link.
#
# Output: build/OpenDisplay Receiver.app — a universal (x86_64 + arm64) bundle
# that runs on the Intel iMac 27" 2017 on Ventura AND on this Apple Silicon Mac.
set -e
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=/Library/Developer/CommandLineTools

APP_NAME="OpenDisplay Receiver"
BIN_NAME="OpenDisplayReceiver"
OUT="build/${APP_NAME}.app"
DEPLOY=13.0                      # the iMac 27" 2017 ceiling (Ventura)

# Source set. The receiver core and renderer are reused from iOS/ verbatim —
# same trick project.yml already uses for OpenSidecarMacTests.
SOURCES=(
  MacReceiver/*.swift
  Receiver/*.swift
  iOS/PhoneReceiver.swift
  iOS/MetalVideoRenderer.swift
  Shared/Protocol.swift
  Shared/AppStore.swift
)

echo "==> compiling both slices at macOS ${DEPLOY}"
mkdir -p build
for arch in arm64 x86_64; do
  swiftc -target ${arch}-apple-macos${DEPLOY} \
         -O -whole-module-optimization \
         -o "build/${BIN_NAME}-${arch}" \
         ${~SOURCES}
done

echo "==> fusing universal binary"
lipo -create "build/${BIN_NAME}-arm64" "build/${BIN_NAME}-x86_64" \
     -output "build/${BIN_NAME}"

echo "==> packaging ${OUT}"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS"
cp "build/${BIN_NAME}" "$OUT/Contents/MacOS/${BIN_NAME}"

# swiftc cannot compile asset catalogues, so the icon is produced separately
# from Mac/Assets.xcassets by MacReceiver/make-icon.sh (iconutil ships with the
# Command Line Tools). Without it the app shows a blank generic icon.
mkdir -p "$OUT/Contents/Resources"
[ -f build/AppIcon.icns ] || ./MacReceiver/make-icon.sh
cp build/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>${BIN_NAME}</string>
  <key>CFBundleIdentifier</key><string>com.peetzweg.opensidecar.macreceiver</string>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>${DEPLOY}</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <!-- Required or Bonjour silently fails on macOS 15+. Harmless on Ventura. -->
  <key>NSBonjourServices</key><array><string>_opensidecar._tcp</string></array>
  <key>NSLocalNetworkUsageDescription</key>
  <string>OpenDisplay advertises itself on the local network so your Mac can connect.</string>
</dict></plist>
PLIST

# Ad-hoc signature. The Intel iMac would run unsigned, but Apple Silicon will
# not, and we test on this Mac first.
codesign -s - --force --deep "$OUT" >/dev/null 2>&1

echo "==> built: $OUT"
lipo -info "$OUT/Contents/MacOS/${BIN_NAME}"
otool -l "$OUT/Contents/MacOS/${BIN_NAME}" | grep minos | head -2
echo
echo "Copy to the iMac with rsync/scp (NOT AirDrop — that sets the quarantine flag):"
echo "  rsync -a \"$OUT\" imac.local:/Users/\$USER/Applications/"
