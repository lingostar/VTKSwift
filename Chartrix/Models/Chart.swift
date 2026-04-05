import SwiftData
import Foundation
import SwiftUI

/// Patient chart — manages multiple Studies (CT/MRI etc.) per patient
@Model
final class Chart {
    // CloudKit: all attributes must have default values
    var alias: String = ""
    var notes: String = ""
    var createdDate: Date = Date()
    var updatedDate: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Study.chart)
    var studies: [Study]?

    @Relationship(deleteRule: .cascade, inverse: \Note.chart)
    var doctorNotes: [Note]?

    init(
        alias: String = "",
        notes: String = ""
    ) {
        self.alias = alias
        self.notes = notes
        self.createdDate = Date()
        self.updatedDate = Date()
    }
}

// MARK: - Study Model

/// Individual DICOM Study — one CT/MRI/US set
@Model
final class Study {
    // CloudKit: all attributes must have default values
    var modality: String = "CT"
    var imageCount: Int = 0
    var studyDescription: String = ""
    var studyDate: String = ""

    /// DICOM file path (relative to Documents)
    var dicomDirectoryPath: String?

    /// USDZ file path
    var usdzFilePath: String?

    var createdDate: Date = Date()

    var chart: Chart?

    @Relationship(deleteRule: .cascade, inverse: \Measurement.study)
    var measurements: [Measurement]?

    /// Inverse reference from Note (Note.study → Study.notes)
    @Relationship(deleteRule: .nullify, inverse: \Note.study)
    var notes: [Note]?

    init(
        modality: String = "CT",
        imageCount: Int = 0,
        studyDescription: String = "",
        studyDate: String = "",
        dicomDirectoryPath: String? = nil,
        usdzFilePath: String? = nil
    ) {
        self.modality = modality
        self.imageCount = imageCount
        self.studyDescription = studyDescription
        self.studyDate = studyDate
        self.dicomDirectoryPath = dicomDirectoryPath
        self.usdzFilePath = usdzFilePath
        self.createdDate = Date()
    }
}

// MARK: - Chart Helpers

extension Chart {
    /// Most recent Study
    var latestStudy: Study? {
        sortedStudies.first
    }

    /// Studies sorted by date (newest first)
    var sortedStudies: [Study] {
        (studies ?? []).sorted { ($0.studyDate) > ($1.studyDate) }
    }

    /// Study summary (e.g., "CT 2 · MRI 1")
    var studySummary: String {
        let all = studies ?? []
        let grouped = Dictionary(grouping: all) { $0.modality.uppercased() }
        let parts = grouped.keys.sorted().compactMap { key -> String? in
            guard let count = grouped[key]?.count else { return nil }
            return "\(key) \(count)"
        }
        return parts.isEmpty ? "No studies" : parts.joined(separator: " · ")
    }

    /// Total image count
    var totalImageCount: Int {
        (studies ?? []).reduce(0) { $0 + $1.imageCount }
    }

    var formattedCreatedDate: String {
        Self.dateFormatter.string(from: createdDate)
    }

    var formattedUpdatedDate: String {
        Self.dateFormatter.string(from: updatedDate)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return f
    }()
}

// MARK: - Study Helpers

extension Study {
    var modalityIcon: String {
        switch modality.uppercased() {
        case "CT": return "ct.scan"
        case "MRI", "MR": return "brain.head.profile"
        case "US", "ULTRASOUND": return "waveform.path.ecg"
        default: return "doc.text"
        }
    }

    var modalityColor: Color {
        switch modality.uppercased() {
        case "CT": return .blue
        case "MRI", "MR": return .purple
        case "US", "ULTRASOUND": return .teal
        default: return .secondary
        }
    }

    var formattedStudyDate: String {
        guard studyDate.count == 8 else { return studyDate }
        let y = studyDate.prefix(4)
        let m = studyDate.dropFirst(4).prefix(2)
        let d = studyDate.dropFirst(6).prefix(2)
        return "\(y).\(m).\(d)"
    }
}
