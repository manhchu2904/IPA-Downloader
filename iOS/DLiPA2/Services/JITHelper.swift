import Foundation
import Darwin

enum JITHelper {
    private static let csOpsStatus: UInt32 = 0
    private static let csDebugged: UInt32 = 0x10000000

    @_silgen_name("csops")
    private static func csops(
        _ pid: pid_t,
        _ ops: UInt32,
        _ useraddr: UnsafeMutableRawPointer?,
        _ usersize: size_t
    ) -> Int32

    static func isJITEnabled() -> Bool {
        var flags: UInt32 = 0
        let result = csops(getpid(), csOpsStatus, &flags, MemoryLayout<UInt32>.size)
        guard result == 0 else { return false }
        return (flags & csDebugged) != 0
    }

    static func codeSigningFlagsHex() -> String {
        var flags: UInt32 = 0
        let result = csops(getpid(), csOpsStatus, &flags, MemoryLayout<UInt32>.size)
        guard result == 0 else { return "unavailable" }
        return String(format: "0x%08X", flags)
    }
}
