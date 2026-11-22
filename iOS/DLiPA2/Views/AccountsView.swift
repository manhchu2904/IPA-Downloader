import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var service: IPAToolService
    @State private var showAddSheet = false
    @State private var showDebugLog = false
    @State private var errorAlert: String?
    @State private var jitEnabled = JITHelper.isJITEnabled()
    @State private var jitPoolReady = JITHelper.isJITPoolReady()
    @AppStorage("otaUseLocalHTTPS") private var otaUseLocalHTTPS = false

    var body: some View {
        NavigationView {
            List {
                Section("Trạng thái JIT (Unicorn SAP)") {
                    HStack {
                        Image(systemName: jitEnabled ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(jitEnabled ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(jitEnabled ? "JIT đang bật (CS_DEBUGGED)" : "JIT chưa được bật")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Flags: \(JITHelper.codeSigningFlagsHex()) • Pool: \(jitPoolReady ? "Sẵn sàng (32 MB)" : "Chưa cấp phát")")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            refreshJITState()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                    }
                    if !jitEnabled {
                        Text("Hãy mở IPA Downloader qua StikDebug (chọn Universal Script trên iOS 26+) để kích hoạt JIT trước khi bấm Đăng nhập.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Button {
                        showDebugLog = true
                    } label: {
                        Label("Xem / Copy Debug Log", systemImage: "doc.text.magnifyingglass")
                    }
                }

                if let initError = service.initError {
                    Section("Lỗi khởi tạo Core") {
                        Text(initError)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    if service.accounts.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary)
                            Text("Chưa có tài khoản Apple ID nào")
                                .font(.headline)
                            Text("Thêm tài khoản Apple ID của bạn để tìm kiếm và tải file .ipa trực tiếp từ App Store.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(service.accounts) { account in
                            Button {
                                service.selectedAccountId = account.id
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(account.displayName)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text(account.email)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Text("Storefront: \(account.storefrontCountryCode)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if service.selectedAccount?.id == account.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accentColor)
                                            .font(.title3)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task {
                                        do {
                                            try await service.removeAccount(account)
                                        } catch {
                                            errorAlert = error.localizedDescription
                                        }
                                    }
                                } label: {
                                    Label("Đăng xuất", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Tài khoản đã đăng nhập")
                } footer: {
                    Text("Thông tin đăng nhập được lưu cục bộ trên thiết bị và chỉ giao tiếp trực tiếp với máy chủ Apple.")
                }

                Section {
                    Picker("Phương thức cài đặt", selection: $otaUseLocalHTTPS) {
                        Text("Trực tiếp (Không cần chứng chỉ)").tag(false)
                        Text("HTTPS Cục bộ (127.0.0.1 / Offline)").tag(true)
                    }
                    .font(.subheadline)

                    if otaUseLocalHTTPS {
                        Button {
                            openLocalCACertInSafari()
                        } label: {
                            Label("Tải & Cài đặt chứng chỉ CA cục bộ", systemImage: "checkmark.shield")
                                .font(.subheadline)
                        }
                    }
                } header: {
                    Text("Cài đặt gói .ipa (OTA)")
                } footer: {
                    Text(otaUseLocalHTTPS
                         ? "Chế độ HTTPS Cục bộ (https://127.0.0.1) hoạt động 100% offline. Lần đầu sử dụng, hãy bấm 'Tải & Cài đặt chứng chỉ CA cục bộ', cài hồ sơ trong Cài đặt và bật Tin cậy trong Cài đặt > Cài đặt chung > Giới thiệu > Cài đặt tin cậy chứng chỉ."
                         : "Chế độ Trực tiếp không cần cài đặt chứng chỉ CA và hoạt động ngay khi nhấn nút Cài trong tab Tải xuống.")
                }

                Section {
                    HStack {
                        Label("Phiên bản", systemImage: "app.badge.checkmark")
                            .font(.subheadline)
                        Spacer()
                        Text("v\(appVersion) (Build \(appBuild))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Core Engine", systemImage: "cpu")
                            .font(.subheadline)
                        Spacer()
                        Text("ipatool v2 • Unicorn 2.1.4")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Cơ chế JIT", systemImage: "memorychip")
                            .font(.subheadline)
                        Spacer()
                        Text("Split-W^X Dual-Map (iOS \(UIDevice.current.systemVersion))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let repoURL = URL(string: "https://github.com/manhchu2904/IPA-Downloader") {
                        Link(destination: repoURL) {
                            HStack {
                                Label("Mã nguồn (GitHub)", systemImage: "chevron.left.forwardslash.chevron.right")
                                    .font(.subheadline)
                                Spacer()
                                Text("manhchu2904/IPA-Downloader")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Image(systemName: "arrow.up.right.square")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if let ipatoolURL = URL(string: "https://github.com/majd/ipatool") {
                        Link(destination: ipatoolURL) {
                            HStack {
                                Label("Lõi ipatool gốc", systemImage: "shippingbox")
                                    .font(.subheadline)
                                Spacer()
                                Text("majd/ipatool")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Image(systemName: "arrow.up.right.square")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Thông tin & Mã nguồn")
                } footer: {
                    Text("IPA Downloader • Tải trực tiếp file .ipa nguyên bản từ máy chủ App Store của Apple.")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
            }
            .navigationTitle("Tài khoản")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddAccountSheet()
                    .environmentObject(service)
            }
            .sheet(isPresented: $showDebugLog) {
                DebugLogView()
            }
            .onAppear {
                jitEnabled = JITHelper.isJITEnabled()
                jitPoolReady = JITHelper.isJITPoolReady()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                refreshJITState()
            }
            .alert("Lỗi", isPresented: Binding(get: { errorAlert != nil }, set: { if !$0 { errorAlert = nil } })) {
                Button("Đóng", role: .cancel) {}
            } message: {
                Text(errorAlert ?? "")
            }
        }
        .navigationViewStyle(.stack)
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }

    private var appBuild: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }

    private func refreshJITState() {
        JITHelper.prepareStartupJIT26PoolIfNeeded()
        jitEnabled = JITHelper.isJITEnabled()
        jitPoolReady = JITHelper.isJITPoolReady()
    }

    private func openLocalCACertInSafari() {
        Task {
            do {
                let url = try await service.startCACertServer()
                await UIApplication.shared.open(url)
            } catch {
                errorAlert = error.localizedDescription
            }
        }
    }
}

private struct AddAccountSheet: View {
    @EnvironmentObject private var service: IPAToolService
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var authCode = ""
    @State private var needsTwoFactor = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isEmailFormatValid: Bool {
        Self.isValidAppleID(email)
    }

    private var isTwoFactorCodeValid: Bool {
        let cleaned = authCode.filter { !$0.isWhitespace }
        return cleaned.count == 6 && cleaned.allSatisfy { $0.isNumber && $0.isASCII }
    }

    private var canSubmitLogin: Bool {
        guard !isLoading, isEmailFormatValid, !password.isEmpty else {
            return false
        }
        if needsTwoFactor {
            return isTwoFactorCodeValid
        }
        return true
    }

    var body: some View {
        NavigationView {
            Form {
                if !JITHelper.isJITEnabled() {
                    Section {
                        Label("JIT chưa bật — bấm Đăng nhập có thể bị văng app. Hãy mở IPA Downloader qua StikDebug trước.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.footnote)
                    }
                }

                Section {
                    TextField("Email hoặc SĐT Apple ID", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: email) { _ in
                            if needsTwoFactor {
                                needsTwoFactor = false
                                authCode = ""
                            }
                            errorMessage = nil
                        }

                    SecureField("Mật khẩu", text: $password)
                        .textContentType(.password)
                        .onChange(of: password) { _ in
                            if needsTwoFactor {
                                needsTwoFactor = false
                                authCode = ""
                            }
                            errorMessage = nil
                        }
                } header: {
                    Text("Thông tin Apple ID")
                } footer: {
                    if !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isEmailFormatValid {
                        Text("Nhập đúng định dạng email (vd: ten@icloud.com) hoặc số điện thoại để bật nút Đăng nhập.")
                            .foregroundColor(.orange)
                    }
                }

                if needsTwoFactor {
                    Section {
                        TextField("Mã xác thực 6 chữ số", text: $authCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)

                        Button("Nhập lại Email / Mật khẩu") {
                            needsTwoFactor = false
                            authCode = ""
                            errorMessage = nil
                        }
                        .font(.footnote)
                    } header: {
                        Text("Xác thực 2 yếu tố (2FA)")
                    } footer: {
                        Text("Nhập mã 6 chữ số được gửi tới thiết bị tin cậy của bạn.\nLưu ý: Máy chủ App Store của Apple trả về cùng một mã phản hồi cho cả trường hợp cần 2FA lẫn khi nhập sai Email/Mật khẩu. Nếu thiết bị của bạn không hiện mã 2FA, hãy kiểm tra lại Email và Mật khẩu.")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button {
                        performLogin()
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                            } else {
                                Text(needsTwoFactor ? "Xác nhận mã 2FA" : "Đăng nhập")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmitLogin)
                }
            }
            .navigationTitle("Thêm Apple ID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
            }
        }
    }

    private static func isValidAppleID(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }) else {
            return false
        }
        if let atIndex = trimmed.firstIndex(of: "@") {
            let local = trimmed[..<atIndex]
            let domain = trimmed[trimmed.index(after: atIndex)...]
            guard !local.isEmpty,
                  !domain.contains("@"),
                  let dotIndex = domain.lastIndex(of: "."),
                  dotIndex > domain.startIndex,
                  dotIndex < domain.index(before: domain.endIndex) else {
                return false
            }
            return true
        }
        var digits = 0
        for (idx, ch) in trimmed.enumerated() {
            if ch.isNumber && ch.isASCII {
                digits += 1
            } else if ch == "+" && idx == 0 {
                continue
            } else if ch == "-" || ch == "(" || ch == ")" {
                continue
            } else {
                return false
            }
        }
        return digits >= 7
    }

    private func performLogin() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidAppleID(trimmedEmail) else {
            errorMessage = "Apple ID không đúng định dạng. Vui lòng nhập email hợp lệ (ví dụ: ten@icloud.com) hoặc số điện thoại."
            return
        }
        if needsTwoFactor {
            let cleanedCode = authCode.filter { !$0.isWhitespace }
            guard cleanedCode.count == 6, cleanedCode.allSatisfy({ $0.isNumber && $0.isASCII }) else {
                errorMessage = "Vui lòng nhập đúng mã 2FA gồm 6 chữ số."
                return
            }
        }

        isLoading = true
        errorMessage = nil

        Task {
            defer { isLoading = false }
            do {
                let res = try await service.login(email: trimmedEmail, password: password, authCode: authCode)
                if res.authCodeRequired {
                    needsTwoFactor = true
                } else if res.success {
                    dismiss()
                } else {
                    errorMessage = res.error ?? "Đăng nhập không thành công."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
