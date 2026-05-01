import SwiftUI
import SwiftData

// MARK: - Full Screen Viewer

/// Full-screen viewer for DICOM, Volume, and USDZ content.
/// Presented via `.fullScreenCover` from each tab view in ChartDetailView.
///
/// Features:
/// - Content fills entire screen with black background
/// - Auto-hiding overlay controls (tap to toggle, 4s auto-hide)
/// - Persistent close + show-controls buttons
/// - DICOM: full measurement support with magnifier
/// - Volume: CT presets and opacity control
/// - USDZ: 3D preview with AR and Share
struct FullScreenViewerView: View {
    let study: Study
    let chartAlias: String
    let tab: ViewerTab
    var initialSlice: Int = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // MARK: Controls Visibility
    @State private var showControls = true
    @State private var hideTask: Task<Void, Never>?

    // MARK: DICOM State
    @State private var sliceImage: CGImage?
    @State private var currentSlice: Double = 0
    @State private var totalSlices: Int = 0
    @State private var measureMode: MeasureMode = .none
    @State private var currentPoints: [CGPoint] = []

    // MARK: Volume State
    @State private var bridge: VTKBridge?
    @State private var volumeLoaded = false
    @State private var volumeLoading = true
    @State private var selectedCTPreset: CTPreset = .softTissue
    @State private var opacityScale: Double = 1.0

    // MARK: USDZ State
    @State private var usdzURL: URL?
    #if os(iOS)
    @State private var showARQuickLook = false
    #endif

    // MARK: - Computed Properties

    /// Measurements for the current DICOM slice
    private var currentMeasurements: [Measurement] {
        guard tab == .dicom else { return [] }
        let slice = Int(currentSlice)
        return (study.measurements ?? [])
            .filter { $0.sliceIndex == slice }
            .sorted { $0.createdDate < $1.createdDate }
    }

    /// MeasureResults for MeasureOverlay rendering
    private var currentMeasureResults: [MeasureResult] {
        currentMeasurements.map { m in
            MeasureResult(type: m.mode, points: m.points, value: m.value)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // 1. Background — fills entire screen
            Color.black.ignoresSafeArea()

            // 2. Main content — fills entire screen
            Group {
                switch tab {
                case .dicom:  dicomContent
                case .volume: volumeContent
                case .usdz:  usdzContent
                }
            }
            .ignoresSafeArea()

            // 3. Auto-hiding overlay controls (behind persistent buttons)
            if showControls {
                VStack(spacing: 0) {
                    topOverlay
                        .allowsHitTesting(false)
                    Spacer()
                    bottomOverlay
                }
                .transition(.opacity)
            }

            // 4. Persistent buttons — ALWAYS on top of everything
            persistentButtons
        }
        #if os(iOS)
        .statusBarHidden(!showControls)
        .persistentSystemOverlays(.hidden)
        #endif
        #if os(macOS)
        .onExitCommand { dismiss() }
        #endif
        .animation(.easeInOut(duration: 0.25), value: showControls)
        .onAppear {
            initializeContent()
            scheduleAutoHide()
        }
        .onDisappear {
            hideTask?.cancel()
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showARQuickLook) {
            if let url = usdzURL {
                ARQuickLookSheet(fileURL: url)
            }
        }
        #endif
    }

    // MARK: - Persistent Buttons (always visible)

    private var persistentButtons: some View {
        VStack {
            HStack {
                Spacer()
                VStack(spacing: 10) {
                    // Close button
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                            .opacity(0.85)
                    }

                    // Show-controls button (visible only when controls are hidden)
                    if !showControls {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showControls = true
                            }
                            scheduleAutoHide()
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                                .opacity(0.85)
                        }
                        .transition(.opacity.combined(with: .scale))
                    }
                }
            }
            .padding(.top, 8)
            .padding(.trailing, 16)
            Spacer()
        }
    }

    // MARK: - Top Overlay

    private var topOverlay: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(study.modality)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(study.modalityColor.opacity(0.8), in: Capsule())

                    if !study.studyDescription.isEmpty {
                        Text(study.studyDescription)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }

                if tab == .dicom && totalSlices > 1 {
                    Text("Slice \(Int(currentSlice) + 1) / \(totalSlices)")
                        .font(.caption2)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.white)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.6), .black.opacity(0.3), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Bottom Overlay

    @ViewBuilder
    private var bottomOverlay: some View {
        switch tab {
        case .dicom:  dicomControls
        case .volume: volumeControls
        case .usdz:  usdzControls
        }
    }

    // MARK: - Controls Toggle & Auto-hide

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showControls.toggle()
        }
        if showControls {
            scheduleAutoHide()
        }
    }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        // Don't auto-hide during measurement
        guard measureMode == .none else { return }

        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                showControls = false
            }
        }
    }

    private func resetAutoHide() {
        scheduleAutoHide()
    }

    // MARK: - Initialize Content

    private func initializeContent() {
        switch tab {
        case .dicom:  loadDICOMContent()
        case .volume: loadVolumeContent()
        case .usdz:   loadUSDZContent()
        }
    }
}

// MARK: - DICOM Full Screen

extension FullScreenViewerView {

    @ViewBuilder
    private var dicomContent: some View {
        if let cgImage = sliceImage {
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
                        sliceImage: sliceImage,
                        onComplete: { result in
                            saveMeasurement(result)
                        }
                    )
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if measureMode == .none {
                        toggleControls()
                    }
                }
            }
        } else {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTapGesture { toggleControls() }
        }
    }

    private var dicomControls: some View {
        VStack(spacing: 10) {
            // Measurement toolbar
            HStack(spacing: 12) {
                ForEach(MeasureMode.allCases, id: \.self) { mode in
                    Button {
                        measureMode = mode
                        currentPoints = []
                        if mode != .none {
                            // Keep controls visible during measurement
                            hideTask?.cancel()
                            withAnimation { showControls = true }
                        } else {
                            scheduleAutoHide()
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: mode.icon)
                                .font(.title3)
                            Text(mode.label)
                                .font(.caption2)
                        }
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 40)
                        .background(measureMode == mode ? Color.white.opacity(0.25) : Color.clear)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    measureMode == mode
                                        ? Color.white.opacity(0.6)
                                        : Color.white.opacity(0.15),
                                    lineWidth: 1
                                )
                        )
                    }
                }

                Spacer()

                // Undo last measurement
                Button {
                    if let last = currentMeasurements.last {
                        modelContext.delete(last)
                        try? modelContext.save()
                    }
                    resetAutoHide()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .opacity(currentMeasurements.isEmpty ? 0.3 : 1)
                .disabled(currentMeasurements.isEmpty)

                // Delete all measurements on this slice
                Button {
                    for m in currentMeasurements { modelContext.delete(m) }
                    try? modelContext.save()
                    resetAutoHide()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.8))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .opacity(currentMeasurements.isEmpty ? 0.3 : 1)
                .disabled(currentMeasurements.isEmpty)
            }

            // Slice slider
            if totalSlices > 1 {
                VStack(spacing: 2) {
                    SliceMeasurementIndicator(
                        totalSlices: totalSlices,
                        measurements: study.measurements ?? []
                    )

                    Slider(
                        value: $currentSlice,
                        in: 0...Double(max(1, totalSlices - 1)),
                        step: 1
                    )
                    .tint(.white)
                    .onChange(of: currentSlice) { _, newValue in
                        currentPoints = []
                        loadSlice(at: Int(newValue))
                        resetAutoHide()
                    }

                    HStack {
                        Text("Slice: \(Int(currentSlice))")
                        Spacer()
                        Text("0–\(totalSlices - 1)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .padding(.top, 20)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.3), .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: DICOM Actions

    private func loadDICOMContent() {
        guard let dirURL = ChartStorage.dicomDirectoryURL(for: study) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let files = DICOMSliceRenderer.sortedDICOMFiles(in: dirURL)
            let sliceIndex = min(initialSlice, max(0, files.count - 1))
            let image = DICOMSliceRenderer.renderSlice(directoryURL: dirURL, sliceIndex: sliceIndex)
            DispatchQueue.main.async {
                totalSlices = files.count
                currentSlice = Double(sliceIndex)
                sliceImage = image
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

    private func saveMeasurement(_ result: MeasureResult) {
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
}

// MARK: - Volume Full Screen

extension FullScreenViewerView {

    @ViewBuilder
    private var volumeContent: some View {
        if volumeLoaded {
            VolumeRenderWrap(bridge: $bridge)
        } else if volumeLoading {
            VStack(spacing: 12) {
                ProgressView().scaleEffect(1.5).tint(.white)
                Text("Loading volume...")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onTapGesture { toggleControls() }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.4))
                Text("Volume rendering unavailable")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onTapGesture { toggleControls() }
        }
    }

    private var volumeControls: some View {
        VStack(spacing: 8) {
            if volumeLoaded {
                // CT Presets
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CTPreset.allCases) { preset in
                            Button {
                                selectedCTPreset = preset
                                bridge?.apply(preset.vtkPreset)
                                resetAutoHide()
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: preset.icon).font(.title3)
                                    Text(preset.title).font(.caption2)
                                }
                                .foregroundStyle(.white)
                                .frame(width: 64, height: 44)
                                .background(
                                    selectedCTPreset == preset
                                        ? Color.white.opacity(0.25)
                                        : Color.clear
                                )
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            selectedCTPreset == preset
                                                ? Color.white.opacity(0.6)
                                                : Color.white.opacity(0.15),
                                            lineWidth: 1
                                        )
                                )
                            }
                        }
                    }
                }

                // Opacity slider
                HStack {
                    Text("Opacity")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    Slider(value: $opacityScale, in: 0.1...2.0, step: 0.05)
                        .tint(.white)
                        .onChange(of: opacityScale) { _, val in
                            bridge?.setVolumeOpacityScale(val)
                            resetAutoHide()
                        }
                    Text(String(format: "%.0f%%", opacityScale * 100))
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .padding(.top, 20)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.3), .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: Volume Loading

    private func loadVolumeContent() {
        guard let path = ChartStorage.dicomDirectoryURL(for: study)?.path else {
            volumeLoading = false
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let b = VTKBridge(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
            if b.loadVolume(fromDICOMDirectory: path) {
                bridge = b
                b.apply(selectedCTPreset.vtkPreset)
                b.setVolumeOpacityScale(opacityScale)
                volumeLoaded = true
            }
            volumeLoading = false
        }
    }
}

// MARK: - USDZ Full Screen

extension FullScreenViewerView {

    @ViewBuilder
    private var usdzContent: some View {
        if let url = usdzURL, FileManager.default.fileExists(atPath: url.path) {
            USDZSceneView(fileURL: url)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.4))
                Text("No 3D model available")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onTapGesture { toggleControls() }
        }
    }

    private var usdzControls: some View {
        HStack(spacing: 16) {
            #if os(iOS)
            if usdzURL != nil {
                Button {
                    showARQuickLook = true
                    resetAutoHide()
                } label: {
                    Label("AR", systemImage: "arkit")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
            #endif

            if let url = usdzURL {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .padding(.top, 20)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.3), .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: USDZ Loading

    private func loadUSDZContent() {
        guard let relPath = study.usdzFilePath, !relPath.isEmpty else { return }
        let url = ChartStorage.documentsDirectory.appendingPathComponent(relPath)
        if FileManager.default.fileExists(atPath: url.path) {
            usdzURL = url
        }
    }
}
