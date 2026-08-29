#!/bin/zsh
# Restore the known-good iMac-as-5K-display configuration.
#
# Run with no argument on the SENDER (MacBook Pro), or `./restore-settings.sh receiver`
# on the RECEIVER (iMac 27" 2017). Settings live in UserDefaults, so a fresh install
# or an accidental change is recoverable without remembering any of this.
#
# Verified working 2026-08-29: 5120x2880 HEVC at 30 Mbit/s, 2560x1440 desktop,
# 1:1 pixels on the iMac's 5K panel, ~50 ms end-to-end over Wi-Fi.
set -e

SENDER=com.peetzweg.opensidecar.mac
RECEIVER=com.peetzweg.opensidecar.macreceiver

if [[ "$1" == "receiver" ]]; then
  echo "==> configuring RECEIVER (run this on the iMac)"

  # Announce a 5120x2880 panel. The sender halves this to derive the desktop, so
  # this is what produces a 2560x1440 desktop — the correct UI size for a 27".
  defaults write $RECEIVER panelPreset -string moreSpace

  # Declared decode ceiling. 5120 is correct ONLY with HEVC; H.264 hardware decode
  # fails above ~4096 wide on every Mac, so drop this to 3840 if HEVC is ever off.
  defaults write $RECEIVER maxEncode -int 5120

  # Draw the video ourselves. The system video layer only offers bilinear
  # magnification and no filter control.
  defaults write $RECEIVER metalRenderer -bool YES

  # 0 = no sharpening. Correct at 5120x2880, where the stream lands 1:1 on the
  # panel and there is no scaling blur to correct. Raise to ~0.6 only if the
  # stream is ever smaller than the panel again.
  defaults write $RECEIVER sharpen -float 0

  echo "    panelPreset   = $(defaults read $RECEIVER panelPreset)"
  echo "    maxEncode     = $(defaults read $RECEIVER maxEncode)"
  echo "    metalRenderer = $(defaults read $RECEIVER metalRenderer)"
  echo "    sharpen       = $(defaults read $RECEIVER sharpen)"
  echo "==> restarting the receiver"
  killall OpenDisplayReceiver 2>/dev/null || true
  sleep 2
  open -a "OpenDisplay Receiver"
else
  echo "==> configuring SENDER (run this on the MacBook Pro)"

  # HEVC is mandatory for 5K: H.264 hardware decode stops below 5120 wide on
  # every Mac tested, including Apple silicon.
  defaults write $SENDER hevc -bool YES

  # 30 is a CEILING, not a suggestion. At 45 the iMac cannot sustain 5K HEVC
  # decode over Wi-Fi; the receiver's watchdog then walks the preset down
  # 5120 -> 3840 -> 2880, which looks like "the UI suddenly got big".
  defaults write $SENDER bitrateMbps -int 30

  defaults write $SENDER quality -string best
  defaults write $SENDER mode -string extend

  # Capture full-range BGRA instead of video-range 4:2:0. Without it blacks are
  # lifted to grey and colour looks flat.
  defaults write $SENDER pixfmt -string bgra

  echo "    hevc        = $(defaults read $SENDER hevc)"
  echo "    bitrateMbps = $(defaults read $SENDER bitrateMbps)"
  echo "    quality     = $(defaults read $SENDER quality)"
  echo "    mode        = $(defaults read $SENDER mode)"
  echo "    pixfmt      = $(defaults read $SENDER pixfmt)"
  echo "==> restarting the sender"
  osascript -e 'quit app "OpenDisplay"' 2>/dev/null || true
  sleep 2
  open ~/Applications/OpenDisplay.app
  echo
  echo "NOTE: rebuilding the sender changes its ad-hoc code signature, so macOS"
  echo "      revokes Screen Recording. Symptom is a black screen. Re-grant it in"
  echo "      the app's Permissions section."
fi
