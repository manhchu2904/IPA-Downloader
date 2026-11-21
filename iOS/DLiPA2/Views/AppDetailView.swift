import SwiftUI
import UIKit

struct AppDetailView: View {
    @EnvironmentObject private var service: IPAToolService

    let app: AppItem
    let platform: String

    @State private var versionHistory: VersionHistory?
    @State private var resolvedMetadata: [String: VersionMetadata] = [:]
    @State private var isLoadingVersions = false
    @State private var loadingVersionId: String?
    @State private var versionFilterText: String = ""
    @State private var showManualVersionAlert = false
    @State private var manualVersionIdInput: String = ""
    @State private var errorMessage: String?
    @State private var downloadStartedBanner = false

    private var activeAccountEmail: String {
        service.selectedAccount?.email ?? "Chưa chọn tài khoản"
    }

    private func filteredVersionIDs(from orderedIds: [String]) -> [String] {
        let query = versionFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return orderedIds }
        return orderedIds.filter { vid in
            if vid.localizedCaseInsensitiveContains(query) {
                return true
            }
            if let displayVer = resolvedMetadata[vid]?.displayVersion,
               displayVer.localizedCaseInsensitiveContains(query) {
                return true
            }
            if let dateStr = resolvedMetadata[vid]?.releaseDate,
               dateStr.localizedCaseInsensitiveContains(query) {
                return true
            }
            return false
        }
    }

    var body: some View {
        List {
            Section("Thông tin ứng dụng") {
                HStack(spacing: 14) {
                    AppIconView(urlString: app.artworkUrl, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name)
                            .font(.headline)
                        if let seller = app.sellerName, !seller.isEmpty {
                            Text(seller)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Text("v\(app.version) • \(app.formattedPrice)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)

                LabeledContentRow(title: "Bundle ID", value: app.bundleId)
                LabeledContentRow(title: "App ID", value: String(app.id))
                LabeledContentRow(title: "Phiên bản mới nhất", value: "v\(app.version)")

                if service.accounts.count > 1 {
                    Picker("Apple ID tải về", selection: Binding(
                        get: { service.selectedAccountId ?? service.accounts.first?.id ?? "" },
                        set: { service.selectedAccountId = $0 }
                    )) {
                        ForEach(service.accounts) { account in
                            Text("\(account.email) (\(account.storefrontCountryCode))").tag(account.id)
                        }
                    }
                } else {
                    LabeledContentRow(title: "Apple ID tải về", value: activeAccountEmail)
                }
            }

            Section {
                Button {
                    service.startDownload(app: app, externalVersionId: "", versionLabel: app.version, platform: platform)
                    downloadStartedBanner = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Tải phiên bản mới nhất (v\(app.version))")
                            .fontWeight(.semibold)
                    }
                }

                Button {
                    manualVersionIdInput = ""
                    showManualVersionAlert = true
                } label: {
                    HStack {
                        Image(systemName: "number.circle")
                        Text("Nhập Version ID thủ công để tải...")
                    }
                }
            } footer: {
                Text("File .ipa tải xong sẽ được lưu riêng vào thư mục của Apple ID: \(activeAccountEmail)")
            }

            Section {
                if isLoadingVersions {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Đang tải danh sách lịch sử phiên bản...")
                            .foregroundColor(.secondary)
                    }
                } else if let history = versionHistory {
                    let orderedIds = Array(history.versionIds.reversed())
                    if orderedIds.isEmpty {
                        Text("Không có dữ liệu phiên bản cũ.")
                            .foregroundColor(.secondary)
                    } else {
                        if orderedIds.count > 5 {
                            HStack {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .foregroundColor(.secondary)
                                TextField("Lọc phiên bản (vd: 8.5, 2025, hoặc ID)...", text: $versionFilterText)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                if !versionFilterText.isEmpty {
                                    Button {
                                        versionFilterText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }

                        let visibleIds = filteredVersionIDs(from: orderedIds)
                        if visibleIds.isEmpty {
                            Text("Không có phiên bản nào khớp với \"\(versionFilterText)\".")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(visibleIds, id: \.self) { vid in
                                versionRow(vid: vid, latestId: history.latestVersionId)
                            }
                        }
                    }
                } else {
                    Button {
                        loadVersions()
                    } label: {
                        Label("Tải lịch sử phiên bản", systemImage: "clock.arrow.circlepath")
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            } header: {
                HStack {
                    Text("Lịch sử phiên bản")
                    if let history = versionHistory, !history.versionIds.isEmpty {
                        Spacer()
                        Text("\(history.versionIds.count) bản")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } footer: {
                Text("Số phiên bản (vd: v1.2.3) được ánh xạ từ danh mục phiên bản công khai mà không gửi nhiều truy vấn lên Apple. Nhấn giữ vào một phiên bản để sao chép nhanh ID hoặc số phiên bản.")
            }
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if versionHistory == nil && !isLoadingVersions {
                loadVersions()
            }
        }
        .alert("Nhập External Version ID", isPresented: $showManualVersionAlert) {
            TextField("Ví dụ: 871234567", text: $manualVersionIdInput)
                .keyboardType(.numberPad)
            Button("Tải ngay") {
                let cleaned = manualVersionIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { return }
                let label = resolvedMetadata[cleaned]?.displayVersion ?? cleaned
                service.startDownload(app: app, externalVersionId: cleaned, versionLabel: label, platform: platform)
                downloadStartedBanner = true
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Nhập mã số External Version ID của phiên bản bạn muốn tải cho \(app.name).")
        }
        .alert("Đã thêm vào hàng đợi tải", isPresented: $downloadStartedBanner) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("File .ipa sẽ được lưu trong thư mục của tài khoản \(activeAccountEmail). Chuyển sang tab Tải xuống để theo dõi tiến trình.")
        }
    }

    @ViewBuilder
    private func versionRow(vid: String, latestId: String) -> some View {
        let meta = resolvedMetadata[vid]
        let isLatest = (vid == latestId)
        let displayVer = meta?.displayVersion ?? (isLatest ? app.version : nil)

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let displayVer, !displayVer.isEmpty {
                        Text("v\(displayVer)")
                            .font(.headline)
                    } else if loadingVersionId == vid {
                        Text("Đang lấy số v...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Version ID: \(vid)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    if isLatest {
                        Text("Mới nhất")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 6) {
                    Text("ID: \(vid)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let dateStr = formattedDate(meta?.releaseDate) {
                        Text("• \(dateStr)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if displayVer == nil {
                Button {
                    fetchMetadata(versionId: vid)
                } label: {
                    if loadingVersionId == vid {
                        ProgressView()
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "info.circle")
                    }
                }
                .buttonStyle(.borderless)
            }

            Button {
                let label = displayVer ?? vid
                service.startDownload(app: app, externalVersionId: vid, versionLabel: label, platform: platform)
                downloadStartedBanner = true
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                let label = displayVer ?? vid
                service.startDownload(app: app, externalVersionId: vid, versionLabel: label, platform: platform)
                downloadStartedBanner = true
            } label: {
                Label("Tải phiên bản này", systemImage: "arrow.down.circle")
            }
            Button {
                UIPasteboard.general.string = vid
            } label: {
                Label("Sao chép Version ID (\(vid))", systemImage: "doc.on.doc")
            }
            if let displayVer, !displayVer.isEmpty {
                Button {
                    UIPasteboard.general.string = "v\(displayVer) (\(vid))"
                } label: {
                    Label("Sao chép v\(displayVer)", systemImage: "tag")
                }
            }
        }
    }

    private func formattedDate(_ isoString: String?) -> String? {
        guard let isoString, !isoString.isEmpty else { return nil }
        return String(isoString.prefix(10))
    }

    private func loadVersions() {
        isLoadingVersions = true
        errorMessage = nil
        Task {
            defer { isLoadingVersions = false }
            async let publicDirTask = service.fetchPublicVersionDirectory(appId: app.id, platform: platform)
            let publicDir = await publicDirTask

            do {
                let history = try await service.listVersions(for: app, platform: platform, purchaseIfNeeded: false)
                versionHistory = history
                hydrateCachedMetadata(for: history, publicMap: publicDir.map)
            } catch {
                // If the account does not yet own a license for this free app (or Apple's endpoint fails),
                // still display the full public version history without error; license acquisition happens on Download.
                if !publicDir.ordered.isEmpty {
                    let newestFirstIds = publicDir.ordered.map { $0.versionId }
                    let fallbackHistory = VersionHistory(
                        latestVersionId: newestFirstIds.first ?? "",
                        versionIds: Array(newestFirstIds.reversed())
                    )
                    versionHistory = fallbackHistory
                    hydrateCachedMetadata(for: fallbackHistory, publicMap: publicDir.map)
                } else {
                    do {
                        let history = try await service.listVersions(for: app, platform: platform, purchaseIfNeeded: true)
                        versionHistory = history
                        hydrateCachedMetadata(for: history, publicMap: publicDir.map)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func hydrateCachedMetadata(for history: VersionHistory, publicMap: [String: VersionMetadata]) {
        if !history.latestVersionId.isEmpty && !app.version.isEmpty {
            resolvedMetadata[history.latestVersionId] = VersionMetadata(
                versionId: history.latestVersionId,
                displayVersion: app.version,
                releaseDate: publicMap[history.latestVersionId]?.releaseDate
            )
        }
        for vid in history.versionIds {
            if let pub = publicMap[vid] {
                resolvedMetadata[vid] = pub
            } else if let cached = service.cachedVersionMetadata(appId: app.id, versionId: vid, platform: platform) {
                resolvedMetadata[vid] = cached
            }
        }
    }

    private func fetchMetadata(versionId: String) {
        loadingVersionId = versionId
        Task {
            defer {
                if loadingVersionId == versionId {
                    loadingVersionId = nil
                }
            }
            do {
                let meta = try await service.versionMetadata(for: app, versionId: versionId, platform: platform)
                resolvedMetadata[versionId] = meta
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct LabeledContentRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}
