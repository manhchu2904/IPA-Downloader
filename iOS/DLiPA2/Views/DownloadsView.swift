import SwiftUI
import UIKit

struct DownloadsView: View {
    @EnvironmentObject private var service: IPAToolService
    @State private var shareURL: URL?

    var body: some View {
        NavigationView {
            List {
                if !service.activeDownloads.isEmpty {
                    Section("Đang tải") {
                        ForEach(service.activeDownloads) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.appName)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(item.versionLabel)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
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
                                        Label("Hoàn tất", systemImage: "checkmark.circle.fill")
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
                    }
                }

                Section {
                    if service.downloadedFiles.isEmpty {
                        Text("Chưa có file .ipa nào được tải về.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(service.downloadedFiles) { file in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(file.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .lineLimit(2)
                                    Text("\(file.formattedSize) • \(file.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button {
                                    shareURL = file.url
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.title3)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 2)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    service.deleteDownloadedFile(file)
                                } label: {
                                    Label("Xóa", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("File .ipa đã lưu (Files > On My iPhone > IPA Downloader > IPAs)")
                }
            }
            .navigationTitle("Tải xuống")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
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
        }
        .navigationViewStyle(.stack)
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
