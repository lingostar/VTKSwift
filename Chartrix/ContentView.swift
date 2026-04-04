import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedChart: Chart?
    @State private var didMigrate = false
    @State private var isMigrating = false
    @StateObject private var syncMonitor = CloudSyncMonitor()

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
    }

    /// 마이그레이션 진행 중 화면
    private var migrationView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "icloud.and.arrow.up")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
                .symbolEffect(.pulse)

            Text("iCloud로 데이터 이동 중...")
                .font(.title3)
                .fontWeight(.medium)

            Text("로컬 데이터를 iCloud에 업로드하고 있습니다.\n잠시만 기다려 주세요.")
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
    /// 마이그레이션 완료 후에 UI가 파일에 접근합니다.
    private func migrateToICloudOnce() async {
        guard !didMigrate else { return }
        didMigrate = true

        // iCloud가 가용하고 로컬에 데이터가 있을 때만 마이그레이션 UI 표시
        let needsMigration = ChartStorage.isICloudAvailable && hasLocalCharts()

        if needsMigration {
            isMigrating = true
        }

        // 백그라운드에서 마이그레이션 실행 (완료까지 대기)
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                ChartStorage.migrateLocalToICloudIfNeeded()
                continuation.resume()
            }
        }

        // 마이그레이션 완료 → UI 전환
        if needsMigration {
            // 살짝 지연을 줘서 iCloud 파일 시스템이 반영할 시간 확보
            try? await Task.sleep(for: .milliseconds(500))
            isMigrating = false
        }
    }

    /// 로컬 Documents/Charts 에 데이터가 있는지 빠르게 확인
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
