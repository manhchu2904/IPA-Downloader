import Foundation
import Darwin

enum DebugLogger {
    static var logURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("debug.log")
    }

    static func start() {
        freopen(logURL.path, "a+", stderr)
        setvbuf(stderr, nil, _IONBF, 0)
        log("DLiPA2 launch (JIT=\(JITHelper.isJITEnabled()), flags=\(JITHelper.codeSigningFlagsHex()))")
    }

    static func log(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        fputs("[\(ts)] \(message)\n", stderr)
    }

    static func readLog() -> String {
        (try? String(contentsOf: logURL, encoding: .utf8)) ?? "(Chưa có log)"
    }

    static func clearLog() {
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
        log("Log cleared")
    }
}
