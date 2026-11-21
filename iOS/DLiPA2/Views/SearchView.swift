import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var service: IPAToolService

    @State private var query = ""
    @State private var selectedStorefront: Storefront = .accountDefault
    @State private var selectedPlatform = "iphone"
    @State private var results: [AppItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    private let platforms = [
        ("iphone", "iPhone"),
        ("ipad", "iPad")
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if service.selectedAccount == nil {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 42))
                            .foregroundColor(.orange)
                        Text("Chưa đăng nhập Apple ID")
                            .font(.headline)
                        Text("Vào tab Tài khoản để đăng nhập Apple ID trước khi tìm kiếm ứng dụng.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    filterBar
                    Divider()

                    if isSearching {
                        ProgressView("Đang tìm kiếm...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMessage {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if results.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary)
                            Text("Nhập tên ứng dụng, Bundle ID, App ID hoặc dán link App Store")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(results) { app in
                            NavigationLink {
                                AppDetailView(app: app, platform: selectedPlatform)
                            } label: {
                                HStack(spacing: 12) {
                                    AppIconView(urlString: app.artworkUrl, size: 52)

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(app.name)
                                                .font(.headline)
                                                .lineLimit(1)
                                            Spacer()
                                            Text(app.formattedPrice)
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(Color.accentColor.opacity(0.15))
                                                .foregroundColor(.accentColor)
                                                .clipShape(Capsule())
                                        }
                                        if let seller = app.sellerName, !seller.isEmpty {
                                            Text(seller)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        } else {
                                            Text(app.bundleId)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        Text("v\(app.version) • \(app.bundleId)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("IPA Downloader")
            .searchable(text: $query, prompt: "Tên app, Bundle ID, App ID hoặc link App Store...")
            .onSubmit(of: .search) {
                runSearch()
            }
        }
        .navigationViewStyle(.stack)
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            if service.accounts.count > 1, let active = service.selectedAccount {
                HStack {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundColor(.accentColor)
                    Text("Apple ID đang dùng:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Menu {
                        ForEach(service.accounts) { account in
                            Button {
                                service.selectedAccountId = account.id
                                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                                    runSearch()
                                }
                            } label: {
                                HStack {
                                    Text("\(account.email) (\(account.storefrontCountryCode))")
                                    if account.id == active.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(active.email)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                    }
                    Spacer()
                }
            }

            HStack(spacing: 12) {
                Menu {
                    ForEach(Storefront.all) { sf in
                        Button {
                            selectedStorefront = sf
                            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                                runSearch()
                            }
                        } label: {
                            Text("\(sf.flag) \(sf.name) (\(sf.code))")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedStorefront.flag)
                        Text(selectedStorefront.code)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                }

                Picker("Nền tảng", selection: $selectedPlatform) {
                    ForEach(platforms, id: \.0) { item in
                        Text(item.1).tag(item.0)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSearching = true
        errorMessage = nil

        Task {
            defer { isSearching = false }
            do {
                results = try await service.search(
                    term: trimmed,
                    storefrontId: selectedStorefront.id,
                    platform: selectedPlatform
                )
            } catch {
                errorMessage = error.localizedDescription
                results = []
            }
        }
    }
}

struct AppIconView: View {
    let urlString: String?
    var size: CGFloat = 52

    private var cornerRadius: CGFloat {
        size * 0.225
    }

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty, .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var placeholder: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Image(systemName: "app.fill")
                .font(.system(size: size * 0.45))
                .foregroundColor(.secondary.opacity(0.5))
        }
    }
}
