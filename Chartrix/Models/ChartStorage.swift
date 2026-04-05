import Foundation
import Combine

/// iCloud container identifier
private let iCloudContainerID = "iCloud.codershigh.Chartrix"

/// Helper for copying/managing DICOM files in iCloud Documents (or local Documents)
enum ChartStorage {

    // MARK: - iCloud / Local Documents Directory

    /// iCloud Documents directory (if available), otherwise local Documents
    /// - iCloud available: `iCloud Drive/Chartrix/Documents/`
    /// - iCloud unavailable: `App Sandbox/Documents/`
    /// Both platforms (iOS/macOS) use the same iCloud container,
    /// so files sync automatically.
    static var documentsDirectory: URL {
        if let iCloudURL = iCloudDocumentsURL {
            return iCloudURL
        }
        // Fall back to local Documents when iCloud unavailable
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// iCloud container's Documents directory (nil = iCloud not configured)
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

    /// Whether iCloud is available
    static var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    // MARK: - iCloud Usage Tracking

    private static let wasUsingICloudKey = "ChartStorage.wasUsingICloud"

    /// Whether iCloud was previously used (UserDefaults-based)
    static var wasUsingICloud: Bool {
        UserDefaults.standard.bool(forKey: wasUsingICloudKey)
    }

    /// Record current iCloud usage state
    static func recordICloudUsage() {
        UserDefaults.standard.set(isICloudAvailable, forKey: wasUsingICloudKey)
    }

    /// "Previously used iCloud but now signed out" state
    static var needsICloudReSignIn: Bool {
        wasUsingICloud && !isICloudAvailable
    }

    /// Charts root directory
    static var chartsDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("Charts", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Local → iCloud Migration

    /// Whether migration is complete (checkable from UI)
    private(set) static var isMigrationComplete = false

    /// Migrate existing data from local Documents/Charts to iCloud (merge strategy)
    ///
    /// - No Charts folder in iCloud: move entirely
    /// - Charts folder exists in iCloud: merge each local chart folder individually
    /// - Delete migrated local folders to prevent duplicates
    ///
    /// This method runs **synchronously**. File access is safe after it returns.
    static func migrateLocalToICloudIfNeeded() {
        defer { isMigrationComplete = true }

        guard let iCloudDocs = iCloudDocumentsURL else { return }

        let localDocs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let localCharts = localDocs.appendingPathComponent("Charts", isDirectory: true)

        let fm = FileManager.default
        guard fm.fileExists(atPath: localCharts.path) else { return }

        // Check if local Charts actually has content
        guard let localContents = try? fm.contentsOfDirectory(
            at: localCharts, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ), !localContents.isEmpty else { return }

        let iCloudCharts = iCloudDocs.appendingPathComponent("Charts", isDirectory: true)

        // Case 1: No Charts folder in iCloud → move entirely
        if !fm.fileExists(atPath: iCloudCharts.path) {
            do {
                try fm.moveItem(at: localCharts, to: iCloudCharts)
                print("[ChartStorage] Migrated local Charts → iCloud (\(localContents.count) items)")
                return
            } catch {
                print("[ChartStorage] Move failed, falling back to merge: \(error.localizedDescription)")
                // If move fails, fall through to merge logic below
            }
        }

        // Case 2: Charts folder already exists in iCloud → merge per chart
        try? fm.createDirectory(at: iCloudCharts, withIntermediateDirectories: true)

        var migratedCount = 0
        var skippedCount = 0

        for localItem in localContents {
            let itemName = localItem.lastPathComponent
            let iCloudDest = iCloudCharts.appendingPathComponent(itemName)

            if fm.fileExists(atPath: iCloudDest.path) {
                // Chart folder with same name already exists in iCloud → skip
                skippedCount += 1
                print("[ChartStorage] Merge skip (already in iCloud): \(itemName)")
                continue
            }

            // Move local chart folder to iCloud
            do {
                try fm.moveItem(at: localItem, to: iCloudDest)
                migratedCount += 1
                print("[ChartStorage] Merged → iCloud: \(itemName)")
            } catch {
                // If move fails, try copy
                do {
                    try fm.copyItem(at: localItem, to: iCloudDest)
                    // Delete local original after successful copy
                    try? fm.removeItem(at: localItem)
                    migratedCount += 1
                    print("[ChartStorage] Copied → iCloud: \(itemName)")
                } catch {
                    print("[ChartStorage] Failed to migrate \(itemName): \(error.localizedDescription)")
                }
            }
        }

        // Remove local Charts folder if empty
        if let remaining = try? fm.contentsOfDirectory(
            at: localCharts, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ), remaining.isEmpty {
            try? fm.removeItem(at: localCharts)
            print("[ChartStorage] Removed empty local Charts folder")
        }

        print("[ChartStorage] Migration complete: \(migratedCount) migrated, \(skippedCount) skipped")
    }

    // MARK: - iCloud → Local Migration (sign-out handling)

    /// On iCloud sign-out: copy to local if iCloud container is still accessible
    ///
    /// iOS/macOS may still have brief access to cached iCloud files after sign-out.
    /// This function copies files locally when possible to prevent data loss.
    ///
    /// Runs synchronously.
    static func migrateICloudToLocalIfNeeded() {
        // No reverse migration needed if iCloud is available
        guard !isICloudAvailable else { return }
        // Nothing to do if iCloud was never used
        guard wasUsingICloud else { return }

        let fm = FileManager.default
        let localDocs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let localCharts = localDocs.appendingPathComponent("Charts", isDirectory: true)

        // Skip if local Charts already exists (previously copied)
        if let localContents = try? fm.contentsOfDirectory(
            at: localCharts, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ), !localContents.isEmpty {
            print("[ChartStorage] Local Charts already exists, skip reverse migration")
            return
        }

        // Attempt to access iCloud container
        // May still be accessible via cache after sign-out
        guard let containerURL = fm.url(forUbiquityContainerIdentifier: iCloudContainerID) else {
            print("[ChartStorage] Cannot access iCloud container after logout")
            return
        }

        let iCloudCharts = containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Charts", isDirectory: true)

        guard fm.fileExists(atPath: iCloudCharts.path) else {
            print("[ChartStorage] No Charts in iCloud container")
            return
        }

        // Copy iCloud → local
        do {
            try fm.copyItem(at: iCloudCharts, to: localCharts)
            print("[ChartStorage] Reverse migration: iCloud Charts → local (\(localCharts.path))")
        } catch {
            print("[ChartStorage] Reverse migration failed: \(error.localizedDescription)")
            // Try copying individual folders
            guard let items = try? fm.contentsOfDirectory(
                at: iCloudCharts, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { return }

            try? fm.createDirectory(at: localCharts, withIntermediateDirectories: true)

            var count = 0
            for item in items {
                let dest = localCharts.appendingPathComponent(item.lastPathComponent)
                do {
                    try fm.copyItem(at: item, to: dest)
                    count += 1
                } catch {
                    print("[ChartStorage] Failed to copy \(item.lastPathComponent): \(error.localizedDescription)")
                }
            }
            print("[ChartStorage] Reverse migration (partial): \(count)/\(items.count) items")
        }
    }

    // MARK: - Import DICOM → Study

    /// Copy DICOM folder into app storage (iCloud or local) and set Study's dicomDirectoryPath
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

    /// Absolute path to Study's DICOM directory
    static func dicomDirectoryURL(for study: Study) -> URL? {
        guard let path = study.dicomDirectoryPath, !path.isEmpty else { return nil }
        return documentsDirectory.appendingPathComponent(path)
    }

    /// Delete all files related to a Chart
    static func deleteFiles(for chart: Chart) {
        let chartDir = chartsDirectory
            .appendingPathComponent(chart.alias.sanitizedFileName, isDirectory: true)
        try? FileManager.default.removeItem(at: chartDir)
    }

    // MARK: - Background USDZ Pre-generation

    /// Pre-generate USDZ in background after DICOM import (Bone preset, ISO 300)
    /// Must be called on main thread (VTKBridge requires OpenGL context)
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

    // MARK: - iCloud Download Support

    /// Download status of iCloud file/directory
    enum DownloadStatus {
        case local              // Already exists locally (not iCloud)
        case downloaded         // Downloaded from iCloud
        case notDownloaded      // Only in iCloud (download needed)
        case downloading        // Currently downloading
    }

    /// Check download status of Study's DICOM directory
    static func downloadStatus(for study: Study) -> DownloadStatus {
        guard let dirURL = dicomDirectoryURL(for: study) else { return .notDownloaded }

        // Local file if not using iCloud
        guard isICloudAvailable else {
            return FileManager.default.fileExists(atPath: dirURL.path) ? .local : .notDownloaded
        }

        return directoryDownloadStatus(dirURL)
    }

    /// Check iCloud download status of a directory
    static func directoryDownloadStatus(_ dirURL: URL) -> DownloadStatus {
        let fm = FileManager.default

        // If directory itself doesn't exist
        guard fm.fileExists(atPath: dirURL.path) else { return .notDownloaded }

        // ⚠️ options: [] — must NOT use .skipsHiddenFiles!
        // Undownloaded iCloud files exist as hidden ".filename.icloud" placeholders
        guard let allFiles = try? fm.contentsOfDirectory(
            at: dirURL, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey],
            options: []
        ) else {
            return .notDownloaded
        }

        // Include only .icloud placeholders and real files, exclude .DS_Store etc.
        let files = allFiles.filter { url in
            let name = url.lastPathComponent
            if name.hasPrefix(".") && name.hasSuffix(".icloud") {
                return true   // iCloud placeholder
            }
            if name.hasPrefix(".") {
                return false  // Exclude system files like .DS_Store
            }
            return true
        }

        if files.isEmpty { return .notDownloaded }

        var downloadedCount = 0
        var downloadingCount = 0

        for file in files {
            let name = file.lastPathComponent

            // .icloud placeholder = not downloaded
            if name.hasPrefix(".") && name.hasSuffix(".icloud") {
                continue
            }

            guard let values = try? file.resourceValues(
                forKeys: [.ubiquitousItemDownloadingStatusKey]
            ) else {
                // resourceValues failed = may be a local file
                downloadedCount += 1
                continue
            }

            if let status = values.ubiquitousItemDownloadingStatus {
                switch status {
                case .current, .downloaded:
                    downloadedCount += 1
                case .notDownloaded:
                    break
                default:
                    downloadingCount += 1
                }
            } else {
                // status is nil = local file
                downloadedCount += 1
            }
        }

        if downloadedCount == files.count { return .downloaded }
        if downloadingCount > 0 { return .downloading }
        return .notDownloaded
    }

    /// Start downloading Study's DICOM files from iCloud
    /// - Returns: true if download was triggered, false if already local or failed
    @discardableResult
    static func startDownloading(study: Study) -> Bool {
        guard let dirURL = dicomDirectoryURL(for: study) else { return false }
        return startDownloadingDirectory(dirURL)
    }

    /// Trigger iCloud download for all files in directory
    @discardableResult
    static func startDownloadingDirectory(_ dirURL: URL) -> Bool {
        let fm = FileManager.default

        // Try downloading the directory itself
        do {
            try fm.startDownloadingUbiquitousItem(at: dirURL)
        } catch {
            print("[ChartStorage] startDownloading directory failed: \(error.localizedDescription)")
        }

        // ⚠️ options: [] — must NOT use .skipsHiddenFiles!
        // Undownloaded iCloud files are hidden ".filename.icloud" placeholders,
        // so hidden files must be included to trigger downloads
        guard let allFiles = try? fm.contentsOfDirectory(
            at: dirURL, includingPropertiesForKeys: nil,
            options: []
        ) else { return false }

        var triggered = false
        for file in allFiles {
            let name = file.lastPathComponent

            // Skip system hidden files like .DS_Store
            if name.hasPrefix(".") && !name.hasSuffix(".icloud") {
                continue
            }

            // .icloud placeholder → convert to original filename URL and trigger download
            let downloadURL: URL
            if name.hasPrefix(".") && name.hasSuffix(".icloud") {
                // ".IMG001.dcm.icloud" → "IMG001.dcm"
                let originalName = String(name.dropFirst().dropLast(7))
                downloadURL = dirURL.appendingPathComponent(originalName)
            } else {
                downloadURL = file
            }

            do {
                try fm.startDownloadingUbiquitousItem(at: downloadURL)
                triggered = true
            } catch {
                // Already local or error — ignore
            }
        }

        let fileCount = allFiles.filter { !$0.lastPathComponent.hasPrefix(".") || $0.lastPathComponent.hasSuffix(".icloud") }.count
        print("[ChartStorage] Triggered download for \(fileCount) files in \(dirURL.lastPathComponent)")
        return triggered
    }

    /// Trigger iCloud download for USDZ file
    @discardableResult
    static func startDownloadingUSDZ(for study: Study) -> Bool {
        guard let relPath = study.usdzFilePath, !relPath.isEmpty else { return false }
        let url = documentsDirectory.appendingPathComponent(relPath)
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            return true
        } catch {
            print("[ChartStorage] startDownloading USDZ failed: \(error.localizedDescription)")
            return false
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
    /// Remove characters that are invalid in file names
    var sanitizedFileName: String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>| ")
        let cleaned = components(separatedBy: illegal).joined(separator: "_")
        return cleaned.isEmpty ? "untitled" : cleaned
    }
}
