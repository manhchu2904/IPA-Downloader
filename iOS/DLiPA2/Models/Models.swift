import Foundation

struct AppleAccount: Codable, Identifiable, Hashable {
    let id: String
    let email: String
    let name: String
    let storeFront: String
    let directoryServicesId: String
    let pod: String

    var displayName: String {
        name.isEmpty ? email : name
    }

    var storefrontCountryCode: String {
        let prefix = storeFront.split(separator: "-").first.map(String.init) ?? storeFront
        return Storefront.all.first(where: { $0.id == prefix })?.code ?? prefix
    }
}

struct LoginResponse: Codable {
    let success: Bool
    let authCodeRequired: Bool
    let account: AppleAccount?
    let error: String?
}

struct AppItem: Codable, Identifiable, Hashable {
    let id: Int64
    let bundleId: String
    let name: String
    let version: String
    let price: Double
    let platforms: [String]?

    var formattedPrice: String {
        price <= 0 ? "Free" : String(format: "$%.2f", price)
    }
}

struct VersionHistory: Codable {
    let latestVersionId: String
    let versionIds: [String]
}

struct VersionMetadata: Codable, Identifiable {
    var id: String { versionId }
    let versionId: String
    let displayVersion: String
    let releaseDate: String?
}

struct DownloadResult: Codable {
    let filePath: String
    let fileName: String
    let fileSize: Int64
}

struct ActiveDownload: Identifiable {
    let id: String
    let appName: String
    let bundleId: String
    let versionLabel: String
    var downloadedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var percent: Double = 0
    var stage: String = "preparing"
    var errorMessage: String?
    var isCompleted: Bool = false
}

struct DownloadedIPA: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let size: Int64
    let createdAt: Date

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
