import Foundation
import SwiftData

// MARK: - Report Record

/// SwiftData model for a saved structured report.
@Model
final class ReportRecord {
    /// Display title (e.g., "CT Chest Report").
    var title: String = ""

    /// Patient name (may be anonymized).
    var patientName: String = "Anonymous"

    /// Patient ID.
    var patientID: String = ""

    /// Study date (DICOM DA format: YYYYMMDD).
    var studyDate: String = ""

    /// Modality (CT, MR, CR, etc.).
    var modality: String = ""

    /// Study description.
    var studyDescription: String = ""

    // Report content
    var findings: String = ""
    var impression: String = ""
    var recommendation: String = ""

    /// Serialized measurement descriptions (one per line).
    var measurementSummary: String = ""

    /// Number of measurements included.
    var measurementCount: Int = 0

    /// Export format used (dicomSR, plainText).
    var exportFormat: String = ""

    /// Relative path to exported file (within Documents).
    var exportedFilePath: String = ""

    /// Creation date.
    var createdDate: Date = Date()

    /// Last modified date.
    var modifiedDate: Date = Date()

    /// Version number (incremented on each edit).
    var version: Int = 1

    /// Associated case record alias (for linkage, not a relationship to avoid schema coupling).
    var linkedCaseAlias: String = ""

    /// Whether this is the latest version for its linked case.
    var isLatestVersion: Bool = true

    init() {}

    // MARK: - Computed

    /// Exported file URL (resolved from Documents directory).
    var exportedFileURL: URL? {
        guard !exportedFilePath.isEmpty else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(exportedFilePath)
    }

    /// Short subtitle for list display.
    var subtitle: String {
        var parts: [String] = []
        if !modality.isEmpty { parts.append(modality) }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        parts.append(formatter.string(from: createdDate))
        if version > 1 { parts.append("v\(version)") }
        return parts.joined(separator: " · ")
    }

    /// Whether the exported file exists on disk.
    var exportedFileExists: Bool {
        guard let url = exportedFileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
