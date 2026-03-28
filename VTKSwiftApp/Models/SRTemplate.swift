import Foundation

// MARK: - SR Content Item Types

/// DICOM SR content item value types.
enum SRValueType: String {
    case container = "CONTAINER"
    case text = "TEXT"
    case num = "NUM"
    case code = "CODE"
    case date = "DATE"
    case pname = "PNAME"
}

/// DICOM SR relationship types.
enum SRRelationship: String {
    case contains = "CONTAINS"
    case hasObsContext = "HAS OBS CONTEXT"
    case hasConceptMod = "HAS CONCEPT MOD"
}

// MARK: - SR Content Item

/// A single content item in the SR tree.
class SRContentItem {
    let valueType: SRValueType
    let relationship: SRRelationship
    /// Concept Name: (scheme designator, code value, code meaning)
    let conceptName: (designator: String, value: String, meaning: String)?
    /// Text value (for TEXT type).
    var textValue: String?
    /// Numeric value (for NUM type).
    var numericValue: Double?
    /// Unit: (designator, value, meaning)
    var unit: (designator: String, value: String, meaning: String)?
    /// Child items.
    var children: [SRContentItem] = []

    init(
        valueType: SRValueType,
        relationship: SRRelationship = .contains,
        conceptName: (designator: String, value: String, meaning: String)? = nil,
        textValue: String? = nil,
        numericValue: Double? = nil,
        unit: (designator: String, value: String, meaning: String)? = nil
    ) {
        self.valueType = valueType
        self.relationship = relationship
        self.conceptName = conceptName
        self.textValue = textValue
        self.numericValue = numericValue
        self.unit = unit
    }
}

// MARK: - SR Template

/// Structured Report template for a basic diagnostic imaging report.
/// Based on DICOM TID 2000 (Basic Diagnostic Imaging Report), simplified.
struct SRTemplate {

    /// Patient information (may be anonymized).
    var patientName: String = "Anonymous"
    var patientID: String = ""
    var studyDate: String = ""
    var modality: String = ""
    var studyDescription: String = ""

    /// Report content.
    var findings: String = ""
    var impression: String = ""
    var recommendation: String = ""

    /// Measurements from M4 measurement tools.
    var measurements: [SRMeasurement] = []

    /// Build the SR content tree.
    func buildContentTree() -> SRContentItem {
        let root = SRContentItem(
            valueType: .container,
            relationship: .contains,
            conceptName: ("DCM", "126000", "Imaging Report")
        )

        // Findings
        let findingsItem = SRContentItem(
            valueType: .text,
            conceptName: ("DCM", "121071", "Finding"),
            textValue: findings.isEmpty ? " " : findings
        )
        root.children.append(findingsItem)

        // Impression
        let impressionItem = SRContentItem(
            valueType: .text,
            conceptName: ("DCM", "121073", "Impression"),
            textValue: impression.isEmpty ? " " : impression
        )
        root.children.append(impressionItem)

        // Recommendation
        let recommendationItem = SRContentItem(
            valueType: .text,
            conceptName: ("DCM", "121074", "Recommendation"),
            textValue: recommendation.isEmpty ? " " : recommendation
        )
        root.children.append(recommendationItem)

        // Measurements container
        if !measurements.isEmpty {
            let measContainer = SRContentItem(
                valueType: .container,
                conceptName: ("DCM", "125007", "Measurement Group")
            )

            for m in measurements {
                let item = SRContentItem(
                    valueType: .num,
                    conceptName: m.conceptName,
                    numericValue: m.value,
                    unit: m.unit
                )
                measContainer.children.append(item)
            }

            root.children.append(measContainer)
        }

        return root
    }
}

// MARK: - SR Measurement

/// A measurement to include in the SR.
struct SRMeasurement {
    let conceptName: (designator: String, value: String, meaning: String)
    let value: Double
    let unit: (designator: String, value: String, meaning: String)

    /// Create a distance measurement in mm.
    static func distance(_ value: Double) -> SRMeasurement {
        SRMeasurement(
            conceptName: ("DCM", "121206", "Distance"),
            value: value,
            unit: ("UCUM", "mm", "mm")
        )
    }

    /// Create an angle measurement in degrees.
    static func angle(_ value: Double) -> SRMeasurement {
        SRMeasurement(
            conceptName: ("DCM", "121207", "Angle"),
            value: value,
            unit: ("UCUM", "deg", "deg")
        )
    }

    /// Create an area measurement in mm^2.
    static func area(_ value: Double) -> SRMeasurement {
        SRMeasurement(
            conceptName: ("DCM", "121216", "Area"),
            value: value,
            unit: ("UCUM", "mm2", "mm2")
        )
    }
}
