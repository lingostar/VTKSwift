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

// MARK: - Volume View

/// Displays DICOM data as a 3D volume rendering with CT presets.
struct VolumeView: View {
    @State private var bridge: VTKBridge?
    @State private var isLoaded = false
    @State private var showFilePicker = false
    @State private var errorMessage: String?
    @State private var selectedPreset: CTPreset = .softTissue
    @State private var opacityScale: Double = 1.0
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            if isLoaded, let bridge {
                // 3D Volume rendering view
                VolumeRenderView(bridge: bridge)
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
                        Slider(value: $opacityScale, in: 0.1...2.0, step: 0.05)
                            .onChange(of: opacityScale) { newValue in
                                bridge.setVolumeOpacityScale(newValue)
                            }
                        Text(String(format: "%.0f%%", opacityScale * 100))
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
                    if isLoading {
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

                        if let errorMessage {
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
            if isLoaded {
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

    // MARK: - Preset Button

    @ViewBuilder
    private func presetButton(_ preset: CTPreset) -> some View {
        Button {
            selectedPreset = preset
            bridge?.apply(preset.vtkPreset)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: preset.icon)
                    .font(.title3)
                Text(preset.title)
                    .font(.caption2)
            }
            .frame(width: 64, height: 48)
            .background(
                selectedPreset == preset
                    ? Color.accentColor.opacity(0.2)
                    : Color.clear
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        selectedPreset == preset
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
            loadVolume(from: url)

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func loadVolume(from url: URL) {
        errorMessage = nil
        isLoading = true

        let didStart = url.startAccessingSecurityScopedResource()

        // VTKBridge creates NSView — must stay on main thread.
        // Use asyncAfter so SwiftUI can render the loading indicator first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let newBridge = VTKBridge(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
            let success = newBridge.loadVolume(fromDICOMDirectory: url.path)

            if didStart { url.stopAccessingSecurityScopedResource() }

            isLoading = false
            if success {
                bridge = newBridge
                selectedPreset = .softTissue
                opacityScale = 1.0
                isLoaded = true
            } else {
                errorMessage = "Failed to load volume from selected directory.\nEnsure the folder contains valid DICOM files."
            }
        }
    }
}

// MARK: - Volume Render View (Platform-specific)

#if os(iOS)
private struct VolumeRenderView: UIViewRepresentable {
    let bridge: VTKBridge

    func makeUIView(context: Context) -> UIView {
        let view = bridge.renderView
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            bridge.render()
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let size = uiView.bounds.size
        if size.width > 0 && size.height > 0 {
            bridge.resize(to: size)
        }
    }
}
#elseif os(macOS)
private struct VolumeRenderView: NSViewRepresentable {
    let bridge: VTKBridge

    func makeNSView(context: Context) -> NSView {
        let view = bridge.renderView
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            bridge.render()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let size = nsView.bounds.size
        if size.width > 0 && size.height > 0 {
            bridge.resize(to: size)
        }
    }
}
#endif
