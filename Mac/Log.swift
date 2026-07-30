import AppKit
import Foundation

/// Appends timestamped lines to a log file (and stdout) so the stream can be
/// debugged without a debugger attached.
///
/// The file is size-capped and rotated rather than unbounded. Any per-frame or
/// per-message code path that starts logging (an encoder failing every frame, a
/// peer sending message types this build predates) would otherwise fill the
/// disk. At most `maxBytes` x 2 survives.
///
/// Note this rotates rather than stopping at a ceiling. A hard cap would keep
/// the *oldest* bytes and discard everything recent, which is backwards: when a
/// report comes in, the useful window is what happened just before the problem.
enum Log {
    /// `~/Library/Logs/OpenDisplay`. The platform convention, and deliberately
    /// not /tmp: macOS clears /tmp on reboot, and rebooting is the first thing
    /// someone tries before filing a bug, so a log there is gone exactly when
    /// it's wanted. Living here also means Console.app lists it under Log
    /// Reports without us doing anything.
    static let directory: URL = {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return library.appendingPathComponent("Logs/OpenDisplay", isDirectory: true)
    }()

    static let fileURL = directory.appendingPathComponent("opendisplay.log")
    /// One generation back, so a rotation mid-incident doesn't leave us with an
    /// almost-empty file and no history. Named so the order reads at a glance
    /// in Finder, since users will be sending both.
    private static let rotatedURL = directory.appendingPathComponent("opendisplay-previous.log")

    /// Sized from the steady-state rate: an active session logs one aggregated
    /// PHONE-STATS line (~256 bytes) every 5s, so ~180 KB per streaming hour.
    /// 8MB is therefore ~45 hours of active streaming in the live file alone,
    /// and rotation means at least that much always survives. Idle time costs
    /// almost nothing, so in wall-clock terms this is comfortably days.
    private static let maxBytes: UInt64 = 8 * 1024 * 1024

    private static let queue = DispatchQueue(label: "log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    // Both only touched inside `queue`, which is serial, so no locking.
    // The handle is held open across lines: reopening per line costs ~22us
    // against ~1us for a write to a live handle.
    private static var handle: FileHandle?
    private static var written: UInt64 = 0

    static func info(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        print(line, terminator: "")
        guard let data = line.data(using: .utf8) else { return }
        queue.async { append(data) }
    }

    /// Shows the log files in Finder, for "send me your logs" support requests.
    /// Hops through `queue` first so anything already logged is on disk before
    /// the user grabs the file.
    static func revealInFinder() {
        queue.async {
            if handle == nil { openLog() }
            let existing = [fileURL, rotatedURL].filter {
                FileManager.default.fileExists(atPath: $0.path)
            }
            DispatchQueue.main.async {
                if existing.isEmpty {
                    // Nothing logged yet; still open the folder so the user
                    // isn't left staring at a menu item that did nothing.
                    NSWorkspace.shared.open(directory)
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting(existing)
                }
            }
        }
    }

    private static func append(_ data: Data) {
        if handle == nil { openLog() }
        if written + UInt64(data.count) > maxBytes { rotate() }
        guard let handle else { return }
        do {
            try handle.write(contentsOf: data)
            written += UInt64(data.count)
        } catch {
            // The file was removed underneath us or the volume went away. Drop
            // the handle so the next line reopens instead of every subsequent
            // write failing forever.
            try? handle.close()
            Log.handle = nil
        }
    }

    private static func openLog() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let opened = FileHandle(forWritingAtPath: fileURL.path) else {
            handle = nil
            written = 0
            return
        }
        handle = opened
        // Append to whatever a previous run left behind.
        written = (try? opened.seekToEnd()) ?? 0
    }

    private static func rotate() {
        try? handle?.close()
        handle = nil
        let fm = FileManager.default
        try? fm.removeItem(at: rotatedURL)
        try? fm.moveItem(at: fileURL, to: rotatedURL)
        openLog()
    }
}
