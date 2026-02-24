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
    var loadedPath: String?
    /// Security-scoped bookmark data for sandboxed re-access.
    var bookmarkData: Data?
}

// MARK: - DICOM View

/// Displays DICOM medical images using VTK with slice navigation.
struct DICOMView: View {
    @ObservedObject var state: DICOMViewState
    @State private var showFilePicker = false

    var body: some View {
        VStack(spacing: 0) {
            if state.isLoaded {
                // DICOM VTK rendering view
                DICOMRenderView(state: state)
                    .ignoresSafeArea()

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
                           in: state.sliceMin...max(state.sliceMin, state.sliceMax),
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

            loadDICOM(from: url.path)

            if didStart { url.stopAccessingSecurityScopedResource() }

        case .failure(let error):
            state.errorMessage = error.localizedDescription
        }
    }

    private func loadDICOM(from path: String) {
        state.errorMessage = nil

        let newBridge = VTKBridge(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let success = newBridge.loadDICOMDirectory(path)

        if success {
            state.bridge = newBridge
            state.sliceMin = Double(newBridge.sliceMin)
            state.sliceMax = Double(newBridge.sliceMax)
            state.sliceIndex = Double(newBridge.currentSlice)
            state.loadedPath = path
            state.isLoaded = true
        } else {
            state.errorMessage = "Failed to load DICOM files from selected directory."
        }
    }
}

// MARK: - DICOM Render View (Platform-specific)
// Uses Coordinator pattern: creates a fresh VTKBridge each time the
// NSView/UIView is created, reloading data from the stored path.
// This avoids stale OpenGL context when SwiftUI recreates the view.

#if os(iOS)
private struct DICOMRenderView: UIViewRepresentable {
    @ObservedObject var state: DICOMViewState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeUIView(context: Context) -> UIView {
        let bridge = VTKBridge(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        context.coordinator.bridge = bridge

        // Reload data if previously loaded
        if let path = resolveAccessiblePath() {
            let success = bridge.loadDICOMDirectory(path)
            if success {
                bridge.setSlice(Int(state.sliceIndex))
                state.bridge = bridge
            }
        }

        let view = bridge.renderView
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            bridge.render()
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

        // Reload data if previously loaded
        if let path = resolveAccessiblePath() {
            let success = bridge.loadDICOMDirectory(path)
            if success {
                bridge.setSlice(Int(state.sliceIndex))
                state.bridge = bridge
            }
        }

        let view = bridge.renderView
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            bridge.render()
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
