import SwiftUI
import SwiftData

/// 차트 목록 — Chartrix 시작 화면 (iPhone NavigationStack용)
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
                    // iCloud 동기화 상태 표시
                    if syncMonitor.isSyncing {
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
            // 동기화 배너 (동기화 진행 중일 때)
            if syncMonitor.isSyncing {
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
        if syncMonitor.isSyncing {
            AnyView(
                VStack(spacing: 20) {
                    Spacer()

                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                        .symbolEffect(.pulse)

                    Text("iCloud 동기화 중...")
                        .font(.title3)
                        .fontWeight(.medium)

                    Text("다른 기기의 차트 데이터를 가져오고 있습니다.\n잠시만 기다려 주세요.")
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

    // MARK: - iCloud Sync Banner

    private var iCloudSyncBanner: some View {
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
        .padding(.vertical, 6)
        .listRowBackground(Color.accentColor.opacity(0.06))
    }

    // MARK: - Actions

    private func handleNewStudy(chart: Chart, study: Study, folderURL: URL) {
        // 1) Chart insert
        if chart.modelContext == nil {
            modelContext.insert(chart)
        }
        // 2) Study 명시적 insert + 관계 설정
        modelContext.insert(study)
        if chart.studies == nil { chart.studies = [] }
        chart.studies?.append(study)
        // 3) DICOM 파일 복사
        ChartStorage.importDICOM(study: study, chartAlias: chart.alias, from: folderURL)
        chart.updatedDate = Date()
        // 4) 명시적 저장
        try? modelContext.save()
        // 백그라운드에서 USDZ 미리 생성
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
