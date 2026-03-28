import SwiftUI

// MARK: - Report State

/// Observable state for the report editor.
final class ReportState: ObservableObject {
    // Patient / Study info (pre-filled from case or DICOM viewer)
    @Published var patientName: String = "Anonymous"
    @Published var patientID: String = ""
    @Published var studyDate: String = ""
    @Published var modality: String = ""
    @Published var studyDescription: String = ""

    // Report content
    @Published var findings: String = ""
    @Published var impression: String = ""
    @Published var recommendation: String = ""

    // Measurements from MeasurementState
    @Published var measurements: [MeasurementRecord] = []

    // Export state
    @Published var isExporting = false
    @Published var exportSuccess = false
    @Published var exportError: String?
    @Published var exportedFileURL: URL?

    /// Whether any content has been entered.
    var hasContent: Bool {
        !findings.isEmpty || !impression.isEmpty || !recommendation.isEmpty || !measurements.isEmpty
    }

    /// Reset all fields.
    func reset() {
        findings = ""
        impression = ""
        recommendation = ""
        measurements = []
        exportSuccess = false
        exportError = nil
        exportedFileURL = nil
    }

    /// Populate from a MeasurementState.
    func importMeasurements(from measurementState: MeasurementState) {
        self.measurements = measurementState.measurements
    }
}

// MARK: - Report Editor View

/// Form UI for authoring structured diagnostic reports.
/// Supports findings, impression, recommendation with auto-inserted measurements.
/// Exports as DICOM SR or plain text.
struct ReportEditorView: View {
    @StateObject private var reportState = ReportState()
    @State private var showExportOptions = false
    @State private var showPreview = false
    @State private var showFilePicker = false

    /// Optional: injected measurement state from DICOM viewer.
    var measurementState: MeasurementState?

    var body: some View {
        Form {
            disclaimerSection
            patientInfoSection
            measurementsSection
            findingsSection
            impressionSection
            recommendationSection
            actionsSection
        }
        .navigationTitle("보고서 작성")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    showPreview = true
                } label: {
                    Label("미리보기", systemImage: "eye")
                }
                .disabled(!reportState.hasContent)

                Button {
                    showExportOptions = true
                } label: {
                    Label("내보내기", systemImage: "square.and.arrow.up")
                }
                .disabled(!reportState.hasContent)
            }
        }
        .sheet(isPresented: $showPreview) {
            ReportPreviewSheet(reportState: reportState)
        }
        .sheet(isPresented: $showExportOptions) {
            ReportExportSheet(reportState: reportState)
        }
        .onAppear {
            if let ms = measurementState {
                reportState.importMeasurements(from: ms)
            }
        }
    }
}

// MARK: - Report Sections

private extension ReportEditorView {

    var disclaimerSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("참고용 보고서 도구")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("이 보고서 도구는 참고용이며, 정식 판독 보고서는 병원 EMR에서 작성하십시오.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    var patientInfoSection: some View {
        Section("검사 정보") {
            HStack {
                Text("환자명")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
                TextField("Anonymous", text: $reportState.patientName)
                    .font(.caption)
            }

            HStack {
                Text("환자 ID")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
                TextField("ID", text: $reportState.patientID)
                    .font(.caption)
            }

            HStack {
                Text("검사일")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
                TextField("YYYYMMDD", text: $reportState.studyDate)
                    .font(.caption)
            }

            HStack {
                Text("모달리티")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
                TextField("CT, MR, CR...", text: $reportState.modality)
                    .font(.caption)
            }

            HStack {
                Text("검사 설명")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
                TextField("Study Description", text: $reportState.studyDescription)
                    .font(.caption)
            }
        }
    }

    var measurementsSection: some View {
        Section("측정값") {
            if reportState.measurements.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "ruler")
                        .foregroundStyle(.secondary)
                    Text("측정값 없음 — DICOM 뷰어에서 측정 후 자동 삽입됩니다")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                ForEach(reportState.measurements) { m in
                    HStack(spacing: 8) {
                        Image(systemName: m.type == .distance ? "ruler" : "angle")
                            .font(.caption2)
                            .foregroundStyle(m.type == .distance ? .yellow : .cyan)
                        Text(m.type == .distance ? "거리" : "각도")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(m.displayString)
                            .font(.caption)
                            .monospacedDigit()
                            .fontWeight(.medium)
                    }
                }

                Button {
                    insertMeasurementsToFindings()
                } label: {
                    Label("소견에 측정값 삽입", systemImage: "text.insert")
                        .font(.caption)
                }
            }
        }
    }

    var findingsSection: some View {
        Section("소견 (Findings)") {
            TextEditor(text: $reportState.findings)
                .font(.body)
                .frame(minHeight: 100)
                .overlay(alignment: .topLeading) {
                    if reportState.findings.isEmpty {
                        Text("소견을 입력하세요...")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    var impressionSection: some View {
        Section("인상 (Impression)") {
            TextEditor(text: $reportState.impression)
                .font(.body)
                .frame(minHeight: 80)
                .overlay(alignment: .topLeading) {
                    if reportState.impression.isEmpty {
                        Text("인상을 입력하세요...")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    var recommendationSection: some View {
        Section("권고 (Recommendation)") {
            TextEditor(text: $reportState.recommendation)
                .font(.body)
                .frame(minHeight: 60)
                .overlay(alignment: .topLeading) {
                    if reportState.recommendation.isEmpty {
                        Text("권고 사항을 입력하세요...")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    var actionsSection: some View {
        Section {
            if reportState.exportSuccess, let url = reportState.exportedFileURL {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text("내보내기 완료")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(url.lastPathComponent)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let error = reportState.exportError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Button(role: .destructive) {
                reportState.reset()
            } label: {
                Label("초기화", systemImage: "trash")
                    .font(.caption)
            }
            .disabled(!reportState.hasContent)
        }
    }

    // MARK: - Helpers

    func insertMeasurementsToFindings() {
        var lines: [String] = []
        for m in reportState.measurements {
            let typeLabel = m.type == .distance ? "거리" : "각도"
            lines.append("- \(typeLabel): \(m.displayString)")
        }
        let measurementText = lines.joined(separator: "\n")

        if reportState.findings.isEmpty {
            reportState.findings = "측정값:\n\(measurementText)"
        } else {
            reportState.findings += "\n\n측정값:\n\(measurementText)"
        }
    }
}

// MARK: - Report Preview Sheet

/// Read-only preview of the report content.
struct ReportPreviewSheet: View {
    @ObservedObject var reportState: ReportState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    VStack(alignment: .center, spacing: 4) {
                        Text("DIAGNOSTIC IMAGING REPORT")
                            .font(.headline)
                        Text("(참고용 — Reference Only)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()

                    // Patient info
                    Group {
                        previewRow("환자명", value: reportState.patientName)
                        previewRow("환자 ID", value: reportState.patientID.isEmpty ? "—" : reportState.patientID)
                        previewRow("검사일", value: reportState.studyDate.isEmpty ? "—" : reportState.studyDate)
                        previewRow("모달리티", value: reportState.modality.isEmpty ? "—" : reportState.modality)
                        if !reportState.studyDescription.isEmpty {
                            previewRow("검사 설명", value: reportState.studyDescription)
                        }
                    }

                    Divider()

                    // Measurements
                    if !reportState.measurements.isEmpty {
                        previewSection("측정값 (Measurements)") {
                            ForEach(reportState.measurements) { m in
                                HStack {
                                    Text(m.type == .distance ? "거리" : "각도")
                                        .font(.caption)
                                    Spacer()
                                    Text(m.displayString)
                                        .font(.caption)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }

                    // Findings
                    previewSection("소견 (Findings)") {
                        Text(reportState.findings.isEmpty ? "(없음)" : reportState.findings)
                            .font(.body)
                    }

                    // Impression
                    previewSection("인상 (Impression)") {
                        Text(reportState.impression.isEmpty ? "(없음)" : reportState.impression)
                            .font(.body)
                    }

                    // Recommendation
                    previewSection("권고 (Recommendation)") {
                        Text(reportState.recommendation.isEmpty ? "(없음)" : reportState.recommendation)
                            .font(.body)
                    }

                    Divider()

                    // Footer
                    VStack(alignment: .leading, spacing: 4) {
                        Text("이 보고서는 참고/열람 목적으로만 사용되며, 공식 의무 기록이 아닙니다.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Generated by VTKSwift SR Engine")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding()
            }
            .navigationTitle("보고서 미리보기")
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

    private func previewRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.caption)
        }
    }

    private func previewSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.accentColor)
            content()
        }
    }
}

// MARK: - Report Export Sheet

/// Export options: DICOM SR or plain text. Saves a ReportRecord to SwiftData.
struct ReportExportSheet: View {
    @ObservedObject var reportState: ReportState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var exportFormat: ReportExportFormat = .dicomSR
    @State private var isExporting = false
    @State private var exportResult: String?
    @State private var reportTitle: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("보고서 제목") {
                    TextField("보고서 제목 (선택)", text: $reportTitle)
                        .font(.body)
                }

                Section("내보내기 형식") {
                    Picker("형식", selection: $exportFormat) {
                        ForEach(ReportExportFormat.allCases) { format in
                            Label(format.title, systemImage: format.icon)
                                .tag(format)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(exportFormat.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        exportReport()
                    } label: {
                        HStack {
                            Spacer()
                            if isExporting {
                                ProgressView()
                                    .controlSize(.small)
                                Text("내보내는 중...")
                            } else {
                                Label("내보내기", systemImage: "square.and.arrow.up")
                            }
                            Spacer()
                        }
                        .font(.body)
                        .fontWeight(.medium)
                    }
                    .disabled(isExporting)
                }

                if let result = exportResult {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(result)
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("보고서 내보내기")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    private func exportReport() {
        isExporting = true
        exportResult = nil

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let reportsDir = documentsDir.appendingPathComponent("VTKSwift_Reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())

        switch exportFormat {
        case .dicomSR:
            let filename = "SR_\(timestamp).dcm"
            let outputURL = reportsDir.appendingPathComponent(filename)

            do {
                try SRExportHelper.exportToFile(
                    url: outputURL,
                    patientName: reportState.patientName,
                    findings: reportState.findings,
                    impression: reportState.impression,
                    recommendation: reportState.recommendation,
                    measurements: reportState.measurements
                )
                reportState.exportedFileURL = outputURL
                reportState.exportSuccess = true
                exportResult = "DICOM SR 저장 완료: \(filename)"
                saveReportRecord(format: "dicomSR", relativePath: "VTKSwift_Reports/\(filename)")
            } catch {
                reportState.exportError = error.localizedDescription
                exportResult = nil
            }

        case .plainText:
            let filename = "Report_\(timestamp).txt"
            let outputURL = reportsDir.appendingPathComponent(filename)

            let text = buildPlainTextReport()
            do {
                try text.write(to: outputURL, atomically: true, encoding: .utf8)
                reportState.exportedFileURL = outputURL
                reportState.exportSuccess = true
                exportResult = "텍스트 보고서 저장 완료: \(filename)"
                saveReportRecord(format: "plainText", relativePath: "VTKSwift_Reports/\(filename)")
            } catch {
                reportState.exportError = error.localizedDescription
                exportResult = nil
            }
        }

        isExporting = false
    }

    private func saveReportRecord(format: String, relativePath: String) {
        let record = ReportRecord()
        record.title = reportTitle.isEmpty ? "\(reportState.modality.isEmpty ? "SR" : reportState.modality) Report" : reportTitle
        record.patientName = reportState.patientName
        record.patientID = reportState.patientID
        record.studyDate = reportState.studyDate
        record.modality = reportState.modality
        record.studyDescription = reportState.studyDescription
        record.findings = reportState.findings
        record.impression = reportState.impression
        record.recommendation = reportState.recommendation
        record.exportFormat = format
        record.exportedFilePath = relativePath
        record.measurementCount = reportState.measurements.count

        // Build measurement summary
        var summaryLines: [String] = []
        for m in reportState.measurements {
            let typeLabel = m.type == .distance ? "거리" : "각도"
            summaryLines.append("\(typeLabel): \(m.displayString)")
        }
        record.measurementSummary = summaryLines.joined(separator: "\n")

        modelContext.insert(record)
    }

    private func buildPlainTextReport() -> String {
        var lines: [String] = []
        lines.append("=" * 60)
        lines.append("DIAGNOSTIC IMAGING REPORT (Reference Only)")
        lines.append("=" * 60)
        lines.append("")
        lines.append("환자명: \(reportState.patientName)")
        if !reportState.patientID.isEmpty {
            lines.append("환자 ID: \(reportState.patientID)")
        }
        if !reportState.studyDate.isEmpty {
            lines.append("검사일: \(reportState.studyDate)")
        }
        if !reportState.modality.isEmpty {
            lines.append("모달리티: \(reportState.modality)")
        }
        if !reportState.studyDescription.isEmpty {
            lines.append("검사 설명: \(reportState.studyDescription)")
        }
        lines.append("")

        if !reportState.measurements.isEmpty {
            lines.append("-" * 40)
            lines.append("[측정값]")
            for m in reportState.measurements {
                let typeLabel = m.type == .distance ? "거리" : "각도"
                lines.append("  \(typeLabel): \(m.displayString)")
            }
            lines.append("")
        }

        lines.append("-" * 40)
        lines.append("[소견 / Findings]")
        lines.append(reportState.findings.isEmpty ? "(없음)" : reportState.findings)
        lines.append("")

        lines.append("-" * 40)
        lines.append("[인상 / Impression]")
        lines.append(reportState.impression.isEmpty ? "(없음)" : reportState.impression)
        lines.append("")

        lines.append("-" * 40)
        lines.append("[권고 / Recommendation]")
        lines.append(reportState.recommendation.isEmpty ? "(없음)" : reportState.recommendation)
        lines.append("")

        lines.append("=" * 60)
        lines.append("이 보고서는 참고/열람 목적으로만 사용됩니다.")
        lines.append("Generated by VTKSwift SR Engine")
        lines.append("Date: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))")

        return lines.joined(separator: "\n")
    }
}

// MARK: - String Repeat Helper

private extension String {
    static func * (lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}

// MARK: - Report Export Format

enum ReportExportFormat: String, CaseIterable, Identifiable {
    case dicomSR = "DICOM SR"
    case plainText = "텍스트"

    var id: String { rawValue }

    var title: String { rawValue }

    var icon: String {
        switch self {
        case .dicomSR: return "doc.badge.gearshape"
        case .plainText: return "doc.text"
        }
    }

    var description: String {
        switch self {
        case .dicomSR:
            return "DICOM Part 10 Structured Report (.dcm) — PACS 시스템과 호환"
        case .plainText:
            return "일반 텍스트 파일 (.txt) — 범용 열람"
        }
    }
}
