import Foundation
import Combine
import CloudKit

/// Monitors CloudKit + iCloud Documents sync status
/// Notifies UI that sync is in progress on first app launch.
/// Also handles iCloud sign-out detection.
@MainActor
final class CloudSyncMonitor: ObservableObject {

    /// Whether sync is currently in progress
    @Published var isSyncing: Bool = false

    /// Signed out from iCloud — data inaccessible
    @Published var isSignedOutFromICloud: Bool = false

    /// iCloud account status
    @Published var accountStatus: CKAccountStatus = .couldNotDetermine

    private var syncTimer: Timer?
    private var startTime: Date?
    private var initialChartCount: Int = 0

    /// Maximum sync wait time (seconds) — auto-completes after this
    private let maxSyncDuration: TimeInterval = 15

    init() {
        checkInitialState()
    }

    // MARK: - Initial State Detection

    private func checkInitialState() {
        // 1) Detect iCloud sign-out
        if ChartStorage.needsICloudReSignIn {
            isSignedOutFromICloud = true
            isSyncing = false
            return
        }

        // 2) Record iCloud availability
        ChartStorage.recordICloudUsage()

        // 3) No sync indicator needed if iCloud unavailable
        guard ChartStorage.isICloudAvailable else {
            isSyncing = false
            return
        }

        // 4) Check iCloud account status
        CKContainer(identifier: "iCloud.codershigh.Chartrix").accountStatus { [weak self] status, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.accountStatus = status

                if status == .available {
                    // iCloud signed in → show sync indicator
                    self.beginSyncWatch()
                } else {
                    self.isSyncing = false
                }
            }
        }

        // 5) Subscribe to iCloud account change notifications
        NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAccountChange()
            }
        }
    }

    /// Handle iCloud account change (sign-in/sign-out)
    private func handleAccountChange() {
        ChartStorage.recordICloudUsage()

        if ChartStorage.isICloudAvailable {
            // Signed back in
            isSignedOutFromICloud = false
        } else if ChartStorage.wasUsingICloud {
            // Signed out
            isSignedOutFromICloud = true
            finishSync()
        }
    }

    /// Begin sync monitoring — until first data arrives or timeout
    private func beginSyncWatch() {
        isSyncing = true
        startTime = Date()

        // Check sync state periodically (every 2 seconds)
        syncTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateSyncState()
            }
        }
    }

    private func evaluateSyncState() {
        guard let startTime else {
            finishSync()
            return
        }

        let elapsed = Date().timeIntervalSince(startTime)

        // Timeout: end sync wait
        if elapsed >= maxSyncDuration {
            finishSync()
            return
        }
    }

    private func finishSync() {
        isSyncing = false
        syncTimer?.invalidate()
        syncTimer = nil
        startTime = nil
    }

    /// Called externally when data has loaded (charts appear in list)
    func notifyDataLoaded() {
        guard isSyncing else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            finishSync()
        }
    }
}
