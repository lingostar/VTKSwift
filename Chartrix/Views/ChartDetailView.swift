import SwiftUI
import SceneKit
#if os(macOS)
import AppKit
#endif

// MARK: - Viewer Tab (legacy enum, still used by FullScreenViewerView)

enum ViewerTab: String, CaseIterable {
    case dicom = "DICOM"
    case volume = "Volume"
    case usdz = "USDZ"
}

// MARK: - Chart Detail View

/// Chart detail — viewer-centric layout with up to 4 panels.
struct ChartDetailView: View {
    let chart: Chart

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var fullScreen: FullScreenState
    @StateObject private var layoutManager = ViewerLayoutManager()

    @State private var showAddStudy = false
    @State private var showDeletePatientAlert = false
    @State private var showNotes = false
    @State private var usdzModalStudy: Study?

    /// Convenience accessor for the shared fullscreen flag.
    private var isFullScreen: Bool { fullScreen.isFullScreen }

    /// Binding bridging the env object for components that need a Binding<Bool>.
    private var isFullScreenBinding: Binding<Bool> {
        Binding(get: { fullScreen.isFullScreen },
                set: { fullScreen.isFullScreen = $0 })
    }

    /// Fraction of the (viewer + controls) area allocated to the bottom controls.
    @State private var controlsRatio: Double = 0.25

    var body: some View {
        VStack(spacing: 0) {
            // Study carousel — hidden in fullscreen for an immersive view
            if !isFullScreen {
                studyCarousel
            }

            // Viewer area + resizable bottom controls
            GeometryReader { geo in
                let dividerHeight: CGFloat = 8
                let total = max(0, geo.size.height - dividerHeight)
                let controlsHeight = total * controlsRatio
                let viewerHeight = total - controlsHeight

                VStack(spacing: 0) {
                    Group {
                        #if os(iOS)
                        if isFullScreen {
                            // iOS uses .fullScreenCover; tear down VTK render views
                            // in this hierarchy so the cover can attach them.
                            Color.black
                        } else {
                            LayoutContainer(
                                manager: layoutManager,
                                allStudies: chart.sortedStudies
                            )
                        }
                        #else
                        // macOS uses native window fullscreen — same view stays.
                        LayoutContainer(
                            manager: layoutManager,
                            allStudies: chart.sortedStudies
                        )
                        #endif
                    }
                    .frame(height: viewerHeight)
                    .padding(.horizontal, 16)

                    ResizeDivider(
                        axis: .horizontal,
                        ratio: Binding(
                            get: { 1.0 - controlsRatio },
                            set: { controlsRatio = max(0.1, min(0.6, 1.0 - $0)) }
                        ),
                        totalSize: total,
                        minRatio: 0.4,
                        maxRatio: 0.9
                    )

                    ScrollView {
                        bottomControlsArea
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                    .frame(height: controlsHeight)
                    .background(isFullScreen ? Color.black : Color.clear)
                }
            }
        }
        .background(isFullScreen ? Color.black : Color.clear)
        .preferredColorScheme(isFullScreen ? .dark : nil)
        .navigationTitle(chart.alias)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    // Full screen toggle
                    Button {
                        toggleFullScreen()
                    } label: {
                        Image(systemName: isFullScreen
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .keyboardShortcut("f", modifiers: .command)
                    .help(isFullScreen ? "Exit Full Screen (⌘F)" : "Full Screen (⌘F)")

                    Button {
                        showNotes = true
                    } label: {
                        Image(systemName: "note.text")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }

                    Menu {
                        Button(role: .destructive) {
                            showDeletePatientAlert = true
                        } label: {
                            Label("Delete Patient", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
        }
        .alert("Delete Patient?", isPresented: $showDeletePatientAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deletePatient() }
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

                // Auto-load into first empty panel (or first panel if all assigned)
                let target = layoutManager.allPanels.first(where: { $0.study == nil })
                    ?? layoutManager.allPanels.first
                target?.setStudy(study)

                ChartStorage.generateUSDZInBackground(study: study, chartAlias: chart.alias)
            }
        }
        .sheet(isPresented: $showNotes) {
            NotesListView(chart: chart)
        }
        .sheet(item: $usdzModalStudy) { study in
            USDZModalView(study: study, chartAlias: chart.alias)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: isFullScreenBinding) {
            PanelLayoutFullScreen(manager: layoutManager, chart: chart)
        }
        #else
        // macOS: native window fullscreen via NSWindow.toggleFullScreen.
        // Tracks the host window's fullscreen state via notifications.
        .background(WindowFullScreenBridge(isFullScreen: isFullScreenBinding))
        #endif
        .onAppear {
            // Load latest study into first panel if empty
            if let firstPanel = layoutManager.allPanels.first,
               firstPanel.study == nil,
               let latest = chart.latestStudy {
                firstPanel.setStudy(latest)
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
                        isSelected: false,
                        onTap: {
                            // Tap loads into first empty panel (or first panel)
                            let target = layoutManager.allPanels.first(where: { $0.study == nil })
                                ?? layoutManager.allPanels.first
                            target?.setStudy(study)
                        },
                        onDelete: { deleteStudy(study) },
                        onShow3D: { usdzModalStudy = study }
                    )
                }

                addStudyCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var addStudyCard: some View {
        Button {
            showAddStudy = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus").font(.title3).fontWeight(.semibold)
                Text("Add Study").font(.caption2)
            }
            .foregroundColor(.accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 80, minHeight: 60)
            .contentShape(Rectangle())
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

    // MARK: - Bottom Controls

    /// Unified bottom controls — always visible, gracefully disables when no DICOM panel.
    @ViewBuilder
    private var bottomControlsArea: some View {
        UnifiedBottomControls(manager: layoutManager, immersive: isFullScreen)
    }

    // MARK: - Full Screen

    /// Toggle full screen.
    /// - iOS: drives `.fullScreenCover` via `isFullScreen`.
    /// - macOS: invokes native `NSWindow.toggleFullScreen` on the host window;
    ///   `WindowFullScreenBridge` keeps `isFullScreen` synced via notifications.
    private func toggleFullScreen() {
        #if os(macOS)
        NSApp.keyWindow?.toggleFullScreen(nil)
        #else
        fullScreen.isFullScreen.toggle()
        #endif
    }

    // MARK: - Actions

    private func deleteStudy(_ study: Study) {
        if let dirPath = study.dicomDirectoryPath {
            let dirURL = ChartStorage.documentsDirectory.appendingPathComponent(dirPath)
            let studyFolderURL = dirURL.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: studyFolderURL)
        }

        // Clear from any panel that has this study
        for panel in layoutManager.allPanels where panel.study?.id == study.id {
            panel.setStudy(nil)
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

// MARK: - Study Card (carousel card with 3D button)

private struct StudyCard: View {
    let study: Study
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onShow3D: () -> Void

    @State private var showDeleteAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(study.modality)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(isSelected ? .white : study.modalityColor)

                Spacer()

                // 3D button (USDZ modal) — styled as a clear pill button
                Button(action: onShow3D) {
                    HStack(spacing: 3) {
                        Image(systemName: "cube.transparent.fill")
                            .font(.caption2)
                        Text("3D")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.28) : Color.accentColor)
                    )
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? Color.white.opacity(0.5) : Color.clear, lineWidth: 0.5)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Show 3D Model")

                // Menu
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
        .frame(minWidth: 160)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? study.modalityColor : Color.gray.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? study.modalityColor : Color.gray.opacity(0.2), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .alert("Delete Study?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("This will permanently delete this \(study.modality) study (\(study.imageCount) images).")
        }
    }
}

// MARK: - Panel Layout Full Screen

/// Full-screen presentation of the current panel layout.
/// Uses the same `ViewerLayoutManager`, so panel state, study assignments,
/// measurements, and slice positions are preserved across enter/exit.
private struct PanelLayoutFullScreen: View {
    @ObservedObject var manager: ViewerLayoutManager
    let chart: Chart

    @Environment(\.dismiss) private var dismiss

    /// Fraction of total height allocated to bottom controls (default 25%).
    @State private var controlsRatio: Double = 0.25

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                let dividerHeight: CGFloat = 8
                let total = max(0, geo.size.height - dividerHeight)
                let controlsHeight = total * controlsRatio
                let viewerHeight = total - controlsHeight

                VStack(spacing: 0) {
                    LayoutContainer(
                        manager: manager,
                        allStudies: chart.sortedStudies
                    )
                    .frame(height: viewerHeight)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                    ResizeDivider(
                        axis: .horizontal,
                        ratio: Binding(
                            get: { 1.0 - controlsRatio },
                            set: { controlsRatio = max(0.1, min(0.6, 1.0 - $0)) }
                        ),
                        totalSize: total,
                        minRatio: 0.4,
                        maxRatio: 0.9
                    )

                    ScrollView {
                        UnifiedBottomControls(manager: manager, immersive: true)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .frame(height: controlsHeight)
                    .background(Color.black)
                }
            }

            // Always-visible close button (top-right)
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("f", modifiers: .command)
                    .help("Exit Full Screen (⌘F)")
                    .padding(.top, 12)
                    .padding(.trailing, 16)
                }
                Spacer()
            }
        }
        #if os(macOS)
        .onExitCommand { dismiss() }
        #endif
    }
}

// MARK: - Unified Bottom Controls

/// Bottom controls — always visible.
/// - Measure toolbar: applies to all DICOM panels (mode synced).
/// - Compatibility warnings: shown when ≥2 active DICOM panels and conditions differ.
/// - Slice slider: synchronized across active DICOM panels (single panel = direct control).
/// - Measurement results: shown for the primary (first) DICOM panel.
/// - When no DICOM panel is active (e.g., Volume-only or empty), the toolbar is disabled.
struct UnifiedBottomControls: View {
    @ObservedObject var manager: ViewerLayoutManager
    var immersive: Bool = false   // dark theme for fullscreen
    @Environment(\.modelContext) private var modelContext

    private var dicomPanels: [PanelState] { manager.activeDICOMPanels }
    private var primaryPanel: PanelState? { dicomPanels.first }
    private var hasDICOM: Bool { !dicomPanels.isEmpty }

    /// Measurements for the primary panel's current slice.
    private var primaryMeasurements: [Measurement] {
        guard let panel = primaryPanel,
              let study = panel.study else { return [] }
        return (study.measurements ?? [])
            .filter { $0.sliceIndex == panel.currentSlice }
            .sorted { $0.createdDate < $1.createdDate }
    }

    /// Union of measurements across all active DICOM panels (for slider indicators).
    private var allMeasurements: [Measurement] {
        dicomPanels.flatMap { $0.study?.measurements ?? [] }
    }

    private var currentMode: MeasureMode { primaryPanel?.measureMode ?? .none }

    var body: some View {
        VStack(spacing: 8) {
            // Measure toolbar — always visible (disabled if no DICOM)
            measureToolbar

            // Compatibility warnings (multi-panel only)
            if !manager.compatibilityWarnings.isEmpty {
                warningBanner
            }

            // Slice slider (when DICOM panels present with > 1 slices)
            if hasDICOM, manager.maxSliceCount > 1 {
                sliceSlider
            }

            // Measurement results for primary panel
            if hasDICOM, !primaryMeasurements.isEmpty {
                measurementResults
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            Group {
                if immersive {
                    RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05))
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial)
                }
            }
        )
    }

    // MARK: Toolbar

    private var measureToolbar: some View {
        HStack(spacing: 12) {
            ForEach(MeasureMode.allCases, id: \.self) { mode in
                Button {
                    for p in dicomPanels {
                        p.measureMode = mode
                        p.currentPoints = []
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: mode.icon).font(.title3)
                        Text(mode.label).font(.caption2)
                    }
                    .frame(width: 60, height: 44)
                    .contentShape(Rectangle())
                    .background(currentMode == mode ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(currentMode == mode ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                if let last = primaryMeasurements.last {
                    modelContext.delete(last)
                    try? modelContext.save()
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(primaryMeasurements.isEmpty)

            Button {
                for m in primaryMeasurements { modelContext.delete(m) }
                try? modelContext.save()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(primaryMeasurements.isEmpty)
        }
        .padding(.horizontal, 4)
        .disabled(!hasDICOM)
        .opacity(hasDICOM ? 1.0 : 0.4)
    }

    // MARK: Warning Banner

    private var warningBanner: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(manager.compatibilityWarnings, id: \.self) { warning in
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption2)
                    Text(warning)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Slice Slider

    private var sliceSlider: some View {
        let maxCount = manager.maxSliceCount
        return VStack(spacing: 2) {
            SliceMeasurementIndicator(
                totalSlices: maxCount,
                measurements: allMeasurements
            )

            Slider(
                value: Binding(
                    get: { Double(manager.syncedSliceIndex) },
                    set: { manager.setSyncedSlice(Int($0)) }
                ),
                in: 0...Double(max(1, maxCount - 1)),
                step: 1
            )

            HStack {
                Text("Slice: \(manager.syncedSliceIndex)")
                Spacer()
                Text("0–\(maxCount - 1)")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .monospacedDigit()
        }
    }

    // MARK: Measurement Results

    private var measurementResults: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(primaryMeasurements) { m in
                HStack {
                    Image(systemName: m.measureType == "distance" ? "ruler" : "angle")
                        .foregroundColor(m.measureType == "distance" ? .yellow : .cyan)
                    Text(m.formattedValue)
                        .font(.caption)
                        .monospacedDigit()
                    Spacer()
                    Button {
                        modelContext.delete(m)
                        try? modelContext.save()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(minWidth: 32, minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Reference only — measurements are for informational purposes")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Slice Measurement Indicator

/// Thin tick marks above the slider showing which slices have measurements.
struct SliceMeasurementIndicator: View {
    let totalSlices: Int
    let measurements: [Measurement]

    private var measuredSlices: Set<Int> {
        Set(measurements.map(\.sliceIndex))
    }

    var body: some View {
        if !measuredSlices.isEmpty {
            GeometryReader { geo in
                let width = geo.size.width
                let padding: CGFloat = 8
                let trackWidth = width - padding * 2
                ForEach(Array(measuredSlices), id: \.self) { slice in
                    let fraction = totalSlices > 1
                        ? CGFloat(slice) / CGFloat(totalSlices - 1)
                        : 0.5
                    let x = padding + fraction * trackWidth
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(Color.yellow.opacity(0.8))
                        .frame(width: 2, height: 8)
                        .position(x: x, y: 4)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Volume Render Wrapper

#if os(iOS)
struct VolumeRenderWrap: UIViewRepresentable {
    @Binding var bridge: VTKBridge?
    func makeUIView(context: Context) -> UIView { bridge?.renderView ?? UIView() }
    func updateUIView(_ v: UIView, context: Context) {
        guard let b = bridge else { return }
        let s = v.bounds.size
        if s.width > 0, s.height > 0 { b.resize(to: s) }
    }
}
#elseif os(macOS)
struct VolumeRenderWrap: NSViewRepresentable {
    @Binding var bridge: VTKBridge?
    func makeNSView(context: Context) -> NSView { bridge?.renderView ?? NSView() }
    func updateNSView(_ v: NSView, context: Context) {
        guard let b = bridge else { return }
        let s = v.bounds.size
        if s.width > 0, s.height > 0 { b.resize(to: s) }
    }
}
#endif

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

// MARK: - AR Quick Look (iOS)

#if os(iOS)
import QuickLook

struct ARQuickLookSheet: View {
    let fileURL: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ARQuickLookRepresentable(fileURL: fileURL)
                .ignoresSafeArea()

            Button { dismiss() } label: {
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

private struct ARQuickLookRepresentable: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
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

// MARK: - USDZ Scene View (SceneKit)

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
        scnView.backgroundColor = .clear

        guard let scene = try? SCNScene(url: fileURL) else { return }
        scnView.scene = scene

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

// MARK: - macOS Window Full Screen Bridge

#if os(macOS)
/// Tracks the host `NSWindow`'s fullscreen state and syncs it to a binding.
/// Used so `ChartDetailView.isFullScreen` reflects the actual window state
/// when the user enters/exits fullscreen via any path (button, ⌘F, green dot,
/// gesture, system menu).
struct WindowFullScreenBridge: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attach(to: view, binding: $isFullScreen)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView, binding: $isFullScreen)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private weak var observedWindow: NSWindow?
        private var enterToken: NSObjectProtocol?
        private var exitToken: NSObjectProtocol?
        private var binding: Binding<Bool>?

        func attach(to view: NSView, binding: Binding<Bool>) {
            self.binding = binding
            let window = view.window
            guard window !== observedWindow else {
                // Same window — just sync state in case it changed
                if let w = window {
                    binding.wrappedValue = w.styleMask.contains(.fullScreen)
                }
                return
            }
            detach()
            observedWindow = window
            guard let window = window else { return }
            // Sync initial state
            binding.wrappedValue = window.styleMask.contains(.fullScreen)
            let nc = NotificationCenter.default
            enterToken = nc.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: window, queue: .main
            ) { [weak self] _ in
                self?.binding?.wrappedValue = true
            }
            exitToken = nc.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window, queue: .main
            ) { [weak self] _ in
                self?.binding?.wrappedValue = false
            }
        }

        func detach() {
            let nc = NotificationCenter.default
            if let t = enterToken { nc.removeObserver(t); enterToken = nil }
            if let t = exitToken { nc.removeObserver(t); exitToken = nil }
            observedWindow = nil
        }

        deinit { detach() }
    }
}
#endif
