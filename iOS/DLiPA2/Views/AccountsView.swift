import SwiftUI
import UIKit

struct AccountsView: View {
    @EnvironmentObject private var service: IPAToolService
    @State private var showAddSheet = false
    @State private var showDebugLog = false
    @State private var errorAlert: String?
    @State private var accountToRemove: AppleAccount?
    @State private var jitEnabled = JITHelper.isJITEnabled()
    @State private var jitBadgeText = JITHelper.activeModeBadgeText()
    @State private var jitDetailText = JITHelper.activeModeDetailText()
    @State private var jitMechanismSummary = JITHelper.activeMechanismSummary(iosVersion: UIDevice.current.systemVersion)
    @AppStorage("otaUseLocalHTTPS") private var otaUseLocalHTTPS = false

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.groupedBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        if let initError = service.initError {
                            ModernCard(padding: 14, cornerRadius: 16) {
                                HStack(spacing: 10) {
                                    ModernIconBadge(systemName: "exclamationmark.octagon.fill", gradient: AppTheme.coralGradient, size: 34, cornerRadius: 10)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Lỗi khởi tạo Core")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.red)
                                        Text(initError)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }

                        accountsSection
                        jitStatusSection
                        otaSettingsSection
                        aboutSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Tài khoản")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
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
                refreshJITState()
                Task {
                    await service.refreshLocalCATrustState()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                refreshJITState()
                Task {
                    await service.refreshLocalCATrustState()
                }
            }
            .alert("Đăng xuất Apple ID?", isPresented: Binding(
                get: { accountToRemove != nil },
                set: { if !$0 { accountToRemove = nil } }
            )) {
                Button("Đăng xuất", role: .destructive) {
                    if let acc = accountToRemove {
                        Task {
                            do {
                                try await service.removeAccount(acc)
                            } catch {
                                errorAlert = error.localizedDescription
                            }
                        }
                    }
                    accountToRemove = nil
                }
                Button("Hủy", role: .cancel) {
                    accountToRemove = nil
                }
            } message: {
                Text("Xóa phiên đăng nhập của \(accountToRemove?.email ?? "") khỏi thiết bị này? Các file .ipa đã tải vẫn được giữ nguyên.")
            }
            .alert("Lỗi", isPresented: Binding(get: { errorAlert != nil }, set: { if !$0 { errorAlert = nil } })) {
                Button("Đóng", role: .cancel) {}
            } message: {
                Text(errorAlert ?? "")
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Sections

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ModernSectionHeader(
                title: "Apple ID đã đăng nhập",
                trailing: service.accounts.isEmpty ? nil : "\(service.accounts.count) tài khoản"
            )

            if service.accounts.isEmpty {
                ModernCard(padding: 18, cornerRadius: 18) {
                    ModernEmptyState(
                        icon: "person.badge.plus",
                        title: "Chưa có tài khoản Apple ID",
                        subtitle: "Đăng nhập Apple ID để tìm kiếm và tải trực tiếp file .ipa từ App Store của Apple.",
                        gradient: AppTheme.primaryGradient,
                        actionTitle: "Thêm Apple ID",
                        actionIcon: "plus",
                        action: { showAddSheet = true }
                    )
                }
            } else {
                ModernCard(padding: 0, cornerRadius: 16) {
                    VStack(spacing: 0) {
                        ForEach(service.accounts) { account in
                            accountRow(account, showDivider: account.id != service.accounts.last?.id)
                        }
                    }
                }
            }

            Text("Thông tin đăng nhập được lưu cục bộ trong Keychain trên thiết bị và chỉ giao tiếp trực tiếp với máy chủ Apple.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
        }
    }

    private func accountRow(_ account: AppleAccount, showDivider: Bool) -> some View {
        let isSelected = (service.selectedAccount?.id == account.id)
        let initial = String(account.displayName.prefix(1)).uppercased()

        return HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    service.selectedAccountId = account.id
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isSelected ? AppTheme.primaryGradient : AppTheme.slateGradient)
                            .frame(width: 40, height: 40)
                        Text(initial.isEmpty ? "A" : initial)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(account.displayName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            ModernStatusPill(text: account.storefrontCountryCode, color: isSelected ? .accentColor : .secondary)
                        }
                        Text(account.email)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                accountToRemove = account
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.red)
                    .frame(width: 30, height: 30)
                    .background(Color.red.opacity(0.10))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            if showDivider {
                Divider().padding(.leading, 62)
            }
        }
        .contextMenu {
            Button {
                service.selectedAccountId = account.id
            } label: {
                Label("Chọn làm tài khoản mặc định", systemImage: "checkmark.circle")
            }
            Button(role: .destructive) {
                accountToRemove = account
            } label: {
                Label("Đăng xuất", systemImage: "trash")
            }
        }
    }

    private var jitStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ModernSectionHeader(title: "Trạng thái JIT (Unicorn SAP)")

            ModernCard(padding: 0, cornerRadius: 16) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        ModernIconBadge(
                            systemName: jitEnabled ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                            gradient: jitEnabled ? AppTheme.emeraldGradient : AppTheme.amberGradient,
                            size: 36,
                            cornerRadius: 10
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(jitEnabled ? "JIT đang bật" : "JIT chưa được bật")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                ModernStatusPill(
                                    text: jitBadgeText,
                                    color: jitEnabled ? .green : .orange
                                )
                            }
                            Text("Flags: \(JITHelper.codeSigningFlagsHex()) • \(jitDetailText)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer(minLength: 6)

                        Button {
                            refreshJITState()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.accentColor)
                                .frame(width: 30, height: 30)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    if !jitEnabled {
                        Divider().padding(.leading, 62)
                        Text("Hãy mở IPA Downloader qua StikDebug (hoặc TrollStore) để bật JIT khi đăng nhập và tải file .ipa.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }

                    Divider().padding(.leading, 62)

                    Button {
                        showDebugLog = true
                    } label: {
                        HStack(spacing: 12) {
                            ModernIconBadge(systemName: "terminal.fill", gradient: AppTheme.slateGradient, size: 30, cornerRadius: 8)
                            Text("Xem / Copy Debug Log")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var otaSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ModernSectionHeader(title: "Cài đặt gói .ipa (OTA)")

            ModernCard(padding: 0, cornerRadius: 16) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        ModernIconBadge(systemName: "iphone.and.arrow.forward", gradient: AppTheme.primaryGradient, size: 30, cornerRadius: 8)
                        Text("Phương thức cài đặt")
                            .font(.subheadline)
                        Spacer(minLength: 8)
                        Menu {
                            Button {
                                otaUseLocalHTTPS = false
                            } label: {
                                HStack {
                                    Text("Trực tiếp (Không cần chứng chỉ)")
                                    if !otaUseLocalHTTPS {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            Button {
                                otaUseLocalHTTPS = true
                            } label: {
                                HStack {
                                    Text("HTTPS Cục bộ (Offline)")
                                    if otaUseLocalHTTPS {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(otaUseLocalHTTPS ? "HTTPS Cục bộ" : "Trực tiếp")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)

                    if otaUseLocalHTTPS {
                        Divider().padding(.leading, 56)

                        HStack(spacing: 12) {
                            ModernIconBadge(
                                systemName: service.localCATrustState.iconName,
                                gradient: localCATrustGradient,
                                size: 30,
                                cornerRadius: 8
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Chứng chỉ CA cục bộ")
                                    .font(.subheadline)
                                Text(service.localCATrustState.title)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(localCATrustColor)
                            }
                            Spacer(minLength: 8)
                            Button {
                                Task {
                                    await service.refreshLocalCATrustState()
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.accentColor)
                                    .frame(width: 28, height: 28)
                                    .background(Color.accentColor.opacity(0.12))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)

                        Divider().padding(.leading, 56)

                        Button {
                            openLocalCACertInSafari()
                        } label: {
                            HStack(spacing: 12) {
                                ModernIconBadge(systemName: "arrow.down.doc.fill", gradient: AppTheme.purpleGradient, size: 30, cornerRadius: 8)
                                Text(service.localCATrustState == .trusted
                                     ? "Tải lại chứng chỉ CA cục bộ"
                                     : "Tải & Cài đặt chứng chỉ CA cục bộ")
                                    .font(.subheadline)
                                    .foregroundColor(.accentColor)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.accentColor.opacity(0.75))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text(otaUseLocalHTTPS
                 ? "Chế độ HTTPS Cục bộ hoạt động trực tiếp trên mạng cục bộ. Hãy bấm 'Tải & Cài đặt chứng chỉ CA cục bộ', cài hồ sơ trong Cài đặt và bật Tin cậy trong Cài đặt > Cài đặt chung > Giới thiệu > Cài đặt tin cậy chứng chỉ."
                 : "Chế độ Trực tiếp không cần cài đặt chứng chỉ CA và hoạt động ngay khi nhấn nút Cài trong tab Tải xuống.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ModernSectionHeader(title: "Thông tin & Mã nguồn")

            ModernCard(padding: 0, cornerRadius: 16) {
                VStack(spacing: 0) {
                    infoRow(icon: "app.badge.checkmark", gradient: AppTheme.primaryGradient, title: "Phiên bản", value: "v\(appVersion) (Build \(appBuild))")
                    Divider().padding(.leading, 56)
                    infoRow(icon: "cpu", gradient: AppTheme.purpleGradient, title: "Core Engine", value: "ipatool • Unicorn 2.1.4")
                    Divider().padding(.leading, 56)
                    infoRow(
                        icon: "memorychip",
                        gradient: jitEnabled ? AppTheme.emeraldGradient : AppTheme.slateGradient,
                        title: "Cơ chế JIT",
                        value: jitMechanismSummary
                    )

                    if let repoURL = URL(string: "https://github.com/manhchu2904/IPA-Downloader") {
                        Divider().padding(.leading, 56)
                        Link(destination: repoURL) {
                            linkRow(icon: "chevron.left.forwardslash.chevron.right", gradient: AppTheme.slateGradient, title: "Mã nguồn", value: "manhchu2904/IPA-Downloader")
                        }
                    }

                    if let ipatoolURL = URL(string: "https://github.com/majd/ipatool") {
                        Divider().padding(.leading, 56)
                        Link(destination: ipatoolURL) {
                            linkRow(icon: "shippingbox.fill", gradient: AppTheme.amberGradient, title: "Lõi ipatool gốc", value: "majd/ipatool")
                        }
                    }
                }
            }

            Text("IPA Downloader • Tải trực tiếp file .ipa nguyên bản từ máy chủ App Store của Apple.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    private func infoRow(icon: String, gradient: LinearGradient, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            ModernIconBadge(systemName: icon, gradient: gradient, size: 30, cornerRadius: 8)
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func linkRow(icon: String, gradient: LinearGradient, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            ModernIconBadge(systemName: icon, gradient: gradient, size: 30, cornerRadius: 8)
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Image(systemName: "arrow.up.right.square")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Helpers

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }

    private var appBuild: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }

    private var localCATrustColor: Color {
        switch service.localCATrustState {
        case .trusted:
            return .green
        case .profileDownloadedNotTrusted:
            return .orange
        case .notInstalled:
            return .red
        }
    }

    private var localCATrustGradient: LinearGradient {
        switch service.localCATrustState {
        case .trusted:
            return AppTheme.emeraldGradient
        case .profileDownloadedNotTrusted:
            return AppTheme.amberGradient
        case .notInstalled:
            return AppTheme.coralGradient
        }
    }

    private func refreshJITState() {
        JITHelper.prepareStartupJITPoolIfNeeded()
        jitEnabled = JITHelper.isJITEnabled()
        jitBadgeText = JITHelper.activeModeBadgeText()
        jitDetailText = JITHelper.activeModeDetailText()
        jitMechanismSummary = JITHelper.activeMechanismSummary(iosVersion: UIDevice.current.systemVersion)
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
            ZStack {
                AppTheme.groupedBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 10) {
                            ModernIconBadge(systemName: "person.crop.circle.badge.plus", gradient: AppTheme.primaryGradient, size: 58, cornerRadius: 16)
                            Text("Đăng nhập Apple ID")
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("Kết nối trực tiếp với máy chủ App Store của Apple. Không qua máy chủ trung gian.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        .padding(.top, 8)

                        if !JITHelper.isJITEnabled() {
                            ModernCard(padding: 13, cornerRadius: 14) {
                                HStack(spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("JIT chưa bật — bấm Đăng nhập có thể bị văng app. Hãy mở IPA Downloader qua StikDebug trước.")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                    Spacer()
                                }
                            }
                        }

                        ModernCard(padding: 0, cornerRadius: 16) {
                            VStack(spacing: 0) {
                                HStack(spacing: 10) {
                                    Image(systemName: "envelope.fill")
                                        .foregroundColor(.secondary)
                                        .frame(width: 22)
                                    TextField("Email hoặc SĐT Apple ID", text: $email)
                                        .font(.subheadline)
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
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)

                                Divider().padding(.leading, 46)

                                HStack(spacing: 10) {
                                    Image(systemName: "lock.fill")
                                        .foregroundColor(.secondary)
                                        .frame(width: 22)
                                    SecureField("Mật khẩu", text: $password)
                                        .font(.subheadline)
                                        .textContentType(.password)
                                        .onChange(of: password) { _ in
                                            if needsTwoFactor {
                                                needsTwoFactor = false
                                                authCode = ""
                                            }
                                            errorMessage = nil
                                        }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                            }
                        }

                        if !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isEmailFormatValid {
                            Text("Email hoặc số điện thoại không hợp lệ.")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                        }

                        if needsTwoFactor {
                            ModernCard(padding: 14, cornerRadius: 16) {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 8) {
                                        ModernIconBadge(systemName: "key.fill", gradient: AppTheme.emeraldGradient, size: 28, cornerRadius: 8)
                                        Text("Xác thực 2 yếu tố (2FA)")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                    }

                                    TextField("Nhập mã xác thực 6 chữ số", text: $authCode)
                                        .font(.title3.monospacedDigit())
                                        .keyboardType(.numberPad)
                                        .textContentType(.oneTimeCode)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(AppTheme.subtleSurface)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                    Text("Nhập mã 6 chữ số được gửi tới thiết bị tin cậy của bạn. Nếu không thấy mã, hãy kiểm tra lại Email và Mật khẩu.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Button("Nhập lại Email / Mật khẩu") {
                                        needsTwoFactor = false
                                        authCode = ""
                                        errorMessage = nil
                                    }
                                    .font(.caption.weight(.semibold))
                                }
                            }
                        }

                        if let errorMessage {
                            ModernCard(padding: 13, cornerRadius: 14) {
                                HStack(spacing: 10) {
                                    Image(systemName: "xmark.octagon.fill")
                                        .foregroundColor(.red)
                                    Text(errorMessage)
                                        .foregroundColor(.red)
                                        .font(.caption)
                                    Spacer()
                                }
                            }
                        }

                        Button {
                            performLogin()
                        } label: {
                            if isLoading {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(.white)
                                    Text("Đang xác thực với Apple...")
                                }
                            } else {
                                Text(needsTwoFactor ? "Xác nhận mã 2FA" : "Đăng nhập")
                            }
                        }
                        .buttonStyle(ModernPrimaryButtonStyle(isDisabled: !canSubmitLogin))
                        .disabled(!canSubmitLogin)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
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
            errorMessage = "Email hoặc số điện thoại không hợp lệ."
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
                    withAnimation(.easeInOut(duration: 0.2)) {
                        needsTwoFactor = true
                    }
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
