import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var service: IPAToolService
    @State private var showAddSheet = false
    @State private var errorAlert: String?
    @State private var jitEnabled = JITHelper.isJITEnabled()

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
                            Text("Flags: \(JITHelper.codeSigningFlagsHex())")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            jitEnabled = JITHelper.isJITEnabled()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                    }
                    if !jitEnabled {
                        Text("Hãy mở DLiPA2 qua StikDebug để kích hoạt JIT trước khi bấm Đăng nhập.")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
            .alert("Lỗi", isPresented: Binding(get: { errorAlert != nil }, set: { if !$0 { errorAlert = nil } })) {
                Button("Đóng", role: .cancel) {}
            } message: {
                Text(errorAlert ?? "")
            }
        }
        .navigationViewStyle(.stack)
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

    var body: some View {
        NavigationView {
            Form {
                Section("Thông tin Apple ID") {
                    TextField("Email Apple ID", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    SecureField("Mật khẩu", text: $password)
                        .textContentType(.password)
                }

                if needsTwoFactor {
                    Section {
                        TextField("Mã xác thực 6 chữ số", text: $authCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                    } header: {
                        Text("Xác thực 2 yếu tố (2FA)")
                    } footer: {
                        Text("Nhập mã 6 chữ số được gửi tới thiết bị tin cậy của bạn.")
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
                    .disabled(isLoading || email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
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

    private func performLogin() {
        isLoading = true
        errorMessage = nil

        Task {
            defer { isLoading = false }
            do {
                let res = try await service.login(email: email, password: password, authCode: authCode)
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
