# DLiPA2 - IPA Downloader for iOS

<p align="center">
  <b>Ứng dụng iOS Native (SwiftUI) tải file <code>.ipa</code> trực tiếp từ máy chủ Apple App Store chính thức.</b><br>
  Nhúng trực tiếp lõi Go mới nhất của <a href="https://github.com/majd/ipatool">majd/ipatool</a> thông qua <code>gomobile</code> (<code>Ipatoolbridge.xcframework</code>).
</p>

---

## 🌟 Tính năng nổi bật

- 🚀 **Tải trực tiếp không qua trung gian**: Giao tiếp trực tiếp 100% giữa thiết bị iOS và máy chủ Apple (iTunes Store API & App Store CDN). Không thông qua bất kỳ server proxy bên thứ ba nào, đảm bảo tối đa bảo mật và quyền riêng tư cho Apple ID của bạn.
- 👥 **Quản lý đa tài khoản Apple ID**: Hỗ trợ đăng nhập cùng lúc nhiều tài khoản, chuyển đổi tài khoản linh hoạt, lưu trữ an toàn trong sandbox Keychain của ứng dụng và hỗ trợ đầy đủ mã xác thực 2 yếu tố (2FA).
- 🌍 **Đổi Storefront linh hoạt**: Dễ dàng chuyển đổi vùng/quốc gia App Store (Việt Nam, Mỹ, Nhật Bản, Hàn Quốc, Anh, v.v.) để tìm kiếm và tải ứng dụng theo từng quốc gia.
- 🔍 **Tìm kiếm & Xem chi tiết ứng dụng**: Tìm kiếm theo tên ứng dụng hoặc Bundle ID, xem đầy đủ metadata, giá bán, phiên bản hiện tại và ảnh minh họa.
- ⏳ **Lịch sử phiên bản (Version History)**: Xem danh sách toàn bộ các bản build cũ trong lịch sử của ứng dụng và cho phép tải về bất kỳ phiên bản nào theo yêu cầu.
- ⚡ **Tự động nhận bản quyền (Auto License Purchase)**: Tự động cấp phép bản quyền cho các ứng dụng miễn phí nếu tài khoản của bạn chưa từng tải trước đó.
- 📥 **Quản lý tiến trình tải thông minh**: Hiển thị phần trăm, tốc độ tải thời gian thực và thời gian dự kiến hoàn thành. Tải song song trên hàng đợi nền không gây đơ lag giao diện.
- 📁 **Tích hợp sâu ứng dụng Tệp (Files)**: File `.ipa` tải về được lưu tại thư mục `Tệp (Files)` → `Trên iPhone của tôi (On My iPhone)` → `IPA Downloader` → `IPAs`. Dễ dàng mở rộng, cài đặt qua TrollStore/AltStore/SideStore hoặc chia sẻ qua AirDrop.
- 🛠️ **JIT Helper & Live Debug Logs**: Tích hợp tiện ích kiểm tra trạng thái JIT (cần thiết cho Apple SAP Signing) và màn hình xem nhật ký gỡ lỗi trực tiếp.

---

## 🏗️ Cấu trúc dự án

```text
.
├── Core/
│   ├── go.mod                      # Phụ thuộc github.com/majd/ipatool/v2
│   └── ipatoolbridge/              # Lớp bridge Go <-> Swift qua gomobile
│       ├── bridge.go               # Quản lý đa tài khoản, Login, 2FA, Revoke
│       ├── search.go               # Tìm kiếm App Store & đổi Storefront
│       ├── versions.go             # Lịch sử phiên bản (ListVersions, Metadata)
│       ├── download.go             # Purchase + Download + ReplicateSinf + Callback tiến trình
│       ├── keychain.go             # Quản lý lưu trữ tài khoản trong sandbox iOS
│       └── machine.go              # Cung cấp định danh thiết bị ổn định trên iOS
├── iOS/
│   ├── project.yml                 # File cấu hình XcodeGen (iOS 15.0+, Swift 5.9)
│   └── DLiPA2/                     # Mã nguồn ứng dụng SwiftUI
│       ├── DLiPA2App.swift         # Entrypoint ứng dụng
│       ├── Models/                 # DTO models & danh sách Storefronts các quốc gia
│       ├── Services/               # IPAToolService, JITHelper, DebugLogger
│       └── Views/                  # SearchView, AppDetailView, DownloadsView, AccountsView, DebugLogView
├── scripts/
│   ├── build-xcframework.sh        # Script build libunicorn.a (iOS arm64) + Ipatoolbridge.xcframework
│   └── patches/unicorn-ios.patch   # Patch W^X / MAP_JIT cho Unicorn Engine trên iOS
└── .github/workflows/build-ios.yml # Workflow tự động build file IPADownloader.ipa trên GitHub Actions
```

---

## 📱 Yêu cầu hệ thống & Lưu ý quan trọng

1. **Yêu cầu iOS**: Thiết bị chạy **iOS 15.0 trở lên**.
2. **Ký & Cài đặt `.ipa`**:
   - File `.ipa` xuất ra từ bản build là **unsigned**.
   - Khuyên dùng cài đặt qua **TrollStore** (tốt nhất vì tự cấp quyền thực thi JIT vĩnh viễn và không bị giới hạn 7 ngày).
   - Ngoài ra có thể cài qua **SideStore**, **AltStore**, **Scarlet**, **Sideloadly**, hoặc chứng chỉ Developer.
3. **Yêu cầu JIT cho Apple SAP Signing (Unicorn Engine)**:
   - Các bản cập nhật gần đây của giao thức Apple yêu cầu thực hiện bắt tay chữ ký SAP (FairPlay/SAP handshake) thông qua **Unicorn Engine** (`libunicorn.a`) giả lập trên thiết bị.
   - Vì iOS áp dụng chính sách bảo mật cấm vùng nhớ thực thi (W^X), thiết bị cần hỗ trợ JIT/W^X khi đăng nhập tài khoản lần đầu.
   - **TrollStore**: Hoạt động ngay lập tức mà không cần thao tác thêm.
   - **SideStore / AltStore**: Cần kích hoạt JIT cho ứng dụng trước khi thực hiện đăng nhập.

---

## 🔨 Hướng dẫn Build file `IPADownloader.ipa`

### Cách 1: Tự động qua GitHub Actions (Khuyên dùng)

Đây là cách đơn giản và tiện lợi nhất, bạn không cần phải có máy Mac:

1. Fork hoặc Push mã nguồn repository này lên GitHub cá nhân của bạn.
2. Trên trang repository, chuyển sang tab **Actions**.
3. Chọn workflow **Build IPA Downloader iOS IPA** ở cột bên trái.
4. Bấm nút **Run workflow** (chọn nhánh `main` và cấu hình `Release`).
5. Đợi workflow hoàn tất (khoảng 5 - 10 phút), cuộn xuống mục **Artifacts** để tải về file zip chứa `IPADownloader-Release.ipa`.

### Cách 2: Build thủ công trên macOS

**Yêu cầu môi trường:**
- macOS có cài sẵn Xcode 15 trở lên
- Go 1.26+
- Công cụ: `cmake`, `xcodegen`, `gomobile`

Chạy các lệnh sau trong Terminal:

```bash
# 1. Cài đặt các công cụ cần thiết
brew install cmake xcodegen
go install golang.org/x/mobile/cmd/gomobile@latest
go install golang.org/x/mobile/cmd/gobind@latest
gomobile init

# 2. Build libunicorn.a (iOS) và Ipatoolbridge.xcframework
chmod +x scripts/build-xcframework.sh
./scripts/build-xcframework.sh

# 3. Tạo dự án Xcode bằng XcodeGen
cd iOS
xcodegen generate

# 4. Mở dự án bằng Xcode để build hoặc chạy thử
open DLiPA2.xcodeproj
```

---

## 💖 Lời cảm ơn (Thanks to / Acknowledgments)

Dự án này gửi lời cảm ơn chân thành và sâu sắc nhất đến **[majd/ipatool](https://github.com/majd/ipatool)** của tác giả **[Majd Alfhaily](https://github.com/majd)** — dự án mã nguồn mở tuyệt vời đã cung cấp toàn bộ nền tảng logic giao tiếp với App Store API, quy trình xác thực Apple ID và cơ chế tải xuống tệp IPA từ Apple.

---

## ⚠️ Tuyên bố miễn trừ trách nhiệm (Disclaimer)

- Dự án này được phát triển hoàn toàn vì mục đích **học tập, nghiên cứu và quản lý ứng dụng cá nhân**.
- Tác giả không khuyến khích và không chịu trách nhiệm cho bất kỳ hành vi lạm dụng, vi phạm Điều khoản Dịch vụ của Apple hoặc phân phối trái phép các phần mềm có bản quyền.
