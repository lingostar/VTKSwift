import SwiftUI
import SceneKit
import ModelIO
#if os(macOS)
import AppKit
#else
import QuickLook
#endif

// MARK: - HU Preset Model

/// Hounsfield Unit presets for isosurface extraction.
enum HUPreset: Int, CaseIterable, Identifiable {
    case skin = 0
    case softTissue = 1
    case bone = 2
    case denseBone = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .skin:       return "Skin"
        case .softTissue: return "Soft Tissue"
        case .bone:       return "Bone"
        case .denseBone:  return "Dense Bone"
        }
    }

    var icon: String {
        switch self {
        case .skin:       return "figure.stand"
        case .softTissue: return "heart"
        case .bone:       return "figure.walk"
        case .denseBone:  return "shield"
        }
    }

    var isoValue: Double {
        switch self {
        case .skin:       return -500
        case .softTissue: return 0
        case .bone:       return 300
        case .denseBone:  return 700
        }
    }
}

// MARK: - USDZ View State

/// Persists DICOM-to-USDZ state across NavigationSplitView re-navigation.
/// Owned by ContentView as @StateObject.
final class USDZViewState: ObservableObject {
    @Published var isLoaded = false
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var usdzURL: URL?
    @Published var loadedPath: String?
    @Published var isoValue: Double = 300       // Default: bone
    @Published var decimation: Double = 0.8     // 80% reduction
    @Published var smoothing: Bool = true
    @Published var triangleCount: Int = 0
    @Published var selectedPreset: HUPreset = .bone

    /// Scene loaded from the generated USDZ, used by SceneView.
    @Published var scene: SCNScene?

    /// VTKBridge kept alive for re-extraction with different parameters.
    /// NOT @Published — no rendering, just a computation engine.
    var bridge: VTKBridge?

    /// Security-scoped bookmark for sandboxed re-access.
    var bookmarkData: Data?
}

// MARK: - USDZ View

/// Converts DICOM data to a 3D isosurface mesh and exports as USDZ for viewing.
struct USDZView: View {
    @ObservedObject var state: USDZViewState
    @State private var showFilePicker = false
    @State private var showQuickLook = false

    var body: some View {
        VStack(spacing: 0) {
            if state.isLoaded, let scene = state.scene {
                // 3D scene viewer
                SceneView(
                    scene: scene,
                    options: [.allowsCameraControl, .autoenablesDefaultLighting]
                )
                .ignoresSafeArea()

                // Controls overlay
                controlsPanel
            } else {
                // Empty / loading state
                emptyState
            }
        }
        .navigationTitle("DICOM USDZ")
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
        #if os(iOS)
        .quickLookPreview(quickLookURL)
        #endif
    }

    #if os(iOS)
    /// Binding for QuickLook preview on iOS.
    private var quickLookURL: Binding<URL?> {
        Binding(
            get: { showQuickLook ? state.usdzURL : nil },
            set: { if $0 == nil { showQuickLook = false } }
        )
    }
    #endif

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            if state.isProcessing {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Extracting isosurface...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "rotate.3d")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("DICOM → USDZ")
                    .font(.title2)

                Text("Select a DICOM folder to extract\na 3D isosurface and export as USDZ")
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
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Controls Panel

    @ViewBuilder
    private var controlsPanel: some View {
        VStack(spacing: 8) {
            // HU Threshold
            HStack {
                Text("HU Threshold")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f", state.isoValue))
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }

            Slider(value: $state.isoValue, in: -1000...3000, step: 10)

            // Presets
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HUPreset.allCases) { preset in
                        presetButton(preset)
                    }
                }
            }

            // Decimation
            HStack {
                Text("Decimation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $state.decimation, in: 0...0.95, step: 0.05)
                Text(String(format: "%.0f%%", state.decimation * 100))
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }

            // Smooth + Actions
            HStack {
                Toggle("Smooth", isOn: $state.smoothing)
                    .font(.caption)
                    .toggleStyle(.switch)
                    .fixedSize()

                Spacer()

                if state.triangleCount > 0 {
                    Text("\(state.triangleCount.formatted()) triangles")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    regenerate()
                } label: {
                    Label(state.isProcessing ? "Processing..." : "Regenerate",
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isProcessing)

                #if os(iOS)
                Button {
                    showQuickLook = true
                } label: {
                    Label("Quick Look", systemImage: "eye")
                }
                .buttonStyle(.bordered)
                .disabled(state.usdzURL == nil)
                #endif

                if let usdzURL = state.usdzURL {
                    #if os(macOS)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([usdzURL])
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    #endif

                    ShareLink(item: usdzURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Preset Button

    @ViewBuilder
    private func presetButton(_ preset: HUPreset) -> some View {
        Button {
            state.selectedPreset = preset
            state.isoValue = preset.isoValue
        } label: {
            VStack(spacing: 4) {
                Image(systemName: preset.icon)
                    .font(.title3)
                Text(preset.title)
                    .font(.caption2)
            }
            .frame(width: 72, height: 48)
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
            loadAndConvert(from: url)

        case .failure(let error):
            state.errorMessage = error.localizedDescription
        }
    }

    /// Load DICOM data and convert to USDZ.
    private func loadAndConvert(from url: URL) {
        // Reset all previous state so the view shows ProgressView
        state.isLoaded = false
        state.scene = nil
        state.usdzURL = nil
        state.bridge = nil
        state.triangleCount = 0
        state.errorMessage = nil
        state.isProcessing = true

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

        let path = url.path

        // Dispatch to let UI show the processing indicator
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Create bridge (1×1 — used only as computation engine, no rendering)
            let bridge = VTKBridge(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            let loadSuccess = bridge.loadDICOMDirectory(path)

            if didStart { url.stopAccessingSecurityScopedResource() }

            guard loadSuccess else {
                state.isProcessing = false
                state.errorMessage = "Failed to load DICOM files from selected directory."
                return
            }

            state.bridge = bridge
            state.loadedPath = path

            // Run extraction
            performExtraction(bridge: bridge)
        }
    }

    /// Re-run extraction with current parameters using the stored bridge.
    private func regenerate() {
        guard let bridge = state.bridge else { return }
        state.isProcessing = true
        state.errorMessage = nil

        // If we have a bookmark, re-access the DICOM directory
        resolveAccessForRegeneration()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            performExtraction(bridge: bridge)
        }
    }

    /// Core extraction: MarchingCubes → STL → USDZ → SceneView.
    private func performExtraction(bridge: VTKBridge) {
        let tempDir = FileManager.default.temporaryDirectory
        let stlURL = tempDir.appendingPathComponent("dicom_surface.stl")
        let usdzURL = tempDir.appendingPathComponent("dicom_surface.usdz")

        // Clean up old files
        try? FileManager.default.removeItem(at: stlURL)
        try? FileManager.default.removeItem(at: usdzURL)

        let stlSuccess = bridge.exportIsosurface(
            asSTL: stlURL.path,
            isoValue: state.isoValue,
            decimationRate: state.decimation,
            smoothing: state.smoothing
        )

        guard stlSuccess else {
            state.isProcessing = false
            state.errorMessage = "Failed to extract isosurface.\nTry adjusting the HU threshold."
            return
        }

        // Read triangle count from STL header
        if let data = try? Data(contentsOf: stlURL), data.count >= 84 {
            let count: UInt32 = data.subdata(in: 80..<84).withUnsafeBytes { $0.load(as: UInt32.self) }
            state.triangleCount = Int(count)
        }

        // Load STL into SceneKit scene via ModelIO
        guard let scene = Self.loadSTLAsScene(stlURL: stlURL) else {
            state.isProcessing = false
            state.errorMessage = "Failed to load STL as SceneKit scene."
            return
        }

        Self.applyMedicalMaterial(to: scene)

        // Write USDZ file for Share / QuickLook / Reveal
        let usdzWritten = scene.write(
            to: usdzURL, options: nil,
            delegate: nil, progressHandler: nil
        )
        if !usdzWritten {
            NSLog("[USDZView] Warning: USDZ file write failed, but scene is available for display")
        }

        state.scene = scene
        state.usdzURL = usdzWritten ? usdzURL : nil
        state.isLoaded = true
        state.isProcessing = false
    }

    // MARK: - STL → SCNScene Loading

    /// Load a binary STL file into an SCNScene.
    /// Tries direct SCNScene loading first, falls back to OBJ intermediate format.
    static func loadSTLAsScene(stlURL: URL) -> SCNScene? {
        // Try loading STL directly into SCNScene (SceneKit uses ModelIO internally)
        if let scene = try? SCNScene(url: stlURL) {
            NSLog("[USDZView] Loaded STL directly into SCNScene")
            return scene
        }

        NSLog("[USDZView] Direct STL load failed, trying OBJ intermediate")

        // Fallback: convert STL → OBJ via MDLAsset, then load OBJ into SCNScene
        let asset = MDLAsset(url: stlURL)
        guard asset.count > 0 else {
            NSLog("[USDZView] MDLAsset failed to load STL from: \(stlURL.path)")
            return nil
        }

        let objURL = stlURL.deletingPathExtension().appendingPathExtension("obj")
        try? FileManager.default.removeItem(at: objURL)

        do {
            try asset.export(to: objURL)
        } catch {
            NSLog("[USDZView] OBJ intermediate export failed: \(error)")
            return nil
        }

        let scene = try? SCNScene(url: objURL)
        // Clean up intermediate file
        try? FileManager.default.removeItem(at: objURL)
        return scene
    }

    /// Apply a bone-white material to all geometry in a SceneKit scene.
    static func applyMedicalMaterial(to scene: SCNScene) {
        scene.rootNode.enumerateChildNodes { node, _ in
            if let geometry = node.geometry {
                let material = SCNMaterial()
                #if os(macOS)
                material.diffuse.contents = NSColor(white: 0.92, alpha: 1.0)
                material.specular.contents = NSColor.white
                #else
                material.diffuse.contents = UIColor(white: 0.92, alpha: 1.0)
                material.specular.contents = UIColor.white
                #endif
                material.shininess = 0.3
                material.lightingModel = .physicallyBased
                geometry.materials = [material]
            }
        }
    }

    // MARK: - Security-Scoped Access

    private func resolveAccessForRegeneration() {
        guard let bookmarkData = state.bookmarkData else { return }
        var isStale = false
        #if os(macOS)
        if let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            _ = url.startAccessingSecurityScopedResource()
        }
        #else
        if let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            bookmarkDataIsStale: &isStale
        ) {
            _ = url.startAccessingSecurityScopedResource()
        }
        #endif
    }
}
