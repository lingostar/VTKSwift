import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedChart: Chart?
    @State private var didMigrate = false
    @StateObject private var syncMonitor = CloudSyncMonitor()

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        Group {
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
        .onAppear { migrateToICloudOnce() }
        .environmentObject(syncMonitor)
    }

    // MARK: - iPad / Mac: NavigationSplitView

    private var splitView: some View {
        NavigationSplitView {
            ChartSplitListView(selectedChart: $selectedChart)
        } detail: {
            if let chart = selectedChart {
                ChartDetailView(chart: chart)
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

    /// 앱 첫 실행 시 로컬 데이터를 iCloud로 마이그레이션
    private func migrateToICloudOnce() {
        guard !didMigrate else { return }
        didMigrate = true
        DispatchQueue.global(qos: .utility).async {
            ChartStorage.migrateLocalToICloudIfNeeded()
        }
    }
}

// MARK: - Split List (selection binding 용)

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
            // 동기화 배너
            if syncMonitor.isSyncing {
                HStack(spacing: 10) {
                    Image(systemName: "icloud.and.arrow.down")
                        .foregroundColor(.accentColor)
                        .symbolEffect(.pulse)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud 동기화 중")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("새로운 데이터가 도착할 수 있습니다")
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
                    if syncMonitor.isSyncing {
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
                // 2) Study를 명시적으로 insert 후 관계 설정
                modelContext.insert(study)
                if chart.studies == nil { chart.studies = [] }
                chart.studies?.append(study)
                // 3) DICOM 파일 복사
                ChartStorage.importDICOM(study: study, chartAlias: chart.alias, from: folderURL)
                chart.updatedDate = Date()
                // 4) 명시적 저장
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
