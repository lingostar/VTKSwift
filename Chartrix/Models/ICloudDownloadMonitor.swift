import Foundation
import Combine

/// iCloud 파일 다운로드 진행 상태를 모니터링하는 ObservableObject
/// NSMetadataQuery를 사용하여 iCloud 다운로드 진행률을 추적합니다.
@MainActor
final class ICloudDownloadMonitor: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case downloading(progress: Double, downloadedFiles: Int, totalFiles: Int)
        case completed
        case failed(String)
    }

    @Published var state: State = .idle

    private var metadataQuery: NSMetadataQuery?
    private var directoryURL: URL?
    private var totalFileCount: Int = 0
    private var pollTimer: Timer?

    /// DICOM 디렉토리의 다운로드를 시작하고 모니터링
    func startMonitoring(directoryURL: URL) {
        self.directoryURL = directoryURL
        state = .checking

        // 먼저 현재 상태 체크
        let status = ChartStorage.directoryDownloadStatus(directoryURL)

        switch status {
        case .local, .downloaded:
            state = .completed
            return
        case .downloading, .notDownloaded:
            // 다운로드 트리거
            ChartStorage.startDownloadingDirectory(directoryURL)
            state = .downloading(progress: 0, downloadedFiles: 0, totalFiles: 0)
            startPolling()
        }
    }

    /// Study 기반으로 다운로드 시작
    func startMonitoring(study: Study) {
        guard let dirURL = ChartStorage.dicomDirectoryURL(for: study) else {
            state = .failed("DICOM directory not found")
            return
        }
        startMonitoring(directoryURL: dirURL)
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        stopMetadataQuery()
    }

    nonisolated func cleanup() {
        // Timer와 query는 MainActor에서 정리해야 함
        Task { @MainActor [weak self] in
            self?.pollTimer?.invalidate()
            self?.pollTimer = nil
            self?.metadataQuery?.stop()
            self?.metadataQuery = nil
        }
    }

    // MARK: - Polling (간단하고 안정적인 방식)

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkProgress()
            }
        }
    }

    private func checkProgress() {
        guard let dirURL = directoryURL else { return }

        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .fileSizeKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            // 디렉토리 아직 안 보임 — 계속 대기
            return
        }

        let total = files.count
        if total == 0 {
            // 아직 placeholder만 있거나 비어있음
            return
        }

        var downloadedCount = 0

        for file in files {
            let values = try? file.resourceValues(
                forKeys: [.ubiquitousItemDownloadingStatusKey]
            )

            if let status = values?.ubiquitousItemDownloadingStatus {
                switch status {
                case .current, .downloaded:
                    downloadedCount += 1
                default:
                    break
                }
            } else {
                // status nil = 로컬 파일
                downloadedCount += 1
            }
        }

        let progress = total > 0 ? Double(downloadedCount) / Double(total) : 0

        if downloadedCount >= total {
            state = .completed
            pollTimer?.invalidate()
            pollTimer = nil
            print("[iCloud] Download complete: \(total) files")
        } else {
            state = .downloading(
                progress: progress,
                downloadedFiles: downloadedCount,
                totalFiles: total
            )
        }
    }

    // MARK: - NSMetadataQuery (optional, for more fine-grained updates)

    private func stopMetadataQuery() {
        metadataQuery?.stop()
        metadataQuery = nil
    }
}
