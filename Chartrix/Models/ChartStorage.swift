import Foundation

/// iCloud 컨테이너 식별자
private let iCloudContainerID = "iCloud.com.codershigh.Chartrix"

/// DICOM 파일을 iCloud Documents(또는 로컬 Documents)에 복사/관리하는 헬퍼
enum ChartStorage {

    // MARK: - iCloud / Local Documents Directory

    /// iCloud Documents 디렉토리 (사용 가능하면), 아니면 로컬 Documents
    /// - iCloud 가용: `iCloud Drive/Chartrix/Documents/`
    /// - iCloud 불가: `App Sandbox/Documents/`
    /// 두 플랫폼(iOS/macOS) 모두 동일한 iCloud 컨테이너를 사용하므로
    /// 파일이 자동으로 동기화됩니다.
    static var documentsDirectory: URL {
        if let iCloudURL = iCloudDocumentsURL {
            return iCloudURL
        }
        // iCloud 불가 시 로컬 Documents 폴더 사용
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// iCloud 컨테이너의 Documents 디렉토리 (nil = iCloud 미설정)
    static var iCloudDocumentsURL: URL? {
        guard let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: iCloudContainerID
        ) else {
            return nil
        }
        let docsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        return docsURL
    }

    /// iCloud 사용 가능 여부
    static var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Charts 루트 디렉토리
    static var chartsDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("Charts", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Local → iCloud Migration

    /// 로컬 Documents/Charts 에 기존 데이터가 있으면 iCloud로 마이그레이션
    /// 앱 시작 시 한 번 호출합니다.
    static func migrateLocalToICloudIfNeeded() {
        guard let iCloudDocs = iCloudDocumentsURL else { return }

        let localDocs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let localCharts = localDocs.appendingPathComponent("Charts", isDirectory: true)

        let fm = FileManager.default
        guard fm.fileExists(atPath: localCharts.path) else { return }

        let iCloudCharts = iCloudDocs.appendingPathComponent("Charts", isDirectory: true)

        // 이미 iCloud에 Charts 폴더가 있으면 마이그레이션 스킵
        if fm.fileExists(atPath: iCloudCharts.path) {
            // iCloud에 이미 데이터가 있으면 로컬을 건드리지 않음
            return
        }

        // 로컬 Charts → iCloud Charts 이동
        do {
            try fm.moveItem(at: localCharts, to: iCloudCharts)
            print("[ChartStorage] Migrated local Charts → iCloud")
        } catch {
            print("[ChartStorage] Migration failed: \(error.localizedDescription)")
            // 이동 실패 시 복사 시도
            do {
                try fm.copyItem(at: localCharts, to: iCloudCharts)
                print("[ChartStorage] Copied local Charts → iCloud (move failed)")
            } catch {
                print("[ChartStorage] Copy also failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Import DICOM → Study

    /// DICOM 폴더를 앱 내부(iCloud 또는 로컬)로 복사하고, Study의 dicomDirectoryPath를 설정
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
                    print("[USDZ-BG] Pre-generated: \(outputURL.lastPathComponent)")
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
