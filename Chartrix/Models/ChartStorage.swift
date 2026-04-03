import Foundation

/// DICOM 파일을 앱 Documents 디렉토리에 복사/관리하는 헬퍼
enum ChartStorage {

    /// 앱 Documents 디렉토리
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// Charts 루트 디렉토리
    static var chartsDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("Charts", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Import DICOM → Study

    /// DICOM 폴더를 앱 내부로 복사하고, Study의 dicomDirectoryPath를 설정
    static func importDICOM(study: Study, chartAlias: String, from sourceURL: URL) {
        // Charts/{alias}/{studyDate}_{modality}/DICOM/
        let studyFolder = "\(study.studyDate)_\(study.modality)".sanitizedFileName
        let studyDir = chartsDirectory
            .appendingPathComponent(chartAlias.sanitizedFileName, isDirectory: true)
            .appendingPathComponent(studyFolder, isDirectory: true)
            .appendingPathComponent("DICOM", isDirectory: true)

        let fm = FileManager.default
        try? fm.createDirectory(at: studyDir, withIntermediateDirectories: true)

        guard let enumerator = fm.enumerator(at: sourceURL, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return
        }

        var copiedCount = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }

            let ext = fileURL.pathExtension.lowercased()
            if ext == "dcm" || ext == "dicom" || ext.isEmpty {
                if isDICOMFile(fileURL) {
                    let dest = studyDir.appendingPathComponent(fileURL.lastPathComponent)
                    try? fm.copyItem(at: fileURL, to: dest)
                    copiedCount += 1
                }
            }
        }

        let relativePath = studyDir.path.replacingOccurrences(
            of: documentsDirectory.path + "/", with: ""
        )
        study.dicomDirectoryPath = relativePath
        study.imageCount = copiedCount
    }

    /// Study의 DICOM 디렉토리 절대 경로
    static func dicomDirectoryURL(for study: Study) -> URL? {
        guard let path = study.dicomDirectoryPath, !path.isEmpty else { return nil }
        return documentsDirectory.appendingPathComponent(path)
    }

    /// Chart 관련 파일 모두 삭제
    static func deleteFiles(for chart: Chart) {
        let chartDir = chartsDirectory
            .appendingPathComponent(chart.alias.sanitizedFileName, isDirectory: true)
        try? FileManager.default.removeItem(at: chartDir)
    }

    // MARK: - Background USDZ Pre-generation

    /// DICOM import 후 백그라운드에서 USDZ를 미리 생성 (Bone 프리셋, ISO 300)
    /// 메인 스레드에서 호출해야 함 (VTKBridge가 OpenGL 컨텍스트 필요)
    static func generateUSDZInBackground(study: Study, chartAlias: String) {
        guard let dirURL = dicomDirectoryURL(for: study) else {
            print("[USDZ-BG] No DICOM directory for study")
            return
        }

        print("[USDZ-BG] Starting background USDZ generation for: \(chartAlias) / \(study.modality)")

        let bridge = VTKBridge(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard bridge.loadDICOMDirectory(dirURL.path) else {
            print("[USDZ-BG] ERROR: Failed to load DICOM from \(dirURL.path)")
            return
        }
        print("[USDZ-BG] DICOM loaded, extracting mesh...")

        let studyFolder = "\(study.studyDate)_\(study.modality)".sanitizedFileName

        DispatchQueue.global(qos: .utility).async {
            let isoValue: Double = 300
            let decimation: Double = 0.8
            let smoothing = true

            var verticesData: NSData?
            var normalsData: NSData?
            var facesData: NSData?

            let ok = bridge.extractIsosurfaceMesh(
                withIsoValue: isoValue,
                decimationRate: decimation,
                smoothing: smoothing,
                vertices: &verticesData,
                normals: &normalsData,
                faces: &facesData
            )

            guard ok,
                  let vData = verticesData as Data?,
                  let nData = normalsData as Data?,
                  let fData = facesData as Data? else {
                print("[USDZ-BG] ERROR: Mesh extraction failed")
                return
            }

            let faceCount = fData.count / (3 * MemoryLayout<UInt32>.size)
            print("[USDZ-BG] Mesh extracted: \(faceCount) faces")

            let outputURL = chartsDirectory
                .appendingPathComponent(chartAlias.sanitizedFileName)
                .appendingPathComponent(studyFolder)
                .appendingPathComponent("Bone.usdz")

            try? FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let color = SIMD3<Float>(0.95, 0.92, 0.84)
            let roughness: Float = 0.45

            let result = USDZGenerator.create(
                vertices: vData, normals: nData, faces: fData,
                color: color, roughness: roughness,
                name: "Bone", outputURL: outputURL
            )

            if result {
                let rel = outputURL.path.replacingOccurrences(
                    of: documentsDirectory.path + "/", with: "")
                DispatchQueue.main.async {
                    study.usdzFilePath = rel
                    try? study.modelContext?.save()
                    print("[USDZ-BG] ✅ Pre-generated: \(outputURL.lastPathComponent)")
                }
            } else {
                print("[USDZ-BG] ERROR: USDZGenerator.create failed")
            }
        }
    }

    private static func isDICOMFile(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { handle.closeFile() }
        let header = handle.readData(ofLength: 132)
        guard header.count >= 132 else { return false }
        return header[128] == 0x44 && header[129] == 0x49
            && header[130] == 0x43 && header[131] == 0x4D
    }
}

// MARK: - String Sanitization

extension String {
    /// 파일 이름에 사용할 수 없는 문자를 제거
    var sanitizedFileName: String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>| ")
        let cleaned = components(separatedBy: illegal).joined(separator: "_")
        return cleaned.isEmpty ? "untitled" : cleaned
    }
}
