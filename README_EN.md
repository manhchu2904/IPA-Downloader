# IPA Downloader

<p align="center">
  <b>A native iOS (SwiftUI) application to search, inspect version history, and download <code>.ipa</code> packages directly from Apple App Store servers.</b><br>
  Powered by <a href="https://github.com/majd/ipatool">majd/ipatool</a> via <code>gomobile</code> (<code>Ipatoolbridge.xcframework</code>) and <b>Unicorn Engine</b>.
</p>

<p align="center">
  <a href="README.md">Tiếng Việt</a> | <b>English</b>
</p>

---

## Highlights

- **Direct & Private**: All requests go directly between your device and Apple servers (iTunes Store API & App Store CDN). No third-party proxy or intermediary servers — credentials stay securely in your device's Keychain.
- **Version History & Downgrade**: Browse past builds/versions of an application and download any specific release.
- **Multi-Account & Country Switching**: Manage multiple Apple ID accounts with full Two-Factor Authentication (2FA) support. Easily switch App Store regions (US, Japan, Vietnam, UK, etc.) to fetch region-locked apps.
- **Automatic License Acquisition**: Automatically purchases/acquires license for free apps if your account hasn't claimed them yet.
- **Seamless Files App Integration**: Downloaded `.ipa` files are saved directly to `Files` → `On My iPhone` → `IPA Downloader` → `IPAs`. Easily open and install them via TrollStore, or share them through AirDrop.
- **Built-in Utilities**: Integrated JIT status checker and live real-time debug logger.

---

## Project Structure

```text
.
├── Core/
│   ├── go.mod                      # Go module depending on majd/ipatool/v2
│   └── ipatoolbridge/              # Go-to-Swift bridge layer via gomobile
├── iOS/
│   ├── project.yml                 # XcodeGen configuration (iOS 15.0+, Swift 5.9)
│   └── DLiPA2/                     # SwiftUI source code
├── scripts/
│   ├── build-xcframework.sh        # Build script for libunicorn.a (iOS arm64) & Ipatoolbridge.xcframework
│   └── patches/unicorn-ios.patch   # W^X / JIT patch for Unicorn Engine on iOS
└── .github/workflows/build-ios.yml # GitHub Actions workflow to package IPA on macOS runners
```

---

## Installation & Requirements

- **System Requirement**: iOS / iPadOS 15.0 or later.
- **Recommended: TrollStore**: Runs best on TrollStore with out-of-the-box JIT entitlement, no 7-day expiration, and no certificate revocation.
- **JIT Requirement for SideStore / AltStore / Sideloadly**:
  Apple's FairPlay SAP signing handshake during authentication requires Unicorn Engine CPU emulation. When signing into an account for the first time on a conventionally sideloaded device, you must enable JIT (via SideStore, AltStore, StikDebug, or JIT Streamer). Once logged in and credentials are saved, ongoing searches and downloads do not require JIT.

---

## Building the IPA

### Option 1: GitHub Actions (Recommended - No Mac required)

1. Fork this repository to your GitHub account.
2. Go to the **Actions** tab → select **Build IPA Downloader iOS IPA**.
3. Click **Run workflow** (branch `main`, configuration `Release`).
4. Wait for the build to finish (about 5–10 minutes), then download the `.ipa` from the **Artifacts** section.

### Option 2: Build Manually on macOS

**Prerequisites**: macOS with Xcode 15+, Go 1.26+, `cmake`, `xcodegen`.

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

---

## License

This project is released under the [MIT License](LICENSE).

---

## Disclaimer

- This project is developed solely for **educational, reverse-engineering research, and personal app backup purposes**.
- This project is not affiliated with, sponsored, or endorsed by Apple Inc.
- The author assumes no responsibility or liability for any misuse, violation of the Apple Media Services Terms and Conditions, or unauthorized distribution of copyrighted material.
