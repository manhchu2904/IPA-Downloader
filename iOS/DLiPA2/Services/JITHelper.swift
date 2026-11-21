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

    @_silgen_name("ipatool_jit26_init_pool")
    private static func ipatoolJIT26InitPool(_ poolSize: Int) -> Int32

    @_silgen_name("ipatool_jit_pool_ready")
    private static func ipatoolJITPoolReady() -> Int32

    static func isJITEnabled() -> Bool {
        var flags: UInt32 = 0
        let result = csops(getpid(), csOpsStatus, &flags, MemoryLayout<UInt32>.size)
        guard result == 0 else { return false }
        return (flags & csDebugged) != 0
    }

    static func isJITPoolReady() -> Bool {
        ipatoolJITPoolReady() != 0
    }

    static func codeSigningFlagsHex() -> String {
        var flags: UInt32 = 0
        let result = csops(getpid(), csOpsStatus, &flags, MemoryLayout<UInt32>.size)
        guard result == 0 else { return "unavailable" }
        return String(format: "0x%08X", flags)
    }

    /// Pre-allocates a 32 MB reusable dual-mapped JIT pool (8 x 4 MB slots) when
    /// JIT is active, guarded safely against unhandled SIGTRAP/SIGBUS faults.
    static func prepareStartupJIT26PoolIfNeeded() {
        guard !isJITPoolReady() else { return }
        guard isJITEnabled() else { return }
        let ok = ipatoolJIT26InitPool(32 * 1024 * 1024)
        DebugLogger.log("JIT26 pool init returned: \(ok) (poolReady=\(isJITPoolReady()))")
    }
}
