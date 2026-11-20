---
name: dlipa2-bridge
description: >-
  Project-specific guide for DLiPA2's Go-to-SwiftUI architecture using gomobile,
  libunicorn.a, XcodeGen, and GitHub Actions iOS IPA builds. Use when modifying
  Core/ipatoolbridge, iOS/DLiPA2/Services/IPAToolService.swift, iOS/project.yml,
  scripts/build-xcframework.sh, or .github/workflows/build-ios.yml.
---

# DLiPA2 Go ↔ SwiftUI Bridge & Build Guide

## Architecture Overview

- **Go Core (`Core/ipatoolbridge/`)**: Wraps `github.com/majd/ipatool/v2` and is compiled into `iOS/Frameworks/Ipatoolbridge.xcframework` via `gomobile bind`.
- **SwiftUI App (`iOS/DLiPA2/`)**: Targets iOS 15.0+ (Swift 5.9), configured via XcodeGen (`iOS/project.yml`).
- **Unicorn Engine (`scripts/build-xcframework.sh`)**: Compiles `libunicorn.a` (v2.1.4 with `scripts/patches/unicorn-ios.patch`) for `arm64-apple-ios15.0` so `majd/ipatool` can perform Apple SAP signing on-device.
- **CI Build (`.github/workflows/build-ios.yml`)**: Runs on `macos-15` to build `libunicorn.a`, `Ipatoolbridge.xcframework`, generate `DLiPA2.xcodeproj`, compile unsigned `DLiPA2.app`, and package `DLiPA2.ipa`.

## `gomobile` Bridge Rules (`Core/ipatoolbridge/`)

1. **Exported signatures**: `gomobile bind` only supports basic types (`string`, `int`, `int64`, `float64`, `bool`, `[]byte`), `error` as the last return value, exported struct pointers, and simple callback interfaces.
2. **JSON DTO pattern**: Complex data structures (accounts, search results, version history, metadata) MUST be marshaled to JSON strings in Go and decoded with `JSONDecoder` in `iOS/DLiPA2/Services/IPAToolService.swift`.
3. **Method naming in Swift**: `gomobile` maps Go methods to Objective-C/Swift selectors (e.g., `NewClient(baseDir)` → `IpatoolbridgeNewClient(_:)`, `client.Search(accountID, term, ...)` → `client.search(_:term:...)`). Always keep Go parameter names and Swift call sites in sync.
4. **Blocking calls**: Every Go bridge call in `IPAToolService.swift` MUST run off the main actor via `runBlocking` (background `DispatchQueue`) and update `@Published` state on `@MainActor`.
5. **iOS Sandbox paths**: Persistent state (cookies, file keychain, machine ID) lives under `Application Support/DLiPA2Core`; downloaded `.ipa` files live under `Documents/IPAs` so they are visible in the iOS Files app.

## XcodeGen & Linking Rules (`iOS/project.yml`)

- Never commit generated `DLiPA2.xcodeproj` or `iOS/Frameworks/*` binaries if ignored; keep all project settings in `iOS/project.yml`.
- Preserve `OTHER_LDFLAGS` (`-ObjC`, `-Wl,-force_load,$(SRCROOT)/Frameworks/libunicorn.a`, `-Wl,-export_dynamic`) and system SDK links (`libresolv.tbd`, `Security.framework`, `SystemConfiguration.framework`).
- Keep `CODE_SIGNING_ALLOWED: NO` and `CODE_SIGNING_REQUIRED: NO` for unsigned IPA packaging.

## Verification Checklist

- After editing Go files in `Core/`, check syntax/types if Go is available (`cd Core && go vet ./...`) or verify all DTO JSON tags match `iOS/DLiPA2/Models/Models.swift`.
- After editing Swift files, ensure compatibility with **iOS 15.0** and **Swift 5.9** (avoid iOS 16+/17+-only APIs without `#available` guards, e.g., prefer `NavigationView` or guard `NavigationStack`, avoid `@Observable` without iOS 17 fallback).
- After editing build scripts or `project.yml`, verify `.github/workflows/build-ios.yml` steps still match expected paths.
