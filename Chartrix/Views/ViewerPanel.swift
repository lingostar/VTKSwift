import SwiftUI

// MARK: - Viewer Panel

/// A single viewer panel — displays a DICOM study in either DICOM or Volume mode.
/// Includes per-panel mode toggle, +/✕ controls, and gear popover for mode-specific settings.
struct ViewerPanel: View {
    @ObservedObject var state: PanelState
    @ObservedObject var manager: ViewerLayoutManager
    let allStudies: [Study]
    let canSplitHorizontal: Bool
    let canSplitVertical: Bool
    let canClose: Bool
    let onSplitHorizontal: () -> Void
    let onSplitVertical: () -> Void
    let onClose: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var showGear = false

    /// When this panel is in Volume mode, find a sibling DICOM panel viewing the same study.
    private var matchingDICOMPanel: PanelState? {
        guard state.mode == .volume,
              let study = state.study else { return nil }
        return manager.allPanels.first { other in
            other !== state &&
            other.mode == .dicom &&
            other.study?.id == study.id &&
            other.totalSlices > 0
        }
    }

    /// Slice fraction (0..1) from the matching DICOM panel, or nil if no match.
    private var matchingSliceFraction: Double? {
        guard let p = matchingDICOMPanel, p.totalSlices > 1 else { return nil }
        return Double(p.currentSlice) / Double(p.totalSlices - 1)
    }

    /// Measurements for the panel's current slice
    private var currentMeasurements: [Measurement] {
        guard let study = state.study else { return [] }
        return (study.measurements ?? [])
            .filter { $0.sliceIndex == state.currentSlice }
            .sorted { $0.createdDate < $1.createdDate }
    }

    private var currentMeasureResults: [MeasureResult] {
        currentMeasurements.map { m in
            MeasureResult(type: m.mode, points: m.points, value: m.value)
        }
    }

    var body: some View {
        ZStack {
            // Content
            if state.study == nil {
                EmptyPanelView(studies: allStudies) { study in
                    state.setStudy(study)
                }
            } else {
                contentView
                    .overlay(alignment: .top) { topInfoBar }
            }
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1.5)
        )
        // Top-right controls — always present (close + mode toggle + gear)
        .overlay(alignment: .topTrailing) { topRightControls }
        // Split buttons on right and bottom edges (hidden when that direction is full)
        .overlay(alignment: .trailing) {
            if canSplitHorizontal {
                splitButton(action: onSplitHorizontal, hint: "Add column")
                    .offset(x: 14)
            }
        }
        .overlay(alignment: .bottom) {
            if canSplitVertical {
                splitButton(action: onSplitVertical, hint: "Add row")
                    .offset(y: 14)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch state.mode {
        case .dicom: dicomContent
        case .volume: volumeContent
        }
    }

    // MARK: - DICOM Content

    @ViewBuilder
    private var dicomContent: some View {
        ZStack {
            Color.black

            if state.isDownloadingFromICloud {
                iCloudDownloadOverlay
            } else if state.isLoadingDICOM {
                ProgressView().tint(.white)
            } else if let cgImage = state.sliceImage {
                GeometryReader { geo in
                    ZStack {
                        Image(decorative: cgImage, scale: 1.0)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        MeasureOverlay(
                            mode: state.measureMode,
                            currentPoints: $state.currentPoints,
                            results: currentMeasureResults,
                            viewSize: geo.size,
                            sliceImage: state.sliceImage,
                            onComplete: { result in
                                saveMeasurement(result)
                            }
                        )
                    }
                }
            } else {
                Text("No image data")
                    .foregroundStyle(.gray)
            }
        }
    }

    // MARK: - iCloud Download Overlay

    @ViewBuilder
    private var iCloudDownloadOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.85))
                .symbolEffect(.pulse)

            Text("Downloading from iCloud…")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))

            switch state.downloadState {
            case .downloading(let progress, let downloaded, let total):
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.cyan)
                        .frame(width: 160)
                    Text("\(downloaded) / \(total) files")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .monospacedDigit()
                }
            case .checking:
                ProgressView().tint(.white)
            case .failed(let message):
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.icloud")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            default:
                ProgressView().tint(.white)
            }
        }
    }

    private func saveMeasurement(_ result: MeasureResult) {
        guard let study = state.study else { return }
        let m = Measurement(
            measureType: result.type == .distance ? "distance" : "angle",
            sliceIndex: state.currentSlice,
            points: result.points,
            value: result.value
        )
        modelContext.insert(m)
        if study.measurements == nil { study.measurements = [] }
        study.measurements?.append(m)
        try? modelContext.save()
        state.currentPoints = []
    }

    // MARK: - Volume Content

    @ViewBuilder
    private var volumeContent: some View {
        ZStack {
            Color.black

            if state.isDownloadingFromICloud {
                iCloudDownloadOverlay
            } else if state.volumeLoaded {
                VolumeRenderWrap(bridge: bridgeBinding)
            } else if state.volumeLoading {
                VStack(spacing: 8) {
                    ProgressView().tint(.white).scaleEffect(1.2)
                    Text("Loading volume...")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Volume rendering unavailable")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .onChange(of: matchingSliceFraction) { _, newValue in
            updateSlicePlane(fraction: newValue)
        }
        .onChange(of: state.volumeLoaded) { _, loaded in
            if loaded { updateSlicePlane(fraction: matchingSliceFraction) }
        }
    }

    /// Update the VTK slice plane to reflect the matching DICOM panel's current slice.
    private func updateSlicePlane(fraction: Double?) {
        guard let bridge = state.bridge else { return }
        if let f = fraction {
            bridge.setSlicePlaneZFraction(f)
            bridge.setSlicePlaneVisible(true)
        } else {
            bridge.setSlicePlaneVisible(false)
        }
    }

    /// Helper binding for VolumeRenderWrap (which expects `@Binding<VTKBridge?>`).
    private var bridgeBinding: Binding<VTKBridge?> {
        Binding(
            get: { state.bridge },
            set: { state.bridge = $0 }
        )
    }

    // MARK: - Top Info Bar (gray text)

    @ViewBuilder
    private var topInfoBar: some View {
        if let study = state.study {
            HStack(spacing: 6) {
                Text(study.modality)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(study.modalityColor.opacity(0.7), in: Capsule())
                    .foregroundStyle(.white)

                if !study.studyDate.isEmpty {
                    Text(study.formattedStudyDate)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }

                if state.mode == .dicom && state.totalSlices > 0 {
                    Text("· \(state.totalSlices) slices")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                }

                if !study.studyDescription.isEmpty {
                    Text("· \(study.studyDescription)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
    }

    // MARK: - Top Right Controls

    @ViewBuilder
    private var topRightControls: some View {
        HStack(spacing: 6) {
            // Mode toggle + gear only when study loaded
            if state.study != nil {
                modeToggle

                if state.mode == .volume {
                    Button { showGear.toggle() } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                    .popover(isPresented: $showGear, arrowEdge: .top) {
                        volumeGearContent
                            .padding(12)
                            .frame(minWidth: 220)
                    }
                }
            }

            // Close — always available when allowed (works for both empty and loaded panels)
            if canClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
    }

    // MARK: - Mode Toggle

    private var modeToggle: some View {
        HStack(spacing: 0) {
            modeButton(.dicom, label: "DICOM")
            modeButton(.volume, label: "Volume")
        }
        .padding(2)
        .background(.black.opacity(0.5), in: Capsule())
    }

    private func modeButton(_ mode: PanelMode, label: String) -> some View {
        Button {
            state.setMode(mode)
        } label: {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(state.mode == mode ? .black : .white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    state.mode == mode ? Color.white : Color.clear,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Volume Gear Popover

    private var volumeGearContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Volume Settings")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            // CT Presets
            VStack(alignment: .leading, spacing: 6) {
                Text("CT Preset").font(.caption2).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(CTPreset.allCases) { preset in
                            Button {
                                state.ctPreset = preset
                                state.bridge?.apply(preset.vtkPreset)
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: preset.icon).font(.caption)
                                    Text(preset.title).font(.caption2)
                                }
                                .frame(width: 56, height: 40)
                                .background(state.ctPreset == preset ? Color.accentColor.opacity(0.2) : Color.clear)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(state.ctPreset == preset ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Opacity
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Opacity").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f%%", state.opacityScale * 100))
                        .font(.caption2).monospacedDigit()
                }
                Slider(value: $state.opacityScale, in: 0.1...2.0, step: 0.05)
                    .onChange(of: state.opacityScale) { _, val in
                        state.bridge?.setVolumeOpacityScale(val)
                    }
            }
        }
    }

    // MARK: - Split Buttons

    private func splitButton(action: @escaping () -> Void, hint: String) -> some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(7)
                .background(Color.accentColor.opacity(0.85), in: Circle())
                .shadow(radius: 2)
        }
        .buttonStyle(.plain)
        .help(hint)
    }
}
