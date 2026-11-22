import Foundation
import Darwin
import Security
import Ipatoolbridge

@MainActor
final class IPAToolService: ObservableObject {
    @Published var accounts: [AppleAccount] = []
    @Published var selectedAccountId: String?
    @Published var activeDownloads: [ActiveDownload] = []
    @Published var downloadedFiles: [DownloadedIPA] = []
    @Published var activeInstallSession: InstallSession?
    @Published var isCACertServerRunning: Bool = false
    @Published var localCATrustState: LocalCACertTrustState = .notInstalled
    @Published var installStage: String = "ready"
    @Published var installTLSDiagnostic: String?
    @Published var installSentBytes: Int64 = 0
    @Published var installTotalBytes: Int64 = 0
    @Published var installPercent: Double = 0
    @Published var initError: String?

    private var client: IpatoolbridgeClient?
    // Concurrent queue so long-running downloads never block search, login, or version lookups.
    private let workQueue = DispatchQueue(label: "com.dlipa2.ipatool.work", qos: .userInitiated, attributes: .concurrent)
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var versionMetadataCache: [String: VersionMetadata] = [:]
    private var versionCacheFileURL: URL?

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
            let baseDir = appSupport.appendingPathComponent("IPADownloaderCore", isDirectory: true)
            let oldBaseDir = appSupport.appendingPathComponent("DLiPA2Core", isDirectory: true)
            if !FileManager.default.fileExists(atPath: baseDir.path), FileManager.default.fileExists(atPath: oldBaseDir.path) {
                try? FileManager.default.moveItem(at: oldBaseDir, to: baseDir)
            }
            try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

            let cacheFile = baseDir.appendingPathComponent("version_metadata_cache.json")
            self.versionCacheFileURL = cacheFile
            if let data = try? Data(contentsOf: cacheFile),
               let cached = try? decoder.decode([String: VersionMetadata].self, from: data) {
                self.versionMetadataCache = cached
            }

            // Ensure HOME and TMPDIR exist before Go's runtime/stdlib cache lookups when launched via debugserver.
            setenv("HOME", baseDir.path, 1)
            if getenv("TMPDIR") == nil {
                setenv("TMPDIR", FileManager.default.temporaryDirectory.path, 1)
            }

            var err: NSError?
            guard let initialized = IpatoolbridgeNewClient(baseDir.path, &err) else {
                throw err ?? NSError(domain: "IPADownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Go core"])
            }
            self.client = initialized

            Task {
                await refreshAccounts()
                refreshDownloadedFiles()
                await refreshLocalCATrustState()
                await prepareRuntimeIfNeeded()
            }
        } catch {
            self.initError = error.localizedDescription
        }
    }

    private func prepareRuntimeIfNeeded() async {
        guard let client else { return }
        DebugLogger.log("prepare() background start")
        do {
            try await runBlocking {
                try client.prepare()
            }
            DebugLogger.log("prepare() background done")
        } catch {
            DebugLogger.log("prepare() background error: \(error.localizedDescription)")
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
            throw NSError(domain: "IPADownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Core not initialized"])
        }
        JITHelper.prepareStartupJIT26PoolIfNeeded()
        DebugLogger.log("login() start: JIT=\(JITHelper.isJITEnabled()) poolReady=\(JITHelper.isJITPoolReady()) flags=\(JITHelper.codeSigningFlagsHex()) has2FA=\(!authCode.isEmpty)")
        do {
            DebugLogger.log("login() prepare assets start")
            try await runBlocking {
                try client.prepare()
            }
            DebugLogger.log("login() prepare assets done")

            let json = try await runBridge { errPtr in
                client.login(email, password: password, authCode: authCode, error: errPtr)
            }
            let response = try decoder.decode(LoginResponse.self, from: Data(json.utf8))
            DebugLogger.log("login() done: success=\(response.success) authCodeRequired=\(response.authCodeRequired)")
            if response.success {
                await refreshAccounts()
                if let acc = response.account {
                    selectedAccountId = acc.id
                }
            }
            return response
        } catch {
            DebugLogger.log("login() error: \(error.localizedDescription)")
            throw error
        }
    }

    func removeAccount(_ account: AppleAccount) async throws {
        guard let client else { return }
        try await runBlocking {
            try client.removeAccount(account.id)
        }
        await refreshAccounts()
    }

    // MARK: - Search & Lookup

    func lookup(bundleId: String = "", appId: Int64 = 0, storefrontId: String, platform: String = "iphone") async throws -> AppItem {
        guard let client else {
            throw NSError(domain: "IPADownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Core not initialized"])
        }
        guard let account = selectedAccount else {
            throw NSError(domain: "IPADownloader", code: -2, userInfo: [NSLocalizedDescriptionKey: "Vui lòng đăng nhập Apple ID trước."])
        }
        let json = try await runBridge { errPtr in
            client.lookup(account.id, bundleID: bundleId, appID: appId, storefrontOverride: storefrontId, platformName: platform, error: errPtr)
        }
        return try decoder.decode(AppItem.self, from: Data(json.utf8))
    }

    private static func extractAppIDFromURLOrNumber(_ raw: String) -> Int64? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = Int64(trimmed), direct > 0 {
            return direct
        }
        // Match App Store URLs like https://apps.apple.com/vn/app/spotify/id324684580
        if let range = trimmed.range(of: #"id(\d{5,15})"#, options: .regularExpression) {
            let digits = trimmed[range].dropFirst(2)
            return Int64(digits)
        }
        return nil
    }

    private static func looksLikeBundleID(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "), !trimmed.hasPrefix("http"), trimmed.contains(".") else {
            return false
        }
        let parts = trimmed.split(separator: ".")
        return parts.count >= 2 && parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }

    func search(term: String, storefrontId: String, platform: String = "iphone", limit: Int = 25) async throws -> [AppItem] {
        guard client != nil else {
            throw NSError(domain: "IPADownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Core not initialized"])
        }
        guard let account = selectedAccount else {
            throw NSError(domain: "IPADownloader", code: -2, userInfo: [NSLocalizedDescriptionKey: "Vui lòng đăng nhập Apple ID trước."])
        }

        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Direct App Store link or numeric App ID lookup
        if let appId = Self.extractAppIDFromURLOrNumber(trimmed) {
            if let exact = try? await lookup(appId: appId, storefrontId: storefrontId, platform: platform) {
                if trimmed.lowercased().contains("apple.com") {
                    return [exact]
                }
                let searchResults = (try? await rawSearch(accountId: account.id, term: trimmed, storefrontId: storefrontId, platform: platform, limit: limit)) ?? []
                return [exact] + searchResults.filter { $0.id != exact.id }
            }
        }

        // 2. Direct Bundle ID lookup (e.g. com.spotify.client) + fallback search
        if Self.looksLikeBundleID(trimmed) {
            if let exact = try? await lookup(bundleId: trimmed, storefrontId: storefrontId, platform: platform) {
                let searchResults = (try? await rawSearch(accountId: account.id, term: trimmed, storefrontId: storefrontId, platform: platform, limit: limit)) ?? []
                return [exact] + searchResults.filter { $0.id != exact.id }
            }
        }

        return try await rawSearch(accountId: account.id, term: trimmed, storefrontId: storefrontId, platform: platform, limit: limit)
    }

    private func rawSearch(accountId: String, term: String, storefrontId: String, platform: String, limit: Int) async throws -> [AppItem] {
        guard let client else {
            throw NSError(domain: "IPADownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Core not initialized"])
        }
        let json = try await runBridge { errPtr in
            client.search(accountId, term: term, storefrontOverride: storefrontId, platformName: platform, limit: limit, error: errPtr)
        }
        return try decoder.decode([AppItem].self, from: Data(json.utf8))
    }

    // MARK: - Version History

    private func versionCacheKey(appId: Int64, versionId: String, platform: String) -> String {
        "\(appId)_\(platform)_\(versionId)"
    }

    func cachedVersionMetadata(appId: Int64, versionId: String, platform: String = "iphone") -> VersionMetadata? {
        versionMetadataCache[versionCacheKey(appId: appId, versionId: versionId, platform: platform)]
    }

    func cacheVersionMetadata(_ meta: VersionMetadata, appId: Int64, platform: String = "iphone") {
        let key = versionCacheKey(appId: appId, versionId: meta.versionId, platform: platform)
        versionMetadataCache[key] = meta
        saveVersionMetadataCacheToDisk()
    }

    private func saveVersionMetadataCacheToDisk() {
        guard let url = versionCacheFileURL,
              let data = try? encoder.encode(versionMetadataCache) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    /// Queries the public version history index (1 anonymous GET request, 0 requests to Apple)
    /// to map External Version IDs -> vX.Y.Z and release dates instantly without triggering
    /// Apple's volumeStoreDownloadProduct rate limits.
    func fetchPublicVersionDirectory(appId: Int64, platform: String = "iphone") async -> (ordered: [VersionMetadata], map: [String: VersionMetadata]) {
        guard let url = URL(string: "https://apis.bilin.eu.org/history/\(appId)") else {
            return ([], [:])
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                return ([], [:])
            }
            let decoded = try decoder.decode(PublicVersionHistoryResponse.self, from: data)
            var ordered: [VersionMetadata] = []
            var mapped: [String: VersionMetadata] = [:]
            for item in decoded.data ?? [] {
                guard !item.versionIdString.isEmpty, !item.bundleVersion.isEmpty else { continue }
                let meta = VersionMetadata(
                    versionId: item.versionIdString,
                    displayVersion: item.bundleVersion,
                    releaseDate: item.createdAt
                )
                if mapped[meta.versionId] == nil {
                    ordered.append(meta)
                }
                mapped[meta.versionId] = meta
                let key = versionCacheKey(appId: appId, versionId: meta.versionId, platform: platform)
                versionMetadataCache[key] = meta
            }
            if !mapped.isEmpty {
                saveVersionMetadataCacheToDisk()
            }
            return (ordered, mapped)
        } catch {
            return ([], [:])
        }
    }

    var hasActiveDownloads: Bool {
        activeDownloads.contains { !$0.isCompleted && $0.errorMessage == nil } || activeInstallSession != nil || isCACertServerRunning
    }

    func listVersions(for app: AppItem, platform: String = "iphone", purchaseIfNeeded: Bool = false) async throws -> VersionHistory {
        guard let client else {
            throw NSError(domain: "IPADownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Core not initialized"])
        }
        guard let account = selectedAccount else {
            throw NSError(domain: "IPADownloader", code: -2, userInfo: [NSLocalizedDescriptionKey: "Vui lòng đăng nhập Apple ID trước."])
        }
        let json = try await runBridge { errPtr in
            client.listVersions(account.id, appID: app.id, bundleID: app.bundleId, price: app.price, platformName: platform, purchaseIfNeeded: purchaseIfNeeded, error: errPtr)
        }
        let history = try decoder.decode(VersionHistory.self, from: Data(json.utf8))
        if !history.latestVersionId.isEmpty && !app.version.isEmpty &&
            cachedVersionMetadata(appId: app.id, versionId: history.latestVersionId, platform: platform) == nil {
            let latestMeta = VersionMetadata(versionId: history.latestVersionId, displayVersion: app.version, releaseDate: nil)
            cacheVersionMetadata(latestMeta, appId: app.id, platform: platform)
        }
        return history
    }

    func versionMetadata(for app: AppItem, versionId: String, platform: String = "iphone") async throws -> VersionMetadata {
        if let cached = cachedVersionMetadata(appId: app.id, versionId: versionId, platform: platform),
           cached.releaseDate != nil {
            return cached
        }
        guard let client else {
            throw NSError(domain: "IPADownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Core not initialized"])
        }
        guard let account = selectedAccount else {
            throw NSError(domain: "IPADownloader", code: -2, userInfo: [NSLocalizedDescriptionKey: "Vui lòng đăng nhập Apple ID trước."])
        }
        let json = try await runBridge { errPtr in
            client.getVersionMetadata(account.id, appID: app.id, bundleID: app.bundleId, versionID: versionId, platformName: platform, error: errPtr)
        }
        let meta = try decoder.decode(VersionMetadata.self, from: Data(json.utf8))
        cacheVersionMetadata(meta, appId: app.id, platform: platform)
        return meta
    }

    // MARK: - Downloads

    static let uncategorizedAccountLabel = "Chưa phân loại"

    private static func sanitizeFolderName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return uncategorizedAccountLabel }
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = trimmed.components(separatedBy: forbidden).joined(separator: "_")
        return cleaned.isEmpty ? uncategorizedAccountLabel : cleaned
    }

    func accountDownloadDirectory(for accountEmail: String) -> URL {
        let folderName = Self.sanitizeFolderName(accountEmail)
        let dir = downloadsDirectory.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func startDownload(app: AppItem, externalVersionId: String = "", versionLabel: String = "Latest", platform: String = "iphone", accountOverride: AppleAccount? = nil) {
        guard let client, let account = accountOverride ?? selectedAccount else { return }
        let downloadId = UUID().uuidString
        let outputDir = accountDownloadDirectory(for: account.email).path

        let item = ActiveDownload(
            id: downloadId,
            appName: app.name,
            bundleId: app.bundleId,
            versionLabel: versionLabel,
            accountEmail: account.email
        )
        activeDownloads.insert(item, at: 0)
        BackgroundDownloadManager.shared.updateActiveDownloadState(isActive: hasActiveDownloads)

        var lastSampleTime = Date()
        var lastSampleBytes: Int64 = 0

        let listener = BridgeProgressListener { [weak self] id, downloaded, total, percent, stage in
            let now = Date()
            let dt = now.timeIntervalSince(lastSampleTime)
            var calculatedSpeed: Double?
            if dt >= 0.35 {
                let deltaBytes = max(0, downloaded - lastSampleBytes)
                calculatedSpeed = Double(deltaBytes) / dt
                lastSampleTime = now
                lastSampleBytes = downloaded
            }
            Task { @MainActor in
                guard let self, let idx = self.activeDownloads.firstIndex(where: { $0.id == id }) else { return }
                self.activeDownloads[idx].downloadedBytes = downloaded
                self.activeDownloads[idx].totalBytes = total
                if let calculatedSpeed {
                    self.activeDownloads[idx].speedBytesPerSec = calculatedSpeed
                }
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
                    activeDownloads[idx].speedBytesPerSec = 0
                    activeDownloads[idx].stage = "completed"
                    activeDownloads[idx].isCompleted = true
                }
                BackgroundDownloadManager.shared.updateActiveDownloadState(isActive: hasActiveDownloads)
                BackgroundDownloadManager.shared.notifyDownloadCompleted(
                    appName: app.name,
                    versionLabel: versionLabel,
                    accountEmail: account.email
                )
                refreshDownloadedFiles()
            } catch {
                if let idx = activeDownloads.firstIndex(where: { $0.id == downloadId }) {
                    activeDownloads[idx].speedBytesPerSec = 0
                    activeDownloads[idx].stage = "failed"
                    activeDownloads[idx].errorMessage = error.localizedDescription
                }
                BackgroundDownloadManager.shared.updateActiveDownloadState(isActive: hasActiveDownloads)
                BackgroundDownloadManager.shared.notifyDownloadFailed(
                    appName: app.name,
                    error: error.localizedDescription
                )
            }
        }
    }

    func cancelDownload(id: String) {
        client?.cancelDownload(id)
        activeDownloads.removeAll { $0.id == id }
        BackgroundDownloadManager.shared.updateActiveDownloadState(isActive: hasActiveDownloads)
    }

    func removeFinishedDownloadEntry(id: String) {
        activeDownloads.removeAll { $0.id == id }
    }

    func clearCompletedDownloads() {
        activeDownloads.removeAll { $0.isCompleted || $0.errorMessage != nil }
    }

    func refreshDownloadedFiles() {
        let fm = FileManager.default
        let rootDir = downloadsDirectory
        guard let topEntries = try? fm.contentsOfDirectory(
            at: rootDir,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            downloadedFiles = []
            return
        }

        var collected: [DownloadedIPA] = []

        for entry in topEntries {
            let resourceValues = try? entry.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey])
            if resourceValues?.isDirectory == true {
                let accountLabel = entry.lastPathComponent
                let subURLs = (try? fm.contentsOfDirectory(
                    at: entry,
                    includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                for fileURL in subURLs where fileURL.pathExtension.lowercased() == "ipa" {
                    let fileVals = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                    collected.append(
                        DownloadedIPA(
                            id: fileURL,
                            url: fileURL,
                            name: fileURL.lastPathComponent,
                            accountEmail: accountLabel,
                            size: Int64(fileVals?.fileSize ?? 0),
                            createdAt: fileVals?.creationDate ?? Date()
                        )
                    )
                }
            } else if entry.pathExtension.lowercased() == "ipa" {
                collected.append(
                    DownloadedIPA(
                        id: entry,
                        url: entry,
                        name: entry.lastPathComponent,
                        accountEmail: Self.uncategorizedAccountLabel,
                        size: Int64(resourceValues?.fileSize ?? 0),
                        createdAt: resourceValues?.creationDate ?? Date()
                    )
                )
            }
        }

        downloadedFiles = collected.sorted { $0.createdAt > $1.createdAt }
    }

    func renameDownloadedFile(_ file: DownloadedIPA, newName: String) throws {
        var cleaned = Self.sanitizeFolderName(newName)
        if !cleaned.lowercased().hasSuffix(".ipa") {
            cleaned += ".ipa"
        }
        let destination = file.url.deletingLastPathComponent().appendingPathComponent(cleaned)
        guard destination != file.url else { return }
        try FileManager.default.moveItem(at: file.url, to: destination)
        refreshDownloadedFiles()
    }

    func deleteDownloadedFile(_ file: DownloadedIPA) {
        let parentDir = file.url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: file.url)
        // Clean up empty account folder
        if parentDir != downloadsDirectory,
           let remaining = try? FileManager.default.contentsOfDirectory(atPath: parentDir.path),
           remaining.isEmpty {
            try? FileManager.default.removeItem(at: parentDir)
        }
        refreshDownloadedFiles()
    }

    func deleteDownloadedFiles(forAccount accountEmail: String?) {
        let targets = downloadedFiles.filter { accountEmail == nil || $0.accountEmail == accountEmail }
        for file in targets {
            try? FileManager.default.removeItem(at: file.url)
        }
        if let accountEmail, accountEmail != Self.uncategorizedAccountLabel {
            let folder = downloadsDirectory.appendingPathComponent(accountEmail, isDirectory: true)
            if let remaining = try? FileManager.default.contentsOfDirectory(atPath: folder.path), remaining.isEmpty {
                try? FileManager.default.removeItem(at: folder)
            }
        }
        refreshDownloadedFiles()
    }

    // MARK: - Direct On-Device OTA Installer (itms-services://)

    func startIPAInstaller(for file: DownloadedIPA) async throws -> InstallSession {
        guard let client else {
            throw NSError(domain: "IPADownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Core not initialized"])
        }

        installStage = "ready"
        installTLSDiagnostic = nil
        installSentBytes = 0
        installTotalBytes = file.size
        installPercent = 0

        let listener = BridgeInstallProgressListener { [weak self] stage, sent, total, pct in
            Task { @MainActor in
                guard let self else { return }
                if stage.hasPrefix("tls_log:") {
                    let msg = String(stage.dropFirst("tls_log:".count))
                    DebugLogger.log("OTA HTTPS server: \(msg)")
                    return
                }
                if stage.hasPrefix("tls_error:") {
                    let msg = String(stage.dropFirst("tls_error:".count))
                    DebugLogger.log("OTA HTTPS server TLS log: \(msg)")
                    self.installTLSDiagnostic = msg
                    return
                }
                if stage != self.installStage {
                    DebugLogger.log("OTA install stage -> \(stage)")
                }
                self.installStage = stage
                self.installSentBytes = sent
                self.installTotalBytes = total
                self.installPercent = pct
            }
        }

        let json = try await runBridge { errPtr in
            client.startIPAInstaller(file.url.path, listener: listener, error: errPtr)
        }
        let session = try decoder.decode(InstallSession.self, from: Data(json.utf8))
        activeInstallSession = session
        BackgroundDownloadManager.shared.updateActiveDownloadState(isActive: hasActiveDownloads)
        DebugLogger.log("OTA installer started: host=\(session.httpsHost ?? "localhost") http=\(session.httpPort) https=\(session.httpsPort)")
        return session
    }

    func stopIPAInstaller() {
        client?.stopIPAInstaller()
        activeInstallSession = nil
        isCACertServerRunning = false
        installStage = "ready"
        installTLSDiagnostic = nil
        installPercent = 0
        BackgroundDownloadManager.shared.updateActiveDownloadState(isActive: hasActiveDownloads)
    }

    func verifyLocalHTTPSLoopback(host: String, httpsPort: Int) async -> String? {
        guard let url = URL(string: "https://\(host):\(httpsPort)/ping") else {
            return "URL \(host) không hợp lệ"
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            DebugLogger.log("OTA HTTPS self-test OK (\(host):\(httpsPort)): status=\(code) body=\(body)")
            return nil
        } catch {
            let nsErr = error as NSError
            let msg = "Self-test https://\(host):\(httpsPort) lỗi (\(nsErr.domain) \(nsErr.code)): \(nsErr.localizedDescription)"
            DebugLogger.log("OTA HTTPS self-test FAILED: \(msg)")
            return msg
        }
    }

    func startCACertServer() async throws -> URL {
        guard let client else {
            throw NSError(domain: "IPADownloader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Core not initialized"])
        }
        isCACertServerRunning = true
        BackgroundDownloadManager.shared.updateActiveDownloadState(isActive: hasActiveDownloads)

        let jsonStr = try await runBridge { errPtr in
            client.startCACertServer(errPtr)
        }
        let dto = try decoder.decode(InstallSession.self, from: Data(jsonStr.utf8))
        guard let url = URL(string: dto.caCertUrl) else {
            isCACertServerRunning = false
            BackgroundDownloadManager.shared.updateActiveDownloadState(isActive: hasActiveDownloads)
            throw NSError(domain: "IPADownloader", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid CA certificate URL"])
        }
        await refreshLocalCATrustState()
        return url
    }

    func refreshLocalCATrustState() async {
        guard let client else { return }
        do {
            let jsonStr = try await runBridge { errPtr in
                client.getInstallerCertChainJSON(errPtr)
            }
            let payload = try decoder.decode(InstallerCertChainPayload.self, from: Data(jsonStr.utf8))
            let hasDownloadedProfile = client.hasServedCACert()
            let isSystemTrusted = Self.evaluateLocalTLSLeafTrust(leafDER: payload.leafDer)
            if isSystemTrusted {
                self.localCATrustState = .trusted
                if self.isCACertServerRunning && self.activeInstallSession == nil {
                    self.isCACertServerRunning = false
                    BackgroundDownloadManager.shared.updateActiveDownloadState(isActive: self.hasActiveDownloads)
                }
            } else if hasDownloadedProfile {
                self.localCATrustState = .profileDownloadedNotTrusted
            } else {
                self.localCATrustState = .notInstalled
            }
        } catch {
            self.localCATrustState = .notInstalled
        }
    }

    private nonisolated static func evaluateLocalTLSLeafTrust(leafDER: Data) -> Bool {
        guard let leafCert = SecCertificateCreateWithData(nil, leafDER as CFData) else {
            return false
        }
        let policy = SecPolicyCreateSSL(true, "localhost" as CFString)
        var trust: SecTrust?
        // Pass ONLY the leaf certificate so trustd must verify against the Root CA installed & trusted in iOS Settings.
        let status = SecTrustCreateWithCertificates([leafCert] as CFArray, policy, &trust)
        guard status == errSecSuccess, let trust else {
            return false
        }
        var cfError: CFError?
        return SecTrustEvaluateWithError(trust, &cfError)
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

private final class BridgeInstallProgressListener: NSObject, IpatoolbridgeInstallProgressListenerProtocol {
    private let handler: (String, Int64, Int64, Double) -> Void

    init(handler: @escaping (String, Int64, Int64, Double) -> Void) {
        self.handler = handler
    }

    func onInstallProgress(_ stage: String?, sentBytes: Int64, totalBytes: Int64, percent: Double) {
        handler(stage ?? "ready", sentBytes, totalBytes, percent)
    }
}

private struct PublicVersionHistoryResponse: Decodable {
    let data: [PublicVersionHistoryItem]?
}

private struct PublicVersionHistoryItem: Decodable {
    let bundleVersion: String
    let versionIdString: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case bundleVersion = "bundle_version"
        case externalIdentifier = "external_identifier"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.bundleVersion = (try? container.decode(String.self, forKey: .bundleVersion)) ?? ""
        if let intId = try? container.decode(Int64.self, forKey: .externalIdentifier) {
            self.versionIdString = String(intId)
        } else if let strId = try? container.decode(String.self, forKey: .externalIdentifier) {
            self.versionIdString = strId
        } else {
            self.versionIdString = ""
        }
        self.createdAt = try? container.decode(String.self, forKey: .createdAt)
    }
}
