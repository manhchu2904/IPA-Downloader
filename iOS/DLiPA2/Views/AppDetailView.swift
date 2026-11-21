import SwiftUI

struct AppDetailView: View {
    @EnvironmentObject private var service: IPAToolService

    let app: AppItem
    let platform: String

    @State private var versionHistory: VersionHistory?
    @State private var resolvedMetadata: [String: VersionMetadata] = [:]
    @State private var isLoadingVersions = false
    @State private var loadingVersionId: String?
    @State private var errorMessage: String?
    @State private var downloadStartedBanner = false

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
                        ForEach(orderedIds, id: \.self) { vid in
                            versionRow(vid: vid, latestId: history.latestVersionId)
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
                Text("Số phiên bản (vd: v1.2.3) được ánh xạ từ danh mục phiên bản công khai mà không gửi nhiều truy vấn lên Apple. Nếu bản nào chưa có tên, bạn có thể nhấn (i) để tra cứu riêng bản đó.")
            }
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if versionHistory == nil && !isLoadingVersions {
                loadVersions()
            }
        }
        .alert("Đã thêm vào hàng đợi tải", isPresented: $downloadStartedBanner) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Chuyển sang tab Tải xuống để theo dõi tiến trình và lấy file .ipa.")
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
            do {
                async let historyTask = service.listVersions(for: app, platform: platform)
                async let publicDirTask = service.fetchPublicVersionDirectory(appId: app.id, platform: platform)

                let history = try await historyTask
                let publicMap = await publicDirTask

                versionHistory = history
                hydrateCachedMetadata(for: history, publicMap: publicMap)
            } catch {
                errorMessage = error.localizedDescription
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
