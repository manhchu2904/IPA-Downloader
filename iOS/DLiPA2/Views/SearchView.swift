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
                            Text("Nhập tên ứng dụng để tìm kiếm trên App Store")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(results) { app in
                            NavigationLink {
                                AppDetailView(app: app, platform: selectedPlatform)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
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
                                    Text(app.bundleId)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    Text("v\(app.version) • ID: \(app.id)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("DLiPA2")
            .searchable(text: $query, prompt: "Tên ứng dụng (vd: Facebook, Spotify...)")
            .onSubmit(of: .search) {
                runSearch()
            }
        }
    }

    private var filterBar: some View {
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
