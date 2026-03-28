import SwiftUI
import SwiftData

// MARK: - Case Action

/// Actions available from a case detail view.
enum CaseAction: Identifiable {
    case dicomViewer(URL)
    case volumeViewer(URL)
    case exportSheet(URL)

    var id: String {
        switch self {
        case .dicomViewer(let url): return "dicom-\(url.path)"
        case .volumeViewer(let url): return "volume-\(url.path)"
        case .exportSheet(let url): return "export-\(url.path)"
        }
    }
}

// MARK: - Case Detail View

/// Displays detailed information about an anonymized DICOM case.
struct CaseDetailView: View {
    @Bindable var record: CaseRecord
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var caseAction: CaseAction?

    // Shared viewer states injected from parent
    var dicomState: DICOMViewState?
    var volumeState: VolumeViewState?

    var body: some View {
        Form {
            viewerActionsSection
            infoSection
            anonymizationStatusSection
            notesSection
            fileInfoSection
        }
        .navigationTitle(record.alias)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    isEditing.toggle()
                } label: {
                    Label(isEditing ? "완료" : "편집", systemImage: isEditing ? "checkmark" : "pencil")
                }
            }
        }
        .sheet(item: $caseAction) { action in
            switch action {
            case .exportSheet(let url):
                let bridge = createBridgeForExport(dicomPath: url.path)
                ExportSheetView(exportState: ExportState(), bridge: bridge)
            default:
                EmptyView()
            }
        }
    }

    private func createBridgeForExport(dicomPath: String) -> VTKBridge {
        let bridge = VTKBridge(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        _ = bridge.loadDICOMDirectory(dicomPath)
        return bridge
    }
}

// MARK: - Detail Sections

private extension CaseDetailView {

    var viewerActionsSection: some View {
        Section("뷰어로 열기") {
            let dirURL = record.anonymizedDirectoryURL
            let dirExists = FileManager.default.fileExists(atPath: dirURL.path)

            if dirExists {
                HStack(spacing: 12) {
                    viewerButton(
                        title: "2D 슬라이스",
                        icon: "doc.text.image",
                        color: .blue
                    ) {
                        openInDICOMViewer(path: dirURL.path)
                    }

                    viewerButton(
                        title: "3D 볼륨",
                        icon: "cube.transparent",
                        color: .purple
                    ) {
                        openInVolumeViewer(path: dirURL.path)
                    }

                    viewerButton(
                        title: "내보내기",
                        icon: "square.and.arrow.up",
                        color: .orange
                    ) {
                        caseAction = .exportSheet(dirURL)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.red)
                    Text("익명화 파일을 찾을 수 없어 뷰어를 열 수 없습니다.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    func viewerButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color.opacity(0.1))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    func openInDICOMViewer(path: String) {
        guard let state = dicomState else { return }
        // Load DICOM in shared state, then navigate via sidebar
        let bridge = VTKBridge(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        if bridge.loadDICOMDirectory(path) {
            state.bridge = bridge
            state.isLoaded = true
            state.loadedPath = path
            state.sliceMin = Double(bridge.sliceMin)
            state.sliceMax = Double(bridge.sliceMax)
            state.sliceIndex = Double(bridge.currentSlice)
            NotificationCenter.default.post(
                name: .switchSidebarItem,
                object: SidebarItem.dicomViewer
            )
        }
    }

    func openInVolumeViewer(path: String) {
        guard let state = volumeState else { return }
        state.loadedPath = path
        state.isLoaded = true
        state.selectedPreset = .softTissue
        state.opacityScale = 1.0
        NotificationCenter.default.post(
            name: .switchSidebarItem,
            object: SidebarItem.volumeViewer
        )
    }

    var infoSection: some View {
        Section("케이스 정보") {
            if isEditing {
                TextField("별칭", text: $record.alias)
            } else {
                detailRow("별칭", value: record.alias)
            }
            detailRow("모달리티", value: record.modality.isEmpty ? "—" : record.modality)

            if let date = record.studyDate {
                detailRow("검사 날짜", value: dateString(date))
            }

            detailRow("이미지 수", value: "\(record.imageCount)")

            if let age = record.patientAge, !age.isEmpty {
                detailRow("나이", value: age)
            }
            if let sex = record.patientSex, !sex.isEmpty {
                detailRow("성별", value: sex)
            }
            if let desc = record.studyDescription, !desc.isEmpty {
                detailRow("검사 설명", value: desc)
            }
            if let desc = record.seriesDescription, !desc.isEmpty {
                detailRow("시리즈 설명", value: desc)
            }
        }
    }

    var anonymizationStatusSection: some View {
        Section("익명화 상태") {
            HStack(spacing: 8) {
                Image(systemName: "shield.checkered")
                    .foregroundStyle(.green)
                Text("환자명, ID, 생년월일, 기관명 제거/대체 완료")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if record.hasBurnedInAnnotation {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading) {
                        Text("Burned-in Annotation 감지")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("이미지 픽셀에 텍스트가 포함되어 있을 수 있습니다. DICOM 태그 익명화만으로는 이 정보가 제거되지 않습니다.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            detailRow("가져온 날짜", value: dateString(record.importDate))
        }
    }

    var notesSection: some View {
        Section("메모") {
            if isEditing {
                TextEditor(text: $record.notes)
                    .frame(minHeight: 80)
            } else if record.notes.isEmpty {
                Text("메모 없음")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text(record.notes)
                    .font(.caption)
            }
        }
    }

    var fileInfoSection: some View {
        Section("저장 위치") {
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(record.anonymizedDirectoryPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            let dirExists = FileManager.default.fileExists(atPath: record.anonymizedDirectoryURL.path)
            HStack {
                Image(systemName: dirExists ? "checkmark.circle" : "xmark.circle")
                    .foregroundStyle(dirExists ? .green : .red)
                Text(dirExists ? "파일 존재 확인됨" : "파일을 찾을 수 없음")
                    .font(.caption)
                    .foregroundColor(dirExists ? .secondary : .red)
            }
        }
    }

    // MARK: - Helpers

    func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.caption)
        }
    }

    func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Notification for sidebar navigation

extension Notification.Name {
    static let switchSidebarItem = Notification.Name("switchSidebarItem")
}
