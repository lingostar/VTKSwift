import SwiftUI
import SwiftData

// MARK: - Report List View

/// Displays saved report history with search, filter, and re-export capabilities.
struct ReportListView: View {
    @Query(sort: \ReportRecord.createdDate, order: .reverse)
    private var reports: [ReportRecord]

    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var selectedReport: ReportRecord?
    @State private var showDeleteConfirm = false
    @State private var reportToDelete: ReportRecord?

    var body: some View {
        List(selection: $selectedReport) {
            if filteredReports.isEmpty {
                emptyState
            } else {
                ForEach(filteredReports) { report in
                    ReportRowView(report: report)
                        .tag(report)
                        .contextMenu {
                            reportContextMenu(for: report)
                        }
                }
                .onDelete(perform: deleteReports)
            }
        }
        .searchable(text: $searchText, prompt: "보고서 검색")
        .navigationTitle("보고서 이력")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text("\(reports.count)건")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(item: $selectedReport) { report in
            ReportDetailSheet(report: report)
        }
        .alert("보고서 삭제", isPresented: $showDeleteConfirm) {
            Button("삭제", role: .destructive) {
                if let report = reportToDelete {
                    deleteReport(report)
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 보고서를 삭제하시겠습니까? 내보낸 파일도 함께 삭제됩니다.")
        }
    }

    private var filteredReports: [ReportRecord] {
        if searchText.isEmpty { return reports }
        let query = searchText.lowercased()
        return reports.filter {
            $0.title.lowercased().contains(query) ||
            $0.patientName.lowercased().contains(query) ||
            $0.modality.lowercased().contains(query) ||
            $0.findings.lowercased().contains(query) ||
            $0.linkedCaseAlias.lowercased().contains(query)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("저장된 보고서가 없습니다")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("보고서 작성 탭에서 보고서를 작성하고 내보내면\n여기에 이력이 표시됩니다.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private func reportContextMenu(for report: ReportRecord) -> some View {
        Button {
            selectedReport = report
        } label: {
            Label("상세 보기", systemImage: "eye")
        }

        if report.exportedFileExists {
            #if os(macOS)
            Button {
                if let url = report.exportedFileURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } label: {
                Label("Finder에서 보기", systemImage: "folder")
            }
            #endif
        }

        Divider()

        Button(role: .destructive) {
            reportToDelete = report
            showDeleteConfirm = true
        } label: {
            Label("삭제", systemImage: "trash")
        }
    }

    private func deleteReports(at offsets: IndexSet) {
        for index in offsets {
            deleteReport(filteredReports[index])
        }
    }

    private func deleteReport(_ report: ReportRecord) {
        // Delete exported file if exists
        if let url = report.exportedFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        modelContext.delete(report)
    }
}

// MARK: - Report Row View

struct ReportRowView: View {
    let report: ReportRecord

    var body: some View {
        HStack(spacing: 12) {
            // Format icon
            Image(systemName: report.exportFormat == "dicomSR" ? "doc.badge.gearshape" : "doc.text")
                .font(.title2)
                .foregroundStyle(report.exportFormat == "dicomSR" ? .blue : .gray)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(report.title.isEmpty ? "Untitled Report" : report.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if !report.linkedCaseAlias.isEmpty {
                        Text(report.linkedCaseAlias)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                }

                Text(report.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !report.findings.isEmpty {
                    Text(report.findings)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Status indicators
            VStack(alignment: .trailing, spacing: 2) {
                if report.measurementCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "ruler")
                            .font(.caption2)
                        Text("\(report.measurementCount)")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }

                if report.exportedFileExists {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else if !report.exportedFilePath.isEmpty {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Report Detail Sheet

struct ReportDetailSheet: View {
    let report: ReportRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    VStack(alignment: .center, spacing: 4) {
                        Text(report.title.isEmpty ? "DIAGNOSTIC IMAGING REPORT" : report.title)
                            .font(.headline)
                        Text("(참고용 — Reference Only)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("v\(report.version) · \(formattedDate(report.createdDate))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()

                    // Patient Info
                    Group {
                        detailRow("환자명", value: report.patientName)
                        if !report.patientID.isEmpty {
                            detailRow("환자 ID", value: report.patientID)
                        }
                        if !report.studyDate.isEmpty {
                            detailRow("검사일", value: report.studyDate)
                        }
                        if !report.modality.isEmpty {
                            detailRow("모달리티", value: report.modality)
                        }
                        if !report.studyDescription.isEmpty {
                            detailRow("검사 설명", value: report.studyDescription)
                        }
                    }

                    // Measurements
                    if !report.measurementSummary.isEmpty {
                        Divider()
                        sectionHeader("측정값")
                        Text(report.measurementSummary)
                            .font(.caption)
                            .monospacedDigit()
                    }

                    Divider()

                    // Findings
                    sectionHeader("소견 (Findings)")
                    Text(report.findings.isEmpty ? "(없음)" : report.findings)
                        .font(.body)

                    // Impression
                    sectionHeader("인상 (Impression)")
                    Text(report.impression.isEmpty ? "(없음)" : report.impression)
                        .font(.body)

                    // Recommendation
                    sectionHeader("권고 (Recommendation)")
                    Text(report.recommendation.isEmpty ? "(없음)" : report.recommendation)
                        .font(.body)

                    Divider()

                    // File info
                    if !report.exportedFilePath.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: report.exportedFileExists ? "checkmark.circle" : "xmark.circle")
                                .foregroundStyle(report.exportedFileExists ? .green : .red)
                            VStack(alignment: .leading) {
                                Text(report.exportedFilePath)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(report.exportedFileExists ? "파일 존재 확인됨" : "파일을 찾을 수 없음")
                                    .font(.caption2)
                                    .foregroundColor(report.exportedFileExists ? .secondary : .red)
                            }
                        }
                    }

                    // Disclaimer
                    Text("이 보고서는 참고/열람 목적으로만 사용되며, 공식 의무 기록이 아닙니다.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("보고서 상세")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.caption)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.accentColor)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
