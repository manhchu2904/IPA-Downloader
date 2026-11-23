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
  <b>Tiếng Việt</b> | <a href="README_EN.md">English</a>
</p>

Ứng dụng iOS viết bằng SwiftUI giúp tìm kiếm ứng dụng, xem lịch sử phiên bản cũ, tải file `.ipa` trực tiếp từ App Store và cài thẳng lên máy mà không cần máy tính.

Ứng dụng nhúng lõi Go từ [`majd/ipatool`](https://github.com/majd/ipatool) qua `gomobile` cùng **Unicorn Engine 2.1.4** để xử lý chữ ký FairPlay SAP ngay trên thiết bị.

---

## Tính năng chính

- **Kết nối trực tiếp tới Apple**: Đăng nhập và tải trực tiếp từ máy chủ Apple. Thông tin tài khoản và phiên đăng nhập được lưu cục bộ trên máy, tự làm mới khi hết hạn.
- **Xem và tải phiên bản cũ**: Tra cứu nhanh danh sách các bản cũ kèm số phiên bản hiển thị (vd: `v1.2.3`) hoặc nhập trực tiếp External Version ID để tải.
- **Quản lý nhiều Apple ID**:
  - Hỗ trợ đăng nhập nhiều tài khoản (có xác thực 2FA) và đổi vùng App Store nhanh.
  - File `.ipa` tải về được chia riêng theo thư mục từng tài khoản (`Documents/IPAs/<Apple_ID>/`) để dễ quản lý và tránh nhầm bản quyền khi cài.
- **Cài đặt trực tiếp vào máy (OTA)**:
  - Cài file `.ipa` ngay trong ứng dụng qua `itms-services://`, có 2 chế độ tuỳ chọn ở tab **Tài khoản**:
    1. **Trực tiếp (Khuyên dùng)**: Không cần cài chứng chỉ. Chỉ gửi thông tin cơ bản (`Bundle ID`, tên app, phiên bản, cổng cục bộ) để tạo manifest HTTPS, còn file `.ipa` truyền trực tiếp từ máy qua `http://127.0.0.1:<port>/payload.ipa`.
    2. **HTTPS Cục bộ (Thử nghiệm)**: Tự tạo chứng chỉ Root CA nội bộ (RSA-2048) trên máy để cấp manifest và `.ipa` qua HTTPS cục bộ (cần cài và bật tin cậy hồ sơ chứng chỉ trong *Cài đặt → Cài đặt chung → Giới thiệu → Cài đặt tin cậy chứng chỉ*).
- **Tải nền ổn định**: Tiếp tục tải khi thoát ra màn hình chính hoặc khoá màn hình, hiển thị tốc độ tải theo thời gian thực và báo khi xong.

---

## Yêu cầu & Lưu ý

- **Hệ điều hành**: iOS / iPadOS 15.0 trở lên.
- **TrollStore**: Hoạt động thuận tiện nhất vì có sẵn quyền JIT và cài đặt vĩnh viễn.
- **SideStore / AltStore / StikDebug**:
  - Chỉ cần bật JIT lúc **đăng nhập Apple ID lần đầu** (hoặc khi phiên đăng nhập hết hạn cần xác thực lại).
  - Sau khi đã đăng nhập, các thao tác tìm kiếm, xem phiên bản cũ, tải `.ipa` và cài OTA đều chạy bình thường không cần JIT.

---

## Cấu trúc mã nguồn

```text
.
├── Core/
│   ├── go.mod                        # Module Go phụ thuộc majd/ipatool/v2
│   └── ipatoolbridge/
│       ├── bridge.go                 # Cầu nối Go <-> Swift
│       └── installer.go              # Máy chủ cục bộ cài đặt OTA
├── iOS/
│   ├── project.yml                   # Cấu hình XcodeGen
│   └── DLiPA2/                       # Giao diện SwiftUI
└── scripts/
    ├── build-xcframework.sh          # Script build libunicorn.a và Ipatoolbridge.xcframework
    └── patches/unicorn-ios.patch     # Bản vá Unicorn 2.1.4 cho iOS arm64
```

---

## Tham khảo & Cảm ơn

- **[majd/ipatool](https://github.com/majd/ipatool)** bởi [Majd Alfhaily](https://github.com/majd) — lõi giao tiếp App Store API và tải IPA.
- **[Unicorn Engine](https://www.unicorn-engine.org/)** — trình giả lập CPU phục vụ ký FairPlay SAP.

---

## Giấy phép

Phát hành theo giấy phép [MIT](LICENSE).

## Miễn trừ trách nhiệm

Dự án phục vụ mục đích học tập và sao lưu ứng dụng cá nhân. Ứng dụng không liên kết với Apple Inc.; người dùng tự chịu trách nhiệm khi sử dụng.
