import SwiftUI
import SwiftData

/// Chart list — Chartrix home screen (for iPhone NavigationStack)
struct ChartListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var syncMonitor: CloudSyncMonitor
    @Query(sort: \Chart.updatedDate, order: .reverse) private var charts: [Chart]

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
        Group {
            if charts.isEmpty {
                emptyState
            } else {
                chartList
            }
        }
        .navigationTitle("Chart")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    // iCloud status indicator
                    if syncMonitor.isSignedOutFromICloud {
                        Image(systemName: "icloud.slash")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else if !ChartrixApp.isCloudKitEnabled {
                        Image(systemName: "exclamationmark.icloud")
                            .font(.caption)
                            .foregroundColor(.red)
                            .help("CloudKit sync is not active")
                    } else if syncMonitor.isSyncing {
                        iCloudSyncIndicator
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
                handleNewStudy(chart: chart, study: study, folderURL: folderURL)
            }
        }
        .onChange(of: charts.count) { _, newCount in
            if newCount > 0 {
                syncMonitor.notifyDataLoaded()
            }
        }
    }

    // MARK: - iCloud Sync Indicator

    private var iCloudSyncIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.caption)
                .foregroundColor(.secondary)
                .symbolEffect(.pulse)
        }
    }

    // MARK: - Chart List

    private var chartList: some View {
        List {
            // iCloud signed-out warning banner
            if syncMonitor.isSignedOutFromICloud {
                iCloudSignedOutBanner
            }
            // Sync banner (shown while syncing)
            else if syncMonitor.isSyncing {
                iCloudSyncBanner
            }

            ForEach(filteredCharts) { chart in
                NavigationLink(value: chart) {
                    ChartRowView(chart: chart)
                }
            }
            .onDelete(perform: deleteCharts)
        }
        .listStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        if syncMonitor.isSignedOutFromICloud {
            AnyView(iCloudSignedOutFullScreen)
        } else if syncMonitor.isSyncing {
            AnyView(
                VStack(spacing: 20) {
                    Spacer()

                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                        .symbolEffect(.pulse)

                    Text("Syncing with iCloud...")
                        .font(.title3)
                        .fontWeight(.medium)

                    Text("Fetching chart data from your other devices.\nPlease wait a moment.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    ProgressView()
                        .padding(.top, 8)

                    Spacer()
                    Spacer()
                }
                .padding()
            )
        } else {
            AnyView(
                ContentUnavailableView {
                    Label("No Charts", systemImage: "chart.bar.doc.horizontal")
                } description: {
                    if ChartStorage.isICloudAvailable {
                        Text("Tap + to create your first patient chart.\niCloud sync is enabled.")
                    } else {
                        Text("Tap + to create your first patient chart.")
                    }
                } actions: {
                    Button("New Chart") {
                        showNewChart = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            )
        }
    }

    // MARK: - iCloud Signed Out UI

    /// Full screen — no charts and iCloud signed out
    private var iCloudSignedOutFullScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "icloud.slash")
                .font(.system(size: 56))
                .foregroundColor(.orange)

            Text("iCloud Not Available")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                Text("Don't worry — your data is safely stored in iCloud.")
                    .font(.body)
                    .fontWeight(.medium)

                Text("Sign in to your iCloud account to access\nyour charts and DICOM studies.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            openSettingsButton

            Spacer()

            VStack(spacing: 8) {
                Divider()
                Text("You can also create new charts locally.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("New Chart") {
                    showNewChart = true
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 24)
        }
        .padding()
    }

    /// List banner — charts visible but iCloud signed out
    private var iCloudSignedOutBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            openSettingsButton
                .font(.caption)
        }
        .padding(.vertical, 8)
        .listRowBackground(Color.orange.opacity(0.08))
    }

    /// Open Settings button
    private var openSettingsButton: some View {
        #if os(iOS)
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            Label("Open Settings", systemImage: "gear")
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        #else
        Button {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane")!)
        } label: {
            Label("Open System Settings", systemImage: "gear")
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        #endif
    }

    // MARK: - iCloud Sync Banner

    private var iCloudSyncBanner: some View {
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
        .padding(.vertical, 6)
        .listRowBackground(Color.accentColor.opacity(0.06))
    }

    // MARK: - Actions

    private func handleNewStudy(chart: Chart, study: Study, folderURL: URL) {
        // 1) Chart insert
        if chart.modelContext == nil {
            modelContext.insert(chart)
        }
        // 2) Explicitly insert Study + set up relationship
        modelContext.insert(study)
        if chart.studies == nil { chart.studies = [] }
        chart.studies?.append(study)
        // 3) Copy DICOM files
        ChartStorage.importDICOM(study: study, chartAlias: chart.alias, from: folderURL)
        chart.updatedDate = Date()
        // 4) Explicit save
        try? modelContext.save()
        // Pre-generate USDZ in background
        ChartStorage.generateUSDZInBackground(study: study, chartAlias: chart.alias)
    }

    private func deleteCharts(at offsets: IndexSet) {
        for index in offsets {
            let chart = filteredCharts[index]
            ChartStorage.deleteFiles(for: chart)
            modelContext.delete(chart)
        }
        try? modelContext.save()
    }
}
