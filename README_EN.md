# IPA Downloader

<p align="center">
  <img src="icon.png" width="110" alt="IPA Downloader Icon" style="border-radius: 24px;" />
</p>

<p align="center">
  <a href="https://github.com/manhchu2904/IPA-Downloader/actions/workflows/release-build.yml"><img src="https://github.com/manhchu2904/IPA-Downloader/actions/workflows/release-build.yml/badge.svg" alt="Release Build" /></a>
  <a href="https://github.com/manhchu2904/IPA-Downloader/actions/workflows/nightly-build.yml"><img src="https://github.com/manhchu2904/IPA-Downloader/actions/workflows/nightly-build.yml/badge.svg" alt="Nightly Build" /></a>
  <a href="https://github.com/manhchu2904/IPA-Downloader/releases"><img src="https://img.shields.io/github/v/release/manhchu2904/IPA-Downloader?include_prereleases&label=Release" alt="Latest Release" /></a>
  <img src="https://img.shields.io/badge/iOS-15.0%2B-blue" alt="iOS 15.0+" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License: MIT" /></a>
</p>

<p align="center">
  <a href="README.md">Tiếng Việt</a> | <b>English</b>
</p>

A native iOS (SwiftUI) application to search, inspect version history, download `.ipa` packages directly from Apple App Store servers, and **install them directly on-device (OTA)** without a computer.

Powered by [`majd/ipatool`](https://github.com/majd/ipatool) via `gomobile` (`Ipatoolbridge.xcframework`) and **Unicorn Engine 2.1.4** (patched with **Split-W^X Dual-Mapped JIT** supporting iOS 15 through iOS 26+).

---

## Highlights

- **Direct & Private**: All requests go directly between your device and Apple servers (iTunes Store API & App Store CDN). Credentials and session tokens stay securely in your device's Keychain, with automatic token refresh when `passwordToken` expires.
- **Instant Version History & Downgrade**: Quickly browse past builds with resolved human-readable version numbers (e.g. `v1.2.3`) without requiring JIT to view the version list.
- **Multi-Account & Per-Account IPA Categorization**:
  - Manage multiple Apple ID accounts with full Two-Factor Authentication (2FA) support and switch App Store storefronts effortlessly.
  - Downloaded `.ipa` packages are automatically organized into per-account folders (`Documents/IPAs/<Apple_ID>/`) so you always know which Apple ID owns the FairPlay license for each package.
- **Direct On-Device OTA Installation (`itms-services://`)**:
  - Install downloaded `.ipa` packages directly onto your device with two selectable modes in the **Accounts** tab:
    1. **Direct Mode (No CA Certificate Required)**: Sends only minimal app metadata (`Bundle ID`, `Title`, `Version`, `Localhost Port`) to generate a signed HTTPS plist manifest while streaming the `.ipa` payload 100% locally from `http://127.0.0.1:<port>/payload.ipa` (zero `.ipa` upload, zero external bandwidth).
    2. **Local HTTPS Mode (100% Offline)**: Generates an on-device ECDSA P-256 Root CA (`127.0.0.1`) so OTA installation works completely offline.
- **Background Download Keep-Alive**: Keeps active downloads running smoothly when switching apps or locking the screen, with live download speed (`MB/s`) and completion notifications.
- **Multi-Generation iOS JIT Engine (iOS 15 – iOS 26+)**: Automatic 3-tier JIT fallback (`Split-W^X vm_remap` for iOS 26 / StikDebug, `MAP_JIT` for TrollStore, and `Classic mprotect` for iOS 15–18).

---

## Project Structure

```text
.
├── Core/
│   ├── go.mod                              # Go module depending on majd/ipatool/v2
│   └── ipatoolbridge/
│       ├── bridge.go                       # Go-to-Swift bridge (Auth, Search, Version, Download)
│       └── installer.go                    # Local HTTP/HTTPS OTA installer server (itms-services)
├── iOS/
│   ├── project.yml                         # XcodeGen configuration (iOS 15.0+, Swift 5.9, arm64)
│   └── DLiPA2/                             # SwiftUI source code
├── scripts/
│   ├── build-xcframework.sh                # Build script for libunicorn.a & Ipatoolbridge.xcframework
│   └── patches/unicorn-ios.patch           # Split-W^X Dual-Mapping & JIT patch for Unicorn 2.1.4
└── .github/workflows/
    ├── release-build.yml                   # Release workflow triggered by Git tags (v*)
    ├── nightly-build.yml                   # Nightly CI workflow triggered on main branch pushes
    └── cleanup-workflows.yml               # Workflow to clean up obsolete and old workflow runs
```

---

## Installation & Requirements

- **System Requirement**: iOS / iPadOS 15.0 or later (fully compatible with iOS 26+).
- **Recommended: TrollStore (iOS 15.0 – 17.0)**: Runs best on TrollStore with out-of-the-box JIT entitlement and permanent installation.
- **JIT Requirement for SideStore / AltStore / Sideloadly / StikDebug**:
  - Apple's FairPlay SAP signing handshake during **initial account sign-in** (or token re-authentication) requires Unicorn Engine CPU emulation. You must enable JIT (via StikDebug, SideStore, or AltStore) when signing into an Apple ID.
  - Once logged in, **App Search**, **Version History lookup**, **IPA Downloading**, and **On-Device OTA Installation** do **not** require JIT.

---

## CI/CD Workflows & Building the IPA

The repository provides two dedicated GitHub Actions workflows:

### 1. `Release Build` (`.github/workflows/release-build.yml`)
- **Triggers**: Automatically runs when pushing a version tag matching `v*` (e.g., `v1.0.0`, `v1.1.0`), or manually via `workflow_dispatch`.
- **Automatic Tag-to-App Version Injection**: Extracts the version string from the Git tag (e.g. `v1.0.1` → `1.0.1`), injects it into `CFBundleShortVersionString` and `CFBundleVersion` inside `iOS/DLiPA2/Info.plist` before compiling, and automatically publishes a **GitHub Release** with `IPADownloader-v<version>.ipa` and its `.sha256` checksum attached.
- **Publishing a new Release via Git tag**:
  ```bash
  git tag v1.0.1
  git push origin v1.0.1
  ```

### 2. `Nightly Build` (`.github/workflows/nightly-build.yml`)
- **Triggers**: Automatically runs on code pushes to `main` or manually via `workflow_dispatch` (with `Release` or `Debug` configuration option).
- **Build Stamping**: Automatically stamps `<base_version>-nightly.<short_sha>` into `Info.plist` (visible in-app under **Accounts → Info & Source Code**) and uploads the `.ipa` package as a workflow artifact.

### 3. `Cleanup Workflow Runs` (`.github/workflows/cleanup-workflows.yml`)
- **Action History Cleanup**: Automatically deletes all historical runs of removed workflow files (such as the old `build-ios.yml`), cleans up failed/cancelled runs, and retains only the most recent runs per active workflow.

### 4. Build Manually on macOS
**Prerequisites**: macOS with Xcode 16+, Go 1.26+, `cmake`, `xcodegen`.

```bash
# 1. Install prerequisites
brew install cmake xcodegen
go install golang.org/x/mobile/cmd/gomobile@latest
go install golang.org/x/mobile/cmd/gobind@latest
gomobile init

# 2. Build framework and generate Xcode project
chmod +x scripts/build-xcframework.sh
./scripts/build-xcframework.sh
cd iOS && xcodegen generate

# 3. Open in Xcode
open DLiPA2.xcodeproj
```

---

## Acknowledgments

Special thanks to:

- **[majd/ipatool](https://github.com/majd/ipatool)** by **[Majd Alfhaily](https://github.com/majd)**: The outstanding open-source CLI tool that provides the core logic for communicating with the App Store API, handling authentication, and downloading IPAs.
- **[Unicorn Engine](https://www.unicorn-engine.org/)**: Multi-architecture CPU emulator framework used for FairPlay SAP signing emulation.

---

## License

This project is released under the [MIT License](LICENSE).

---

## Disclaimer

- This project is developed solely for **educational, reverse-engineering research, and personal app backup purposes**.
- This project is not affiliated with, sponsored, or endorsed by Apple Inc.
- The author assumes no responsibility or liability for any misuse, violation of the Apple Media Services Terms and Conditions, or unauthorized distribution of copyrighted material.
