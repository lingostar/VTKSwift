import SwiftUI

// MARK: - USDZ Modal View

/// Modal sheet for USDZ 3D model viewing/generation per study.
/// Future expansion area for additional 3D-related features.
struct USDZModalView: View {
    let study: Study
    let chartAlias: String

    @Environment(\.dismiss) private var dismiss

    // USDZ state
    @State private var selectedPreset: USDZTissuePreset = .bone
    @State private var huThreshold: Double = 300
    @State private var decimationRate: Double = 0.8
    @State private var smoothing = true
    @State private var isGenerating = false
    @State private var triangleCount: Int = 0
    @State private var exportedURL: URL?
    @State private var errorMessage: String?
    #if os(iOS)
    @State private var showARQuickLook = false
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // 3D preview
                    previewArea
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 400)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1.5)
                        )

                    // Controls
                    controlsArea

                    Text("Reference Only — This model is for reference purposes, not for clinical diagnosis.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle("3D Model")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { loadPreGeneratedUSDZ() }
            #if os(iOS)
            .fullScreenCover(isPresented: $showARQuickLook) {
                if let url = exportedURL {
                    ARQuickLookSheet(fileURL: url)
                }
            }
            #endif
        }
    }

    // MARK: - Preview Area

    @ViewBuilder
    private var previewArea: some View {
        ZStack {
            Color.gray.opacity(0.05)

            if isGenerating {
                VStack(spacing: 8) {
                    ProgressView().scaleEffect(1.5)
                    Text("Generating 3D model...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if let url = exportedURL, FileManager.default.fileExists(atPath: url.path) {
                USDZSceneView(fileURL: url)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Tap Regenerate to create 3D model")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Controls

    private var controlsArea: some View {
        VStack(spacing: 12) {
            // HU Threshold
            VStack(spacing: 4) {
                HStack {
                    Text("HU Threshold")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(huThreshold))")
                        .font(.caption)
                        .monospacedDigit()
                }
                Slider(value: $huThreshold, in: -500...1500, step: 10)
            }

            // Tissue Presets
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(USDZTissuePreset.allCases) { preset in
                        Button {
                            selectedPreset = preset
                            huThreshold = preset.isoValue
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: preset.icon).font(.title3)
                                Text(preset.label).font(.caption2)
                            }
                            .frame(width: 80, height: 48)
                            .contentShape(Rectangle())
                            .background(selectedPreset == preset ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedPreset == preset ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Decimation
            HStack {
                Text("Decimation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $decimationRate, in: 0...0.95, step: 0.05)
                Text("\(Int(decimationRate * 100))%")
                    .font(.caption).monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }

            // Smooth + Triangle count
            HStack {
                Toggle("Smooth", isOn: $smoothing).font(.caption)
                Spacer()
                if triangleCount > 0 {
                    Text("\(triangleCount.formatted()) triangles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                Button { generateUSDZ() } label: {
                    Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)

                if let url = exportedURL {
                    #if os(iOS)
                    Button { showARQuickLook = true } label: {
                        Label("AR", systemImage: "arkit")
                    }
                    .buttonStyle(.bordered)
                    #endif

                    #if os(macOS)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    #endif

                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Loading & Generation

    private func loadPreGeneratedUSDZ() {
        guard exportedURL == nil,
              let relPath = study.usdzFilePath, !relPath.isEmpty else { return }
        let url = ChartStorage.documentsDirectory.appendingPathComponent(relPath)
        if FileManager.default.fileExists(atPath: url.path) {
            exportedURL = url
        }
    }

    private func generateUSDZ() {
        guard let dirURL = ChartStorage.dicomDirectoryURL(for: study) else {
            errorMessage = "DICOM directory not found."
            return
        }

        let status = ChartStorage.directoryDownloadStatus(dirURL)
        if status == .notDownloaded || status == .downloading {
            errorMessage = "DICOM files are still downloading from iCloud. Please wait."
            ChartStorage.startDownloadingDirectory(dirURL)
            return
        }

        isGenerating = true
        errorMessage = nil

        let bridge = VTKBridge(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard bridge.loadDICOMDirectory(dirURL.path) else {
            isGenerating = false
            errorMessage = "Failed to load DICOM."
            return
        }

        let isoVal = huThreshold
        let decRate = decimationRate
        let smooth = smoothing
        let preset = selectedPreset
        let studyFolder = "\(study.studyDate)_\(study.modality)".sanitizedFileName

        DispatchQueue.global(qos: .userInitiated).async {
            var verticesData: NSData?
            var normalsData: NSData?
            var facesData: NSData?

            let ok = bridge.extractIsosurfaceMesh(
                withIsoValue: isoVal,
                decimationRate: decRate,
                smoothing: smooth,
                vertices: &verticesData,
                normals: &normalsData,
                faces: &facesData
            )

            guard ok,
                  let vData = verticesData as Data?,
                  let nData = normalsData as Data?,
                  let fData = facesData as Data? else {
                DispatchQueue.main.async {
                    isGenerating = false
                    errorMessage = "Failed to extract mesh."
                }
                return
            }

            let faceCount = fData.count / (3 * MemoryLayout<UInt32>.size)
            let outputURL = ChartStorage.chartsDirectory
                .appendingPathComponent(chartAlias.sanitizedFileName)
                .appendingPathComponent(studyFolder)
                .appendingPathComponent("\(preset.label).usdz")

            try? FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let result = USDZGenerator.create(
                vertices: vData, normals: nData, faces: fData,
                color: preset.color, roughness: preset.roughness,
                name: preset.label, outputURL: outputURL
            )

            DispatchQueue.main.async {
                isGenerating = false
                if result {
                    exportedURL = outputURL
                    triangleCount = faceCount
                    let rel = outputURL.path.replacingOccurrences(
                        of: ChartStorage.documentsDirectory.path + "/", with: "")
                    study.usdzFilePath = rel
                } else {
                    errorMessage = "Failed to create USDZ."
                }
            }
        }
    }
}
