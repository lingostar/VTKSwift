import SwiftUI

// MARK: - Viewer Tab

enum ViewerTab: String, CaseIterable {
    case dicom = "DICOM"
    case volume = "Volume"
    case usdz = "USDZ"
}

// MARK: - Chart Detail View

/// Chart detail — Study carousel + segmented viewer
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
            // Study carousel (always visible — includes + card)
            studyCarousel

            // Segment control
            Picker("Viewer", selection: $selectedTab) {
                ForEach(ViewerTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 4)

            // Viewer area
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
                if chart.studies == nil { chart.studies = [] }
                chart.studies?.append(study)
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

                // + card (add new Study)
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
        // Delete files
        if let dirPath = study.dicomDirectoryPath {
            let dirURL = ChartStorage.documentsDirectory.appendingPathComponent(dirPath)
            // Delete parent of DICOM folder (studyDate_modality folder)
            let studyFolderURL = dirURL.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: studyFolderURL)
        }

        // Deselect
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

    /// Auto-generate USDZ in background if none exists
    private func ensureUSDZExists() {
        for study in (chart.studies ?? []) {
            if let rel = study.usdzFilePath, !rel.isEmpty {
                let url = ChartStorage.documentsDirectory.appendingPathComponent(rel)
                if FileManager.default.fileExists(atPath: url.path) { continue }
            }
            ChartStorage.generateUSDZInBackground(study: study, chartAlias: chart.alias)
        }
    }
}

// MARK: - Study Card (carousel card)

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

                // ... menu
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
                if ChartStorage.isICloudAvailable,
                   ChartStorage.downloadStatus(for: study) != .downloaded,
                   ChartStorage.downloadStatus(for: study) != .local {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.caption2)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
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

/// DICOM 2D slice viewer + measurement tools
private struct DICOMTabView: View {
    let study: Study

    @Environment(\.modelContext) private var modelContext
    @State private var sliceImage: CGImage?
    @State private var currentSlice: Double = 0
    @State private var totalSlices: Int = 0
    @State private var isLoading = true
    @State private var viewerHeight: CGFloat = 400
    @State private var dragStartHeight: CGFloat = 400

    // iCloud download
    @StateObject private var downloadMonitor = ICloudDownloadMonitor()
    @State private var isDownloadingFromICloud = false

    // Measurement
    @State private var measureMode: MeasureMode = .none
    @State private var currentPoints: [CGPoint] = []

    /// Saved measurements for current slice
    var currentMeasurements: [Measurement] {
        let slice = Int(currentSlice)
        return (study.measurements ?? [])
            .filter { $0.sliceIndex == slice }
            .sorted { $0.createdDate < $1.createdDate }
    }

    /// Convert to MeasureResult for MeasureOverlay
    var currentMeasureResults: [MeasureResult] {
        currentMeasurements.map { m in
            MeasureResult(type: m.mode, points: m.points, value: m.value)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Viewer box: image + controls + resize handle
                VStack(spacing: 0) {
                    // CT image + measurement overlay
                    ZStack {
                        Color.black

                        if isDownloadingFromICloud {
                            iCloudDownloadOverlay
                        } else if isLoading {
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
                                            if study.measurements == nil { study.measurements = [] }
                                            study.measurements?.append(m)
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

                    // Controls area
                    VStack(spacing: 8) {
                        // Measurement toolbar
                        measureToolbar

                        // Slice slider
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

                    // Resize handle
                    ViewerResizeHandle(viewerHeight: $viewerHeight, dragStartHeight: $dragStartHeight)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.5), lineWidth: 2)
                )

                // Measurement results
                if !currentMeasurements.isEmpty {
                    measureResults
                }

                // Info
                StudyInfoSection(study: study)
            }
            .padding()
        }
        .task { checkAndLoad() }
        .onChange(of: downloadMonitor.state) { _, newState in
            if case .completed = newState {
                isDownloadingFromICloud = false
                loadInitialSlice()
            }
        }
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
                    // Individual delete button
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

            Text("Reference only — measurements are for informational purposes")
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

    // MARK: - iCloud Download

    /// Check iCloud download status and start download if needed
    private func checkAndLoad() {
        let status = ChartStorage.downloadStatus(for: study)

        switch status {
        case .local, .downloaded:
            // Already local → load immediately
            loadInitialSlice()

        case .notDownloaded, .downloading:
            // Needs download from iCloud
            isDownloadingFromICloud = true
            isLoading = false
            downloadMonitor.startMonitoring(study: study)
        }
    }

    /// iCloud download progress overlay
    private var iCloudDownloadOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.8))
                .symbolEffect(.pulse)

            Text("Downloading from iCloud...")
                .font(.callout)
                .foregroundColor(.white.opacity(0.9))

            switch downloadMonitor.state {
            case .downloading(let progress, let downloaded, let total):
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.cyan)
                        .frame(width: 200)

                    Text("\(downloaded) / \(total) files")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .monospacedDigit()
                }

            case .checking:
                ProgressView()
                    .tint(.white)

            case .failed(let message):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.icloud")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.orange)
                    Button("Retry") {
                        downloadMonitor.startMonitoring(study: study)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }

            default:
                ProgressView()
                    .tint(.white)
            }
        }
    }
}

// MARK: - Volume Tab

/// VTK 3D volume rendering
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

    // iCloud download
    @StateObject private var downloadMonitor = ICloudDownloadMonitor()
    @State private var isDownloadingFromICloud = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Viewer box: render view + controls + resize handle
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
                    } else if isDownloadingFromICloud {
                        volumeDownloadOverlay
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

                    // Resize handle
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
        .task { checkAndLoadVolume() }
        .onChange(of: downloadMonitor.state) { _, newState in
            if case .completed = newState {
                isDownloadingFromICloud = false
                loadVolume()
            }
        }
    }

    /// Check iCloud download status and start download if needed
    private func checkAndLoadVolume() {
        let status = ChartStorage.downloadStatus(for: study)

        switch status {
        case .local, .downloaded:
            loadVolume()
        case .notDownloaded, .downloading:
            isDownloadingFromICloud = true
            isLoading = false
            downloadMonitor.startMonitoring(study: study)
        }
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

    /// iCloud download progress overlay (Volume tab)
    private var volumeDownloadOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
                .symbolEffect(.pulse)

            Text("Downloading from iCloud...")
                .font(.callout)
                .foregroundColor(.secondary)

            if case .downloading(let progress, let downloaded, let total) = downloadMonitor.state {
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                        .frame(width: 200)

                    Text("\(downloaded) / \(total) files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            } else {
                ProgressView()
            }
        }
    }
}

// MARK: - USDZ Tab

/// USDZ generation/preview — HU Threshold, presets, Decimation, Smooth
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
    #if os(iOS)
    @State private var showARQuickLook = false
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Viewer box: 3D view + controls + Regenerate + resize handle
                VStack(spacing: 0) {
                    // 3D preview area
                    ZStack {
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color.gray.opacity(0.05))

                        if isGenerating {
                            VStack(spacing: 8) {
                                ProgressView().scaleEffect(1.5)
                                Text("Generating 3D model...").font(.callout).foregroundColor(.secondary)
                            }
                        } else if let url = exportedURL, FileManager.default.fileExists(atPath: url.path) {
                            USDZSceneView(fileURL: url)
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

                    // Controls area
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
                                #if os(iOS)
                                Button {
                                    showARQuickLook = true
                                } label: {
                                    Label("AR", systemImage: "arkit")
                                }
                                .buttonStyle(.bordered)
                                #endif

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

                    // Resize handle (bottom of box)
                    ViewerResizeHandle(viewerHeight: $viewerHeight, dragStartHeight: $dragStartHeight)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor.opacity(0.5), lineWidth: 2)
                )

                Text("Reference Only — This model is for reference purposes, not for clinical diagnosis.")
                    .font(.caption2).foregroundColor(.secondary)

                // Info
                StudyInfoSection(study: study)
            }
            .padding()
        }
        .onAppear { loadPreGeneratedUSDZ() }
        #if os(iOS)
        .fullScreenCover(isPresented: $showARQuickLook) {
            if let url = exportedURL {
                ARQuickLookSheet(fileURL: url)
            }
        }
        #endif
    }

    /// Load pre-generated USDZ if available
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

        // Check iCloud download status
        let status = ChartStorage.directoryDownloadStatus(dirURL)
        if status == .notDownloaded || status == .downloading {
            errorMessage = "DICOM files are still downloading from iCloud. Please wait."
            ChartStorage.startDownloadingDirectory(dirURL)
            return
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

/// Drag handle for adjusting viewer area height
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

// MARK: - AR Quick Look Sheet (iOS full-screen)

#if os(iOS)
import QuickLook

/// Full-screen AR Quick Look for USDZ files with a close button overlay
struct ARQuickLookSheet: View {
    let fileURL: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ARQuickLookRepresentable(fileURL: fileURL)
                .ignoresSafeArea()

            // Close button — always visible on top
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding(.top, 12)
            .padding(.trailing, 16)
        }
    }
}

/// UIViewControllerRepresentable wrapper for QLPreviewController
private struct ARQuickLookRepresentable: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        // Hide default navigation bar to avoid conflicts
        vc.navigationItem.rightBarButtonItem = nil
        return vc
    }

    func updateUIViewController(_ vc: QLPreviewController, context: Context) {}

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

/// 3D preview of USDZ file using SCNView (rotate with mouse/touch)
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

        // Auto-position camera to fit model bounding box
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
