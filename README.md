# DLiPA2

Ứng dụng iOS Native (**SwiftUI**) tải file `.ipa` trực tiếp từ máy chủ chính thức của Apple, nhúng trực tiếp lõi Go mới nhất của [`majd/ipatool`](https://github.com/majd/ipatool) thông qua `gomobile` (`Ipatoolbridge.xcframework`).

- **Không dùng máy chủ trung gian**: Toàn bộ đăng nhập (hỗ trợ 2FA), tìm kiếm, tra cứu phiên bản và tải `.ipa` đều giao tiếp trực tiếp với máy chủ Apple.
- **Dễ cập nhật**: Khi Apple thay đổi luồng xác thực/tải xuống và `majd/ipatool` cập nhật bản sửa lỗi, chỉ cần chạy lại workflow build là ứng dụng tự động nhận lõi mới nhất.

---

## Cấu trúc dự án

```text
.
├── Core/
│   ├── go.mod                      # Phụ thuộc trực tiếp github.com/majd/ipatool/v2
│   └── ipatoolbridge/              # Lớp bridge Go <-> Swift (gomobile)
│       ├── bridge.go               # Quản lý đa tài khoản, Login + 2FA, Revoke
│       ├── search.go               # Tìm kiếm App Store & đổi Storefront
│       ├── versions.go             # Lịch sử phiên bản (ListVersions, GetVersionMetadata)
│       ├── download.go             # Purchase + Download + ReplicateSinf + tiến trình
│       ├── keychain.go             # Lưu thông tin tài khoản theo sandbox iOS
│       └── machine.go              # Định danh thiết bị ổn định cho sandbox iOS
├── iOS/
│   ├── project.yml                 # Cấu hình XcodeGen
│   └── DLiPA2/                     # Mã nguồn SwiftUI (iOS 15+)
├── scripts/
│   ├── build-xcframework.sh        # Build libunicorn.a (iOS) + Ipatoolbridge.xcframework
│   └── patches/unicorn-ios.patch   # Patch W^X cho Unicorn Engine trên iOS
└── .github/workflows/build-ios.yml # Tự động build file DLiPA2.ipa trên macOS runner
```

---

## Cách build file `DLiPA2.ipa`

### Cách 1: Tự động qua GitHub Actions (khuyên dùng nếu dùng Windows)
1. Push thư mục dự án này lên một repository GitHub của bạn.
2. Vào tab **Actions** → chọn workflow **Build DLiPA2 iOS IPA** → nhấn **Run workflow**.
3. Sau khi chạy xong, tải file `DLiPA2.ipa` ở mục **Artifacts**.

### Cách 2: Build trực tiếp trên macOS
Yêu cầu: Xcode, Go 1.26+, `cmake`, `xcodegen`, `gomobile`.

```bash
brew install cmake xcodegen
go install golang.org/x/mobile/cmd/gomobile@latest
go install golang.org/x/mobile/cmd/gobind@latest
gomobile init

./scripts/build-xcframework.sh
cd iOS && xcodegen generate
open DLiPA2.xcodeproj
```

---

## Lưu ý quan trọng khi chạy trên iOS

1. **Ký & Cài đặt `.ipa`**: File `.ipa` xuất ra từ GitHub Actions là bản **unsigned**. Bạn có thể ký và cài đặt qua **TrollStore**, **SideStore**, **AltStore**, hoặc chứng chỉ nhà phát triển cá nhân.
2. **Yêu cầu JIT cho SAP Signing (Unicorn Engine)**: Phiên bản mới của `majd/ipatool` sử dụng **Unicorn Engine** (`libunicorn.a`) để thực hiện bắt tay chữ ký SAP của Apple cục bộ. Khi đăng nhập trên iOS, thiết bị cần môi trường cho phép thực thi bộ nhớ W^X / JIT (ví dụ: TrollStore, máy đã Jailbreak, hoặc bật JIT qua SideStore/StikDebug).
3. **Vị trí lưu file `.ipa`**: Các file tải về được lưu trực tiếp trong ứng dụng **Tệp (Files)** → **Trên iPhone của tôi (On My iPhone)** → **DLiPA2** → **IPAs** và có thể chia sẻ trực tiếp từ tab **Tải xuống**.
