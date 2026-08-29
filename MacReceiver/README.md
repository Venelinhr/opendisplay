# OpenDisplay — macOS receiver

Use an older Mac as a **real second display** for a newer one, over Wi-Fi.

Upstream OpenDisplay turns an iPad or iPhone into a second monitor. There was no
receiver for macOS, so a Mac could only ever be the sender. This adds one.

---

## The problem it solves

An **iMac 27" 2017** has a beautiful 5K panel and no way to use it as a monitor:

| Option | Why it doesn't work |
|---|---|
| Target Display Mode | Apple removed it after 2014 |
| AirPlay to Mac | Needs a 2019 or newer iMac |
| Run the OpenDisplay sender on it | Sender needs macOS 14; this iMac stops at Ventura 13 |
| Sidecar | iPad only |

So a perfectly good 5K display becomes e-waste. This makes it a monitor again.

---

## Tested and validated

| | |
|---|---|
| **Resolution** | **5120 × 2880 — 14.7 MP, 1:1 pixels** |
| **Desktop** | 2560 × 1440 @2x |
| **Codec** | HEVC Main, 30 Mbit/s |
| **Latency** | 54 ms median, 62 ms p95 |
| **Round trip** | 5–6 ms |
| **Machine** | i5-7600, Radeon Pro 575, **Ventura 13.7.8**, **Wi-Fi** |

Sender was a MacBook Pro M4 Pro on macOS 26. Colour is captured full-range BGRA;
Ventura 13.7.8 is the last macOS this iMac supports, which is why it can never run
the sender itself.

**1:1 pixels** is the part that matters: the stream is the same size as the panel,
so nothing is scaled and nothing is blurred. Every codec and resolution limit
below was established by end-to-end playback on this hardware, not from spec sheets.

Good for writing, browsing, design tools, reference material, terminals. Not for
gaming or fast video — that is a Wi-Fi limit, not a code one.

---

## Codec support — measured, not assumed

Established by end-to-end playback on real hardware:

| Codec | 2560×1440 | 3840×2160 | **5120×2880** |
|---|---|---|---|
| **H.264** | OK | OK | **Fails — on every Mac** |
| **HEVC** | OK | OK | **OK** |

Two things worth knowing:

**H.264 cannot do 5K on any Mac**, including an M4 Pro. Hardware decode stops
below 5120 wide. It is a format ceiling, not an age limit — so **HEVC is
mandatory for 5K**, on new machines as much as old ones.

**A 2017 Intel iMac decodes 5K HEVC fine.** The Kaby Lake media engine handles it.
Do not assume old hardware is the limit before measuring it.

`tools/decode-probe.swift` reports what any given Mac can actually decode. Note
that `VTDecompressionSessionCreate` succeeding proves nothing on its own — it will
build sessions the hardware cannot sustain. Only playback is a valid test.

---

## Install

Two apps. Each runs on its own machine.

| App | Runs on | Requires |
|---|---|---|
| `OpenDisplay Sender.app` | the newer Mac | macOS 14+ |
| `OpenDisplay Receiver.app` | the older Mac | macOS 13+, Intel or Apple silicon |

1. Copy each app to `~/Applications` on its machine.
   Use **AirDrop, `scp`, `rsync` or a USB stick.**
2. **Right-click → Open** the first time. These are ad-hoc signed, so a
   double-click is blocked. If macOS still refuses:
   ```
   xattr -dr com.apple.quarantine "OpenDisplay Receiver.app"
   ```
3. On the **sender**, grant **Screen Recording** when the app asks.
   Accessibility is not needed — this build forwards no input.

### Apply the settings

```
./restore-settings.sh              # on the sender
./restore-settings.sh receiver     # on the receiver
```

Or by hand:

```sh
# Sender
defaults write com.peetzweg.opensidecar.mac hevc         -bool YES
defaults write com.peetzweg.opensidecar.mac bitrateMbps  -int  30
defaults write com.peetzweg.opensidecar.mac quality      -string best
defaults write com.peetzweg.opensidecar.mac mode         -string extend
defaults write com.peetzweg.opensidecar.mac pixfmt       -string bgra

# Receiver
defaults write com.peetzweg.opensidecar.macreceiver panelPreset   -string moreSpace
defaults write com.peetzweg.opensidecar.macreceiver maxEncode     -int  5120
defaults write com.peetzweg.opensidecar.macreceiver metalRenderer -bool YES
defaults write com.peetzweg.opensidecar.macreceiver sharpen       -float 0
```

Restart both apps afterwards — settings are read at launch.

---

## Connect and use

1. Open **OpenDisplay Receiver** on the older Mac. It waits, showing
   *Listening on :9000*.
2. Open **OpenDisplay** on the newer Mac. The receiver appears by computer name.
3. Set **Mode → Extend**, then click **Connect**.
4. macOS asks what to show — choose **Extended Display**.

The older Mac now has its own desktop.

- **Move windows there** by dragging past the screen edge.
- **Set the position** with *Arrange Displays…* so the edge you cross matches
  where the machine physically sits.
- **Full screen** on the receiver: `Ctrl-Cmd-F`. `Esc` exits.
- **Wallpaper**: a new display starts blank. Right-click the desktop to set one —
  otherwise an empty desktop looks like a failure when it isn't.

### Extend vs Mirror

| Mode | |
|---|---|
| **Extend** | Its own desktop. Move windows onto it. **Use this.** |
| Mirror | A copy of the sender's screen. Windows cannot be moved onto it, and it can never exceed the sender's own resolution. |

### Turn Universal Control off

If both Macs share an Apple ID, Universal Control competes for the same screen
edge — and wins. The pointer jumps to the other Mac's *own* desktop instead of
onto your extended display, and windows will not follow.

**System Settings → Displays → Advanced** → turn off *"Allow your pointer and
keyboard to move between any nearby Mac or iPad"*.

You do not need it: the sender's own keyboard and trackpad drive the extended
screen natively, and they do so over an encrypted channel rather than this one
(the wire protocol has no TLS and no authentication — see PROTOCOL.md §1).

---

## Two traps that cost a whole evening

**30 Mbit/s is a ceiling, not a suggestion.** At 45 the 2017 iMac cannot sustain
5K HEVC decode over Wi-Fi. The receiver's watchdog then steps the announced size
down 5120 → 3840 → 2880, which presents as **"the UI suddenly got big"** — not as
an error message. If that happens, lower the bitrate; do not chase the resolution.

**Rebuilding the sender silently revokes Screen Recording.** The ad-hoc code
signature changes, macOS treats it as a different app, and the only symptom is a
black screen. Remove and re-add it in Privacy & Security.

---

## Sharpening

`sharpen` drives an unsharp mask in the Metal renderer, for when the stream is
**smaller** than the panel and has to be magnified.

| Situation | Value |
|---|---|
| 5120×2880 on a 5K panel (1:1) | **0** — nothing to correct; anything higher looks artificial |
| 3840×2160 on a 5K panel (1.33× magnified) | 0.6-1.0 |

macOS only offers bilinear magnification through the system video layer, which is
why the renderer draws the video itself.

---

## Building

No Xcode required. Developed on a managed Mac with no admin rights, where the
Xcode licence can never be accepted and `xcodebuild` / `xcodegen` are unusable —
`DEVELOPER_DIR` points at the Command Line Tools instead.

```sh
./MacReceiver/build.sh          # universal (Intel + Apple silicon), macOS 13+
./MacSenderShim/build-sender.sh # arm64, macOS 14+
```

If Xcode ever *is* available, adding a proper `project.yml` target would be a
reasonable follow-up; this path exists because that one was closed.

---

## Compatibility

| Receiver | Works? |
|---|---|
| iMac 27" 2020 | Yes — best case, newer decoder |
| iMac 27" 2019 | Yes |
| **iMac 27" 2017** | **Yes — verified, this is the reference machine** |
| iMac 21.5" 4K 2017 / 2019 | Yes — announces 4096×2304 instead |
| Anything below macOS 13 | Not as built; lower the deployment target in `build.sh` |

Sender needs macOS 14+, so a 2017 iMac can only ever be the receiver.
