import SwiftData
import Foundation

/// 의사의 환자 노트 — Chart별 여러 개, 선택적으로 Study 참조
@Model
final class Note {
    // CloudKit: 모든 속성에 기본값 필수
    var title: String = ""
    var content: String = ""
    var createdDate: Date = Date()
    var updatedDate: Date = Date()

    var chart: Chart?

    /// 특정 Study와 연관된 노트 (선택) — inverse: Study.notes
    var study: Study?

    init(
        title: String = "",
        content: String = "",
        study: Study? = nil
    ) {
        self.title = title
        self.content = content
        self.study = study
        self.createdDate = Date()
        self.updatedDate = Date()
    }
}

// MARK: - Note Helpers

extension Note {
    var formattedCreatedDate: String {
        Self.dateFormatter.string(from: createdDate)
    }

    var formattedUpdatedDate: String {
        Self.dateFormatter.string(from: updatedDate)
    }

    /// 노트 미리보기 (첫 줄 또는 100자)
    var preview: String {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "Empty note" }
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        if firstLine.count > 100 {
            return String(firstLine.prefix(100)) + "…"
        }
        return firstLine
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd HH:mm"
        return f
    }()
}
