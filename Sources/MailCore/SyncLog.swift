import Foundation

/// Timing lines for sync diagnostics in ~/Library/Logs/NMail/sync.log. Never logs tokens or message content.
public enum SyncLog {
    private static let lock = NSLock()
    private static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/NMail")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "sync.log")
    }()
    private static let start = Date()

    public static func write(_ line: String) {
        let stamped = String(format: "%8.2fs ", Date().timeIntervalSince(start)) + line + "\n"
        lock.withLock {
            guard let handle = try? FileHandle(forWritingTo: url) else {
                try? Data(stamped.utf8).write(to: url)
                return
            }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(stamped.utf8))
        }
    }

    /// Runs `work`, logging how long it took.
    public static func time<T>(_ label: String, _ work: () async throws -> T) async rethrows -> T {
        let t0 = Date()
        let result = try await work()
        write("\(label) \(Int(Date().timeIntervalSince(t0) * 1000))ms")
        return result
    }
}
