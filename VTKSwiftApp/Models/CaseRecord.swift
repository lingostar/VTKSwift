import Foundation
import SwiftData

// MARK: - Case Record

/// A locally stored DICOM case with anonymized data.
@Model
final class CaseRecord {
    /// User-assigned alias (e.g. "Knee CT - Case 001").
    var alias: String

    /// Modality (e.g. "CT", "MR", "CR").
    var modality: String

    /// Study date extracted from DICOM (may be nil if removed during anonymization).
    var studyDate: Date?

    /// Number of DICOM images in this case.
    var imageCount: Int

    /// Study description from DICOM (if preserved).
    var studyDescription: String?

    /// Series description from DICOM (if preserved).
    var seriesDescription: String?

    /// Patient age (if preserved during anonymization).
    var patientAge: String?

    /// Patient sex (if preserved).
    var patientSex: String?

    /// User-added notes/memo.
    var notes: String

    /// Relative path to the anonymized DICOM directory (under app's Documents).
    var anonymizedDirectoryPath: String

    /// Date the case was imported.
    var importDate: Date

    /// Whether burned-in annotations were detected.
    var hasBurnedInAnnotation: Bool

    init(
        alias: String,
        modality: String = "",
        studyDate: Date? = nil,
        imageCount: Int = 0,
        studyDescription: String? = nil,
        seriesDescription: String? = nil,
        patientAge: String? = nil,
        patientSex: String? = nil,
        notes: String = "",
        anonymizedDirectoryPath: String,
        importDate: Date = Date(),
        hasBurnedInAnnotation: Bool = false
    ) {
        self.alias = alias
        self.modality = modality
        self.studyDate = studyDate
        self.imageCount = imageCount
        self.studyDescription = studyDescription
        self.seriesDescription = seriesDescription
        self.patientAge = patientAge
        self.patientSex = patientSex
        self.notes = notes
        self.anonymizedDirectoryPath = anonymizedDirectoryPath
        self.importDate = importDate
        self.hasBurnedInAnnotation = hasBurnedInAnnotation
    }

    /// Full URL to the anonymized DICOM directory.
    var anonymizedDirectoryURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent(anonymizedDirectoryPath)
    }

    /// Display subtitle (modality + date + image count).
    var subtitle: String {
        var parts: [String] = []
        if !modality.isEmpty { parts.append(modality) }
        if let date = studyDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            parts.append(formatter.string(from: date))
        }
        parts.append("\(imageCount) images")
        return parts.joined(separator: " · ")
    }
}
