---
name: unicorn-ios
description: >-
  Troubleshooting and build guide for Unicorn Engine (libunicorn.a v2.1.4) on
  iOS arm64 in DLiPA2, including scripts/patches/unicorn-ios.patch, CMake
  cross-compilation, MAP_JIT vs W^X mprotect, pthread_jit_write_protect_np,
  and linker integration with majd/ipatool via gomobile. Use when fixing Unicorn
  build failures, patch apply errors, undefined symbols, or iOS runtime JIT
  crashes during Apple SAP signing.
---

# Unicorn Engine on iOS (`libunicorn.a`) — DLiPA2 Guide

## How Unicorn Fits Into DLiPA2

- `github.com/majd/ipatool/v2` uses Unicorn Engine (x86 emulation via TCG) to run Apple's SAP signing handshake locally.
- On iOS arm64, `scripts/build-xcframework.sh` downloads Unicorn `2.1.4`, applies `scripts/patches/unicorn-ios.patch`, cross-compiles `libunicorn.a` with CMake (`-DUNICORN_ARCH=x86`), and copies it to `iOS/Frameworks/libunicorn.a`.
- `iOS/project.yml` links `libunicorn.a` into the final app with:
  - `-ObjC`
  - `-Wl,-force_load,$(SRCROOT)/Frameworks/libunicorn.a`
  - `-Wl,-export_dynamic`

## Key Patch Mechanics (`scripts/patches/unicorn-ios.patch`)

1. **`qemu/configure` & `qemu/include/tcg/tcg-apple-jit.h`**:
   - Replaces macOS-only `HAVE_PTHREAD_JIT_PROTECT` compile-time checks with `#if defined(__ENVIRONMENT_IPHONE_OS_VERSION_MIN_REQUIRED__)`.
   - Routes `jit_write_protect(enabled)` to `ipatool_jit_write_protect(uc, enabled)`.
2. **`qemu/accel/tcg/translate-all.c`**:
   - Tries `mmap(..., PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS | 0x0800, ...)` (`MAP_JIT = 0x0800`) first (`mode=1`).
   - Falls back to `PROT_READ | PROT_WRITE` (`mode=3`, W^X `mprotect` toggling) when `MAP_JIT` is denied.
   - Resolves `pthread_jit_write_protect_supported_np` and `pthread_jit_write_protect_np` dynamically via `dlsym(RTLD_DEFAULT, ...)` to avoid missing-symbol link errors on iOS SDKs.
3. **`uc.c`**:
   - Guards `save_jit_state` under `__ENVIRONMENT_IPHONE_OS_VERSION_MIN_REQUIRED__`.

## Common Failure Modes & Where to Look

1. **Patch apply failure (`patch -p1 < unicorn-ios.patch`)**:
   - Occurs if Unicorn version changes or line numbers/context drift. Check `UNICORN_TAR` URL and SHA-256 in `scripts/build-xcframework.sh`.
2. **CMake iOS cross-compile errors**:
   - Verify `-DCMAKE_SYSTEM_NAME=iOS`, `-DCMAKE_OSX_SYSROOT="$SDKROOT"`, `-DCMAKE_OSX_ARCHITECTURES=arm64`, `-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0`, and `-DCMAKE_C_FLAGS='-target arm64-apple-ios15.0'`.
   - Ensure `DUNICORN_ARCH=x86` matches what `majd/ipatool` emulates.
3. **Linker errors in `xcodebuild` / `gomobile`**:
   - `Undefined symbol: _uc_open` (or `_uc_emu_start`, etc.): Check that `libunicorn.a` was built for `arm64` iOS (not macOS host) and is force-loaded via `-Wl,-force_load,$(SRCROOT)/Frameworks/libunicorn.a`.
   - Duplicate symbols or CGO header mismatch: Check `majd/ipatool/v2` version in `Core/go.mod` vs how `ipatool` binds Unicorn (purego/dlopen vs CGO). Note `-Wl,-export_dynamic` is required when Go loads `libunicorn` symbols dynamically from the main binary via `dlsym`!
4. **Runtime crash on iOS during login / SAP handshake (`EXC_BAD_ACCESS` / `SIGBUS` / `SIGKILL CS_KILL`)**:
   - Check stderr logs for `[unicorn-ios] alloc_code_gen_buffer: mode=1` vs `mode=3` and `mprotect(...) failed errno=...`.
   - `mode=1` (`MAP_JIT`) requires JIT entitlement or debugger/StikDebug/TrollStore/Jailbreak.
   - `mode=3` (`mprotect` toggling RW <-> RX) fails with `EACCES` (`errno=13`) on stock non-JIT iOS without dynamic code signing / `CS_DEBUGGED`.
   - If `pthread_jit_write_protect_np` is unavailable or `mprotect` fails, verify thread write-protection state and instruction cache invalidation (`sys_icache_invalidate`).
