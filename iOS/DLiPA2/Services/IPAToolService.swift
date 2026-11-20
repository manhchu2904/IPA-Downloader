import Foundation
import Ipatoolbridge

@MainActor
final class IPAToolService: ObservableObject {
    @Published var accounts: [AppleAccount] = []
    @Published var selectedAccountId: String?
    @Published var activeDownloads: [ActiveDownload] = []
    @Published var downloadedFiles: [DownloadedIPA] = []
    @Published var initError: String?

    private var client: IpatoolbridgeClient?
    // Concurrent queue so long-running downloads never block search, login, or version lookups.
    private let workQueue = DispatchQueue(label: "com.dlipa2.ipatool.work", qos: .userInitiated, attributes: .concurrent)
    private let decoder = JSONDecoder()

    var selectedAccount: AppleAccount? {
        if let id = selectedAccountId, let match = accounts.first(where: { $0.id == id }) {
            return match
        }
        return accounts.first
    }

    var downloadsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("IPAs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        do {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let baseDir = appSupport.appendingPathComponent("DLiPA2Core", isDirectory: true)
            try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

            var err: NSError?
            guard let initialized = IpatoolbridgeNewClient(baseDir.path, &err) else {
                throw err ?? NSError(domain: "DLiPA2", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Go core"])
            }
            self.client = initialized

            Task {
                await refreshAccounts()
                refreshDownloadedFiles()
            }
        } catch {
            self.initError = error.localizedDescription
        }
    }

    // MARK: - Accounts

    func refreshAccounts() async {
        guard let client else { return }
        do {
            let json = try await runBridge { errPtr in
                client.listAccounts(errPtr)
            }
            let list = try decoder.decode([AppleAccount].self, from: Data(json.utf8))
            self.accounts = list.sorted { $0.email.lowercased() < $1.email.lowercased() }
            if selectedAccountId == nil || !accounts.contains(where: { $0.id == selectedAccountId }) {
                selectedAccountId = accounts.first?.id
            }
        } catch {
            self.accounts = []
        }
    }

    func login(email: String, password: String, authCode: String) async throws -> LoginResponse {
        guard let client else {
            throw NSError(domain: "DLiPA2", code: -1, userInfo: [NSLocalizedDescriptionKey: "Core not initialized"])
        }
        let json = try await runBridge { errPtr in
            client.login(email, password: password, authCode: authCode, error: errPtr)
        }
        let response = try decoder.decode(LoginResponse.self, from: Data(json.utf8))
        if response.success {
            await refreshAccounts()
            if let acc = response.account {
                selectedAccountId = acc.id
            }
        }
        return response
    }

    func removeAccount(_ account: AppleAccount) async throws {
        guard let client else { return }
        try await runBlocking {
            try client.removeAccount(account.id)
        }
        await refreshAccounts()
    }

    // MARK: - Search & Lookup

    func search(term: String, storefrontId: String, platform: String = "iphone", limit: Int = 25) async throws -> [AppItem] {
        guard let client else {
            throw NSError(domain: "DLiPA2", code: -1, userInfo: [NSLocalizedDescriptionKey: "Core not initialized"])
        }
        guard let account = selectedAccount else {
            throw NSError(domain: "DLiPA2", code: -2, userInfo: [NSLocalizedDescriptionKey: "Vui lòng đăng nhập Apple ID trước."])
        }
        let json = try await runBridge { errPtr in
            client.search(account.id, term: term, storefrontOverride: storefrontId, platformName: platform, limit: limit, error: errPtr)
        }
        return try decoder.decode([AppItem].self, from: Data(json.utf8))
    }

    // MARK: - Version History

    func listVersions(for app: AppItem, platform: String = "iphone") async throws -> VersionHistory {
        guard let client else {
            throw NSError(domain: "DLiPA2", code: -1, userInfo: [NSLocalizedDescriptionKey: "Core not initialized"])
        }
        guard let account = selectedAccount else {
            throw NSError(domain: "DLiPA2", code: -2, userInfo: [NSLocalizedDescriptionKey: "Vui lòng đăng nhập Apple ID trước."])
        }
        let json = try await runBridge { errPtr in
            client.listVersions(account.id, appID: app.id, bundleID: app.bundleId, price: app.price, platformName: platform, purchaseIfNeeded: true, error: errPtr)
        }
        return try decoder.decode(VersionHistory.self, from: Data(json.utf8))
    }

    func versionMetadata(for app: AppItem, versionId: String, platform: String = "iphone") async throws -> VersionMetadata {
        guard let client else {
            throw NSError(domain: "DLiPA2", code: -1, userInfo: [NSLocalizedDescriptionKey: "Core not initialized"])
        }
        guard let account = selectedAccount else {
            throw NSError(domain: "DLiPA2", code: -2, userInfo: [NSLocalizedDescriptionKey: "Vui lòng đăng nhập Apple ID trước."])
        }
        let json = try await runBridge { errPtr in
            client.getVersionMetadata(account.id, appID: app.id, bundleID: app.bundleId, versionID: versionId, platformName: platform, error: errPtr)
        }
        return try decoder.decode(VersionMetadata.self, from: Data(json.utf8))
    }

    // MARK: - Downloads

    func startDownload(app: AppItem, externalVersionId: String = "", versionLabel: String = "Latest", platform: String = "iphone") {
        guard let client, let account = selectedAccount else { return }
        let downloadId = UUID().uuidString
        let outputDir = downloadsDirectory.path

        let item = ActiveDownload(
            id: downloadId,
            appName: app.name,
            bundleId: app.bundleId,
            versionLabel: versionLabel
        )
        activeDownloads.insert(item, at: 0)

        let listener = BridgeProgressListener { [weak self] id, downloaded, total, percent, stage in
            Task { @MainActor in
                guard let self, let idx = self.activeDownloads.firstIndex(where: { $0.id == id }) else { return }
                self.activeDownloads[idx].downloadedBytes = downloaded
                self.activeDownloads[idx].totalBytes = total
                self.activeDownloads[idx].percent = percent
                self.activeDownloads[idx].stage = stage
            }
        }

        Task {
            do {
                _ = try await runBridge { errPtr in
                    client.download(
                        downloadId,
                        accountID: account.id,
                        appID: app.id,
                        bundleID: app.bundleId,
                        appName: app.name,
                        price: app.price,
                        externalVersionID: externalVersionId,
                        platformName: platform,
                        outputDir: outputDir,
                        purchaseIfNeeded: true,
                        listener: listener,
                        error: errPtr
                    )
                }
                if let idx = activeDownloads.firstIndex(where: { $0.id == downloadId }) {
                    activeDownloads[idx].percent = 1.0
                    activeDownloads[idx].stage = "completed"
                    activeDownloads[idx].isCompleted = true
                }
                refreshDownloadedFiles()
            } catch {
                if let idx = activeDownloads.firstIndex(where: { $0.id == downloadId }) {
                    activeDownloads[idx].stage = "failed"
                    activeDownloads[idx].errorMessage = error.localizedDescription
                }
            }
        }
    }

    func cancelDownload(id: String) {
        client?.cancelDownload(id)
        activeDownloads.removeAll { $0.id == id }
    }

    func removeFinishedDownloadEntry(id: String) {
        activeDownloads.removeAll { $0.id == id }
    }

    func refreshDownloadedFiles() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: downloadsDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            downloadedFiles = []
            return
        }

        downloadedFiles = urls
            .filter { $0.pathExtension.lowercased() == "ipa" }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                return DownloadedIPA(
                    id: url,
                    url: url,
                    name: url.lastPathComponent,
                    size: Int64(values?.fileSize ?? 0),
                    createdAt: values?.creationDate ?? Date()
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func deleteDownloadedFile(_ file: DownloadedIPA) {
        try? FileManager.default.removeItem(at: file.url)
        refreshDownloadedFiles()
    }

    // MARK: - Helpers

    private func runBridge(_ work: @escaping (NSErrorPointer) -> String) async throws -> String {
        try await runBlocking {
            var err: NSError?
            let result = work(&err)
            if let err {
                throw err
            }
            return result
        }
    }

    private func runBlocking<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            workQueue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private final class BridgeProgressListener: NSObject, IpatoolbridgeProgressListenerProtocol {
    private let handler: (String, Int64, Int64, Double, String) -> Void

    init(handler: @escaping (String, Int64, Int64, Double, String) -> Void) {
        self.handler = handler
    }

    func onProgress(_ downloadID: String?, downloadedBytes: Int64, totalBytes: Int64, percent: Double, stage: String?) {
        handler(downloadID ?? "", downloadedBytes, totalBytes, percent, stage ?? "")
    }
}
