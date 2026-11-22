import SwiftUI
import UIKit

struct DownloadsView: View {
    @EnvironmentObject private var service: IPAToolService
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
            List {
                if !service.downloadedFiles.isEmpty {
                    Section {
                        HStack {
                            Label("\(filteredFiles.count) file .ipa", systemImage: "archivebox.fill")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: totalStorageBytes, countStyle: .file))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.accentColor)
                        }

                        if availableAccountGroups.count > 1 || selectedAccountFilter != "ALL" {
                            HStack {
                                Text("Lọc theo Apple ID")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer(minLength: 12)
                                Menu {
                                    Button {
                                        selectedAccountFilter = "ALL"
                                    } label: {
                                        HStack {
                                            Text("Tất cả Apple ID (\(service.downloadedFiles.count))")
                                            if selectedAccountFilter == "ALL" {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                    ForEach(availableAccountGroups, id: \.self) { email in
                                        let count = service.downloadedFiles.filter { $0.accountEmail == email }.count
                                        Button {
                                            selectedAccountFilter = email
                                        } label: {
                                            HStack {
                                                Text("\(email) (\(count))")
                                                if selectedAccountFilter == email {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(selectedAccountFilter == "ALL" ? "Tất cả (\(service.downloadedFiles.count))" : selectedAccountFilter)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.85)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }

                if !service.activeDownloads.isEmpty {
                    Section {
                        ForEach(service.activeDownloads) { item in
                            activeDownloadRow(item)
                        }
                    } header: {
                        HStack {
                            Text("Tiến trình tải (\(service.activeDownloads.count))")
                            Spacer()
                            if service.activeDownloads.contains(where: { $0.isCompleted || $0.errorMessage != nil }) {
                                Button("Xóa mục đã xong") {
                                    service.clearCompletedDownloads()
                                }
                                .font(.caption)
                            }
                        }
                    } footer: {
                        if service.hasActiveDownloads {
                            Label("Chế độ giữ tải ngầm đang hoạt động — bạn có thể chuyển sang ứng dụng khác hoặc khóa màn hình.", systemImage: "bolt.shield.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                }

                if service.downloadedFiles.isEmpty {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary)
                            Text("Chưa có file .ipa nào được tải về")
                                .font(.headline)
                            Text("Các file .ipa khi tải xong sẽ được tự động phân loại vào thư mục riêng theo từng Apple ID.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } header: {
                        Text("File .ipa đã lưu (Files > On My iPhone > IPA Downloader > IPAs)")
                    }
                } else if groupedAccountKeys.isEmpty {
                    Section {
                        Text("Không tìm thấy file .ipa nào khớp bộ lọc.")
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(groupedAccountKeys, id: \.self) { accountEmail in
                        let groupFiles = filteredFiles.filter { $0.accountEmail == accountEmail }
                        let groupBytes = groupFiles.reduce(Int64(0)) { $0 + $1.size }

                        Section {
                            ForEach(groupFiles) { file in
                                downloadedFileRow(file)
                            }
                        } header: {
                            HStack {
                                Image(systemName: "person.crop.circle.fill")
                                    .foregroundColor(.accentColor)
                                Text(accountEmail)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .textCase(nil)
                                Spacer()
                                Text("\(groupFiles.count) file • \(ByteCountFormatter.string(fromByteCount: groupBytes, countStyle: .file))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .textCase(nil)
                            }
                        } footer: {
                            Text("Thư mục: Files > On My iPhone > IPA Downloader > IPAs > \(accountEmail)")
                        }
                    }
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

    @ViewBuilder
    private func activeDownloadRow(_ item: ActiveDownload) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.appName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("v\(item.versionLabel)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 4) {
                Image(systemName: "person.fill")
                    .font(.caption2)
                    .foregroundColor(.accentColor)
                Text("ID: \(item.accountEmail)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if let err = item.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                Button("Xóa khỏi danh sách") {
                    service.removeFinishedDownloadEntry(id: item.id)
                }
                .font(.caption)
            } else if item.isCompleted {
                HStack {
                    Label("Hoàn tất (đã lưu vào thư mục \(item.accountEmail))", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Spacer()
                    Button("Ẩn") {
                        service.removeFinishedDownloadEntry(id: item.id)
                    }
                    .font(.caption)
                }
            } else {
                ProgressView(value: min(max(item.percent, 0), 1))
                HStack {
                    Text(stageLabel(item.stage))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if item.speedBytesPerSec > 0 && item.stage == "downloading" {
                        Text("• \(ByteCountFormatter.string(fromByteCount: Int64(item.speedBytesPerSec), countStyle: .file))/s")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                    Spacer()
                    if item.totalBytes > 0 {
                        Text("\(ByteCountFormatter.string(fromByteCount: item.downloadedBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Button("Hủy", role: .destructive) {
                        service.cancelDownload(id: item.id)
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func downloadedFileRow(_ file: DownloadedIPA) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(file.formattedSize)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                    Text("• \(file.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text("Apple ID: \(file.accountEmail)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()

            Button {
                fileToInstall = file
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.app.fill")
                    Text("Cài")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.15))
                .foregroundColor(.accentColor)
                .clipShape(Capsule())
            }
            .buttonStyle(.borderless)

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
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
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
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                service.deleteDownloadedFile(file)
            } label: {
                Label("Xóa", systemImage: "trash")
            }
            Button {
                newFileName = file.name.replacingOccurrences(of: ".ipa", with: "")
                fileToRename = file
            } label: {
                Label("Đổi tên", systemImage: "pencil")
            }
            .tint(.orange)
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
                .minimumScaleFactor(0.85)
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section("Thông tin gói .ipa") {
                    if let session {
                        infoRow(title: "Ứng dụng", value: session.appName, bold: true)
                        infoRow(title: "Bundle ID", value: session.bundleId)
                        infoRow(title: "Phiên bản", value: "v\(session.version)")
                    } else {
                        infoRow(title: "Tên file", value: file.name)
                    }
                    infoRow(title: "Dung lượng", value: file.formattedSize)
                    infoRow(title: "Apple ID bản quyền", value: file.accountEmail)
                    infoRow(
                        title: "Chế độ OTA",
                        value: useLocalHTTPSMode
                            ? "HTTPS Cục bộ (\(session?.httpsHost ?? "Offline"))"
                            : "Trực tiếp"
                    )
                }

                Section {
                    if isStarting {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Đang khởi tạo máy chủ cài đặt cục bộ...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else if let errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.subheadline)
                    } else if let session {
                        if useLocalHTTPSMode && service.localCATrustState != .trusted {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
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
                                    Label("Tải chứng chỉ CA cục bộ qua Safari", systemImage: "arrow.down.doc.fill")
                                        .font(.subheadline)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        if useLocalHTTPSMode, let tlsDiag = service.installTLSDiagnostic {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Chẩn đoán TLS cục bộ", systemImage: "exclamationmark.shield.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.red)
                                Text(tlsDiag)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Button {
                                    useLocalHTTPSMode = false
                                    service.installTLSDiagnostic = nil
                                    triggerITMSInstall(session: session)
                                } label: {
                                    Label("Chuyển sang Chế độ Trực tiếp & Cài ngay", systemImage: "bolt.fill")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: statusIcon)
                                    .font(.title2)
                                    .foregroundColor(statusColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(statusTitle)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(statusSubtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            if service.installStage == "sending_payload" || service.installStage == "completed" {
                                ProgressView(value: min(max(service.installPercent, 0), 1))
                                HStack {
                                    Text("\(Int(min(max(service.installPercent, 0), 1) * 100))%")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text("\(ByteCountFormatter.string(fromByteCount: service.installSentBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: max(service.installTotalBytes, session.fileSize), countStyle: .file))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)

                        Button {
                            triggerITMSInstall(session: session)
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "arrow.down.app.fill")
                                Text("Hiện hộp thoại Cài đặt iOS")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }

                        Button {
                            let urlStr = useLocalHTTPSMode ? "\(session.safariInstallUrl)?mode=local" : session.safariInstallUrl
                            if let url = URL(string: urlStr) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Mở trang cài đặt qua trình duyệt Safari", systemImage: "safari")
                                .font(.subheadline)
                        }
                    }
                } header: {
                    Text("Trạng thái cài đặt OTA")
                } footer: {
                    Text("Sau khi bấm 'Cài đặt' trên hộp thoại hệ thống iOS, bạn có thể ra màn hình chính để xem ứng dụng được cài đặt (giữ IPA Downloader chạy ngầm, không vuốt tắt app cho đến khi cài xong). Có thể đổi phương thức cài đặt trong tab Tài khoản.")
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

    private var statusIcon: String {
        switch service.installStage {
        case "ready": return "iphone.and.arrow.forward"
        case "sending_manifest": return "doc.badge.gearshape"
        case "sending_payload": return "arrow.up.doc.fill"
        case "completed": return "checkmark.seal.fill"
        default: return "iphone.and.arrow.forward"
        }
    }

    private var statusColor: Color {
        switch service.installStage {
        case "completed": return .green
        case "sending_payload", "sending_manifest": return .accentColor
        default: return .orange
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
                            UIApplication.shared.open(fallbackURL)
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
        if let url = URL(string: target) {
            UIApplication.shared.open(url)
        }
    }
}
