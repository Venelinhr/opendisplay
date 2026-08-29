// OpenDisplay Receiver for macOS — turns this Mac into a second display for
// another Mac running the OpenDisplay sender.
//
// Built for an iMac 27" 2017 (Retina 5K), which caps at macOS 13 Ventura and so
// cannot run the sender app at all (that needs 14+). This target deploys to 13.0.
//
// Input is deliberately absent: macOS Universal Control already shares keyboard
// and mouse between two Macs, over Apple's own encrypted channel. The OpenDisplay
// wire has no TLS and no auth (PROTOCOL.md section 1), so not putting keystrokes
// on it is a feature.

import AppKit
import AVFoundation
import Combine

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Logged at launch so "did the new copy actually get installed?" is
    /// answerable from the log. Deliberately not in the window title — that is
    /// the user's screen, not a build stamp.
    static let buildTag = "v9"

    // NSApplication.delegate is weak, so the instance must be owned here.
    private static var shared: AppDelegate?

    /// Set when we announce a new panel size, cleared when a picture actually
    /// arrives for it. If it is still set when the watchdog fires, this Mac
    /// could not decode what the sender produced — so step down instead of
    /// sitting on a black screen with no way to tell why.
    private var awaitingFirstFrame = false
    private var flushBaseline = 0
    private var watchdog: DispatchWorkItem?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.shared = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    private var window: NSWindow!
    private var hostView: VideoHostView!
    private var receiver: PhoneReceiver!
    private var presentation: PresentationController!
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let displayLayer = AVSampleBufferDisplayLayer()
        receiver = PhoneReceiver(displayLayer: displayLayer)
        hostView = VideoHostView(displayLayer: displayLayer)

        buildWindow()
        buildMenu()
        presentation = PresentationController(window: window)

        // Measured on an iMac 27" 2017 (Kaby Lake + Radeon Pro 575): 3840x2160
        // H.264 decodes, 5120x2880 does not. Declaring it lets us ask for a
        // 2560x1440 desktop while the sender encodes only 3840x2160.
        //
        // Tunable, because the sharpest setting is not always the biggest one:
        // on a 5120-wide panel a 2560-wide stream scales up by exactly 2x with
        // no resampling blur, which can read as crisper than a 3840-wide stream
        // stretched by 1.33x — fewer pixels, but every one lands on a boundary.
        //   defaults write com.peetzweg.opensidecar.macreceiver maxEncode 2560
        // integer(forKey:) rather than object(forKey:) as? Int, because a plain
        // `defaults write ... maxEncode 2560` stores a STRING, which would fail
        // the cast and silently keep the default.
        let stored = UserDefaults.standard.integer(forKey: "maxEncode")
        let cap = stored > 0 ? stored : 3840
        receiver.maxEncodeWide = cap
        receiver.maxEncodeHigh = (Int(Double(cap) * 9.0 / 16.0)) & ~1
        Log.info("declaring decode ceiling \(cap)x\(receiver.maxEncodeHigh ?? 0)")

        applyPreset(PanelPreset.current)
        receiver.setServiceName(ReceiverPlatform.defaultDeviceName)

        wireReceiver()
        observeSystem()

        receiver.start()
        Log.info("receiver \(Self.buildTag) launched — listening on 9000, "
                 + "preset=\(PanelPreset.current.rawValue)")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // shutDown() posts `closing` asynchronously. Returning .terminateNow here
        // would kill the process first, and the sender would then sit through its
        // 10-second silence timeout on every quit.
        presentation.setDisplayAwake(false)
        receiver.shutDown {
            DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Wiring

    private func wireReceiver() {
        receiver.onCursor = { [weak self] x, y, visible in
            self?.hostView.setCursor(x: x, y: y, visible: visible)
        }
        receiver.onCursorImage = { [weak self] image, anchor, normSize in
            self?.hostView.setCursorSprite(image, anchor: anchor, normSize: normSize)
        }

        // The Metal path decodes explicitly and hands us frames; without this
        // wiring, turning on "metalRenderer" produces a permanently black screen.
        if let metal = hostView.metalRenderer {
            receiver.onDecodedFrame = { pixelBuffer, captureMs in
                metal.render(pixelBuffer, captureMs: captureMs)
            }
            metal.onPresented = { [weak self] presentedTime, captureMs in
                self?.receiver.recordPresented(presentedTime: presentedTime, captureMs: captureMs)
            }
            Log.info("using Metal renderer, sharpen=\(MetalVideoRenderer.sharpenAmount)")
        }

        // Video dimensions come from the SPS, never from `hello` — PROTOCOL.md 5.2.
        receiver.$videoSize
            .receive(on: DispatchQueue.main)
            .sink { [weak self] size in
                guard let self, size.width > 0 else { return }
                self.hostView.videoSize = size
                self.awaitingFirstFrame = false
                Log.info("decoding \(Int(size.width))x\(Int(size.height))")
            }
            .store(in: &cancellables)

        receiver.$connected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                guard let self else { return }
                self.presentation.setDisplayAwake(connected)
                self.updateTitle()
                Log.info(connected ? "session connected" : "session disconnected")
                if connected { self.armDecodeWatchdog() }
            }
            .store(in: &cancellables)

        receiver.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateTitle() }
            .store(in: &cancellables)
    }

    /// Mirrors the iOS lifecycle hooks onto their AppKit equivalents.
    private func observeSystem() {
        let wsc = NSWorkspace.shared.notificationCenter
        wsc.addObserver(forName: NSWorkspace.willSleepNotification,
                        object: nil, queue: .main) { [weak self] _ in
            self?.receiver.enterSleep()
        }
        wsc.addObserver(forName: NSWorkspace.didWakeNotification,
                        object: nil, queue: .main) { [weak self] _ in
            self?.receiver.ensureListening()
        }
        wsc.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                        object: nil, queue: .main) { [weak self] _ in
            self?.receiver.enterSleep()
        }
        wsc.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                        object: nil, queue: .main) { [weak self] _ in
            self?.receiver.ensureListening()
        }

        // Escape hatch — kiosk mode hides the menu bar, so this is the only way
        // back out on a machine with no other window.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.presentation.isKiosk else { return event }
            if event.keyCode == 53 {                       // Escape
                self.presentation.setKiosk(false)
                return nil
            }
            return event
        }
    }

    // MARK: - Window & menu

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "OpenDisplay Receiver"
        window.contentView = hostView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateTitle() {
        guard !presentation.isKiosk else { return }
        // `status` already carries the dimensions once connected, so appending
        // videoSize as well printed them twice. The build tag stays out of the
        // title and lives in the launch log instead — it exists to answer "did
        // the new copy install?", which is a development question, not something
        // to put in front of a user every time they glance at the screen.
        window.title = "OpenDisplay Receiver — \(receiver.status)"
    }

    private func applyPreset(_ preset: PanelPreset) {
        let d = preset.pixels
        // long/short, not width/height: setNativePanel takes the landscape pair.
        receiver.setNativePanel(long: d.w, short: d.h, scale: 2)
        // setNativePanel seeds devicePixelsWide/High ONLY while they are still
        // zero, so on every later preset change it updates nativeLong/Short and
        // nothing else — the receiver kept announcing the original size forever.
        // setOrientation applies the new pair and re-sends hello on the live
        // connection, which is what makes the sender rebuild its virtual display.
        receiver.setOrientation(portrait: false)
        Log.info("announcing \(d.w)x\(d.h) -> expect a \(d.w / 2)x\(d.h / 2) point desktop")
        armDecodeWatchdog()
    }

    /// Give the new stream a few seconds to produce a picture. If none arrives —
    /// or the display layer starts throwing frames away — this Mac's decoder
    /// cannot handle it, so drop to the next smaller announcement automatically.
    private func armDecodeWatchdog() {
        watchdog?.cancel()
        awaitingFirstFrame = true
        flushBaseline = receiver.perf.decodeFlushes

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.receiver.connected else { return }
            let choking = self.receiver.perf.decodeFlushes > self.flushBaseline
            guard self.awaitingFirstFrame || choking else { return }   // healthy

            guard let next = PanelPreset.current.smaller else {
                Log.info("no picture at \(PanelPreset.current.rawValue) and nothing smaller left "
                         + "— lower Quality on the Mac")
                return
            }
            Log.info("no decodable picture at \(PanelPreset.current.rawValue) "
                     + "(flushes \(self.flushBaseline)->\(self.receiver.perf.decodeFlushes)) "
                     + "— falling back to \(next.rawValue)")
            PanelPreset.select(next)
            self.applyPreset(next)      // re-arms the watchdog itself
            self.buildMenu()
        }
        watchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let preset = PanelPreset(rawValue: sender.representedObject as? String ?? "")
        else { return }
        PanelPreset.select(preset)
        applyPreset(preset)          // re-announces on the live connection
        buildMenu()
    }

    @objc private func toggleKiosk() { presentation.toggleKiosk() }

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About OpenDisplay Receiver",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let kiosk = NSMenuItem(title: "Full Screen (kiosk)",
                               action: #selector(toggleKiosk), keyEquivalent: "f")
        kiosk.keyEquivalentModifierMask = [.command, .control]
        kiosk.target = self
        appMenu.addItem(kiosk)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let displayItem = NSMenuItem()
        let displayMenu = NSMenu(title: "Display")
        for preset in PanelPreset.allCases {
            let item = NSMenuItem(title: preset.title, action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.representedObject = preset.rawValue
            item.target = self
            item.state = (preset == PanelPreset.current) ? .on : .off
            displayMenu.addItem(item)
        }
        displayItem.submenu = displayMenu
        main.addItem(displayItem)

        NSApp.mainMenu = main
    }
}
