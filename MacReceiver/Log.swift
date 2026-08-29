// Logging for the macOS receiver.
//
// Deliberately NOT Mac/Log.swift: that one's RotatingLogFile hardcodes the
// base name "opendisplay" in the same directory, so running the sender and the
// receiver on one machine (which is the main dev loop) would have two processes
// rotating the same file and corrupting it. Separate file, separate rotation.

import Foundation

enum Log {
    private static let queue = DispatchQueue(label: "receiver.log")
    private static let maxBytes = 2 * 1024 * 1024

    private static let fileURL: URL? = {
        guard let logs = FileManager.default.urls(for: .libraryDirectory,
                                                  in: .userDomainMask).first?
            .appendingPathComponent("Logs/OpenDisplay", isDirectory: true)
        else { return nil }
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("opendisplay-receiver.log")
    }()

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func info(_ message: String) {
        let line = "\(stamp.string(from: Date())) \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        queue.async { append(line) }
    }

    private static func append(_ line: String) {
        guard let url = fileURL, let data = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        // Cheap rotation: once over the cap, keep the newer half.
        if let size = try? handle.offset(), size > maxBytes,
           let all = try? Data(contentsOf: url) {
            try? all.suffix(maxBytes / 2).write(to: url)
        }
    }

    /// Present so shared code that calls it still links; the receiver has no
    /// snapshot UI of its own.
    static func snapshot(context: Any? = nil, extra: Any? = nil) {}
}
