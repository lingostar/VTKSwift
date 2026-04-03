import SwiftUI
import SwiftData

@main
struct ChartrixApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Chart.self, Study.self, Measurement.self, Note.self])
    }
}
