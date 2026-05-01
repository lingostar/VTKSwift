import SwiftUI
import SwiftData
import CloudKit

@main
struct ChartrixApp: App {
    let modelContainer: ModelContainer
    /// Whether the container was created with CloudKit sync enabled
    static var isCloudKitEnabled: Bool = false

    init() {
        let schema = Schema([Chart.self, Study.self, Measurement.self, Note.self])

        // 1) Attempt CloudKit sync
        if let container = Self.makeCloudKitContainer(schema: schema) {
            modelContainer = container
            Self.isCloudKitEnabled = true
            print("[Chartrix] ModelContainer created with CloudKit sync")
        }
        // 2) Fall back to local-only if CloudKit fails
        else if let container = Self.makeLocalContainer(schema: schema) {
            modelContainer = container
            Self.isCloudKitEnabled = false
            print("[Chartrix] ⚠️ ModelContainer created (local only, CloudKit unavailable)")
        }
        // 3) On DB conflict: delete existing store and recreate with CloudKit
        else {
            Self.deleteExistingStore()
            do {
                let config = ModelConfiguration(
                    schema: schema,
                    cloudKitDatabase: .private("iCloud.codershigh.Chartrix")
                )
                modelContainer = try ModelContainer(for: schema, configurations: [config])
                Self.isCloudKitEnabled = true
                print("[Chartrix] ModelContainer created after store reset")
            } catch {
                fatalError("Failed to create ModelContainer after reset: \(error)")
            }
        }

        // Log CloudKit diagnostics on startup
        Self.logCloudKitDiagnostics()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }

    // MARK: - Container Factories

    private static func makeCloudKitContainer(schema: Schema) -> ModelContainer? {
        do {
            let config = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private("iCloud.codershigh.Chartrix")
            )
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            print("[Chartrix] ❌ CloudKit container failed: \(error)")
            print("[Chartrix] ❌ Error details: \(error.localizedDescription)")
            return nil
        }
    }

    private static func makeLocalContainer(schema: Schema) -> ModelContainer? {
        do {
            let config = ModelConfiguration(schema: schema)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            print("[Chartrix] ❌ Local container also failed: \(error)")
            return nil
        }
    }

    private static func deleteExistingStore() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let storeURL = appSupport.appendingPathComponent("default.store")
        for ext in ["", "-wal", "-shm"] {
            let path = ext.isEmpty ? storeURL.path : storeURL.path + ext
            try? FileManager.default.removeItem(atPath: path)
        }
        print("[Chartrix] Deleted existing SwiftData store for clean migration")
    }

    // MARK: - CloudKit Diagnostics

    private static func logCloudKitDiagnostics() {
        let container = CKContainer(identifier: "iCloud.codershigh.Chartrix")

        // Check account status
        container.accountStatus { status, error in
            let statusName: String
            switch status {
            case .available: statusName = "available ✓"
            case .noAccount: statusName = "noAccount ✗"
            case .restricted: statusName = "restricted ✗"
            case .couldNotDetermine: statusName = "couldNotDetermine"
            case .temporarilyUnavailable: statusName = "temporarilyUnavailable"
            @unknown default: statusName = "unknown(\(status.rawValue))"
            }
            print("[Chartrix-CK] Account status: \(statusName)")
            if let error {
                print("[Chartrix-CK] Account error: \(error)")
            }

            // If available, verify private database access
            if status == .available {
                Self.verifyCloudKitAccess(container: container)
            }
        }

        // Log iCloud ubiquity token
        if let token = FileManager.default.ubiquityIdentityToken {
            print("[Chartrix-CK] Ubiquity token: present (\(token))")
        } else {
            print("[Chartrix-CK] ⚠️ Ubiquity token: nil (iCloud Drive may be off)")
        }

        print("[Chartrix-CK] CloudKit container enabled: \(isCloudKitEnabled)")
    }

    /// Attempt a lightweight fetch on the private database to verify access
    private static func verifyCloudKitAccess(container: CKContainer) {
        let privateDB = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(
            zoneName: "com.apple.coredata.cloudkit.zone",
            ownerName: CKCurrentUserDefaultName
        )

        // Check if the SwiftData zone exists
        privateDB.fetch(withRecordZoneID: zoneID) { zone, error in
            if let zone {
                print("[Chartrix-CK] SwiftData zone found: \(zone.zoneID.zoneName) ✓")
            } else if let ckError = error as? CKError {
                print("[Chartrix-CK] ❌ Zone fetch error: \(ckError.code.rawValue) - \(ckError.localizedDescription)")
                if ckError.code == .zoneNotFound {
                    print("[Chartrix-CK] ❌ Zone not found — schema may not be deployed to Production")
                }
            } else if let error {
                print("[Chartrix-CK] ❌ Zone fetch error: \(error)")
            }
        }
    }
}
