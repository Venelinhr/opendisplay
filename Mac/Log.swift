import Foundation

/// Appends timestamped lines to /tmp/opensidecar-mac.log (and stdout) so the
/// stream can be debugged without a debugger attached.
///
/// The file is size-capped and rotated rather than unbounded. When a report
/// comes in, the useful window is the last few minutes before the problem, so
/// old history is worth nothing and a log that can grow without limit is a
/// liability: any per-frame or per-message code path that starts logging (an
/// encoder failing every frame, a peer sending message types this build
/// predates) would otherwise fill the disk. At most `maxBytes` x 2 survives.
///
/// Note this rotates rather than stopping at a ceiling. A hard cap would keep
/// the *oldest* bytes and discard everything recent, which is backwards.
enum Log {
    private static let path = "/tmp/opensidecar-mac.log"
    /// One generation back, so a rotation mid-incident doesn't leave us with an
    /// almost-empty file and no history.
    private static let rotatedPath = "/tmp/opensidecar-mac.log.1"
    /// Deliberately small. Normal operation logs session lifecycle events only,
    /// a few KB per session, and even at the worst spam rate we've measured
    /// (~24 KB/s) this still holds minutes, which is the window that matters.
    private static let maxBytes: UInt64 = 4 * 1024 * 1024

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

    private static func append(_ data: Data) {
        if handle == nil { openLog() }
        if written + UInt64(data.count) > maxBytes { rotate() }
        guard let handle else { return }
        do {
            try handle.write(contentsOf: data)
            written += UInt64(data.count)
        } catch {
            // The file was removed underneath us (/tmp cleaners do this) or the
            // volume went away. Drop the handle so the next line reopens
            // instead of every subsequent write failing forever.
            try? handle.close()
            Log.handle = nil
        }
    }

    private static func openLog() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }
        guard let opened = FileHandle(forWritingAtPath: path) else {
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
        try? fm.removeItem(atPath: rotatedPath)
        try? fm.moveItem(atPath: path, toPath: rotatedPath)
        openLog()
    }
}
