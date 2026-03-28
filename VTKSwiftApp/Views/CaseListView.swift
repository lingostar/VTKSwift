import SwiftUI
import SwiftData

// MARK: - Case List View

/// Displays all imported DICOM cases with search, filter, and import capabilities.
struct CaseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CaseRecord.importDate, order: .reverse) private var cases: [CaseRecord]
    @State private var searchText = ""
    @State private var showImportSheet = false
    @State private var selectedCase: CaseRecord?
    var dicomState: DICOMViewState?
    var volumeState: VolumeViewState?

    var filteredCases: [CaseRecord] {
        if searchText.isEmpty { return cases }
        return cases.filter { caseRecord in
            caseRecord.alias.localizedCaseInsensitiveContains(searchText) ||
            caseRecord.modality.localizedCaseInsensitiveContains(searchText) ||
            (caseRecord.studyDescription?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        Group {
            if cases.isEmpty {
                emptyState
            } else {
                caseList
            }
        }
        .navigationTitle("Cases")
        .searchable(text: $searchText, prompt: "별칭, 모달리티 검색")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showImportSheet = true
                } label: {
                    Label("케이스 추가", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showImportSheet) {
            CaseImportView()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("저장된 케이스 없음")
                .font(.title2)
            Text("DICOM 폴더를 선택하면 자동 익명화 후 로컬에 저장됩니다.")
                .foregroundStyle(.secondary)
                .font(.callout)
                .multilineTextAlignment(.center)
            Button {
                showImportSheet = true
            } label: {
                Label("DICOM 폴더 가져오기...", systemImage: "folder")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var caseList: some View {
        List {
            ForEach(filteredCases) { record in
                NavigationLink(value: record.persistentModelID) {
                    CaseRowView(record: record)
                }
            }
            .onDelete(perform: deleteCases)
        }
        .navigationDestination(for: PersistentIdentifier.self) { id in
            if let record = cases.first(where: { $0.persistentModelID == id }) {
                CaseDetailView(
                    record: record,
                    dicomState: dicomState,
                    volumeState: volumeState
                )
            }
        }
    }

    private func deleteCases(at offsets: IndexSet) {
        for index in offsets {
            let record = filteredCases[index]
            // Delete anonymized files
            let dirURL = record.anonymizedDirectoryURL
            try? FileManager.default.removeItem(at: dirURL)
            modelContext.delete(record)
        }
    }
}

// MARK: - Case Row View

struct CaseRowView: View {
    let record: CaseRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconForModality(record.modality))
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.alias)
                    .font(.headline)
                    .lineLimit(1)
                Text(record.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let desc = record.studyDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if record.hasBurnedInAnnotation {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .help("Burned-in annotation 감지됨")
            }
        }
        .padding(.vertical, 4)
    }

    private func iconForModality(_ modality: String) -> String {
        switch modality.uppercased() {
        case "CT": return "cube.transparent"
        case "MR", "MRI": return "brain.head.profile"
        case "CR", "DX": return "xray"
        case "US": return "waveform.path.ecg"
        case "NM", "PT": return "atom"
        default: return "doc.text.image"
        }
    }
}

// MARK: - Case Import View

/// Sheet for importing a new DICOM case with anonymization.
struct CaseImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var alias = ""
    @State private var keepAge = true
    @State private var keepDescriptions = true
    @State private var keepStudyDate = false
    @State private var isImporting = false
    @State private var showFilePicker = false
    @State private var selectedURL: URL?
    @State private var metadata: DICOMMetadata?
    @State private var errorMessage: String?
    @State private var importProgress: String?

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                if metadata != nil {
                    metadataPreviewSection
                    aliasSection
                    anonymizationOptionsSection
                    importButtonSection
                }
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("케이스 가져오기")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleFolderSelection(result)
            }
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 400)
        #endif
    }
}

// MARK: - Import View Sections

private extension CaseImportView {

    var sourceSection: some View {
        Section("DICOM 소스") {
            if let url = selectedURL {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue)
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                    Spacer()
                    Button("변경") { showFilePicker = true }
                        .font(.caption)
                }
            } else {
                Button {
                    showFilePicker = true
                } label: {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("DICOM 폴더 선택...")
                    }
                }
            }
        }
    }

    var metadataPreviewSection: some View {
        Section("원본 정보 (익명화 전)") {
            if let meta = metadata {
                metadataRow("환자명", value: meta.patientName, sensitive: true)
                metadataRow("환자 ID", value: meta.patientID, sensitive: true)
                metadataRow("생년월일", value: meta.patientBirthDate, sensitive: true)
                metadataRow("모달리티", value: meta.modality, sensitive: false)
                metadataRow("검사 설명", value: meta.studyDescription, sensitive: false)
                metadataRow("기관명", value: meta.institutionName, sensitive: true)

                if meta.hasBurnedInAnnotation {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("이미지에 Burned-in annotation이 포함되어 있을 수 있습니다.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    func metadataRow(_ label: String, value: String?, sensitive: Bool) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            if let value = value, !value.isEmpty {
                if sensitive {
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Image(systemName: "lock.slash")
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else {
                    Text(value)
                        .font(.caption)
                }
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    var aliasSection: some View {
        Section("케이스 별칭") {
            TextField("예: Knee CT - 2026-03", text: $alias)
                .textFieldStyle(.roundedBorder)
            Text("개인정보 대신 사용할 식별 이름을 입력하세요.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    var anonymizationOptionsSection: some View {
        Section("익명화 옵션") {
            Toggle("나이 보존", isOn: $keepAge)
                .font(.caption)
            Toggle("검사 설명 보존", isOn: $keepDescriptions)
                .font(.caption)
            Toggle("검사 날짜 보존", isOn: $keepStudyDate)
                .font(.caption)

            HStack(spacing: 6) {
                Image(systemName: "shield.checkered")
                    .foregroundStyle(.green)
                Text("환자명, ID, 생년월일, 기관명, 의사명은 항상 제거/대체됩니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var importButtonSection: some View {
        Section {
            Button {
                performImport()
            } label: {
                HStack {
                    Spacer()
                    if isImporting {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text(importProgress ?? "익명화 중...")
                    } else {
                        Image(systemName: "shield.checkered")
                        Text("익명화 후 가져오기")
                    }
                    Spacer()
                }
                .font(.headline)
                .padding(.vertical, 4)
            }
            .disabled(isImporting || alias.trimmingCharacters(in: .whitespaces).isEmpty)
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    func handleFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didStart = url.startAccessingSecurityScopedResource()
            selectedURL = url
            errorMessage = nil

            // Extract metadata from first DICOM file
            let anonymizer = DICOMAnonymizer()
            let fm = FileManager.default
            if let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                let dcmFile = contents.first { f in
                    let ext = f.pathExtension.lowercased()
                    return ext == "dcm" || ext == "dicom" || ext == "ima"
                } ?? contents.first

                if let file = dcmFile {
                    metadata = anonymizer.extractMetadata(from: file)
                    // Pre-fill alias from study description or modality
                    if alias.isEmpty {
                        alias = metadata?.studyDescription ?? metadata?.modality ?? "Case"
                    }
                }
            }

            if didStart { url.stopAccessingSecurityScopedResource() }

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    func performImport() {
        guard let sourceURL = selectedURL else { return }
        isImporting = true
        errorMessage = nil
        importProgress = "DICOM 파일 스캔 중..."

        let trimmedAlias = alias.trimmingCharacters(in: .whitespaces)
        let keepAge = self.keepAge
        let keepDescriptions = self.keepDescriptions
        let keepStudyDate = self.keepStudyDate

        DispatchQueue.global(qos: .userInitiated).async {
            let didStart = sourceURL.startAccessingSecurityScopedResource()
            defer { if didStart { sourceURL.stopAccessingSecurityScopedResource() } }

            // Create unique output directory
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let casesDir = documents.appendingPathComponent("AnonymizedCases")
            let caseID = UUID().uuidString.prefix(8)
            let relativePath = "AnonymizedCases/\(caseID)"
            let outputDir = casesDir.appendingPathComponent(String(caseID))

            do {
                var profile = AnonymizationProfile()
                profile.patientAlias = trimmedAlias
                profile.keepAge = keepAge
                profile.keepDescriptions = keepDescriptions
                profile.keepStudyDate = keepStudyDate

                DispatchQueue.main.async {
                    importProgress = "익명화 처리 중..."
                }

                let anonymizer = DICOMAnonymizer()
                let result = try anonymizer.anonymizeDirectory(
                    at: sourceURL,
                    outputDirectory: outputDir,
                    profile: profile
                )

                // Parse study date from metadata
                var parsedStudyDate: Date?
                if keepStudyDate, let meta = anonymizer.extractMetadata(from: sourceURL.appendingPathComponent(
                    (try? FileManager.default.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil))?
                        .first(where: { $0.pathExtension.lowercased() == "dcm" })?.lastPathComponent ?? ""
                )) {
                    if let dateStr = meta.studyDate {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyyMMdd"
                        parsedStudyDate = formatter.date(from: dateStr)
                    }
                }

                let meta = metadata

                DispatchQueue.main.async {
                    // Create SwiftData record
                    let record = CaseRecord(
                        alias: trimmedAlias,
                        modality: meta?.modality ?? "",
                        studyDate: parsedStudyDate,
                        imageCount: result.totalFiles,
                        studyDescription: keepDescriptions ? meta?.studyDescription : nil,
                        seriesDescription: keepDescriptions ? meta?.seriesDescription : nil,
                        patientAge: keepAge ? meta?.patientAge : nil,
                        patientSex: meta?.patientSex,
                        anonymizedDirectoryPath: relativePath,
                        hasBurnedInAnnotation: result.hasBurnedInAnnotations
                    )
                    modelContext.insert(record)

                    isImporting = false
                    importProgress = nil
                    dismiss()
                }

            } catch {
                DispatchQueue.main.async {
                    isImporting = false
                    importProgress = nil
                    errorMessage = "가져오기 실패: \(error.localizedDescription)"
                }
            }
        }
    }
}
