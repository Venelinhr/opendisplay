// OpenDisplay Receiver: the standalone "this Mac is a display" app (issues
// #82/#17). It is a separate bundle from the sender on purpose: the sender
// needs macOS 14 for its capture/virtual-display stack, while receiving only
// needs the decoder and a window, so this target keeps a much lower
// deployment floor and old Macs can serve as screens (issue #241).
//
// The receiver starts at launch and stays up for the app's lifetime; the
// window is just the control panel (name, status, HUD toggle). The video
// window itself is managed by ReceiverController.

import SwiftUI
import Sparkle

@main
struct OpenSidecarMacReceiverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = ReceiverController.shared

    var body: some Scene {
        WindowGroup("OpenDisplay Receiver") {
            ReceiverContentView(controller: controller, updater: appDelegate.updater)
        }
        .commands {
            // One control window: no File > New.
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let updater = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        ReceiverController.shared.start()
    }

    // Reopening (Dock click) with the panel closed brings it back; the
    // receiver itself never stopped.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            NSApp.windows.first { $0.title == "OpenDisplay Receiver" }?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    // Closing the panel is not quitting: a spare Mac sits there as a display
    // with nothing but the video window (or nothing at all) on screen.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Quitting while being a display: tell the sender we're closing (it ends
    // the session instead of retrying a dead peer) before the process goes.
    // stop() calls back once the message is out or a second has passed.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ReceiverController.shared.active else { return .terminateNow }
        ReceiverController.shared.stop {
            DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }
}

struct ReceiverContentView: View {
    @ObservedObject var controller: ReceiverController
    let updater: SPUStandardUpdaterController?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenDisplay Receiver")
                        .font(.title3.bold())
                    Text("This Mac as an extra display for another Mac")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(16)

            Divider()

            Form {
                ReceiverSections(controller: controller)
            }
            .groupedFormStyle()

            Divider()

            HStack(spacing: 8) {
                Circle()
                    .fill(controller.connected ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 9, height: 9)
                Text(controller.connected ? "Receiving from a Mac" : "Waiting for a Mac to connect")
                    .font(.callout)
                    .lineLimit(1)
                Spacer()
                Button("Logs") { Log.revealInFinder() }
                    .controlSize(.small)
                    .help("Reveal the OpenDisplay Receiver log files in Finder")
                if let updater {
                    CheckForUpdatesView(updater: updater)
                }
                Button("Quit") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 440, height: 520)
    }
}

extension View {
    /// `.formStyle(.grouped)` where it exists (macOS 13); the default form on
    /// macOS 12 is the same content in the older flat layout.
    @ViewBuilder
    func groupedFormStyle() -> some View {
        if #available(macOS 13, *) {
            formStyle(.grouped)
        } else {
            self
        }
    }
}
