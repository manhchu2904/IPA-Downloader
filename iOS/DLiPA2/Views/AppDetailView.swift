import SwiftUI
import UIKit

struct AppDetailView: View {
    @EnvironmentObject private var service: IPAToolService

    let app: AppItem
    let platform: String
    var onOpenDownloads: () -> Void = {}

    @State private var versionHistory: VersionHistory?
    @State private var resolvedMetadata: [String: VersionMetadata] = [:]
    @State private var isLoadingVersions = false
    @State private var loadingVersionId: String?
    @State private var versionFilterText: String = ""
    @State private var showManualVersionAlert = false
    @State private var manualVersionIdInput: String = ""
    @State private var errorMessage: String?
    @State private var toastMessage: String?
    @State private var toastIsDownload = false
    @State private var toastDismissTask: Task<Void, Never>?

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
        ZStack(alignment: .bottom) {
            AppTheme.groupedBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    metadataCard
                    versionHistorySection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 84)
            }

            if let toastMessage {
                ModernFloatingToast(
                    icon: toastIsDownload ? "arrow.down.circle.fill" : "checkmark.circle.fill",
                    title: toastMessage,
                    subtitle: toastIsDownload ? "Lưu vào thư mục \(activeAccountEmail)" : nil,
                    actionTitle: toastIsDownload ? "Xem" : nil,
                    action: toastIsDownload ? {
                        withAnimation(.easeOut(duration: 0.2)) {
                            self.toastMessage = nil
                        }
                        onOpenDownloads()
                    } : nil
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: toastMessage != nil)
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if versionHistory == nil && !isLoadingVersions {
                loadVersions()
            }
        }
        .onDisappear {
            toastDismissTask?.cancel()
        }
        .alert("Nhập External Version ID", isPresented: $showManualVersionAlert) {
            TextField("Ví dụ: 871234567", text: $manualVersionIdInput)
                .keyboardType(.numberPad)
            Button("Tải ngay") {
                let cleaned = manualVersionIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { return }
                let label = resolvedMetadata[cleaned]?.displayVersion ?? cleaned
                triggerDownload(externalVersionId: cleaned, versionLabel: label)
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Nhập mã số External Version ID của phiên bản bạn muốn tải cho \(app.name).")
        }
    }

    private var heroCard: some View {
        ModernCard(padding: 18, cornerRadius: 20) {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 15) {
                    AppIconView(urlString: app.artworkUrl, size: 80)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(app.name)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)

                        if let seller = app.sellerName, !seller.isEmpty {
                            Text(seller)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        HStack(spacing: 6) {
                            ModernStatusPill(text: "v\(app.version)", color: .accentColor, icon: "tag.fill")
                            ModernStatusPill(
                                text: app.price <= 0 ? "Miễn phí" : app.formattedPrice,
                                color: app.price <= 0 ? .green : .orange,
                                icon: app.price <= 0 ? "checkmark" : "cart.fill"
                            )
                            ModernStatusPill(
                                text: platform == "ipad" ? "iPad" : "iPhone",
                                color: .secondary,
                                icon: platform == "ipad" ? "ipad" : "iphone"
                            )
                        }
                        .padding(.top, 2)
                    }

                    Spacer(minLength: 0)
                }

                VStack(spacing: 10) {
                    Button {
                        triggerDownload(externalVersionId: "", versionLabel: app.version)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Tải phiên bản mới nhất (v\(app.version))")
                        }
                    }
                    .buttonStyle(ModernPrimaryButtonStyle())

                    Button {
                        manualVersionIdInput = ""
                        showManualVersionAlert = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "number.circle.fill")
                            Text("Nhập Version ID thủ công")
                        }
                    }
                    .buttonStyle(ModernSecondaryButtonStyle())
                }
            }
        }
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ModernSectionHeader(title: "Thông tin gói ứng dụng")

            ModernCard(padding: 0, cornerRadius: 16) {
                VStack(spacing: 0) {
                    copyableInfoRow(icon: "shippingbox.fill", gradient: AppTheme.primaryGradient, title: "Bundle ID", value: app.bundleId)
                    Divider().padding(.leading, 54)
                    copyableInfoRow(icon: "number", gradient: AppTheme.purpleGradient, title: "App ID", value: String(app.id))
                    Divider().padding(.leading, 54)

                    HStack(spacing: 12) {
                        ModernIconBadge(systemName: "person.crop.circle.fill", gradient: AppTheme.emeraldGradient, size: 30, cornerRadius: 8)
                        Text("Apple ID tải về")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer(minLength: 10)

                        if service.accounts.count > 1 {
                            Menu {
                                ForEach(service.accounts) { account in
                                    Button {
                                        service.selectedAccountId = account.id
                                    } label: {
                                        HStack {
                                            Text("\(account.email) (\(account.storefrontCountryCode))")
                                            if account.id == service.selectedAccount?.id {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(activeAccountEmail)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption)
                                }
                            }
                        } else {
                            Text(activeAccountEmail)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                }
            }

            Text("File .ipa tải xong sẽ được lưu riêng vào thư mục của Apple ID: \(activeAccountEmail)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
        }
    }

    private func copyableInfoRow(icon: String, gradient: LinearGradient, title: String, value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            showToast(title: "Đã sao chép \(title)", isDownload: false)
        } label: {
            HStack(spacing: 12) {
                ModernIconBadge(systemName: icon, gradient: gradient, size: 30, cornerRadius: 8)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer(minLength: 10)
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var versionHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ModernSectionHeader(
                title: "Lịch sử phiên bản",
                trailing: versionHistory.map { "\($0.versionIds.count) bản" }
            )

            if isLoadingVersions {
                ModernCard(padding: 20, cornerRadius: 16) {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Đang tải danh sách lịch sử phiên bản...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            } else if let history = versionHistory {
                let orderedIds = Array(history.versionIds.reversed())
                if orderedIds.isEmpty {
                    ModernCard(padding: 16, cornerRadius: 16) {
                        Text("Không có dữ liệu phiên bản cũ.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    if orderedIds.count > 5 {
                        HStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                .foregroundColor(.secondary)
                            TextField("Lọc phiên bản (vd: 8.5, 2025, hoặc ID)...", text: $versionFilterText)
                                .font(.subheadline)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            if !versionFilterText.isEmpty {
                                Button {
                                    versionFilterText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
                        )
                    }

                    let visibleIds = filteredVersionIDs(from: orderedIds)
                    if visibleIds.isEmpty {
                        ModernCard(padding: 16, cornerRadius: 16) {
                            Text("Không có phiên bản nào khớp với \"\(versionFilterText)\".")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        ModernCard(padding: 0, cornerRadius: 16) {
                            LazyVStack(spacing: 0) {
                                ForEach(visibleIds, id: \.self) { vid in
                                    versionRow(vid: vid, latestId: history.latestVersionId)
                                    if vid != visibleIds.last {
                                        Divider().padding(.leading, 16)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                Button {
                    loadVersions()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("Tải lịch sử phiên bản")
                    }
                }
                .buttonStyle(ModernSecondaryButtonStyle())
            }

            if let errorMessage {
                ModernCard(padding: 12, cornerRadius: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.footnote)
                        Spacer()
                    }
                }
            }

            Text("Số phiên bản (vd: v1.2.3) được ánh xạ từ danh mục công khai. Nhấn giữ vào một phiên bản để sao chép nhanh ID hoặc số phiên bản.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private func versionRow(vid: String, latestId: String) -> some View {
        let meta = resolvedMetadata[vid]
        let isLatest = (vid == latestId)
        let displayVer = meta?.displayVersion ?? (isLatest ? app.version : nil)

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let displayVer, !displayVer.isEmpty {
                        Text("v\(displayVer)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
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
                        ModernStatusPill(text: "Mới nhất", color: .accentColor, icon: "sparkles")
                    }
                }

                HStack(spacing: 6) {
                    Text("ID: \(vid)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                    if let dateStr = formattedDate(meta?.releaseDate) {
                        Text("• \(dateStr)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer(minLength: 8)

            if displayVer == nil {
                Button {
                    fetchMetadata(versionId: vid)
                } label: {
                    if loadingVersionId == vid {
                        ProgressView()
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "info.circle")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 32, height: 32)
                            .background(AppTheme.subtleSurface)
                            .clipShape(Circle())
                    }
                }
                .buttonStyle(.plain)
            }

            Button {
                let label = displayVer ?? vid
                triggerDownload(externalVersionId: vid, versionLabel: label)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.caption.weight(.bold))
                    Text("Tải")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.accentColor.opacity(0.14))
                .foregroundColor(.accentColor)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                let label = displayVer ?? vid
                triggerDownload(externalVersionId: vid, versionLabel: label)
            } label: {
                Label("Tải phiên bản này", systemImage: "arrow.down.circle")
            }
            Button {
                UIPasteboard.general.string = vid
                showToast(title: "Đã sao chép Version ID", isDownload: false)
            } label: {
                Label("Sao chép Version ID (\(vid))", systemImage: "doc.on.doc")
            }
            if let displayVer, !displayVer.isEmpty {
                Button {
                    UIPasteboard.general.string = "v\(displayVer) (\(vid))"
                    showToast(title: "Đã sao chép v\(displayVer)", isDownload: false)
                } label: {
                    Label("Sao chép v\(displayVer)", systemImage: "tag")
                }
            }
        }
    }

    private func triggerDownload(externalVersionId: String, versionLabel: String) {
        service.startDownload(app: app, externalVersionId: externalVersionId, versionLabel: versionLabel, platform: platform)
        showToast(title: "Đang tải \(app.name) v\(versionLabel)", isDownload: true)
    }

    private func showToast(title: String, isDownload: Bool) {
        toastDismissTask?.cancel()
        toastIsDownload = isDownload
        toastMessage = title
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                toastMessage = nil
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
            let publicDir = await service.fetchPublicVersionDirectory(appId: app.id, platform: platform)

            // Fast path (<0.3s): immediately display the public version directory if available
            // without waiting 5-8s for Unicorn StoreAMD + volumeStoreDownloadProduct.
            if !publicDir.ordered.isEmpty {
                let newestFirstIds = publicDir.ordered.map { $0.versionId }
                let fastHistory = VersionHistory(
                    latestVersionId: newestFirstIds.first ?? "",
                    versionIds: Array(newestFirstIds.reversed())
                )
                versionHistory = fastHistory
                hydrateCachedMetadata(for: fastHistory, publicMap: publicDir.map)
                return
            }

            // Fallback path for rare/new apps not yet indexed in the public version directory
            do {
                let history = try await service.listVersions(for: app, platform: platform, purchaseIfNeeded: false)
                versionHistory = history
                hydrateCachedMetadata(for: history, publicMap: publicDir.map)
            } catch {
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
