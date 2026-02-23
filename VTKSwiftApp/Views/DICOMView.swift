import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Displays DICOM medical images using VTK's vtkDICOMImageReader + vtkImageViewer2.
struct DICOMView: View {
    @State private var bridge: VTKBridge?
    @State private var isLoaded = false
    @State private var sliceIndex: Double = 0
    @State private var sliceMin: Double = 0
    @State private var sliceMax: Double = 0
    @State private var showFilePicker = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if isLoaded, let bridge {
                // DICOM VTK rendering view
                DICOMRenderView(bridge: bridge)
                    .ignoresSafeArea()

                // Slice navigation controls
                VStack(spacing: 8) {
                    HStack {
                        Text("Slice: \(Int(sliceIndex))")
                            .monospacedDigit()
                        Spacer()
                        Text("\(Int(sliceMin))–\(Int(sliceMax))")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                    Slider(value: $sliceIndex,
                           in: sliceMin...max(sliceMin, sliceMax),
                           step: 1)
                    .onChange(of: sliceIndex) { newValue in
                        bridge.setSlice(Int(newValue))
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

                    if let errorMessage {
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

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Start accessing security-scoped resource
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart { url.stopAccessingSecurityScopedResource() }
            }

            loadDICOM(from: url.path)

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func loadDICOM(from path: String) {
        errorMessage = nil

        let newBridge = VTKBridge(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let success = newBridge.loadDICOMDirectory(path)

        if success {
            bridge = newBridge
            sliceMin = Double(newBridge.sliceMin)
            sliceMax = Double(newBridge.sliceMax)
            sliceIndex = Double(newBridge.currentSlice)
            isLoaded = true
        } else {
            errorMessage = "Failed to load DICOM files from selected directory."
        }
    }
}

// MARK: - DICOM Render View (Platform-specific)

#if os(iOS)
private struct DICOMRenderView: UIViewRepresentable {
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
private struct DICOMRenderView: NSViewRepresentable {
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
