import Foundation
import Darwin

enum JITHelper {
    private static let csOpsStatus: UInt32 = 0
    private static let csDebugged: UInt32 = 0x10000000
    private static let mapJITFlag: Int32 = 0x0800

    @_silgen_name("csops")
    private static func csops(
        _ pid: pid_t,
        _ ops: UInt32,
        _ useraddr: UnsafeMutableRawPointer?,
        _ usersize: size_t
    ) -> Int32

    @_silgen_name("ipatool_jit26_init_pool")
    private static func ipatoolInitJITPool(_ poolSize: Int) -> Int32

    @_silgen_name("ipatool_jit_pool_ready")
    private static func ipatoolJITPoolReady() -> Int32

    static func isCSDebugged() -> Bool {
        var flags: UInt32 = 0
        let result = csops(getpid(), csOpsStatus, &flags, MemoryLayout<UInt32>.size)
        guard result == 0 else { return false }
        return (flags & csDebugged) != 0
    }

    static func canAllocateMapJIT() -> Bool {
        let pageSize = Int(getpagesize())
        guard pageSize > 0 else { return false }
        let ptr = mmap(
            nil,
            pageSize,
            PROT_READ | PROT_WRITE | PROT_EXEC,
            MAP_PRIVATE | MAP_ANON | mapJITFlag,
            -1,
            0
        )
        guard ptr != MAP_FAILED, let validPtr = ptr else {
            return false
        }
        munmap(validPtr, pageSize)
        return true
    }

    static func isJITEnabled() -> Bool {
        isJITPoolReady() || isCSDebugged() || canAllocateMapJIT()
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

    static func activeModeBadgeText() -> String {
        if isJITPoolReady() {
            return "Pool 32 MB"
        }
        if isCSDebugged() {
            return "Split-W^X"
        }
        if canAllocateMapJIT() {
            return "MAP_JIT"
        }
        return "Chưa kích hoạt"
    }

    static func activeModeDetailText() -> String {
        if isJITPoolReady() || isCSDebugged() {
            return "Split-W^X Dual-Map"
        }
        if canAllocateMapJIT() {
            return "MAP_JIT (TrollStore)"
        }
        return "Cần bật JIT để sử dụng"
    }

    static func activeMechanismSummary(iosVersion: String) -> String {
        if isJITPoolReady() || isCSDebugged() {
            return "Split-W^X (iOS \(iosVersion))"
        }
        if canAllocateMapJIT() {
            return "MAP_JIT (iOS \(iosVersion))"
        }
        return "Chưa bật JIT (iOS \(iosVersion))"
    }

    /// Pre-allocates a 32 MB reusable dual-mapped JIT pool (8 x 4 MB slots) on all iOS
    /// versions when CS_DEBUGGED or jailbreak is active, guarded safely against SIGTRAP/SIGBUS faults.
    static func prepareStartupJITPoolIfNeeded() {
        guard !isJITPoolReady() else { return }
        guard isCSDebugged() || access("/var/jb", F_OK) == 0 else { return }
        let ok = ipatoolInitJITPool(32 * 1024 * 1024)
        DebugLogger.log("JIT pool init returned: \(ok) (poolReady=\(isJITPoolReady()))")
    }
}
