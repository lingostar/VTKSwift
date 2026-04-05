import SwiftData
import Foundation

/// Doctor's patient note — multiple per Chart, optionally linked to a Study
@Model
final class Note {
    // CloudKit: all attributes must have default values
    var title: String = ""
    var content: String = ""
    var createdDate: Date = Date()
    var updatedDate: Date = Date()

    var chart: Chart?

    /// Note linked to a specific Study (optional) — inverse: Study.notes
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

    /// Note preview (first line or 100 characters)
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
