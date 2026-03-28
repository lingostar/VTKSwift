import SwiftUI
import ModelIO
import Metal
import MetalKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Export Format

enum ExportFormat: String, CaseIterable, Identifiable {
    case stl = "STL"
    case obj = "OBJ"
    case multiOBJ = "Multi-OBJ"
    case usdz = "USDZ"
    case multiUSDZ = "Multi-USDZ"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .stl: return "Binary STL — 3D 프린팅에 최적화"
        case .obj: return "OBJ + MTL — 색상/재질 정보 포함"
        case .multiOBJ: return "다중 조직 OBJ — 뼈+연조직+피부 분리"
        case .usdz: return "USDZ — AR Quick Look / Vision Pro"
        case .multiUSDZ: return "다중 조직 USDZ — 뼈+연조직+피부 AR"
        }
    }

    var icon: String {
        switch self {
        case .stl: return "printer.fill"
        case .obj: return "paintpalette"
        case .multiOBJ: return "square.3.layers.3d"
        case .usdz: return "arkit"
        case .multiUSDZ: return "cube.transparent"
        }
    }

    var fileExtension: String {
        switch self {
        case .stl: return "stl"
        case .obj, .multiOBJ: return "obj"
        case .usdz, .multiUSDZ: return "usdz"
        }
    }

    /// Whether this format uses a single ISO value or multi-layer
    var isMultiLayer: Bool {
        self == .multiOBJ || self == .multiUSDZ
    }
}

// MARK: - Export State

final class ExportState: ObservableObject {
    @Published var format: ExportFormat = .stl
    @Published var isoValue: Double = 300
    @Published var decimationRate: Double = 0.5
    @Published var smoothing: Bool = true
    @Published var isExporting: Bool = false
    @Published var exportProgress: String?
    @Published var exportedFileURL: URL?
    @Published var errorMessage: String?
    @Published var showUSDZPreview: Bool = false
}

// MARK: - Export Sheet View

struct ExportSheetView: View {
    @ObservedObject var exportState: ExportState
    let bridge: VTKBridge?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                disclaimerSection
                formatSection
                if isUSDZFormat {
                    usdzPresetSection
                } else {
                    isoValueSection
                }
                processingSection
                exportButtonSection
                errorSection
                resultSection
            }
            .navigationTitle("3D 내보내기")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
        .sheet(isPresented: $exportState.showUSDZPreview) {
            if let url = exportState.exportedFileURL {
                USDZPreviewView(fileURL: url)
            }
        }
    }
}

// MARK: - Sections

private extension ExportSheetView {

    var disclaimerSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("이 모형은 참고용이며 수술 가이드로 사용할 수 없습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var formatSection: some View {
        Section("파일 형식") {
            ForEach(ExportFormat.allCases) { format in
                formatRow(format)
            }
        }
    }

    func formatRow(_ format: ExportFormat) -> some View {
        Button {
            exportState.format = format
        } label: {
            HStack {
                Image(systemName: format.icon)
                    .frame(width: 24)
                VStack(alignment: .leading) {
                    Text(format.rawValue)
                        .font(.headline)
                    Text(format.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if exportState.format == format {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    var isUSDZFormat: Bool {
        exportState.format == .usdz || exportState.format == .multiUSDZ
    }

    var usdzPresetSection: some View {
        Section("USDZ 프리셋") {
            if exportState.format == .usdz {
                usdzSinglePresetButtons
                isoSliderRow
            } else {
                // Multi-USDZ: show the 3-layer description
                VStack(alignment: .leading, spacing: 6) {
                    Label("뼈 (300 HU) — 아이보리, 약간 금속질", systemImage: "figure.walk")
                        .font(.caption)
                    Label("연조직 (40 HU) — 반투명 핑크", systemImage: "figure.stand")
                        .font(.caption)
                    Label("피부 (-200 HU) — 반투명 피치", systemImage: "person")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                Text("USDZ는 PBR(물리 기반 렌더링) 재질이 적용됩니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var usdzSinglePresetButtons: some View {
        HStack(spacing: 8) {
            usdzQuickPresetButton(name: "Bone", value: 300, icon: "figure.walk", color: .white)
            usdzQuickPresetButton(name: "Soft Tissue", value: 40, icon: "figure.stand", color: .pink)
            usdzQuickPresetButton(name: "Skin", value: -200, icon: "person", color: .orange)
        }
    }

    func usdzQuickPresetButton(name: String, value: Double, icon: String, color: Color) -> some View {
        Button {
            exportState.isoValue = value
        } label: {
            let isSelected = abs(exportState.isoValue - value) < 1
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? color : .secondary)
                Text(name)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    var isoValueSection: some View {
        Section("Isosurface 값 (HU)") {
            isoPresetRow
            isoSliderRow
        }
    }

    var isoPresetRow: some View {
        HStack(spacing: 8) {
            isoPresetButton(name: "Bone", value: 300, icon: "figure.walk")
            isoPresetButton(name: "Soft Tissue", value: 40, icon: "figure.stand")
            isoPresetButton(name: "Skin", value: -200, icon: "person")
        }
    }

    func isoPresetButton(name: String, value: Double, icon: String) -> some View {
        Button {
            exportState.isoValue = value
        } label: {
            let isSelected = abs(exportState.isoValue - value) < 1
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(name)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    var isoSliderRow: some View {
        HStack {
            Text("ISO Value")
                .font(.caption)
            Slider(value: $exportState.isoValue, in: -500...1500, step: 10)
            Text(String(format: "%.0f", exportState.isoValue))
                .font(.caption)
                .monospacedDigit()
                .frame(width: 50, alignment: .trailing)
        }
    }

    var processingSection: some View {
        Section("처리 옵션") {
            HStack {
                Text("삼각형 축소")
                    .font(.caption)
                Slider(value: $exportState.decimationRate, in: 0...0.95, step: 0.05)
                Text(String(format: "%.0f%%", exportState.decimationRate * 100))
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            Toggle("스무딩 적용", isOn: $exportState.smoothing)
                .font(.caption)
        }
    }

    var exportButtonSection: some View {
        Section {
            Button {
                performExport()
            } label: {
                HStack {
                    Spacer()
                    if exportState.isExporting {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text(exportState.exportProgress ?? "내보내는 중...")
                    } else {
                        Image(systemName: "square.and.arrow.up")
                        Text("\(exportState.format.rawValue)로 내보내기")
                    }
                    Spacer()
                }
                .font(.headline)
                .padding(.vertical, 4)
            }
            .disabled(exportState.isExporting || bridge == nil)
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    var errorSection: some View {
        if let error = exportState.errorMessage {
            Section {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    var resultSection: some View {
        if let url = exportState.exportedFileURL {
            Section("내보내기 완료") {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text(url.lastPathComponent)
                            .font(.headline)
                        Text(fileSizeString(url: url))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isUSDZFile(url: url) {
                        Button {
                            exportState.showUSDZPreview = true
                        } label: {
                            Label("미리보기", systemImage: "arkit")
                        }
                    }
                    Button {
                        shareFile(url: url)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }

                if isUSDZFile(url: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "visionpro")
                            .foregroundStyle(.blue)
                        Text("Vision Pro에서 공간에 배치하거나, iPhone/iPad에서 AR로 볼 수 있습니다.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Actions

private extension ExportSheetView {

    func isUSDZFile(url: URL) -> Bool {
        url.pathExtension.lowercased() == "usdz"
    }

    func fileSizeString(url: URL) -> String {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    func performExport() {
        guard let bridge = bridge else { return }
        exportState.isExporting = true
        exportState.errorMessage = nil
        exportState.exportedFileURL = nil
        exportState.exportProgress = "Isosurface 추출 중..."

        let format = exportState.format
        let isoValue = exportState.isoValue
        let decimation = exportState.decimationRate
        let smooth = exportState.smoothing

        DispatchQueue.global(qos: .userInitiated).async {
            let ext = format.fileExtension
            let tempDir = FileManager.default.temporaryDirectory
            let fileName: String
            if format.isMultiLayer {
                fileName = "multi_isosurface.\(ext)"
            } else {
                fileName = "isosurface_\(Int(isoValue))HU.\(ext)"
            }
            let outputURL = tempDir.appendingPathComponent(fileName)

            try? FileManager.default.removeItem(at: outputURL)

            let success: Bool
            switch format {
            case .stl:
                success = bridge.exportIsosurface(
                    asSTL: outputURL.path,
                    isoValue: isoValue,
                    decimationRate: decimation,
                    smoothing: smooth
                )
            case .obj:
                success = bridge.exportIsosurface(
                    asOBJ: outputURL.path,
                    isoValue: isoValue,
                    decimationRate: decimation,
                    smoothing: smooth
                )
            case .multiOBJ:
                let isoValues: [NSNumber] = [300, 40, -200]
                let names: [String] = ["Bone", "SoftTissue", "Skin"]
                success = bridge.exportMultiIsosurface(
                    asOBJ: outputURL.path,
                    isoValues: isoValues,
                    names: names,
                    decimationRate: decimation,
                    smoothing: smooth
                )
            case .usdz:
                success = Self.exportUSDZ(
                    bridge: bridge,
                    outputURL: outputURL,
                    isoValue: isoValue,
                    decimationRate: decimation,
                    smoothing: smooth
                )
            case .multiUSDZ:
                success = Self.exportMultiUSDZ(
                    bridge: bridge,
                    outputURL: outputURL,
                    decimationRate: decimation,
                    smoothing: smooth
                )
            }

            DispatchQueue.main.async {
                exportState.isExporting = false
                exportState.exportProgress = nil

                if success {
                    exportState.exportedFileURL = outputURL
                } else {
                    exportState.errorMessage = "내보내기 실패. DICOM 데이터가 올바르게 로드되었는지 확인하세요."
                }
            }
        }
    }

    // MARK: - USDZ Export Helpers

    /// Export a single isosurface as USDZ using ModelIO.
    static func exportUSDZ(
        bridge: VTKBridge,
        outputURL: URL,
        isoValue: Double,
        decimationRate: Double,
        smoothing: Bool
    ) -> Bool {
        // Extract mesh data from VTK
        var vertices: NSData?
        var normals: NSData?
        var faces: NSData?

        let extracted = bridge.extractIsosurfaceMesh(
            withIsoValue: isoValue,
            decimationRate: decimationRate,
            smoothing: smoothing,
            vertices: &vertices,
            normals: &normals,
            faces: &faces
        )

        guard extracted,
              let vData = vertices as Data?,
              let nData = normals as Data?,
              let fData = faces as Data? else {
            return false
        }

        let vertexCount = vData.count / (3 * MemoryLayout<Float>.size)
        let triangleCount = fData.count / (3 * MemoryLayout<UInt32>.size)
        guard vertexCount > 0, triangleCount > 0 else { return false }

        // Determine material based on ISO value
        let preset = usdzPreset(for: isoValue)

        return buildAndExportUSDZ(
            outputURL: outputURL,
            layers: [(vData, nData, fData, preset)]
        )
    }

    /// Export multiple isosurfaces as a single USDZ file.
    static func exportMultiUSDZ(
        bridge: VTKBridge,
        outputURL: URL,
        decimationRate: Double,
        smoothing: Bool
    ) -> Bool {
        let layerDefs: [(iso: Double, preset: USDZPreset)] = [
            (300, .bone),
            (40, .softTissue),
            (-200, .skin),
        ]

        var layers: [(Data, Data, Data, USDZPreset)] = []

        for def in layerDefs {
            var vertices: NSData?
            var normals: NSData?
            var faces: NSData?

            let extracted = bridge.extractIsosurfaceMesh(
                withIsoValue: def.iso,
                decimationRate: decimationRate,
                smoothing: smoothing,
                vertices: &vertices,
                normals: &normals,
                faces: &faces
            )

            guard extracted,
                  let vData = vertices as Data?,
                  let nData = normals as Data?,
                  let fData = faces as Data? else {
                continue
            }

            let vertexCount = vData.count / (3 * MemoryLayout<Float>.size)
            guard vertexCount > 0 else { continue }

            layers.append((vData, nData, fData, def.preset))
        }

        guard !layers.isEmpty else { return false }

        return buildAndExportUSDZ(outputURL: outputURL, layers: layers)
    }

    /// Build MDLAsset from mesh layers and export as USDZ.
    static func buildAndExportUSDZ(
        outputURL: URL,
        layers: [(vertices: Data, normals: Data, faces: Data, preset: USDZPreset)]
    ) -> Bool {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        let allocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset()

        for layer in layers {
            let vertexCount = layer.vertices.count / (3 * MemoryLayout<Float>.size)
            let triangleCount = layer.faces.count / (3 * MemoryLayout<UInt32>.size)
            guard vertexCount > 0, triangleCount > 0 else { continue }

            // Interleave positions and normals: [px,py,pz,nx,ny,nz, ...]
            let stride = MemoryLayout<Float>.size * 6
            var interleavedData = Data(count: vertexCount * stride)

            interleavedData.withUnsafeMutableBytes { destPtr in
                guard let dest = destPtr.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
                layer.vertices.withUnsafeBytes { vPtr in
                    layer.normals.withUnsafeBytes { nPtr in
                        guard let vSrc = vPtr.baseAddress?.assumingMemoryBound(to: Float.self),
                              let nSrc = nPtr.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
                        for i in 0..<vertexCount {
                            dest[i * 6 + 0] = vSrc[i * 3 + 0]
                            dest[i * 6 + 1] = vSrc[i * 3 + 1]
                            dest[i * 6 + 2] = vSrc[i * 3 + 2]
                            dest[i * 6 + 3] = nSrc[i * 3 + 0]
                            dest[i * 6 + 4] = nSrc[i * 3 + 1]
                            dest[i * 6 + 5] = nSrc[i * 3 + 2]
                        }
                    }
                }
            }

            let vertexBuffer = allocator.newBuffer(with: interleavedData, type: .vertex)
            let indexBuffer = allocator.newBuffer(with: layer.faces, type: .index)

            let submesh = MDLSubmesh(
                indexBuffer: indexBuffer,
                indexCount: triangleCount * 3,
                indexType: .uint32,
                geometryType: .triangles,
                material: createMaterial(preset: layer.preset)
            )

            let descriptor = MDLVertexDescriptor()
            let posAttr = MDLVertexAttribute(
                name: MDLVertexAttributePosition,
                format: .float3,
                offset: 0,
                bufferIndex: 0
            )
            let normAttr = MDLVertexAttribute(
                name: MDLVertexAttributeNormal,
                format: .float3,
                offset: MemoryLayout<Float>.size * 3,
                bufferIndex: 0
            )
            descriptor.attributes = NSMutableArray(array: [posAttr, normAttr])
            descriptor.layouts = NSMutableArray(array: [MDLVertexBufferLayout(stride: stride)])

            let mesh = MDLMesh(
                vertexBuffer: vertexBuffer,
                vertexCount: vertexCount,
                descriptor: descriptor,
                submeshes: [submesh]
            )
            mesh.name = layer.preset.name

            asset.add(mesh)
        }

        do {
            try asset.export(to: outputURL)
            return true
        } catch {
            NSLog("USDZ export failed: %@", error.localizedDescription)
            return false
        }
    }

    /// Simple USDZ material preset for the app-side (no VTKSwift dependency).
    enum USDZPreset {
        case bone, softTissue, skin

        var name: String {
            switch self {
            case .bone: return "Bone"
            case .softTissue: return "SoftTissue"
            case .skin: return "Skin"
            }
        }

        var baseColor: (r: Float, g: Float, b: Float, a: Float) {
            switch self {
            case .bone: return (0.95, 0.93, 0.88, 1.0)
            case .softTissue: return (0.85, 0.55, 0.55, 0.85)
            case .skin: return (0.87, 0.74, 0.60, 0.6)
            }
        }

        var roughness: Float {
            switch self {
            case .bone: return 0.45
            case .softTissue: return 0.7
            case .skin: return 0.6
            }
        }

        var metallic: Float {
            switch self {
            case .bone: return 0.05
            case .softTissue: return 0.0
            case .skin: return 0.0
            }
        }
    }

    static func usdzPreset(for isoValue: Double) -> USDZPreset {
        if isoValue >= 200 { return .bone }
        if isoValue >= -50 { return .softTissue }
        return .skin
    }

    static func createMaterial(preset: USDZPreset) -> MDLMaterial {
        let scatteringFunction = MDLPhysicallyPlausibleScatteringFunction()
        let material = MDLMaterial(name: preset.name, scatteringFunction: scatteringFunction)

        let c = preset.baseColor
        let baseColor = MDLMaterialProperty(
            name: "baseColor",
            semantic: .baseColor,
            color: CGColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: CGFloat(c.a))
        )
        material.setProperty(baseColor)

        material.setProperty(MDLMaterialProperty(name: "roughness", semantic: .roughness, float: preset.roughness))
        material.setProperty(MDLMaterialProperty(name: "metallic", semantic: .metallic, float: preset.metallic))

        if c.a < 1.0 {
            material.setProperty(MDLMaterialProperty(name: "opacity", semantic: .opacity, float: c.a))
        }

        return material
    }

    func shareFile(url: URL) {
        #if os(iOS)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        let ac = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        ac.popoverPresentationController?.sourceView = rootVC.view
        rootVC.present(ac, animated: true)
        #elseif os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }
}
