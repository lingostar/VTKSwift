import Foundation
import Combine
import CloudKit
import CoreData

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

    /// Last sync event description (for diagnostics)
    @Published var lastSyncEvent: String = ""

    /// Whether a sync error has occurred
    @Published var hasSyncError: Bool = false

    private var syncTimer: Timer?
    private var startTime: Date?
    private var eventObservers: [Any] = []

    /// Maximum sync wait time (seconds) — auto-completes after this
    private let maxSyncDuration: TimeInterval = 15

    init() {
        setupPersistentStoreEventObserver()
        checkInitialState()
    }

    deinit {
        for observer in eventObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Core Data / CloudKit Event Monitoring

    /// Observe NSPersistentCloudKitContainer sync events for diagnostics
    private func setupPersistentStoreEventObserver() {
        // Monitor remote change notifications (CloudKit data arrived)
        let remoteChange = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastSyncEvent = "Remote change received"
                self.hasSyncError = false
                print("[CloudSync] Remote change notification received")

                // If we're still in sync-wait, finish early
                if self.isSyncing {
                    self.finishSync()
                }
            }
        }
        eventObservers.append(remoteChange)

        // Monitor Core Data import events
        let importNotification = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NSPersistentCloudKitContainer.eventChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let event = notification.userInfo?["event"] as? NSObject {
                    let desc = String(describing: event)
                    print("[CloudSync] CK event: \(desc)")
                    self.lastSyncEvent = desc
                }
            }
        }
        eventObservers.append(importNotification)
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

                if let error {
                    print("[CloudSync] Account status error: \(error)")
                    self.lastSyncEvent = "Account error: \(error.localizedDescription)"
                    self.hasSyncError = true
                }

                if status == .available {
                    print("[CloudSync] iCloud account available — starting sync watch")
                    self.beginSyncWatch()
                } else {
                    print("[CloudSync] iCloud account status: \(status.rawValue)")
                    self.lastSyncEvent = "iCloud account not available (status: \(status.rawValue))"
                    self.isSyncing = false
                }
            }
        }

        // 5) Subscribe to iCloud account change notifications
        let accountChange = NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAccountChange()
            }
        }
        eventObservers.append(accountChange)
    }

    /// Handle iCloud account change (sign-in/sign-out)
    private func handleAccountChange() {
        ChartStorage.recordICloudUsage()

        if ChartStorage.isICloudAvailable {
            // Signed back in
            isSignedOutFromICloud = false
            lastSyncEvent = "iCloud account restored"
        } else if ChartStorage.wasUsingICloud {
            // Signed out
            isSignedOutFromICloud = true
            lastSyncEvent = "iCloud sign-out detected"
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
            print("[CloudSync] Sync watch timeout (\(maxSyncDuration)s)")
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

    // MARK: - Diagnostics

    /// Summary string for debugging sync state
    var diagnosticSummary: String {
        var lines: [String] = []
        lines.append("CloudKit enabled: \(ChartrixApp.isCloudKitEnabled)")
        lines.append("iCloud available: \(ChartStorage.isICloudAvailable)")
        lines.append("Account status: \(accountStatusName)")
        lines.append("Signed out: \(isSignedOutFromICloud)")
        lines.append("Syncing: \(isSyncing)")
        if !lastSyncEvent.isEmpty {
            lines.append("Last event: \(lastSyncEvent)")
        }
        return lines.joined(separator: "\n")
    }

    private var accountStatusName: String {
        switch accountStatus {
        case .available: return "available"
        case .noAccount: return "noAccount"
        case .restricted: return "restricted"
        case .couldNotDetermine: return "couldNotDetermine"
        case .temporarilyUnavailable: return "temporarilyUnavailable"
        @unknown default: return "unknown(\(accountStatus.rawValue))"
        }
    }
}
