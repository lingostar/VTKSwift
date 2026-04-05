import Foundation
import Combine

/// ObservableObject that monitors iCloud file download progress
/// Tracks iCloud download progress using NSMetadataQuery.
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

    /// Number of consecutive polls where the directory was not found
    private var directoryMissingCount: Int = 0

    /// Maximum polls with missing directory before reporting failure (1 poll/sec)
    private let maxDirectoryMissingPolls: Int = 15

    /// Start monitoring and downloading a DICOM directory
    func startMonitoring(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.directoryMissingCount = 0
        state = .checking

        let fm = FileManager.default

        // Early detection: iCloud Documents not accessible + directory doesn't exist locally
        // This happens when CloudKit metadata synced but iCloud Drive is unavailable
        // (e.g., simulator, iCloud Drive disabled, or iCloud not signed in)
        if !fm.fileExists(atPath: directoryURL.path) && !ChartStorage.isICloudAvailable {
            state = .failed("iCloud Drive is not available.\nSign in to iCloud and enable iCloud Drive to download DICOM files.")
            print("[iCloud] Download failed: iCloud Documents not accessible, directory does not exist locally")
            return
        }

        // Check current status
        let status = ChartStorage.directoryDownloadStatus(directoryURL)

        switch status {
        case .local, .downloaded:
            state = .completed
            return
        case .downloading, .notDownloaded:
            // Trigger download
            ChartStorage.startDownloadingDirectory(directoryURL)
            state = .downloading(progress: 0, downloadedFiles: 0, totalFiles: 0)
            startPolling()
        }
    }

    /// Start download based on Study
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
        // Timer and query must be cleaned up on MainActor
        Task { @MainActor [weak self] in
            self?.pollTimer?.invalidate()
            self?.pollTimer = nil
            self?.metadataQuery?.stop()
            self?.metadataQuery = nil
        }
    }

    // MARK: - Polling (simple and reliable approach)

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

        // Check if directory exists at all
        guard fm.fileExists(atPath: dirURL.path) else {
            directoryMissingCount += 1
            print("[iCloud] Directory not found (attempt \(directoryMissingCount)/\(maxDirectoryMissingPolls)): \(dirURL.lastPathComponent)")

            if directoryMissingCount >= maxDirectoryMissingPolls {
                // Directory never appeared — iCloud Documents likely not accessible
                pollTimer?.invalidate()
                pollTimer = nil

                if !ChartStorage.isICloudAvailable {
                    state = .failed("iCloud Drive is not available.\nSign in to iCloud and enable iCloud Drive to download DICOM files.")
                } else {
                    state = .failed("Unable to download files from iCloud.\nPlease check your network connection and try again.")
                }
            }
            return
        }

        // Reset missing counter once directory appears
        directoryMissingCount = 0

        // ⚠️ options: [] — must NOT use .skipsHiddenFiles!
        // Undownloaded iCloud files exist as hidden ".filename.icloud"
        // placeholders, so hidden files must be included to count files correctly
        guard let allFiles = try? fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .fileSizeKey
            ],
            options: []
        ) else {
            // Directory exists but can't read contents — keep waiting
            return
        }

        // Include only .icloud placeholders and real files, exclude .DS_Store etc.
        let files = allFiles.filter { url in
            let name = url.lastPathComponent
            if name.hasPrefix(".") && name.hasSuffix(".icloud") {
                return true   // iCloud placeholder (undownloaded file)
            }
            if name.hasPrefix(".") {
                return false  // Exclude system hidden files like .DS_Store
            }
            return true       // Regular file (downloaded or local)
        }

        let total = files.count
        if total == 0 {
            return
        }

        var downloadedCount = 0

        for file in files {
            let name = file.lastPathComponent

            // .icloud placeholder = not yet downloaded
            if name.hasPrefix(".") && name.hasSuffix(".icloud") {
                continue
            }

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
                // status nil = local file
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
