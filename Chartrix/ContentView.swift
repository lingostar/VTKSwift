import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedChart: Chart?
    @State private var didMigrate = false
    @State private var isMigrating = false
    @StateObject private var syncMonitor = CloudSyncMonitor()
    @StateObject private var fullScreen = FullScreenState()

    /// NavigationSplitView column visibility. Driven by `fullScreen.isFullScreen`
    /// so the sidebar is hidden in fullscreen for an immersive viewer.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        Group {
            if isMigrating {
                migrationView
            } else {
                #if os(macOS)
                splitView
                #else
                if horizontalSizeClass == .regular {
                    splitView
                } else {
                    stackView
                }
                #endif
            }
        }
        .task { await migrateToICloudOnce() }
        .environmentObject(syncMonitor)
        .environmentObject(fullScreen)
        .onChange(of: fullScreen.isFullScreen) { _, value in
            withAnimation(.easeInOut(duration: 0.2)) {
                columnVisibility = value ? .detailOnly : .all
            }
        }
    }

    /// Migration in-progress screen
    private var migrationView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "icloud.and.arrow.up")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
                .symbolEffect(.pulse)

            Text("Moving data to iCloud...")
                .font(.title3)
                .fontWeight(.medium)

            Text("Uploading local data to iCloud.\nPlease wait a moment.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            ProgressView()
                .padding(.top, 8)

            Spacer()
            Spacer()
        }
        .padding()
    }

    // MARK: - iPad / Mac: NavigationSplitView

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ChartSplitListView(selectedChart: $selectedChart)
        } detail: {
            if let chart = selectedChart {
                ChartDetailView(chart: chart)
                    .id(chart.id)
            } else {
                ContentUnavailableView(
                    "Select a Chart",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("Choose a patient chart from the list.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - iPhone: NavigationStack

    private var stackView: some View {
        NavigationStack {
            ChartListView()
                .navigationDestination(for: Chart.self) { chart in
                    ChartDetailView(chart: chart)
                }
        }
    }

    /// Handle migration on first app launch
    ///
    /// - iCloud available: Local → iCloud migration
    /// - iCloud signed out: Attempt reverse iCloud → Local migration
    /// - UI accesses files only after migration completes.
    private func migrateToICloudOnce() async {
        guard !didMigrate else { return }
        didMigrate = true

        if ChartStorage.isICloudAvailable {
            // iCloud available — forward migration
            let needsMigration = hasLocalCharts()

            if needsMigration {
                isMigrating = true
            }

            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    ChartStorage.migrateLocalToICloudIfNeeded()
                    ChartStorage.recordICloudUsage()
                    continuation.resume()
                }
            }

            if needsMigration {
                try? await Task.sleep(for: .milliseconds(500))
                isMigrating = false
            }
        } else if ChartStorage.needsICloudReSignIn {
            // iCloud signed out — attempt reverse migration
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    ChartStorage.migrateICloudToLocalIfNeeded()
                    continuation.resume()
                }
            }
        }
    }

    /// Quick check whether local Documents/Charts contains data
    private func hasLocalCharts() -> Bool {
        let localDocs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let localCharts = localDocs.appendingPathComponent("Charts", isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: localCharts, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return false }
        return !contents.isEmpty
    }
}

// MARK: - Split List (for selection binding)

private struct ChartSplitListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var syncMonitor: CloudSyncMonitor
    @Query(sort: \Chart.updatedDate, order: .reverse) private var charts: [Chart]
    @Binding var selectedChart: Chart?

    @State private var showNewChart = false
    @State private var searchText = ""

    var filteredCharts: [Chart] {
        if searchText.isEmpty { return charts }
        return charts.filter {
            $0.alias.localizedCaseInsensitiveContains(searchText) ||
            $0.studySummary.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(selection: $selectedChart) {
            // iCloud signed-out warning
            if syncMonitor.isSignedOutFromICloud {
                HStack(spacing: 10) {
                    Image(systemName: "icloud.slash")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud Not Available")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("Don't worry — your data is safely stored in iCloud. Sign in to access all your studies.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.orange.opacity(0.08))
            }
            // Sync banner
            else if syncMonitor.isSyncing {
                HStack(spacing: 10) {
                    Image(systemName: "icloud.and.arrow.down")
                        .foregroundColor(.accentColor)
                        .symbolEffect(.pulse)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Syncing with iCloud")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("New data may be arriving")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.accentColor.opacity(0.06))
            }

            ForEach(filteredCharts) { chart in
                ChartRowView(chart: chart)
                    .tag(chart)
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteChart(chart)
                        } label: {
                            Label("Delete Patient", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Chart")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    if syncMonitor.isSignedOutFromICloud {
                        Image(systemName: "icloud.slash")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else if syncMonitor.isSyncing {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .symbolEffect(.pulse)
                    }
                    Button {
                        showNewChart = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search charts")
        .sheet(isPresented: $showNewChart) {
            NewChartSheet { chart, study, folderURL in
                // 1) Chart insert
                if chart.modelContext == nil {
                    modelContext.insert(chart)
                }
                // 2) Explicitly insert Study and set up relationship
                modelContext.insert(study)
                if chart.studies == nil { chart.studies = [] }
                chart.studies?.append(study)
                // 3) Copy DICOM files
                ChartStorage.importDICOM(study: study, chartAlias: chart.alias, from: folderURL)
                chart.updatedDate = Date()
                // 4) Explicit save
                try? modelContext.save()
                selectedChart = chart
                ChartStorage.generateUSDZInBackground(study: study, chartAlias: chart.alias)
            }
        }
    }

    private func deleteChart(_ chart: Chart) {
        if selectedChart?.id == chart.id {
            selectedChart = nil
        }
        ChartStorage.deleteFiles(for: chart)
        modelContext.delete(chart)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Chart.self, Study.self, Measurement.self, Note.self], inMemory: true)
        .environmentObject(CloudSyncMonitor())
}
