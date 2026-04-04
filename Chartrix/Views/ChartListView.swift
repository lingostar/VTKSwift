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
                    // iCloud 상태 표시
                    if syncMonitor.isSignedOutFromICloud {
                        Image(systemName: "icloud.slash")
                            .font(.caption)
                            .foregroundColor(.orange)
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
            // iCloud 로그아웃 경고 배너
            if syncMonitor.isSignedOutFromICloud {
                iCloudSignedOutBanner
            }
            // 동기화 배너 (동기화 진행 중일 때)
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

    // MARK: - iCloud Signed Out UI

    /// 전체 화면 — 차트가 없고 iCloud 로그아웃 상태
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

    /// 리스트 배너 — 차트는 보이지만 iCloud 로그아웃 상태
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

    /// 설정 열기 버튼
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
