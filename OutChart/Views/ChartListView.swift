import SwiftUI
import SwiftData

/// 차트 목록 — OutChart 시작 화면 (iPhone NavigationStack용)
struct ChartListView: View {
    @Environment(\.modelContext) private var modelContext
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
                Button {
                    showNewChart = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search charts")
        .sheet(isPresented: $showNewChart) {
            NewChartSheet { chart, study, folderURL in
                handleNewStudy(chart: chart, study: study, folderURL: folderURL)
            }
        }
    }

    // MARK: - Chart List

    private var chartList: some View {
        List {
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
        ContentUnavailableView {
            Label("No Charts", systemImage: "chart.bar.doc.horizontal")
        } description: {
            Text("Tap + to create your first patient chart.")
        } actions: {
            Button("New Chart") {
                showNewChart = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func handleNewStudy(chart: Chart, study: Study, folderURL: URL) {
        // 1) Chart insert
        if chart.modelContext == nil {
            modelContext.insert(chart)
        }
        // 2) Study 명시적 insert + 관계 설정
        modelContext.insert(study)
        chart.studies.append(study)
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
