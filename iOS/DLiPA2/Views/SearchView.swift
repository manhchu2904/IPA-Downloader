import SwiftUI
import UIKit

struct SearchView: View {
    @EnvironmentObject private var service: IPAToolService

    var onOpenAccounts: () -> Void = {}
    var onOpenDownloads: () -> Void = {}

    @State private var query = ""
    @State private var selectedStorefront: Storefront = .accountDefault
    @State private var selectedPlatform = "iphone"
    @State private var results: [AppItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var showEmptyClipboardAlert = false
    @State private var searchTask: Task<Void, Never>?

    private let platforms = [
        ("iphone", "iPhone"),
        ("ipad", "iPad")
    ]

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.groupedBackground
                    .ignoresSafeArea()

                if service.selectedAccount == nil {
                    ScrollView {
                        ModernEmptyState(
                            icon: "person.crop.circle.badge.exclamationmark",
                            title: "Chưa đăng nhập Apple ID",
                            subtitle: "Đăng nhập tài khoản Apple ID của bạn để tìm kiếm, xem lịch sử phiên bản cũ và tải trực tiếp file .ipa từ App Store.",
                            gradient: AppTheme.amberGradient,
                            tintColor: .orange,
                            actionTitle: "Đi tới Tài khoản",
                            actionIcon: "person.badge.plus",
                            action: onOpenAccounts
                        )
                        .padding(.top, 20)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            filterHeader

                            if isSearching {
                                VStack(spacing: 14) {
                                    ProgressView()
                                        .scaleEffect(1.15)
                                    Text("Đang tìm trên App Store...")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 72)
                            } else if let errorMessage {
                                ModernEmptyState(
                                    icon: "exclamationmark.triangle.fill",
                                    title: "Không thể tìm kiếm",
                                    subtitle: errorMessage,
                                    gradient: AppTheme.coralGradient,
                                    tintColor: .red,
                                    actionTitle: "Thử lại",
                                    actionIcon: "arrow.clockwise",
                                    action: { runSearch() }
                                )
                                .padding(.top, 12)
                            } else if results.isEmpty {
                                searchEmptyStateContent
                            } else {
                                resultsListContent
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .navigationTitle("IPA Downloader")
            .alert("Bảng nhớ tạm trống", isPresented: $showEmptyClipboardAlert) {
                Button("Đóng", role: .cancel) {}
            } message: {
                Text("Hãy sao chép tên ứng dụng, Bundle ID, App ID hoặc liên kết App Store trước khi dán.")
            }
        }
        .navigationViewStyle(.stack)
    }

    private var filterHeader: some View {
        LiquidGlassGroup(spacing: 10) {
            VStack(spacing: 10) {
                ModernSearchBar(
                    text: $query,
                    prompt: "Tên app, Bundle ID, App ID hoặc link App Store...",
                    onSubmit: { runSearch() },
                    onClear: { clearSearchResults() }
                )
                .onChange(of: query) { newValue in
                    if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        clearSearchResults()
                    }
                }

                HStack(spacing: 10) {
                    Menu {
                        ForEach(Storefront.all) { sf in
                            Button {
                                selectedStorefront = sf
                                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                                    runSearch()
                                }
                            } label: {
                                HStack {
                                    Text("\(sf.flag) \(sf.name) (\(sf.code))")
                                    if sf.id == selectedStorefront.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedStorefront.flag)
                                .font(.subheadline)
                            Text(selectedStorefront.code)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundColor(.primary)
                        .liquidGlassRoundedRect(cornerRadius: 10, interactive: true)
                    }

                    Picker("Nền tảng", selection: $selectedPlatform) {
                        ForEach(platforms, id: \.0) { item in
                            Text(item.1).tag(item.0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedPlatform) { _ in
                        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            runSearch()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var searchEmptyStateContent: some View {
        VStack(spacing: 10) {
            ModernEmptyState(
                icon: "magnifyingglass",
                title: "Khám phá & Tải gói .ipa",
                subtitle: "Tìm ứng dụng theo tên, Bundle ID, mã App ID hoặc dán trực tiếp liên kết chia sẻ từ App Store.",
                gradient: AppTheme.primaryGradient,
                compact: true
            )

            ModernCard(padding: 12, cornerRadius: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("HỖ TRỢ TÌM NHANH")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    searchTipRow(icon: "text.magnifyingglass", gradient: AppTheme.primaryGradient, title: "Tên ứng dụng", example: "Spotify, Facebook, TikTok...")
                    Divider()
                    searchTipRow(icon: "link", gradient: AppTheme.purpleGradient, title: "Link App Store", example: "https://apps.apple.com/...")
                    Divider()
                    searchTipRow(icon: "tag.fill", gradient: AppTheme.emeraldGradient, title: "Bundle ID / App ID", example: "com.spotify.client hoặc 324684580")
                }
            }
            .padding(.horizontal, 16)

            Button {
                pasteAndSearchFromClipboard()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard.fill")
                    Text("Dán & Tìm từ Bảng nhớ tạm")
                }
            }
            .buttonStyle(ModernSecondaryButtonStyle())
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 20)
    }

    private func searchTipRow(icon: String, gradient: LinearGradient, title: String, example: String) -> some View {
        HStack(spacing: 12) {
            ModernIconBadge(systemName: icon, gradient: gradient, size: 30, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(example)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var resultsListContent: some View {
        LazyVStack(spacing: 10) {
            ModernSectionHeader(title: "Kết quả tìm kiếm", trailing: "\(results.count) ứng dụng")
                .padding(.top, 8)

            ForEach(results) { app in
                NavigationLink {
                    AppDetailView(app: app, platform: selectedPlatform, onOpenDownloads: onOpenDownloads)
                } label: {
                    SearchAppCard(app: app)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    private func pasteAndSearchFromClipboard() {
        let pb = UIPasteboard.general
        let raw = pb.string
            ?? pb.url?.absoluteString
            ?? pb.strings?.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            ?? pb.urls?.first?.absoluteString

        guard let pasted = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pasted.isEmpty else {
            showEmptyClipboardAlert = true
            return
        }
        query = pasted
        runSearch(explicitTerm: pasted)
    }

    private func clearSearchResults() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        errorMessage = nil
        results = []
    }

    private func runSearch(explicitTerm: String? = nil) {
        let trimmed = (explicitTerm ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearSearchResults()
            return
        }

        searchTask?.cancel()
        isSearching = true
        errorMessage = nil

        searchTask = Task {
            defer {
                if !Task.isCancelled {
                    isSearching = false
                }
            }
            do {
                let fetched = try await service.search(
                    term: trimmed,
                    storefrontId: selectedStorefront.id,
                    platform: selectedPlatform
                )
                guard !Task.isCancelled else { return }
                results = fetched
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                results = []
            }
        }
    }
}

private struct SearchAppCard: View {
    let app: AppItem

    private static func compactVersion(_ version: String, maxLength: Int = 14) -> String {
        guard version.count > maxLength else { return version }
        return String(version.prefix(maxLength - 1)) + "…"
    }

    var body: some View {
        ModernCard(padding: 13, cornerRadius: 16) {
            HStack(spacing: 13) {
                AppIconView(urlString: app.artworkUrl, size: 58)

                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let seller = app.sellerName, !seller.isEmpty {
                        Text(seller)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        Text("v\(Self.compactVersion(app.version))")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.subtleSurface)
                            .foregroundColor(.secondary)
                            .clipShape(Capsule())

                        Text(app.bundleId)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(app.price <= 0 ? "Miễn phí" : app.formattedPrice)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.14))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
        }
    }
}

private final class AppIconCache {
    static let shared = AppIconCache()
    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 200
        return c
    }()

    func image(for urlString: String) -> UIImage? {
        cache.object(forKey: urlString as NSString)
    }

    func setImage(_ image: UIImage, for urlString: String) {
        cache.setObject(image, forKey: urlString as NSString)
    }
}

struct AppIconView: View {
    let urlString: String?
    var size: CGFloat = 52

    @State private var loadedImage: UIImage?

    private var cornerRadius: CGFloat {
        size * 0.225
    }

    private var resolvedImage: UIImage? {
        if let loadedImage {
            return loadedImage
        }
        if let urlString {
            return AppIconCache.shared.image(for: urlString)
        }
        return nil
    }

    var body: some View {
        Group {
            if let uiImage = resolvedImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
        .task(id: urlString) {
            guard let urlString, !urlString.isEmpty else {
                loadedImage = nil
                return
            }
            if let cached = AppIconCache.shared.image(for: urlString) {
                if loadedImage !== cached {
                    loadedImage = cached
                }
                return
            }
            loadedImage = nil
            guard let url = URL(string: urlString) else { return }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled else { return }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    return
                }
                guard let decoded = UIImage(data: data) else { return }
                let prepared = await decoded.byPreparingForDisplay() ?? decoded
                guard !Task.isCancelled else { return }
                AppIconCache.shared.setImage(prepared, for: urlString)
                loadedImage = prepared
            } catch {
                // Keep placeholder if network fetch fails or is cancelled
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            AppTheme.subtleSurface
            Image(systemName: "app.fill")
                .font(.system(size: size * 0.44))
                .foregroundColor(.secondary.opacity(0.45))
        }
    }
}
