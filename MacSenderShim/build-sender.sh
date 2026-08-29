#!/bin/zsh
# Build the macOS SENDER without Xcode (no admin rights on this machine).
# Same DEVELOPER_DIR trick as MacReceiver/build.sh, plus:
#   -import-objc-header  for the private CGVirtualDisplay declarations
#   MacSenderShim/       for the Sparkle stub
#
# arm64 only: the sender needs macOS 14+, so it runs on the MacBook, not the iMac.
set -e
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=/Library/Developer/CommandLineTools

APP_NAME="OpenDisplay Sender"
BIN_NAME="OpenDisplaySender"
OUT="build/${APP_NAME}.app"
DEPLOY=14.0

SOURCES=(
  Mac/*.swift
  Shared/*.swift
  MacSenderShim/SparkleStub.swift
)

echo "==> compiling sender (arm64, macOS ${DEPLOY})"
mkdir -p build
swiftc -target arm64-apple-macos${DEPLOY} \
       -import-objc-header Mac/OpenSidecarMac-Bridging-Header.h \
       -O -whole-module-optimization \
       -o "build/${BIN_NAME}" \
       ${~SOURCES}

echo "==> packaging ${OUT}"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS"
cp "build/${BIN_NAME}" "$OUT/Contents/MacOS/${BIN_NAME}"

# See MacReceiver/build.sh — swiftc cannot compile asset catalogues.
mkdir -p "$OUT/Contents/Resources"
[ -f build/AppIcon.icns ] || ./MacReceiver/make-icon.sh
cp build/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>${BIN_NAME}</string>
  <key>CFBundleIdentifier</key><string>com.peetzweg.opensidecar.mac</string>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>1.17.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>${DEPLOY}</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSBonjourServices</key><array><string>_opensidecar._tcp</string></array>
  <key>NSLocalNetworkUsageDescription</key>
  <string>OpenDisplay connects to your iPad, iPhone or Mac over the local network.</string>
</dict></plist>
PLIST

codesign -s - --force --deep "$OUT" >/dev/null 2>&1
echo "==> built: $OUT"
