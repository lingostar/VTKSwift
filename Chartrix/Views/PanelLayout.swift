import Foundation
import SwiftUI
import Combine

// MARK: - Per-Panel State

/// State for a single viewer panel. Reference type so multiple views can observe it.
@MainActor
final class PanelState: ObservableObject, Identifiable {
    let id: UUID

    @Published var study: Study?
    @Published var mode: PanelMode = .dicom

    // MARK: DICOM state
    @Published var sliceImage: CGImage?
    @Published var totalSlices: Int = 0
    @Published var currentSlice: Int = 0
    @Published var isLoadingDICOM = false

    // MARK: Volume state
    @Published var bridge: VTKBridge?
    @Published var volumeLoaded = false
    @Published var volumeLoading = false
    @Published var ctPreset: CTPreset = .softTissue
    @Published var opacityScale: Double = 1.0

    // MARK: Measurement state
    @Published var measureMode: MeasureMode = .none
    @Published var currentPoints: [CGPoint] = []

    // MARK: iCloud download state
    @Published var isDownloadingFromICloud = false
    @Published var downloadState: ICloudDownloadMonitor.State = .idle
    private let downloadMonitor = ICloudDownloadMonitor()
    private var downloadObserver: AnyCancellable?

    init(id: UUID = UUID(), study: Study? = nil) {
        self.id = id
        self.study = study

        // Forward download monitor state changes to our @Published property
        // and trigger loading once download completes.
        downloadObserver = downloadMonitor.$state.sink { [weak self] newState in
            DispatchQueue.main.async {
                self?.handleDownloadStateChange(newState)
            }
        }
    }

    deinit {
        downloadMonitor.cleanup()
    }

    // MARK: - DICOM Loading

    func loadInitialDICOMSlice() {
        guard let study = study,
              let dirURL = ChartStorage.dicomDirectoryURL(for: study) else {
            isLoadingDICOM = false
            return
        }
        isLoadingDICOM = true
        DispatchQueue.global(qos: .userInitiated).async {
            let files = DICOMSliceRenderer.sortedDICOMFiles(in: dirURL)
            let mid = max(0, files.count / 2)
            let image = DICOMSliceRenderer.renderSlice(directoryURL: dirURL, sliceIndex: mid)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.totalSlices = files.count
                self.currentSlice = mid
                self.sliceImage = image
                self.isLoadingDICOM = false
            }
        }
    }

    func loadDICOMSlice(at index: Int) {
        guard let study = study,
              let dirURL = ChartStorage.dicomDirectoryURL(for: study) else { return }
        let clamped = min(max(0, index), max(0, totalSlices - 1))
        currentSlice = clamped
        DispatchQueue.global(qos: .userInitiated).async {
            let image = DICOMSliceRenderer.renderSlice(directoryURL: dirURL, sliceIndex: clamped)
            DispatchQueue.main.async { [weak self] in
                self?.sliceImage = image
            }
        }
    }

    // MARK: - Volume Loading

    func loadVolume() {
        guard let study = study,
              let path = ChartStorage.dicomDirectoryURL(for: study)?.path else {
            volumeLoading = false
            return
        }
        volumeLoading = true
        volumeLoaded = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            let b = VTKBridge(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
            if b.loadVolume(fromDICOMDirectory: path) {
                self.bridge = b
                b.apply(self.ctPreset.vtkPreset)
                b.setVolumeOpacityScale(self.opacityScale)
                self.volumeLoaded = true
            }
            self.volumeLoading = false
        }
    }

    func unloadVolume() {
        bridge = nil
        volumeLoaded = false
        volumeLoading = false
    }

    /// Switch to a different study. Resets DICOM/Volume state.
    func setStudy(_ newStudy: Study?) {
        sliceImage = nil
        totalSlices = 0
        currentSlice = 0
        unloadVolume()
        isDownloadingFromICloud = false
        downloadState = .idle
        downloadMonitor.stopMonitoring()

        study = newStudy
        if newStudy != nil {
            beginLoadingForCurrentMode()
        }
    }

    func setMode(_ newMode: PanelMode) {
        guard newMode != mode else { return }
        mode = newMode
        guard study != nil else { return }

        // If a download is already in progress, the completion handler will trigger
        // loading for whatever mode is current at that time.
        if isDownloadingFromICloud { return }

        switch newMode {
        case .dicom:
            unloadVolume()
            if sliceImage == nil { beginLoadingForCurrentMode() }
        case .volume:
            if !volumeLoaded { beginLoadingForCurrentMode() }
        }
    }

    /// Check iCloud download status, then either load directly or wait for download.
    private func beginLoadingForCurrentMode() {
        guard let study = study else { return }
        let status = ChartStorage.downloadStatus(for: study)
        switch status {
        case .local, .downloaded:
            switch mode {
            case .dicom: loadInitialDICOMSlice()
            case .volume: loadVolume()
            }
        case .notDownloaded, .downloading:
            isDownloadingFromICloud = true
            isLoadingDICOM = false
            downloadMonitor.startMonitoring(study: study)
        }
    }

    private func handleDownloadStateChange(_ newState: ICloudDownloadMonitor.State) {
        downloadState = newState
        switch newState {
        case .completed:
            isDownloadingFromICloud = false
            guard study != nil else { return }
            switch mode {
            case .dicom: loadInitialDICOMSlice()
            case .volume: loadVolume()
            }
        case .failed:
            isDownloadingFromICloud = false
            // Keep .failed state so UI can display the error message.
        default:
            break
        }
    }
}

enum PanelMode {
    case dicom
    case volume
}

// MARK: - Layout Manager (regular grid: rows × cols, each 1 or 2)

/// Manages a regular grid of viewer panels (max 2×2).
/// Splitting in one direction adds panels equal to the count in the other direction.
@MainActor
final class ViewerLayoutManager: ObservableObject {
    @Published private(set) var rows: Int = 1
    @Published private(set) var cols: Int = 1
    @Published private(set) var panels: [[PanelState]]

    /// Width ratio of the left column (0.2 ... 0.8). Used when cols == 2.
    @Published var colRatio: Double = 0.5

    /// Height ratio of the top row (0.2 ... 0.8). Used when rows == 2.
    @Published var rowRatio: Double = 0.5

    /// Forward each panel's objectWillChange to the manager so views observing
    /// the manager (e.g. shared bottom controls) re-render on per-panel state changes.
    private var panelSubscriptions: [UUID: AnyCancellable] = [:]

    init() {
        let initial = PanelState()
        self.panels = [[initial]]
        subscribe(to: initial)
    }

    private func subscribe(to panel: PanelState) {
        let cancellable = panel.objectWillChange.sink { [weak self] in
            // Bounce to next runloop to avoid "Publishing changes from within view updates"
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }
        panelSubscriptions[panel.id] = cancellable
    }

    private func unsubscribe(panel: PanelState) {
        panelSubscriptions.removeValue(forKey: panel.id)
    }

    var totalPanelCount: Int { rows * cols }

    /// Whether a horizontal split (adding a column) is allowed.
    var canSplitHorizontal: Bool { cols < 2 }

    /// Whether a vertical split (adding a row) is allowed.
    var canSplitVertical: Bool { rows < 2 }

    /// Whether any panel can be closed (must keep ≥ 1 panel).
    var canClose: Bool { totalPanelCount > 1 }

    /// Add a column. New panels are appended to each existing row (count = rows).
    func splitHorizontal() {
        guard canSplitHorizontal else { return }
        for r in 0..<rows {
            let newPanel = PanelState()
            panels[r].append(newPanel)
            subscribe(to: newPanel)
        }
        cols += 1
    }

    /// Add a row. New panels make up the new row (count = cols).
    func splitVertical() {
        guard canSplitVertical else { return }
        let newRow = (0..<cols).map { _ -> PanelState in
            let p = PanelState()
            subscribe(to: p)
            return p
        }
        panels.append(newRow)
        rows += 1
    }

    /// Close the given panel. Collapses to a smaller regular grid.
    /// - 1×2 / 2×1 → 1×1: removes only that panel.
    /// - 2×2 → 1×2: removes the entire row containing the panel.
    func close(panel: PanelState) {
        guard canClose else { return }
        guard let pos = position(of: panel) else { return }
        let r = pos.row
        let c = pos.col

        if rows == 1 && cols == 2 {
            // 1×2 → 1×1
            let removed = panels[0].remove(at: c)
            unsubscribe(panel: removed)
            cols = 1
        } else if rows == 2 && cols == 1 {
            // 2×1 → 1×1
            let row = panels.remove(at: r)
            for p in row { unsubscribe(panel: p) }
            rows = 1
        } else if rows == 2 && cols == 2 {
            // 2×2 → 1×2 (remove the row containing the panel)
            let row = panels.remove(at: r)
            for p in row { unsubscribe(panel: p) }
            rows = 1
        }
    }

    func position(of panel: PanelState) -> (row: Int, col: Int)? {
        for r in 0..<rows {
            for c in 0..<cols where panels[r][c] === panel {
                return (r, c)
            }
        }
        return nil
    }

    // MARK: - Helpers

    /// All panels, flattened in row-major order.
    var allPanels: [PanelState] {
        panels.flatMap { $0 }
    }

    /// DICOM-mode panels with a study and slice data loaded.
    var activeDICOMPanels: [PanelState] {
        allPanels.filter { $0.mode == .dicom && $0.study != nil && $0.totalSlices > 0 }
    }

    /// Maximum slice count among active DICOM panels.
    var maxSliceCount: Int {
        activeDICOMPanels.map(\.totalSlices).max() ?? 0
    }

    /// Common slice index for sync slider (taken from first active DICOM panel).
    var syncedSliceIndex: Int {
        activeDICOMPanels.first?.currentSlice ?? 0
    }

    /// Apply a synced slice index across all active DICOM panels (clamped per panel).
    func setSyncedSlice(_ value: Int) {
        for p in activeDICOMPanels {
            let clamped = min(value, max(0, p.totalSlices - 1))
            if p.currentSlice != clamped {
                p.loadDICOMSlice(at: clamped)
            }
        }
    }

    /// Compatibility warnings across active DICOM panels.
    var compatibilityWarnings: [String] {
        let panels = activeDICOMPanels
        guard panels.count >= 2 else { return [] }

        var warnings: [String] = []

        let modalities = Set(panels.compactMap { $0.study?.modality })
        if modalities.count > 1 {
            warnings.append("Different modalities: \(modalities.sorted().joined(separator: ", "))")
        }

        let counts = panels.map(\.totalSlices)
        if let mn = counts.min(), let mx = counts.max(), mn > 0,
           Double(mx) / Double(mn) > 1.25 {
            warnings.append("Slice counts differ significantly (\(mn) vs \(mx))")
        }

        return warnings
    }
}
