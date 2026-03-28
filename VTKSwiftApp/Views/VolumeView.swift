import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - CT Preset Model

/// Maps VTKVolumePreset enum to user-facing names and icons.
enum CTPreset: Int, CaseIterable, Identifiable {
    case softTissue = 0
    case bone = 1
    case lung = 2
    case brain = 3
    case abdomen = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .softTissue: return "Soft Tissue"
        case .bone:       return "Bone"
        case .lung:       return "Lung"
        case .brain:      return "Brain"
        case .abdomen:    return "Abdomen"
        }
    }

    var icon: String {
        switch self {
        case .softTissue: return "figure.stand"
        case .bone:       return "figure.walk"
        case .lung:       return "lungs"
        case .brain:      return "brain.head.profile"
        case .abdomen:    return "stomach"
        }
    }

    /// Convert to VTKVolumePreset (NSInteger-based enum).
    var vtkPreset: VTKVolumePreset {
        VTKVolumePreset(rawValue: rawValue) ?? .softTissue
    }
}

// MARK: - Volume View State

/// Persists volume rendering state across NavigationSplitView re-navigation.
/// Owned by ContentView as @StateObject so it survives detail-view recreation.
final class VolumeViewState: ObservableObject {
    @Published var bridge: VTKBridge?
    @Published var isLoaded = false
    @Published var selectedPreset: CTPreset = .softTissue
    @Published var opacityScale: Double = 1.0
    @Published var errorMessage: String?
    @Published var isLoading = false

    /// Path of the loaded DICOM directory (for reload on view recreation).
    @Published var loadedPath: String?
    /// Security-scoped bookmark data for sandboxed re-access.
    var bookmarkData: Data?
}

// MARK: - Volume View

/// Displays DICOM data as a 3D volume rendering with CT presets.
struct VolumeView: View {
    @ObservedObject var state: VolumeViewState
    @State private var showFilePicker = false
    @State private var showExportSheet = false
    @StateObject private var exportState = ExportState()

    var body: some View {
        VStack(spacing: 0) {
            if state.isLoaded {
                // 3D Volume rendering view.
                // .id(loadedPath) forces SwiftUI to destroy & recreate the
                // Representable when the user opens a different DICOM folder.
                VolumeRenderView(state: state)
                    .id(state.loadedPath)
                    .ignoresSafeArea()

                // Controls overlay
                VStack(spacing: 8) {
                    // Preset picker
                    HStack {
                        Text("CT Preset")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CTPreset.allCases) { preset in
                                presetButton(preset)
                            }
                        }
                    }

                    // Opacity slider
                    HStack {
                        Text("Opacity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $state.opacityScale, in: 0.1...2.0, step: 0.05)
                            .onChange(of: state.opacityScale) { newValue in
                                state.bridge?.setVolumeOpacityScale(newValue)
                            }
                        Text(String(format: "%.0f%%", state.opacityScale * 100))
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            } else {
                // Empty state — prompt user to load DICOM for volume rendering
                VStack(spacing: 16) {
                    if state.isLoading {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading volume data...")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        Text("3D Volume Rendering")
                            .font(.title2)

                        Text("Select a folder containing DICOM (.dcm) files\nfor 3D volume visualization")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .multilineTextAlignment(.center)

                        Button {
                            showFilePicker = true
                        } label: {
                            Label("Open DICOM Folder...", systemImage: "folder")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)

                        if let errorMessage = state.errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("3D Volume")
        .toolbar {
            if state.isLoaded {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Open Folder", systemImage: "folder")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showExportSheet = true
                    } label: {
                        Label("Export 3D", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheetView(exportState: exportState, bridge: state.bridge)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
    }

    // MARK: - Preset Button

    @ViewBuilder
    private func presetButton(_ preset: CTPreset) -> some View {
        Button {
            state.selectedPreset = preset
            state.bridge?.apply(preset.vtkPreset)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: preset.icon)
                    .font(.title3)
                Text(preset.title)
                    .font(.caption2)
            }
            .frame(width: 64, height: 48)
            .background(
                state.selectedPreset == preset
                    ? Color.accentColor.opacity(0.2)
                    : Color.clear
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        state.selectedPreset == preset
                            ? Color.accentColor
                            : Color.gray.opacity(0.3),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - File Handling

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            prepareVolume(from: url)

        case .failure(let error):
            state.errorMessage = error.localizedDescription
        }
    }

    /// Validate the DICOM directory for volume rendering, save metadata, and
    /// trigger view creation.  The actual VTKBridge is created only in
    /// VolumeRenderView.makeNSView/makeUIView.
    private func prepareVolume(from url: URL) {
        state.errorMessage = nil
        state.isLoading = true

        let didStart = url.startAccessingSecurityScopedResource()

        // Save bookmark for future re-access
        #if os(macOS)
        state.bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        state.bookmarkData = try? url.bookmarkData(
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif

        // Quick-validate: use a temporary bridge to check DICOM volume data.
        // asyncAfter lets SwiftUI render the loading indicator first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let tempBridge = VTKBridge(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            let success = tempBridge.loadVolume(fromDICOMDirectory: url.path)

            if didStart { url.stopAccessingSecurityScopedResource() }

            state.isLoading = false
            if success {
                state.selectedPreset = .softTissue
                state.opacityScale = 1.0
                state.loadedPath = url.path
                // bridge is intentionally NOT stored — VolumeRenderView creates its own.
                state.isLoaded = true
            } else {
                state.errorMessage = "Failed to load volume from selected directory.\nEnsure the folder contains valid DICOM files."
            }
            // tempBridge deallocates here — only used for validation.
        }
    }
}

// MARK: - Volume Render View (Platform-specific)
// Uses Coordinator pattern: creates a fresh VTKBridge each time the
// NSView/UIView is created, reloading data from the stored path.
// This avoids stale OpenGL context when SwiftUI recreates the view.

#if os(iOS)
private struct VolumeRenderView: UIViewRepresentable {
    @ObservedObject var state: VolumeViewState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeUIView(context: Context) -> UIView {
        let bridge = VTKBridge(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        context.coordinator.bridge = bridge

        // Load volume data (no rendering — that waits until view is in hierarchy)
        if let path = resolveAccessiblePath() {
            _ = bridge.loadVolume(fromDICOMDirectory: path)
        }

        let view = bridge.renderView
        // Defer all state updates & rendering until the view is in the hierarchy.
        // Setting @Published in makeUIView causes "Publishing changes from within
        // view updates" and undefined SwiftUI behavior.
        let preset = state.selectedPreset.vtkPreset
        let opacity = state.opacityScale
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.state.bridge = bridge
            bridge.apply(preset)
            bridge.setVolumeOpacityScale(opacity)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let bridge = context.coordinator.bridge else { return }
        let size = uiView.bounds.size
        if size.width > 0 && size.height > 0 {
            bridge.resize(to: size)
        }
    }

    private func resolveAccessiblePath() -> String? {
        if let bookmarkData = state.bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                bookmarkDataIsStale: &isStale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                return url.path
            }
        }
        return state.loadedPath
    }

    class Coordinator {
        var bridge: VTKBridge?
        let state: VolumeViewState
        init(state: VolumeViewState) { self.state = state }
    }
}

#elseif os(macOS)
private struct VolumeRenderView: NSViewRepresentable {
    @ObservedObject var state: VolumeViewState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeNSView(context: Context) -> NSView {
        let bridge = VTKBridge(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        context.coordinator.bridge = bridge

        // Load volume data (no rendering — that waits until view is in hierarchy)
        if let path = resolveAccessiblePath() {
            _ = bridge.loadVolume(fromDICOMDirectory: path)
        }

        let view = bridge.renderView
        // Defer all state updates & rendering until the view is in the hierarchy.
        // Setting @Published in makeNSView causes "Publishing changes from within
        // view updates" and undefined SwiftUI behavior.
        let preset = state.selectedPreset.vtkPreset
        let opacity = state.opacityScale
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.state.bridge = bridge
            bridge.apply(preset)
            bridge.setVolumeOpacityScale(opacity)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let bridge = context.coordinator.bridge else { return }
        let size = nsView.bounds.size
        if size.width > 0 && size.height > 0 {
            bridge.resize(to: size)
        }
    }

    private func resolveAccessiblePath() -> String? {
        if let bookmarkData = state.bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                return url.path
            }
        }
        return state.loadedPath
    }

    class Coordinator {
        var bridge: VTKBridge?
        let state: VolumeViewState
        init(state: VolumeViewState) { self.state = state }
    }
}
#endif
