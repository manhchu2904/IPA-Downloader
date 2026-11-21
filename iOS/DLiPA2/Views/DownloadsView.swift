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
                            Picker("Lọc theo Apple ID", selection: $selectedAccountFilter) {
                                Text("Tất cả Apple ID (\(service.downloadedFiles.count))").tag("ALL")
                                ForEach(availableAccountGroups, id: \.self) { email in
                                    let count = service.downloadedFiles.filter { $0.accountEmail == email }.count
                                    Text("\(email) (\(count))").tag(email)
                                }
                            }
                            .font(.subheadline)
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
            Menu {
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
                Image(systemName: "square.and.arrow.up.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
        .contextMenu {
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
