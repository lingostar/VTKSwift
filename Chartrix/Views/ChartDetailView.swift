import SwiftUI

// MARK: - Viewer Tab

enum ViewerTab: String, CaseIterable {
    case dicom = "DICOM"
    case volume = "Volume"
    case usdz = "USDZ"
}

// MARK: - Chart Detail View

/// 차트 상세 — Study 캐러셀 + 세그먼트 뷰어
struct ChartDetailView: View {
    let chart: Chart

    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: ViewerTab = .dicom
    @State private var selectedStudy: Study?
    @State private var showAddStudy = false
    @State private var showDeletePatientAlert = false
    @State private var showNotes = false

    var body: some View {
        VStack(spacing: 0) {
            // Study 캐러셀 (항상 표시 — + 카드 포함)
            studyCarousel

            // 세그먼트 컨트롤
            Picker("Viewer", selection: $selectedTab) {
                ForEach(ViewerTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 4)

            // 뷰어 영역
            if let study = selectedStudy {
                switch selectedTab {
                case .dicom:
                    DICOMTabView(study: study)
                case .volume:
                    VolumeTabView(study: study)
                case .usdz:
                    USDZTabView(study: study, chartAlias: chart.alias)
                }
            } else {
                ContentUnavailableView(
                    "No Studies",
                    systemImage: "doc.text",
                    description: Text("Tap + to add a DICOM study.")
                )
            }
        }
        .navigationTitle(chart.alias)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Button {
                        showNotes = true
                    } label: {
                        Image(systemName: "note.text")
                    }

                    Menu {
                        Button(role: .destructive) {
                            showDeletePatientAlert = true
                        } label: {
                            Label("Delete Patient", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("Delete Patient?", isPresented: $showDeletePatientAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deletePatient()
            }
        } message: {
            Text("This will permanently delete \"\(chart.alias)\" and all associated studies and files.")
        }
        .sheet(isPresented: $showAddStudy) {
            AddStudySheet(chart: chart) { study, folderURL in
                modelContext.insert(study)
                chart.studies.append(study)
                ChartStorage.importDICOM(study: study, chartAlias: chart.alias, from: folderURL)
                chart.updatedDate = Date()
                try? modelContext.save()
                selectedStudy = study
                ChartStorage.generateUSDZInBackground(study: study, chartAlias: chart.alias)
            }
        }
        .sheet(isPresented: $showNotes) {
            NotesListView(chart: chart)
        }
        .onAppear {
            if selectedStudy == nil {
                selectedStudy = chart.latestStudy
            }
            ensureUSDZExists()
        }
    }

    // MARK: - Study Carousel

    private var studyCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(chart.sortedStudies) { study in
                    StudyCard(
                        study: study,
                        isSelected: selectedStudy?.id == study.id,
                        onDelete: { deleteStudy(study) }
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedStudy = study
                        }
                    }
                }

                // + 카드 (새 Study 추가)
                addStudyCard
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var addStudyCard: some View {
        Button {
            showAddStudy = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Add Study")
                    .font(.caption2)
            }
            .foregroundColor(.accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 80, minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                    .foregroundColor(.accentColor.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func deleteStudy(_ study: Study) {
        // 파일 삭제
        if let dirPath = study.dicomDirectoryPath {
            let dirURL = ChartStorage.documentsDirectory.appendingPathComponent(dirPath)
            // DICOM 폴더의 상위 (studyDate_modality 폴더) 삭제
            let studyFolderURL = dirURL.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: studyFolderURL)
        }

        // 선택 해제
        if selectedStudy?.id == study.id {
            selectedStudy = chart.sortedStudies.first(where: { $0.id != study.id })
        }

        modelContext.delete(study)
        chart.updatedDate = Date()
        try? modelContext.save()
    }

    private func deletePatient() {
        ChartStorage.deleteFiles(for: chart)
        modelContext.delete(chart)
        try? modelContext.save()
    }

    /// USDZ 파일이 없으면 백그라운드에서 자동 생성
    private func ensureUSDZExists() {
        for study in chart.studies {
            if let rel = study.usdzFilePath, !rel.isEmpty {
                let url = ChartStorage.documentsDirectory.appendingPathComponent(rel)
                if FileManager.default.fileExists(atPath: url.path) { continue }
            }
            ChartStorage.generateUSDZInBackground(study: study, chartAlias: chart.alias)
        }
    }
}

// MARK: - Study Card (캐러셀 카드)

private struct StudyCard: View {
    let study: Study
    let isSelected: Bool
    let onDelete: () -> Void

    @State private var showDeleteAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(study.modality)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(isSelected ? .white : study.modalityColor)

                Spacer()

                // ... 메뉴
                Menu {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("Delete Study", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
            }

            HStack(spacing: 4) {
                Text("\(study.imageCount) images")
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }

            if !study.studyDate.isEmpty {
                Text(study.formattedStudyDate)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white.opacity(0.9) : .primary)
            }

            if !study.studyDescription.isEmpty {
                Text(study.studyDescription)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minWidth: 140)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? study.modalityColor : Color.gray.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? study.modalityColor : Color.gray.opacity(0.2), lineWidth: 1.5)
        )
        .alert("Delete Study?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This will permanently delete this \(study.modality) study (\(study.imageCount) images).")
        }
    }
}

// MARK: - DICOM Tab

/// DICOM 2D 슬라이스 뷰어 + 측정 도구
private struct DICOMTabView: View {
    let study: Study

    @Environment(\.modelContext) private var modelContext
    @State private var sliceImage: CGImage?
    @State private var currentSlice: Double = 0
    @State private var totalSlices: Int = 0
    @State private var isLoading = true
    @State private var viewerHeight: CGFloat = 400
    @State private var dragStartHeight: CGFloat = 400

    // 측정
    @State private var measureMode: MeasureMode = .none
    @State private var currentPoints: [CGPoint] = []

    /// 현재 슬라이스의 저장된 측정 결과
    var currentMeasurements: [Measurement] {
        let slice = Int(currentSlice)
        return study.measurements
            .filter { $0.sliceIndex == slice }
            .sorted { $0.createdDate < $1.createdDate }
    }

    /// MeasureOverlay에 전달할 MeasureResult 변환
    var currentMeasureResults: [MeasureResult] {
        currentMeasurements.map { m in
            MeasureResult(type: m.mode, points: m.points, value: m.value)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Viewer 박스: 이미지 + 컨트롤 + 리사이즈 핸들
                VStack(spacing: 0) {
                    // CT 이미지 + 측정 오버레이
                    ZStack {
                        Color.black

                        if isLoading {
                            ProgressView().tint(.white)
                        } else if let cgImage = sliceImage {
                            GeometryReader { geo in
                                ZStack {
                                    Image(decorative: cgImage, scale: 1.0)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                                    MeasureOverlay(
                                        mode: measureMode,
                                        currentPoints: $currentPoints,
                                        results: currentMeasureResults,
                                        viewSize: geo.size,
                                        onComplete: { result in
                                            let m = Measurement(
                                                measureType: result.type == .distance ? "distance" : "angle",
                                                sliceIndex: Int(currentSlice),
                                                points: result.points,
                                                value: result.value
                                            )
                                            modelContext.insert(m)
                                            study.measurements.append(m)
                                            try? modelContext.save()
                                            currentPoints = []
                                        }
                                    )
                                }
                            }
                        } else {
                            Text("No image data")
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: viewerHeight)

                    // 컨트롤 영역
                    VStack(spacing: 8) {
                        // 측정 툴바
                        measureToolbar

                        // 슬라이스 슬라이더
                        if totalSlices > 1 {
                            VStack(spacing: 4) {
                                Slider(value: $currentSlice,
                                       in: 0...Double(max(1, totalSlices - 1)),
                                       step: 1)
                                .onChange(of: currentSlice) { _, newValue in
                                    currentPoints = []
                                    loadSlice(at: Int(newValue))
                                }

                                HStack {
                                    Text("Slice: \(Int(currentSlice))")
                                    Spacer()
                                    Text("0–\(totalSlices - 1)")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)

                    // 리사이즈 핸들
                    ViewerResizeHandle(viewerHeight: $viewerHeight, dragStartHeight: $dragStartHeight)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.5), lineWidth: 2)
                )

                // 측정 결과
                if !currentMeasurements.isEmpty {
                    measureResults
                }

                // Info
                StudyInfoSection(study: study)
            }
            .padding()
        }
        .task { loadInitialSlice() }
    }

    // MARK: - Measure Toolbar

    private var measureToolbar: some View {
        HStack(spacing: 12) {
            ForEach(MeasureMode.allCases, id: \.self) { mode in
                Button {
                    measureMode = mode
                    currentPoints = []
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: mode.icon)
                            .font(.title3)
                        Text(mode.label)
                            .font(.caption2)
                    }
                    .frame(width: 60, height: 44)
                    .background(measureMode == mode ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(measureMode == mode ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                if let last = currentMeasurements.last {
                    modelContext.delete(last)
                    try? modelContext.save()
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(currentMeasurements.isEmpty)

            Button {
                for m in currentMeasurements {
                    modelContext.delete(m)
                }
                try? modelContext.save()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .disabled(currentMeasurements.isEmpty)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Measure Results

    private var measureResults: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(currentMeasurements) { measurement in
                HStack {
                    Image(systemName: measurement.measureType == "distance" ? "ruler" : "angle")
                        .foregroundColor(measurement.measureType == "distance" ? .yellow : .cyan)
                    Text(measurement.formattedValue)
                        .font(.caption)
                        .monospacedDigit()
                    Spacer()
                    // 개별 삭제 버튼
                    Button {
                        modelContext.delete(measurement)
                        try? modelContext.save()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Reference only — 참고용 측정값")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Loading

    private func loadInitialSlice() {
        guard let dirURL = ChartStorage.dicomDirectoryURL(for: study) else {
            isLoading = false; return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let files = DICOMSliceRenderer.sortedDICOMFiles(in: dirURL)
            let mid = files.count / 2
            let image = DICOMSliceRenderer.renderSlice(directoryURL: dirURL, sliceIndex: mid)
            DispatchQueue.main.async {
                totalSlices = files.count
                currentSlice = Double(mid)
                sliceImage = image
                isLoading = false
            }
        }
    }

    private func loadSlice(at index: Int) {
        guard let dirURL = ChartStorage.dicomDirectoryURL(for: study) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let image = DICOMSliceRenderer.renderSlice(directoryURL: dirURL, sliceIndex: index)
            DispatchQueue.main.async { sliceImage = image }
        }
    }
}

// MARK: - Volume Tab

/// VTK 3D 볼륨 렌더링
private struct VolumeTabView: View {
    let study: Study

    @State private var bridge: VTKBridge?
    @State private var isLoaded = false
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var selectedPreset: CTPreset = .softTissue
    @State private var opacityScale: Double = 1.0
    @State private var viewerHeight: CGFloat = 400
    @State private var dragStartHeight: CGFloat = 400

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Viewer 박스: 렌더뷰 + 컨트롤 + 리사이즈 핸들
                VStack(spacing: 0) {
                    if isLoaded {
                        VolumeRenderWrap(bridge: $bridge)
                            .frame(maxWidth: .infinity)
                            .frame(height: viewerHeight)

                        VStack(spacing: 8) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(CTPreset.allCases) { preset in
                                        Button {
                                            selectedPreset = preset
                                            bridge?.apply(preset.vtkPreset)
                                        } label: {
                                            VStack(spacing: 4) {
                                                Image(systemName: preset.icon).font(.title3)
                                                Text(preset.title).font(.caption2)
                                            }
                                            .frame(width: 64, height: 48)
                                            .background(selectedPreset == preset ? Color.accentColor.opacity(0.2) : Color.clear)
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(selectedPreset == preset ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            HStack {
                                Text("Opacity").font(.caption).foregroundColor(.secondary)
                                Slider(value: $opacityScale, in: 0.1...2.0, step: 0.05)
                                    .onChange(of: opacityScale) { _, val in
                                        bridge?.setVolumeOpacityScale(val)
                                    }
                                Text(String(format: "%.0f%%", opacityScale * 100))
                                    .font(.caption).monospacedDigit()
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                    } else if loadFailed {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("Volume rendering unavailable")
                                .font(.callout)
                                .foregroundColor(.secondary)
                            Text("Use USDZ tab for 3D preview.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: viewerHeight)
                    } else if isLoading {
                        VStack(spacing: 12) {
                            ProgressView().scaleEffect(1.5)
                            Text("Loading volume...").font(.callout).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: viewerHeight)
                    }

                    // 리사이즈 핸들
                    ViewerResizeHandle(viewerHeight: $viewerHeight, dragStartHeight: $dragStartHeight)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.5), lineWidth: 2)
                )

                StudyInfoSection(study: study)
            }
            .padding()
        }
        .task { loadVolume() }
    }

    private func loadVolume() {
        guard let path = ChartStorage.dicomDirectoryURL(for: study)?.path else {
            isLoading = false
            loadFailed = true
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let b = VTKBridge(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
            if b.loadVolume(fromDICOMDirectory: path) {
                bridge = b
                b.apply(selectedPreset.vtkPreset)
                b.setVolumeOpacityScale(opacityScale)
                isLoaded = true
            } else {
                loadFailed = true
            }
            isLoading = false
        }
    }
}

// MARK: - USDZ Tab

/// USDZ 생성/프리뷰 — HU Threshold, 프리셋, Decimation, Smooth
private struct USDZTabView: View {
    let study: Study
    let chartAlias: String

    @State private var selectedPreset: USDZTissuePreset = .bone
    @State private var huThreshold: Double = 300
    @State private var decimationRate: Double = 0.8
    @State private var smoothing = true
    @State private var isGenerating = false
    @State private var triangleCount: Int = 0
    @State private var exportedURL: URL?
    @State private var errorMessage: String?
    @State private var viewerHeight: CGFloat = 400
    @State private var dragStartHeight: CGFloat = 400

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Viewer 박스: 3D뷰 + 컨트롤 + Regenerate + 리사이즈 핸들
                VStack(spacing: 0) {
                    // 3D 미리보기 영역
                    ZStack {
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color.gray.opacity(0.05))

                        if isGenerating {
                            VStack(spacing: 8) {
                                ProgressView().scaleEffect(1.5)
                                Text("Generating 3D model...").font(.callout).foregroundColor(.secondary)
                            }
                        } else if let url = exportedURL, FileManager.default.fileExists(atPath: url.path) {
                            #if os(iOS)
                            USDZQuickLookView(fileURL: url)
                            #else
                            USDZSceneView(fileURL: url)
                            #endif
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "cube.transparent")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                Text("Tap Regenerate to create 3D model")
                                    .font(.callout).foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: viewerHeight)

                    // 컨트롤 영역
                    VStack(spacing: 8) {
                        // HU Threshold
                        VStack(spacing: 4) {
                            HStack {
                                Text("HU Threshold")
                                    .font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(huThreshold))")
                                    .font(.caption).monospacedDigit()
                            }
                            Slider(value: $huThreshold, in: -500...1500, step: 10)
                        }

                        // Tissue Presets
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(USDZTissuePreset.allCases) { preset in
                                    Button {
                                        selectedPreset = preset
                                        huThreshold = preset.isoValue
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: preset.icon).font(.title3)
                                            Text(preset.label).font(.caption2)
                                        }
                                        .frame(width: 80, height: 48)
                                        .background(selectedPreset == preset ? Color.accentColor.opacity(0.2) : Color.clear)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(selectedPreset == preset ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Decimation
                        HStack {
                            Text("Decimation")
                                .font(.caption).foregroundColor(.secondary)
                            Slider(value: $decimationRate, in: 0...0.95, step: 0.05)
                            Text("\(Int(decimationRate * 100))%")
                                .font(.caption).monospacedDigit()
                                .frame(width: 36, alignment: .trailing)
                        }

                        // Smooth + Triangle count
                        HStack {
                            Toggle("Smooth", isOn: $smoothing)
                                .font(.caption)
                            Spacer()
                            if triangleCount > 0 {
                                Text("\(triangleCount.formatted()) triangles")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Action buttons
                        HStack(spacing: 12) {
                            Button {
                                generateUSDZ()
                            } label: {
                                Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isGenerating)

                            if let url = exportedURL {
                                #if os(macOS)
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                } label: {
                                    Label("Reveal", systemImage: "folder")
                                }
                                .buttonStyle(.bordered)
                                #endif

                                ShareLink(item: url) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        if let error = errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundColor(.red).font(.caption)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)

                    // 리사이즈 핸들 (박스 맨 아래)
                    ViewerResizeHandle(viewerHeight: $viewerHeight, dragStartHeight: $dragStartHeight)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor.opacity(0.5), lineWidth: 2)
                )

                Text("Reference Only — 이 모델은 참고용이며 진단 목적이 아닙니다.")
                    .font(.caption2).foregroundColor(.secondary)

                // Info
                StudyInfoSection(study: study)
            }
            .padding()
        }
        .onAppear { loadPreGeneratedUSDZ() }
    }

    /// 이미 생성된 USDZ가 있으면 로드
    private func loadPreGeneratedUSDZ() {
        guard exportedURL == nil,
              let relPath = study.usdzFilePath, !relPath.isEmpty else { return }
        let url = ChartStorage.documentsDirectory.appendingPathComponent(relPath)
        if FileManager.default.fileExists(atPath: url.path) {
            exportedURL = url
            print("[USDZ-Tab] Loaded pre-generated USDZ: \(url.lastPathComponent)")
        }
    }

    // MARK: - Generate

    private func generateUSDZ() {
        guard let dirURL = ChartStorage.dicomDirectoryURL(for: study) else {
            errorMessage = "DICOM directory not found."; return
        }

        isGenerating = true
        errorMessage = nil

        let bridge = VTKBridge(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        print("[USDZ-Gen] Loading DICOM from: \(dirURL.path)")
        guard bridge.loadDICOMDirectory(dirURL.path) else {
            isGenerating = false
            errorMessage = "Failed to load DICOM."
            print("[USDZ-Gen] ERROR: loadDICOMDirectory failed")
            return
        }
        print("[USDZ-Gen] DICOM loaded. Extracting mesh on background...")

        let isoVal = huThreshold
        let decRate = decimationRate
        let smooth = smoothing
        let preset = selectedPreset
        let studyFolder = "\(study.studyDate)_\(study.modality)".sanitizedFileName

        DispatchQueue.global(qos: .userInitiated).async {
            var verticesData: NSData?
            var normalsData: NSData?
            var facesData: NSData?

            let ok = bridge.extractIsosurfaceMesh(
                withIsoValue: isoVal,
                decimationRate: decRate,
                smoothing: smooth,
                vertices: &verticesData,
                normals: &normalsData,
                faces: &facesData
            )

            print("[USDZ-Gen] extractIsosurfaceMesh result=\(ok)")

            guard ok,
                  let vData = verticesData as Data?,
                  let nData = normalsData as Data?,
                  let fData = facesData as Data? else {
                print("[USDZ-Gen] ERROR: Mesh extraction failed or empty data")
                DispatchQueue.main.async {
                    isGenerating = false
                    errorMessage = "Failed to extract mesh."
                }
                return
            }

            print("[USDZ-Gen] Mesh: v=\(vData.count) bytes, n=\(nData.count) bytes, f=\(fData.count) bytes")
            let faceCount = fData.count / (3 * MemoryLayout<UInt32>.size)

            let outputURL = ChartStorage.chartsDirectory
                .appendingPathComponent(chartAlias.sanitizedFileName)
                .appendingPathComponent(studyFolder)
                .appendingPathComponent("\(preset.label).usdz")

            try? FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let result = USDZGenerator.create(
                vertices: vData, normals: nData, faces: fData,
                color: preset.color, roughness: preset.roughness,
                name: preset.label, outputURL: outputURL
            )

            DispatchQueue.main.async {
                isGenerating = false
                if result {
                    exportedURL = outputURL
                    triangleCount = faceCount
                    let rel = outputURL.path.replacingOccurrences(
                        of: ChartStorage.documentsDirectory.path + "/", with: "")
                    study.usdzFilePath = rel
                    print("[USDZ-Gen] Success! \(faceCount) triangles → \(outputURL.lastPathComponent)")
                } else {
                    errorMessage = "Failed to create USDZ."
                    print("[USDZ-Gen] ERROR: USDZGenerator.create returned false")
                }
            }
        }
    }
}

// MARK: - USDZ Tissue Preset

enum USDZTissuePreset: String, CaseIterable, Identifiable {
    case skin = "skin"
    case softTissue = "softTissue"
    case bone = "bone"
    case denseBone = "denseBone"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .skin: return "Skin"
        case .softTissue: return "Soft Tissue"
        case .bone: return "Bone"
        case .denseBone: return "Dense Bone"
        }
    }

    var icon: String {
        switch self {
        case .skin: return "hand.raised"
        case .softTissue: return "heart"
        case .bone: return "figure.walk"
        case .denseBone: return "circle.hexagongrid"
        }
    }

    var isoValue: Double {
        switch self {
        case .skin: return -500
        case .softTissue: return -100
        case .bone: return 300
        case .denseBone: return 800
        }
    }

    var color: SIMD3<Float> {
        switch self {
        case .skin: return SIMD3<Float>(0.96, 0.80, 0.69)
        case .softTissue: return SIMD3<Float>(0.85, 0.55, 0.55)
        case .bone: return SIMD3<Float>(0.95, 0.92, 0.84)
        case .denseBone: return SIMD3<Float>(0.98, 0.97, 0.95)
        }
    }

    var roughness: Float {
        switch self {
        case .skin: return 0.6
        case .softTissue: return 0.7
        case .bone: return 0.45
        case .denseBone: return 0.3
        }
    }
}

// MARK: - Viewer Resize Handle

/// 뷰어 영역 높이를 드래그로 조절하는 핸들
struct ViewerResizeHandle: View {
    @Binding var viewerHeight: CGFloat
    @Binding var dragStartHeight: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 20)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let newHeight = dragStartHeight + value.translation.height
                    viewerHeight = min(max(newHeight, 200), 900)
                }
                .onEnded { _ in
                    dragStartHeight = viewerHeight
                }
        )
        #if os(macOS)
        .onHover { inside in
            if inside {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        #endif
    }
}

// MARK: - Study Info Section

struct StudyInfoSection: View {
    let study: Study

    var body: some View {
        VStack(spacing: 12) {
            Text("Info")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                infoRow("Modality", value: study.modality)
                infoRow("Images", value: "\(study.imageCount)")
                if !study.studyDate.isEmpty {
                    infoRow("Study Date", value: study.formattedStudyDate)
                }
                if !study.studyDescription.isEmpty {
                    infoRow("Description", value: study.studyDescription)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.subheadline)
        }
    }
}

// MARK: - Volume Render Wrapper

#if os(iOS)
private struct VolumeRenderWrap: UIViewRepresentable {
    @Binding var bridge: VTKBridge?
    func makeUIView(context: Context) -> UIView { bridge?.renderView ?? UIView() }
    func updateUIView(_ v: UIView, context: Context) {
        guard let b = bridge else { return }
        let s = v.bounds.size
        if s.width > 0, s.height > 0 { b.resize(to: s) }
    }
}
#elseif os(macOS)
private struct VolumeRenderWrap: NSViewRepresentable {
    @Binding var bridge: VTKBridge?
    func makeNSView(context: Context) -> NSView { bridge?.renderView ?? NSView() }
    func updateNSView(_ v: NSView, context: Context) {
        guard let b = bridge else { return }
        let s = v.bounds.size
        if s.width > 0, s.height > 0 { b.resize(to: s) }
    }
}
#endif

// MARK: - USDZ Quick Look (iOS)

#if os(iOS)
import QuickLook

struct USDZQuickLookView: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: QLPreviewController, context: Context) {
        vc.reloadData()
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: fileURL) }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}
#endif

// MARK: - USDZ 3D Preview (SceneKit)

import SceneKit

/// SCNView로 USDZ 파일을 3D 프리뷰 (마우스/터치로 회전 가능)
struct USDZSceneView {
    let fileURL: URL
}

#if os(macOS)
extension USDZSceneView: NSViewRepresentable {
    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        configureSceneView(scnView)
        return scnView
    }
    func updateNSView(_ scnView: SCNView, context: Context) {}
}
#else
extension USDZSceneView: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        configureSceneView(scnView)
        return scnView
    }
    func updateUIView(_ scnView: SCNView, context: Context) {}
}
#endif

extension USDZSceneView {
    func configureSceneView(_ scnView: SCNView) {
        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = true
        scnView.antialiasingMode = .multisampling4X
        #if os(macOS)
        scnView.backgroundColor = .clear
        #else
        scnView.backgroundColor = .clear
        #endif

        guard let scene = try? SCNScene(url: fileURL) else { return }
        scnView.scene = scene

        // 모델 바운딩 박스에 맞춰 카메라 자동 배치
        let (minVec, maxVec) = scene.rootNode.boundingBox
        let center = SCNVector3(
            (minVec.x + maxVec.x) / 2,
            (minVec.y + maxVec.y) / 2,
            (minVec.z + maxVec.z) / 2
        )
        let size = SCNVector3(
            maxVec.x - minVec.x,
            maxVec.y - minVec.y,
            maxVec.z - minVec.z
        )
        let maxDim = max(size.x, max(size.y, size.z))

        let camera = SCNCamera()
        camera.automaticallyAdjustsZRange = true

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(
            center.x,
            center.y,
            center.z + maxDim * 1.8
        )
        cameraNode.look(at: center)
        scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode
    }
}
