import SwiftData
import Foundation
import SwiftUI

/// 환자 차트 — 한 환자에 여러 Study(CT/MRI 등)를 관리
@Model
final class Chart {
    var alias: String
    var notes: String
    var createdDate: Date
    var updatedDate: Date

    @Relationship(deleteRule: .cascade)
    var studies: [Study]?

    @Relationship(deleteRule: .cascade)
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

/// 개별 DICOM Study — CT/MRI/US 한 세트
@Model
final class Study {
    var modality: String          // CT, MRI, Ultrasound
    var imageCount: Int
    var studyDescription: String
    var studyDate: String         // YYYYMMDD (DICOM에서 읽음)

    /// DICOM 파일 경로 (Documents 기준 상대 경로)
    var dicomDirectoryPath: String?

    /// USDZ 파일 경로
    var usdzFilePath: String?

    var createdDate: Date

    @Relationship(inverse: \Chart.studies)
    var chart: Chart?

    @Relationship(deleteRule: .cascade)
    var measurements: [Measurement]?

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
    /// 가장 최근 Study
    var latestStudy: Study? {
        sortedStudies.first
    }

    /// 날짜순 정렬된 Studies (최신 먼저)
    var sortedStudies: [Study] {
        (studies ?? []).sorted { ($0.studyDate) > ($1.studyDate) }
    }

    /// Study 요약 (예: "CT 2 · MRI 1")
    var studySummary: String {
        let all = studies ?? []
        let grouped = Dictionary(grouping: all) { $0.modality.uppercased() }
        let parts = grouped.keys.sorted().compactMap { key -> String? in
            guard let count = grouped[key]?.count else { return nil }
            return "\(key) \(count)"
        }
        return parts.isEmpty ? "No studies" : parts.joined(separator: " · ")
    }

    /// 전체 이미지 수
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
