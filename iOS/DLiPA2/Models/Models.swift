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
    let artworkUrl: String?
    let sellerName: String?
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
    let accountEmail: String
    var downloadedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var speedBytesPerSec: Double = 0
    var percent: Double = 0
    var stage: String = "preparing"
    var errorMessage: String?
    var isCompleted: Bool = false
}

struct DownloadedIPA: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let accountEmail: String
    let size: Int64
    let createdAt: Date

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct InstallSession: Codable, Identifiable {
    var id: String { "\(bundleId)_\(httpPort)" }
    let bundleId: String
    let appName: String
    let version: String
    let fileSize: Int64
    let httpPort: Int
    let httpsPort: Int
    let httpsHost: String?
    let directItmsUrl: String
    let localHttpsItmsUrl: String
    let localHttpsFallbackItmsUrl: String?
    let safariInstallUrl: String
    let caCertUrl: String
}

enum LocalCACertTrustState: Equatable {
    case notInstalled
    case profileDownloadedNotTrusted
    case trusted

    var title: String {
        switch self {
        case .notInstalled:
            return "Chưa tải / Chưa cài hồ sơ"
        case .profileDownloadedNotTrusted:
            return "Đã tải hồ sơ • Chưa bật Tin cậy"
        case .trusted:
            return "Đã cài đặt & Đã tin cậy"
        }
    }

    var iconName: String {
        switch self {
        case .notInstalled:
            return "xmark.shield.fill"
        case .profileDownloadedNotTrusted:
            return "exclamationmark.shield.fill"
        case .trusted:
            return "checkmark.shield.fill"
        }
    }
}

struct InstallerCertChainPayload: Codable {
    let caDer: Data
    let leafDer: Data
}
