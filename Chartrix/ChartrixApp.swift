import SwiftUI
import SwiftData

@main
struct ChartrixApp: App {
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([Chart.self, Study.self, Measurement.self, Note.self])

        // 1) CloudKit 동기화 시도
        if let container = Self.makeCloudKitContainer(schema: schema) {
            modelContainer = container
            print("[Chartrix] ModelContainer created with CloudKit sync")
        }
        // 2) CloudKit 실패 시 로컬 전용으로 폴백
        else if let container = Self.makeLocalContainer(schema: schema) {
            modelContainer = container
            print("[Chartrix] ModelContainer created (local only, CloudKit unavailable)")
        }
        // 3) 기존 DB 충돌 시: 기존 store 삭제 후 CloudKit으로 재생성
        else {
            Self.deleteExistingStore()
            do {
                let config = ModelConfiguration(
                    schema: schema,
                    cloudKitDatabase: .private("iCloud.codershigh.Chartrix")
                )
                modelContainer = try ModelContainer(for: schema, configurations: [config])
                print("[Chartrix] ModelContainer created after store reset")
            } catch {
                fatalError("Failed to create ModelContainer after reset: \(error)")
            }
        }
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
            print("[Chartrix] CloudKit container failed: \(error)")
            return nil
        }
    }

    private static func makeLocalContainer(schema: Schema) -> ModelContainer? {
        do {
            let config = ModelConfiguration(schema: schema)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            print("[Chartrix] Local container also failed: \(error)")
            return nil
        }
    }

    private static func deleteExistingStore() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let storeURL = appSupport.appendingPathComponent("default.store")
        for ext in ["", "-wal", "-shm"] {
            let url = storeURL.appendingPathExtension(ext.isEmpty ? "" : String(ext.dropFirst()))
            let path = ext.isEmpty ? storeURL.path : storeURL.path + ext
            try? FileManager.default.removeItem(atPath: path)
        }
        print("[Chartrix] Deleted existing SwiftData store for clean migration")
    }
}
