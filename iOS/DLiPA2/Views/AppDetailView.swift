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
                LabeledContentRow(title: "Tên", value: app.name)
                LabeledContentRow(title: "Bundle ID", value: app.bundleId)
                LabeledContentRow(title: "App ID", value: String(app.id))
                LabeledContentRow(title: "Phiên bản mới nhất", value: app.version)
                LabeledContentRow(title: "Giá", value: app.formattedPrice)
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
                    HStack {
                        ProgressView()
                        Text("Đang tải danh sách phiên bản...")
                            .foregroundColor(.secondary)
                    }
                } else if let history = versionHistory {
                    if history.versionIds.isEmpty {
                        Text("Không có dữ liệu phiên bản cũ.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(history.versionIds.reversed(), id: \.self) { vid in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    if let meta = resolvedMetadata[vid] {
                                        Text("v\(meta.displayVersion)")
                                            .font(.headline)
                                        Text("ID: \(vid)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Version ID: \(vid)")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        if vid == history.latestVersionId {
                                            Text("Mới nhất")
                                                .font(.caption2)
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                }

                                Spacer()

                                if resolvedMetadata[vid] == nil {
                                    Button {
                                        fetchMetadata(versionId: vid)
                                    } label: {
                                        if loadingVersionId == vid {
                                            ProgressView()
                                        } else {
                                            Image(systemName: "info.circle")
                                        }
                                    }
                                    .buttonStyle(.borderless)
                                }

                                Button {
                                    let label = resolvedMetadata[vid]?.displayVersion ?? vid
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
                    }
                } else {
                    Button {
                        loadVersions()
                    } label: {
                        Label("Tải lịch sử phiên bản (External Version IDs)", systemImage: "clock.arrow.circlepath")
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            } header: {
                Text("Lịch sử phiên bản")
            } footer: {
                Text("Nhấn biểu tượng (i) để tra cứu số phiên bản hiển thị (vd: 1.2.3) hoặc nhấn mũi tên để tải thẳng phiên bản đó.")
            }
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Đã thêm vào hàng đợi tải", isPresented: $downloadStartedBanner) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Chuyển sang tab Tải xuống để theo dõi tiến trình và lấy file .ipa.")
        }
    }

    private func loadVersions() {
        isLoadingVersions = true
        errorMessage = nil
        Task {
            defer { isLoadingVersions = false }
            do {
                versionHistory = try await service.listVersions(for: app, platform: platform)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func fetchMetadata(versionId: String) {
        loadingVersionId = versionId
        Task {
            defer { loadingVersionId = nil }
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
