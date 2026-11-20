import Foundation
import Darwin

enum DebugLogger {
    private static let lock = NSLock()
    private static let maxLogBytes = 512 * 1024

    static var logURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("debug.log")
    }

    static func start() {
        trimIfOversized()
        freopen(logURL.path, "a+", stderr)
        setvbuf(stderr, nil, _IONBF, 0)
        log("DLiPA2 launch (JIT=\(JITHelper.isJITEnabled()), flags=\(JITHelper.codeSigningFlagsHex()))")
    }

    static func log(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let ts = ISO8601DateFormatter().string(from: Date())
        fputs("[\(ts)] \(message)\n", stderr)
    }

    static func readLog() -> String {
        (try? String(contentsOf: logURL, encoding: .utf8)) ?? "(Chưa có log)"
    }

    static func clearLog() {
        lock.lock()
        defer { lock.unlock() }
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
        let ts = ISO8601DateFormatter().string(from: Date())
        fputs("[\(ts)] Log cleared\n", stderr)
    }

    private static func trimIfOversized() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
              let size = attrs[.size] as? Int,
              size > maxLogBytes else {
            return
        }
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
    }
}
