import SwiftUI
import UIKit

struct DownloadsView: View {
    @EnvironmentObject private var service: IPAToolService

    var onOpenSearch: () -> Void = {}

    @State private var shareURL: URL?
    @State private var selectedAccountFilter: String = "ALL"
    @State private var searchText: String = ""
    @State private var fileToRename: DownloadedIPA?
    @State private var newFileName: String = ""
    @State private var renameError: String?
    @State private var confirmDeleteAccount: String?
    @State private var fileToInstall: DownloadedIPA?

    private var availableAccountGroups: [String] {
        let emails = Set(service.downloadedFiles.map { $0.accountEmail })
        return emails.sorted { a, b in
            if a == IPAToolService.uncategorizedAccountLabel { return false }
            if b == IPAToolService.uncategorizedAccountLabel { return true }
            return a.lowercased() < b.lowercased()
        }
    }

    private var filteredFiles: [DownloadedIPA] {
        service.downloadedFiles.filter { file in
            let matchesAccount = (selectedAccountFilter == "ALL" || file.accountEmail == selectedAccountFilter)
            let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = trimmedSearch.isEmpty ||
                file.name.localizedCaseInsensitiveContains(trimmedSearch) ||
                file.accountEmail.localizedCaseInsensitiveContains(trimmedSearch)
            return matchesAccount && matchesSearch
        }
    }

    private var groupedAccountKeys: [String] {
        if selectedAccountFilter != "ALL" {
            return availableAccountGroups.filter { $0 == selectedAccountFilter }
        }
        return availableAccountGroups.filter { group in
            filteredFiles.contains { $0.accountEmail == group }
        }
    }

    private var totalStorageBytes: Int64 {
        filteredFiles.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.groupedBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        if !service.activeDownloads.isEmpty {
                            activeDownloadsSection
                        }

                        if !service.downloadedFiles.isEmpty {
                            storageSummaryCard
                        }

                        if service.downloadedFiles.isEmpty && service.activeDownloads.isEmpty {
                            ModernEmptyState(
                                icon: "arrow.down.doc.fill",
                                title: "Chưa có file .ipa nào",
                                subtitle: "Các gói .ipa tải từ App Store sẽ tự động phân loại theo từng tài khoản Apple ID để cài đặt trực tiếp hoặc chia sẻ.",
                                gradient: AppTheme.primaryGradient,
                                actionTitle: "Tìm ứng dụng ngay",
                                actionIcon: "magnifyingglass",
                                action: onOpenSearch
                            )
                            .padding(.top, 16)
                        } else if !service.downloadedFiles.isEmpty && groupedAccountKeys.isEmpty {
                            ModernEmptyState(
                                icon: "doc.text.magnifyingglass",
                                title: "Không tìm thấy gói .ipa",
                                subtitle: "Không có file nào khớp với từ khóa hoặc bộ lọc hiện tại.",
                                gradient: AppTheme.slateGradient,
                                compact: true
                            )
                            .padding(.top, 12)
                        } else {
                            ForEach(groupedAccountKeys, id: \.self) { accountEmail in
                                accountFilesSection(accountEmail: accountEmail)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Tải xuống")
            .searchable(text: $searchText, prompt: "Tìm kiếm file .ipa hoặc Apple ID...")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !service.downloadedFiles.isEmpty {
                        Menu {
                            if selectedAccountFilter != "ALL" {
                                Button(role: .destructive) {
                                    confirmDeleteAccount = selectedAccountFilter
                                } label: {
                                    Label("Xóa tất cả IPA của \(selectedAccountFilter)", systemImage: "trash")
                                }
                            }
                            ForEach(availableAccountGroups, id: \.self) { email in
                                Button(role: .destructive) {
                                    confirmDeleteAccount = email
                                } label: {
                                    Label("Xóa nhóm: \(email)", systemImage: "folder.badge.minus")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }

                    Button {
                        service.refreshDownloadedFiles()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(item: Binding(
                get: { shareURL.map { IdentifiableURL(url: $0) } },
                set: { shareURL = $0?.url }
            )) { item in
                ShareSheet(activityItems: [item.url])
            }
            .sheet(item: $fileToInstall) { file in
                IPAInstallerSheet(file: file)
                    .environmentObject(service)
            }
            .alert("Đổi tên file .ipa", isPresented: Binding(
                get: { fileToRename != nil },
                set: { if !$0 { fileToRename = nil } }
            )) {
                TextField("Tên file .ipa", text: $newFileName)
                Button("Lưu") {
                    if let file = fileToRename {
                        do {
                            try service.renameDownloadedFile(file, newName: newFileName)
                        } catch {
                            renameError = error.localizedDescription
                        }
                    }
                    fileToRename = nil
                }
                Button("Hủy", role: .cancel) {
                    fileToRename = nil
                }
            } message: {
                Text("Nhập tên mới cho file (vẫn giữ trong thư mục Apple ID hiện tại).")
            }
            .alert("Xác nhận xóa", isPresented: Binding(
                get: { confirmDeleteAccount != nil },
                set: { if !$0 { confirmDeleteAccount = nil } }
            )) {
                Button("Xóa tất cả", role: .destructive) {
                    if let acc = confirmDeleteAccount {
                        service.deleteDownloadedFiles(forAccount: acc)
                        if selectedAccountFilter == acc {
                            selectedAccountFilter = "ALL"
                        }
                    }
                    confirmDeleteAccount = nil
                }
                Button("Hủy", role: .cancel) {
                    confirmDeleteAccount = nil
                }
            } message: {
                Text("Bạn có chắc muốn xóa toàn bộ file .ipa đã tải bằng tài khoản \(confirmDeleteAccount ?? "")?")
            }
            .alert("Lỗi", isPresented: Binding(
                get: { renameError != nil },
                set: { if !$0 { renameError = nil } }
            )) {
                Button("Đóng", role: .cancel) {}
            } message: {
                Text(renameError ?? "")
            }
        }
        .navigationViewStyle(.stack)
    }

    private var storageSummaryCard: some View {
        ModernCard(padding: 15, cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ModernIconBadge(systemName: "archivebox.fill", gradient: AppTheme.primaryGradient, size: 38, cornerRadius: 11)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kho gói .ipa đã lưu")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("\(filteredFiles.count) gói • \(availableAccountGroups.count) tài khoản")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: totalStorageBytes, countStyle: .file))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())
                }

                if availableAccountGroups.count > 1 || selectedAccountFilter != "ALL" {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LiquidGlassGroup(spacing: 8) {
                            HStack(spacing: 8) {
                                filterChip(
                                    title: "Tất cả (\(service.downloadedFiles.count))",
                                    isSelected: selectedAccountFilter == "ALL"
                                ) {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        selectedAccountFilter = "ALL"
                                    }
                                }

                                ForEach(availableAccountGroups, id: \.self) { email in
                                    let count = service.downloadedFiles.filter { $0.accountEmail == email }.count
                                    filterChip(
                                        title: "\(email) (\(count))",
                                        isSelected: selectedAccountFilter == email
                                    ) {
                                        withAnimation(.easeInOut(duration: 0.18)) {
                                            selectedAccountFilter = email
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundColor(isSelected ? .white : .primary)
                .liquidGlassCapsule(tint: isSelected ? Color.accentColor.opacity(0.75) : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private var activeDownloadsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ModernSectionHeader(title: "Tiến trình tải (\(service.activeDownloads.count))")
                if service.activeDownloads.contains(where: { $0.isCompleted || $0.errorMessage != nil }) {
                    Button("Xóa mục xong") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            service.clearCompletedDownloads()
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            if service.hasActiveDownloads {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.shield.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("Giữ tải ngầm đang bật — có thể thoát app hoặc khóa màn hình.")
                        .font(.caption)
                        .foregroundColor(.green)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            ForEach(service.activeDownloads) { item in
                activeDownloadCard(item)
            }
        }
    }

    @ViewBuilder
    private func activeDownloadCard(_ item: ActiveDownload) -> some View {
        ModernCard(padding: 14, cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ModernIconBadge(
                        systemName: item.errorMessage != nil
                            ? "exclamationmark.triangle.fill"
                            : (item.isCompleted ? "checkmark.circle.fill" : "arrow.down.circle.fill"),
                        gradient: item.errorMessage != nil
                            ? AppTheme.coralGradient
                            : (item.isCompleted ? AppTheme.emeraldGradient : AppTheme.primaryGradient),
                        size: 34,
                        cornerRadius: 10
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.appName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            Text("v\(item.versionLabel)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        }
                        Text(item.accountEmail)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    if item.errorMessage == nil && !item.isCompleted {
                        Button("Hủy", role: .destructive) {
                            service.cancelDownload(id: item.id)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.12))
                        .foregroundColor(.red)
                        .clipShape(Capsule())
                    } else {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                service.removeFinishedDownloadEntry(id: item.id)
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.secondary)
                                .frame(width: 26, height: 26)
                                .background(AppTheme.subtleSurface)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let err = item.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                } else if item.isCompleted {
                    ModernStatusPill(
                        text: "Hoàn tất • Đã lưu vào \(item.accountEmail)",
                        color: .green,
                        icon: "checkmark"
                    )
                } else {
                    VStack(spacing: 6) {
                        ProgressView(value: min(max(item.percent, 0), 1))
                            .tint(.accentColor)

                        HStack {
                            Text(stageLabel(item.stage))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if item.speedBytesPerSec > 0 && item.stage == "downloading" {
                                Text("• \(ByteCountFormatter.string(fromByteCount: Int64(item.speedBytesPerSec), countStyle: .file))/s")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.accentColor)
                            }
                            Spacer()
                            if item.totalBytes > 0 {
                                Text("\(ByteCountFormatter.string(fromByteCount: item.downloadedBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func accountFilesSection(accountEmail: String) -> some View {
        let groupFiles = filteredFiles.filter { $0.accountEmail == accountEmail }
        let groupBytes = groupFiles.reduce(Int64(0)) { $0 + $1.size }

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text(accountEmail)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("\(groupFiles.count) file • \(ByteCountFormatter.string(fromByteCount: groupBytes, countStyle: .file))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)

            ModernCard(padding: 0, cornerRadius: 16) {
                VStack(spacing: 0) {
                    ForEach(groupFiles) { file in
                        downloadedFileRow(file, showDivider: file.id != groupFiles.last?.id)
                    }
                }
            }

            Text("Files > On My iPhone > IPA Downloader > IPAs > \(accountEmail)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private func downloadedFileRow(_ file: DownloadedIPA, showDivider: Bool) -> some View {
        HStack(spacing: 12) {
            ModernIconBadge(systemName: "shippingbox.fill", gradient: AppTheme.purpleGradient, size: 36, cornerRadius: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(file.formattedSize)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                    Text("• \(file.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            HStack(spacing: 8) {
                Button {
                    fileToInstall = file
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.app.fill")
                            .font(.caption)
                        Text("Cài")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(AppTheme.primaryGradient)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Menu {
                    Button {
                        fileToInstall = file
                    } label: {
                        Label("Cài đặt trực tiếp vào máy (OTA)", systemImage: "arrow.down.app.fill")
                    }

                    Button {
                        shareURL = file.url
                    } label: {
                        Label("Chia sẻ / Mở qua ESign, TrollStore...", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        newFileName = file.name.replacingOccurrences(of: ".ipa", with: "")
                        fileToRename = file
                    } label: {
                        Label("Đổi tên file .ipa", systemImage: "pencil")
                    }

                    Button {
                        UIPasteboard.general.string = "\(file.name) (Apple ID: \(file.accountEmail), Size: \(file.formattedSize))"
                    } label: {
                        Label("Sao chép thông tin & Apple ID", systemImage: "doc.on.doc")
                    }

                    Divider()

                    Button(role: .destructive) {
                        service.deleteDownloadedFile(file)
                    } label: {
                        Label("Xóa file", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 30, height: 30)
                        .background(AppTheme.subtleSurface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            if showDivider {
                Divider().padding(.leading, 56)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                fileToInstall = file
            } label: {
                Label("Cài đặt trực tiếp vào máy (OTA)", systemImage: "arrow.down.app.fill")
            }
            Button {
                shareURL = file.url
            } label: {
                Label("Chia sẻ / Mở bằng...", systemImage: "square.and.arrow.up")
            }
            Button {
                newFileName = file.name.replacingOccurrences(of: ".ipa", with: "")
                fileToRename = file
            } label: {
                Label("Đổi tên file", systemImage: "pencil")
            }
            Button {
                UIPasteboard.general.string = file.accountEmail
            } label: {
                Label("Copy Apple ID đã tải (\(file.accountEmail))", systemImage: "person.badge.key")
            }
            Button(role: .destructive) {
                service.deleteDownloadedFile(file)
            } label: {
                Label("Xóa file", systemImage: "trash")
            }
        }
    }

    private func stageLabel(_ stage: String) -> String {
        switch stage {
        case "preparing": return "Đang chuẩn bị..."
        case "acquiring_license": return "Đang nhận bản quyền miễn phí..."
        case "downloading": return "Đang tải xuống..."
        case "patching_sinf": return "Đang đóng gói SINF..."
        case "completed": return "Hoàn tất"
        default: return stage
        }
    }
}

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct IPAInstallerSheet: View {
    @EnvironmentObject private var service: IPAToolService
    @Environment(\.dismiss) private var dismiss

    let file: DownloadedIPA

    @State private var session: InstallSession?
    @State private var isStarting = true
    @State private var errorMessage: String?
    @AppStorage("otaUseLocalHTTPS") private var useLocalHTTPSMode = false

    private func infoRow(title: String, value: String, bold: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline)
                .fontWeight(bold ? .semibold : .regular)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.groupedBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        packageInfoCard
                        statusAndActionsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Cài đặt vào máy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        dismiss()
                    }
                }
            }
            .task {
                await service.refreshLocalCATrustState()
                await startServer()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task {
                    await service.refreshLocalCATrustState()
                }
            }
            .onDisappear {
                service.stopIPAInstaller()
            }
        }
    }

    private var packageInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ModernSectionHeader(title: "Thông tin gói .ipa")

            ModernCard(padding: 0, cornerRadius: 16) {
                VStack(spacing: 0) {
                    if let session {
                        infoRow(title: "Ứng dụng", value: session.appName, bold: true)
                        Divider().padding(.leading, 14)
                        infoRow(title: "Bundle ID", value: session.bundleId)
                        Divider().padding(.leading, 14)
                        infoRow(title: "Phiên bản", value: "v\(session.version)")
                        Divider().padding(.leading, 14)
                    } else {
                        infoRow(title: "Tên file", value: file.name, bold: true)
                        Divider().padding(.leading, 14)
                    }
                    infoRow(title: "Dung lượng", value: file.formattedSize)
                    Divider().padding(.leading, 14)
                    infoRow(title: "Apple ID bản quyền", value: file.accountEmail)
                    Divider().padding(.leading, 14)
                    infoRow(
                        title: "Chế độ OTA",
                        value: useLocalHTTPSMode
                            ? "HTTPS Cục bộ (\(session?.httpsHost ?? "Offline"))"
                            : "Trực tiếp"
                    )
                }
            }
        }
    }

    private var statusAndActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ModernSectionHeader(title: "Trạng thái cài đặt OTA")

            if isStarting {
                ModernCard(padding: 18, cornerRadius: 16) {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Đang khởi tạo máy chủ cài đặt cục bộ...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            } else if let errorMessage {
                ModernCard(padding: 16, cornerRadius: 16) {
                    HStack(spacing: 10) {
                        ModernIconBadge(systemName: "exclamationmark.triangle.fill", gradient: AppTheme.coralGradient, size: 32, cornerRadius: 9)
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.subheadline)
                        Spacer()
                    }
                }
            } else if let session {
                if useLocalHTTPSMode && service.localCATrustState != .trusted {
                    ModernCard(padding: 14, cornerRadius: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                ModernIconBadge(systemName: "exclamationmark.shield.fill", gradient: AppTheme.amberGradient, size: 32, cornerRadius: 9)
                                Text(service.localCATrustState.title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            }
                            Text("Hãy cài hồ sơ chứng chỉ CA cục bộ và bật Tin cậy trong Cài đặt > Cài đặt chung > Giới thiệu > Cài đặt tin cậy chứng chỉ để dùng chế độ HTTPS Cục bộ.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button {
                                if let url = URL(string: session.caCertUrl) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down.doc.fill")
                                    Text("Tải chứng chỉ CA cục bộ qua Safari")
                                }
                            }
                            .buttonStyle(ModernSecondaryButtonStyle())
                        }
                    }
                }

                if useLocalHTTPSMode, let tlsDiag = service.installTLSDiagnostic {
                    ModernCard(padding: 14, cornerRadius: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.shield.fill")
                                    .foregroundColor(.red)
                                Text("Chẩn đoán TLS cục bộ")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.red)
                            }
                            Text(tlsDiag)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button {
                                useLocalHTTPSMode = false
                                service.installTLSDiagnostic = nil
                                triggerITMSInstall(session: session)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "bolt.fill")
                                    Text("Chuyển sang Chế độ Trực tiếp & Cài ngay")
                                }
                            }
                            .buttonStyle(ModernPrimaryButtonStyle())
                        }
                    }
                }

                ModernCard(padding: 16, cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            ModernIconBadge(systemName: statusIcon, gradient: statusGradient, size: 42, cornerRadius: 12)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(statusTitle)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text(statusSubtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer(minLength: 0)
                        }

                        if service.installStage == "sending_payload" || service.installStage == "completed" {
                            VStack(spacing: 6) {
                                ProgressView(value: min(max(service.installPercent, 0), 1))
                                    .tint(service.installStage == "completed" ? .green : .accentColor)
                                HStack {
                                    Text("\(Int(min(max(service.installPercent, 0), 1) * 100))%")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(service.installStage == "completed" ? .green : .accentColor)
                                    Spacer()
                                    Text("\(ByteCountFormatter.string(fromByteCount: service.installSentBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: max(service.installTotalBytes, session.fileSize), countStyle: .file))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        LiquidGlassGroup(spacing: 10) {
                            VStack(spacing: 10) {
                                Button {
                                    triggerITMSInstall(session: session)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.down.app.fill")
                                        Text("Hiện hộp thoại Cài đặt iOS")
                                    }
                                }
                                .buttonStyle(ModernPrimaryButtonStyle())

                                Button {
                                    let urlStr: String
                                    if useLocalHTTPSMode {
                                        let host = session.httpsHost ?? "app.localtest.me"
                                        urlStr = "https://\(host):\(session.httpsPort)/install?mode=local"
                                    } else {
                                        urlStr = session.safariInstallUrl
                                    }
                                    DebugLogger.log("OTA opening Safari URL: \(urlStr)")
                                    if let url = URL(string: urlStr) {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "safari.fill")
                                        Text("Mở trang cài đặt qua trình duyệt Safari")
                                    }
                                }
                                .buttonStyle(ModernSecondaryButtonStyle())
                            }
                        }
                    }
                }
            }

            Text("Sau khi bấm 'Cài đặt' trên hộp thoại hệ thống iOS, bạn có thể ra màn hình chính để xem ứng dụng được cài đặt (giữ IPA Downloader chạy ngầm, không vuốt tắt app cho đến khi cài xong). Có thể đổi phương thức cài đặt trong tab Tài khoản.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
        }
    }

    private var statusIcon: String {
        switch service.installStage {
        case "ready": return "iphone.and.arrow.forward"
        case "sending_manifest": return "doc.badge.gearshape"
        case "sending_payload": return "arrow.up.doc.fill"
        case "completed": return "checkmark.seal.fill"
        default: return "iphone.and.arrow.forward"
        }
    }

    private var statusGradient: LinearGradient {
        switch service.installStage {
        case "completed": return AppTheme.emeraldGradient
        case "sending_payload", "sending_manifest": return AppTheme.primaryGradient
        default: return AppTheme.amberGradient
        }
    }

    private var statusTitle: String {
        switch service.installStage {
        case "ready":
            return "Sẵn sàng cài đặt"
        case "sending_manifest":
            return "Đã gửi Manifest cho iOS..."
        case "sending_payload":
            return "Đang truyền gói .ipa vào hệ thống iOS..."
        case "completed":
            return "Đã truyền xong gói .ipa!"
        default:
            return service.installStage
        }
    }

    private var statusSubtitle: String {
        switch service.installStage {
        case "ready":
            return "Nhấn 'Cài đặt' trên hộp thoại hệ thống iOS để bắt đầu."
        case "sending_manifest":
            return "Hệ thống iOS đang xác thực thông tin gói cài đặt."
        case "sending_payload":
            return "Giữ ứng dụng chạy (hoặc thoát ra màn hình chính theo dõi, không vuốt đóng app)."
        case "completed":
            return "iOS đang tiến hành giải nén và cài đặt ứng dụng ngoài màn hình chính."
        default:
            return ""
        }
    }

    private func startServer() async {
        isStarting = true
        errorMessage = nil
        do {
            let started = try await service.startIPAInstaller(for: file)
            session = started
            isStarting = false
            if useLocalHTTPSMode {
                if service.localCATrustState == .trusted {
                    let host = started.httpsHost ?? "app.localtest.me"
                    if let diagErr = await service.verifyLocalHTTPSLoopback(host: host, httpsPort: started.httpsPort) {
                        service.installTLSDiagnostic = diagErr
                        if let fallbackStr = started.localHttpsFallbackItmsUrl,
                           let fallbackURL = URL(string: fallbackStr) {
                            await UIApplication.shared.open(fallbackURL)
                            return
                        }
                    }
                    triggerITMSInstall(session: started)
                }
            } else {
                triggerITMSInstall(session: started)
            }
        } catch {
            errorMessage = error.localizedDescription
            isStarting = false
        }
    }

    private func triggerITMSInstall(session: InstallSession) {
        let target = useLocalHTTPSMode ? session.localHttpsItmsUrl : session.directItmsUrl
        DebugLogger.log("OTA opening ITMS URL: \(target)")
        if let url = URL(string: target) {
            UIApplication.shared.open(url, options: [:]) { success in
                DebugLogger.log("OTA open ITMS result: \(success)")
            }
        }
    }
}
