import AVFoundation
import Foundation
import UIKit
import UserNotifications

@MainActor
final class BackgroundDownloadManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = BackgroundDownloadManager()

    private var audioPlayer: AVAudioPlayer?
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    private var isKeepingAlive = false
    private var hasRequestedNotifications = false

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resumeAudioKeepAliveIfNeeded()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.ensureBackgroundTaskOnEnterBackground()
            }
        }
    }

    func updateActiveDownloadState(isActive: Bool) {
        if isActive {
            startKeepAliveIfNeeded()
        } else {
            stopKeepAlive()
        }
    }

    private func startKeepAliveIfNeeded() {
        requestNotificationPermissionIfNeeded()
        UIApplication.shared.isIdleTimerDisabled = true
        beginSystemBackgroundTaskIfNeeded()

        guard !isKeepingAlive else {
            resumeAudioKeepAliveIfNeeded()
            return
        }
        isKeepingAlive = true

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            if audioPlayer == nil {
                let wavData = Self.makeSilentWAVData()
                let player = try AVAudioPlayer(data: wavData, fileTypeHint: AVFileType.wav.rawValue)
                player.numberOfLoops = -1
                player.volume = 0.0
                player.prepareToPlay()
                audioPlayer = player
            }
            audioPlayer?.play()
            DebugLogger.log("Background keep-alive started")
        } catch {
            DebugLogger.log("Background keep-alive audio error: \(error.localizedDescription)")
        }
    }

    private func resumeAudioKeepAliveIfNeeded() {
        guard isKeepingAlive else { return }
        if audioPlayer?.isPlaying != true {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            audioPlayer?.play()
        }
    }

    private func ensureBackgroundTaskOnEnterBackground() {
        guard isKeepingAlive else { return }
        beginSystemBackgroundTaskIfNeeded()
        resumeAudioKeepAliveIfNeeded()
    }

    private func stopKeepAlive() {
        UIApplication.shared.isIdleTimerDisabled = false
        endSystemBackgroundTask()

        guard isKeepingAlive else { return }
        isKeepingAlive = false

        audioPlayer?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        DebugLogger.log("Background keep-alive stopped")
    }

    private func beginSystemBackgroundTaskIfNeeded() {
        guard backgroundTaskId == .invalid else { return }
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "IPADownloaderBackgroundTransfer") { [weak self] in
            Task { @MainActor in
                self?.endSystemBackgroundTask()
                self?.resumeAudioKeepAliveIfNeeded()
            }
        }
    }

    private func endSystemBackgroundTask() {
        guard backgroundTaskId != .invalid else { return }
        let id = backgroundTaskId
        backgroundTaskId = .invalid
        UIApplication.shared.endBackgroundTask(id)
    }

    // MARK: - Local Notifications

    private func requestNotificationPermissionIfNeeded() {
        guard !hasRequestedNotifications else { return }
        hasRequestedNotifications = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func notifyDownloadCompleted(appName: String, versionLabel: String, accountEmail: String) {
        let content = UNMutableNotificationContent()
        content.title = "Tải hoàn tất: \(appName)"
        content.body = "Phiên bản v\(versionLabel) đã được lưu vào thư mục của \(accountEmail)."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "ipa_done_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func notifyDownloadFailed(appName: String, error: String) {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = "Tải thất bại: \(appName)"
        content.body = error
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "ipa_fail_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // MARK: - In-Memory Silent WAV Generator (1s, 8000 Hz, 16-bit Mono PCM)

    private static func makeSilentWAVData() -> Data {
        let sampleRate: UInt32 = 8000
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let numSamples: UInt32 = sampleRate
        let dataSize: UInt32 = numSamples * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let chunkSize: UInt32 = 36 + dataSize
        let byteRate: UInt32 = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = numChannels * (bitsPerSample / 8)

        var data = Data(capacity: Int(44 + dataSize))
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        data.append(littleEndianBytes(chunkSize))
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        data.append(littleEndianBytes(UInt32(16)))        // Subchunk1Size (16 for PCM)
        data.append(littleEndianBytes(UInt16(1)))         // AudioFormat (1 = PCM)
        data.append(littleEndianBytes(numChannels))
        data.append(littleEndianBytes(sampleRate))
        data.append(littleEndianBytes(byteRate))
        data.append(littleEndianBytes(blockAlign))
        data.append(littleEndianBytes(bitsPerSample))
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.append(littleEndianBytes(dataSize))
        data.append(Data(count: Int(dataSize)))           // 0-amplitude silence
        return data
    }

    private static func littleEndianBytes<T: FixedWidthInteger>(_ value: T) -> Data {
        var le = value.littleEndian
        return withUnsafeBytes(of: &le) { Data($0) }
    }
}
