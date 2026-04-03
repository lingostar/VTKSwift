import SwiftUI
import SwiftData

@main
struct ChartrixApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([Chart.self, Study.self, Measurement.self, Note.self])
            let config = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private("iCloud.com.codershigh.Chartrix")
            )
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
