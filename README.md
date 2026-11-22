# IPA Downloader

<p align="center">
  <b>Tiếng Việt</b> | <a href="README_EN.md">English</a>
</p>

Ứng dụng iOS thuần (SwiftUI) cho phép tìm kiếm, tra cứu phiên bản cũ và tải file `.ipa` trực tiếp từ máy chủ App Store về iPhone/iPad mà không cần thông qua máy tính hay bất kỳ server trung gian nào.

Dự án nhúng trực tiếp lõi Go của [`majd/ipatool`](https://github.com/majd/ipatool) vào iOS qua `gomobile` (`Ipatoolbridge.xcframework`), kết hợp cùng **Unicorn Engine** để xử lý chữ ký số SAP FairPlay ngay trên thiết bị.

---

## Điểm nổi bật

- **Trực tiếp & Bảo mật**: Thiết bị của bạn giao tiếp thẳng với máy chủ Apple (iTunes API & App Store CDN). Thông tin đăng nhập Apple ID được lưu an toàn trong Keychain trên máy, không gửi qua bất kỳ bên thứ ba nào.
- **Tải phiên bản cũ (Version History)**: Xem danh sách các bản build trước đây của ứng dụng và tải về phiên bản bạn cần.
- **Đa tài khoản & Đổi vùng**: Đăng nhập nhiều Apple ID cùng lúc (hỗ trợ 2FA), dễ dàng đổi Storefront sang các quốc gia khác (Mỹ, Nhật, Việt Nam,...) để tải app giới hạn vùng.
- **Tự động nhận giấy phép**: Tự động "mua" bản quyền cho các app miễn phí nếu tài khoản của bạn chưa từng tải ứng dụng đó trước đây.
- **Tiện lợi với ứng dụng Tệp (Files)**: File `.ipa` tải về được lưu tại `Tệp` → `Trên iPhone` → `IPA Downloader` → `IPAs`. Bạn có thể mở trực tiếp bằng TrollStore để cài đặt ngay, hoặc chia sẻ qua AirDrop.
- **Công cụ hỗ trợ tích hợp**: Có sẵn màn hình kiểm tra trạng thái JIT và trình xem nhật ký gỡ lỗi (Debug Logs) ngay trong app.

---

## Cấu trúc thư mục

```text
.
├── Core/
│   ├── go.mod                      # Module Go phụ thuộc majd/ipatool/v2
│   └── ipatoolbridge/              # Lớp cầu nối Go <-> Swift qua gomobile
├── iOS/
│   ├── project.yml                 # Cấu hình dự án cho XcodeGen
│   └── DLiPA2/                     # Mã nguồn giao diện SwiftUI (iOS 15+)
├── scripts/
│   ├── build-xcframework.sh        # Script build libunicorn.a và Ipatoolbridge.xcframework
│   └── patches/unicorn-ios.patch   # Patch hỗ trợ W^X / JIT cho Unicorn Engine trên iOS
└── .github/workflows/build-ios.yml # Workflow CI tự động đóng gói IPA trên macOS runner
```

---

## Cài đặt & Lưu ý khi sử dụng

- **Yêu cầu hệ điều hành**: iOS / iPadOS 15.0 trở lên.
- **Khuyên dùng TrollStore**: Ứng dụng chạy mượt mà nhất trên TrollStore vì được cấp sẵn quyền thực thi mã động (JIT), không bị giới hạn 7 ngày và không cần gia hạn chứng chỉ.
- **Lưu ý về JIT (khi dùng SideStore / AltStore / Sideloadly)**:
  Apple yêu cầu thuật toán ký SAP khi đăng nhập, phần này được chạy qua Unicorn Engine giả lập. Vì vậy, khi đăng nhập tài khoản lần đầu trên các máy cài qua sideload thông thường, bạn cần kích hoạt JIT cho app (qua SideStore/AltStore/StikDebug). Sau khi đã đăng nhập thành công và lưu phiên, các thao tác sau sẽ không cần JIT nữa.

---

## Cách build file IPA

### Cách 1: Tự động qua GitHub Actions (Không cần Mac)

1. Fork repository này về tài khoản GitHub của bạn.
2. Vào tab **Actions** → chọn workflow **Build IPA Downloader iOS IPA**.
3. Bấm **Run workflow** (chọn nhánh `main`, cấu hình `Release`).
4. Chờ build xong (khoảng 5-10 phút), tải file `.ipa` tại mục **Artifacts**.

### Cách 2: Tự build trên máy Mac

**Yêu cầu**: macOS có sẵn Xcode 15+, Go 1.26+, `cmake`, `xcodegen`.

```bash
# Cài đặt công cụ
brew install cmake xcodegen
go install golang.org/x/mobile/cmd/gomobile@latest
go install golang.org/x/mobile/cmd/gobind@latest
gomobile init

# Build framework và generate Xcode project
chmod +x scripts/build-xcframework.sh
./scripts/build-xcframework.sh
cd iOS && xcodegen generate

# Mở dự án trong Xcode
open DLiPA2.xcodeproj
```

---

## Lời cảm ơn

Dự án được phát triển dựa trên nền tảng của:

- **[majd/ipatool](https://github.com/majd/ipatool)** bởi **[Majd Alfhaily](https://github.com/majd)**: Công cụ CLI mã nguồn mở tuyệt vời giúp giao tiếp với App Store API, xử lý xác thực và tải xuống file IPA.

---

## Giấy phép

Dự án được phân phối dưới giấy phép [MIT](LICENSE).

---

## Miễn trừ trách nhiệm

- Dự án này được phát triển hoàn toàn vì mục đích **học tập, nghiên cứu kỹ thuật và quản lý/sao lưu ứng dụng cá nhân**.
- Ứng dụng không liên kết, không được tài trợ hoặc xác nhận bởi Apple Inc.
- Tác giả không chịu trách nhiệm đối với bất kỳ hành vi lạm dụng, vi phạm Điều khoản Dịch vụ của Apple (Apple Terms of Service) hoặc phân phối lại các ứng dụng có bản quyền trái phép.
