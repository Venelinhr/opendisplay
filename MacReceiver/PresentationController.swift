// Fullscreen presentation on the receiving Mac, plus keeping its display awake.
//
// Kiosk mode defaults OFF on purpose: a borderless .screenSaver-level window
// with no menu bar can lock you out of the machine you are developing on.
// Escape and Command-Q always drop out of it.

import AppKit
import IOKit.pwr_mgt

final class PresentationController {

    private weak var window: NSWindow?
    private var sleepAssertion: IOPMAssertionID = 0
    private var holdingAssertion = false
    private(set) var isKiosk = false

    init(window: NSWindow) {
        self.window = window
    }

    // MARK: - Kiosk

    func setKiosk(_ on: Bool) {
        guard on != isKiosk, let window else { return }
        isKiosk = on

        if on {
            guard let screen = window.screen ?? NSScreen.main else { return }
            // .hideMenuBar without a Dock option raises — they must be paired.
            NSApp.presentationOptions = [.hideDock, .hideMenuBar]
            window.styleMask = [.borderless]
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window.isMovable = false
            window.setFrame(screen.frame, display: true)
            window.makeKeyAndOrderFront(nil)
            NSCursor.hide()
        } else {
            NSApp.presentationOptions = []
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.level = .normal
            window.isMovable = true
            window.title = "OpenDisplay Receiver"
            NSCursor.unhide()
        }
        Log.info("kiosk \(on ? "on" : "off")")
    }

    func toggleKiosk() { setKiosk(!isKiosk) }

    // MARK: - Display sleep

    /// Held only while a session is live. Holding it permanently would stop the
    /// iMac ever sleeping, which is not ours to decide.
    func setDisplayAwake(_ awake: Bool) {
        guard awake != holdingAssertion else { return }
        if awake {
            let ok = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "OpenDisplay receiving" as CFString,
                &sleepAssertion)
            holdingAssertion = (ok == kIOReturnSuccess)
            Log.info("display-sleep assertion \(holdingAssertion ? "taken" : "FAILED")")
        } else {
            IOPMAssertionRelease(sleepAssertion)
            holdingAssertion = false
            Log.info("display-sleep assertion released")
        }
    }
}
