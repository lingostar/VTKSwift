import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - DICOM View State

/// Persists DICOM viewer state across NavigationSplitView re-navigation.
/// Owned by ContentView as @StateObject so it survives detail-view recreation.
final class DICOMViewState: ObservableObject {
    @Published var bridge: VTKBridge?
    @Published var isLoaded = false
    @Published var sliceIndex: Double = 0
    @Published var sliceMin: Double = 0
    @Published var sliceMax: Double = 0
    @Published var errorMessage: String?

    /// Path of the loaded DICOM directory (for reload on view recreation).
    @Published var loadedPath: String?
    /// Security-scoped bookmark data for sandboxed re-access.
    var bookmarkData: Data?
}

// MARK: - DICOM View

/// Displays DICOM medical images using VTK with slice navigation.
struct DICOMView: View {
    @ObservedObject var state: DICOMViewState
    @State private var showFilePicker = false
    @StateObject private var measurementState = MeasurementState()

    var body: some View {
        VStack(spacing: 0) {
            if state.isLoaded {
                // DICOM VTK rendering view with measurement overlay.
                ZStack {
                    DICOMRenderView(state: state)
                        .id(state.loadedPath)

                    MeasurementOverlayView(state: measurementState)

                    // Measurement results panel (top-right)
                    VStack {
                        HStack {
                            Spacer()
                            MeasurementResultsPanel(state: measurementState)
                                .padding(8)
                        }
                        Spacer()
                    }
                }
                .ignoresSafeArea()

                // Measurement toolbar
                MeasurementToolbar(state: measurementState)
                    .padding(.top, 4)

                // Slice navigation controls
                VStack(spacing: 8) {
                    HStack {
                        Text("Slice: \(Int(state.sliceIndex))")
                            .monospacedDigit()
                        Spacer()
                        Text("\(Int(state.sliceMin))–\(Int(state.sliceMax))")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                    Slider(value: $state.sliceIndex,
                           in: state.sliceMin...max(state.sliceMin + 1, state.sliceMax),
                           step: 1)
                    .onChange(of: state.sliceIndex) { newValue in
                        state.bridge?.setSlice(Int(newValue))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            } else {
                // Empty state — prompt user to load DICOM
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.image")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("Load DICOM Directory")
                        .font(.title2)

                    Text("Select a folder containing DICOM (.dcm) files")
                        .foregroundStyle(.secondary)
                        .font(.callout)

                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Open Folder...", systemImage: "folder")
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("DICOM Reader")
        .toolbar {
            if state.isLoaded {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Open Folder", systemImage: "folder")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .onChange(of: state.isLoaded) { loaded in
            if loaded, let bridge = state.bridge {
                updateMeasurementSpacing(from: bridge)
            }
        }
    }

    private func updateMeasurementSpacing(from bridge: VTKBridge) {
        let px = bridge.pixelSpacingX
        let py = bridge.pixelSpacingY
        if px > 0 { measurementState.pixelSpacingX = px }
        if py > 0 { measurementState.pixelSpacingY = py }
        let w = bridge.imageWidth
        let h = bridge.imageHeight
        if w > 0 { measurementState.imageWidth = Int(w) }
        if h > 0 { measurementState.imageHeight = Int(h) }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

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

            prepareDICOM(from: url.path)

            if didStart { url.stopAccessingSecurityScopedResource() }

        case .failure(let error):
            state.errorMessage = error.localizedDescription
        }
    }

    /// Validate the DICOM directory, save metadata, and trigger view creation.
    /// The actual VTKBridge is created only in DICOMRenderView.makeNSView/makeUIView.
    private func prepareDICOM(from path: String) {
        state.errorMessage = nil

        // Quick-validate: use a temporary bridge to read DICOM metadata
        let tempBridge = VTKBridge(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        let success = tempBridge.loadDICOMDirectory(path)

        if success {
            state.sliceMin = Double(tempBridge.sliceMin)
            state.sliceMax = Double(tempBridge.sliceMax)
            state.sliceIndex = Double(tempBridge.currentSlice)
            state.loadedPath = path
            // bridge is intentionally NOT stored — DICOMRenderView creates its own.
            state.isLoaded = true
        } else {
            state.errorMessage = "Failed to load DICOM files from selected directory."
        }
        // tempBridge deallocates here — only used for validation & metadata.
    }
}

// MARK: - DICOM Render View (Platform-specific)
// Uses Coordinator pattern: creates a fresh VTKBridge each time the
// NSView/UIView is created, reloading data from the stored path.
// This avoids stale OpenGL/Metal context when SwiftUI recreates the view.

#if os(iOS)
private struct DICOMRenderView: UIViewRepresentable {
    @ObservedObject var state: DICOMViewState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeUIView(context: Context) -> UIView {
        let bridge = VTKBridge(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        context.coordinator.bridge = bridge

        // Load DICOM data (no rendering — that waits until view is in hierarchy)
        if let path = resolveAccessiblePath() {
            _ = bridge.loadDICOMDirectory(path)
        }

        let view = bridge.renderView
        // Defer all state updates & rendering until the view is in the hierarchy.
        // Setting @Published in makeUIView causes "Publishing changes from within
        // view updates" and undefined SwiftUI behavior.
        let sliceToRestore = Int(state.sliceIndex)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.state.bridge = bridge
            bridge.setSlice(sliceToRestore)
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
        let state: DICOMViewState
        init(state: DICOMViewState) { self.state = state }
    }
}

#elseif os(macOS)
private struct DICOMRenderView: NSViewRepresentable {
    @ObservedObject var state: DICOMViewState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeNSView(context: Context) -> NSView {
        let bridge = VTKBridge(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        context.coordinator.bridge = bridge

        // Load DICOM data (no rendering — that waits until view is in hierarchy)
        if let path = resolveAccessiblePath() {
            _ = bridge.loadDICOMDirectory(path)
        }

        let view = bridge.renderView
        // Defer all state updates & rendering until the view is in the hierarchy.
        // Setting @Published in makeNSView causes "Publishing changes from within
        // view updates" and undefined SwiftUI behavior.
        let sliceToRestore = Int(state.sliceIndex)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.state.bridge = bridge
            bridge.setSlice(sliceToRestore)
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
        let state: DICOMViewState
        init(state: DICOMViewState) { self.state = state }
    }
}
#endif
