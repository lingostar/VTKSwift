import Foundation
import CryptoKit

// MARK: - DICOM SR Writer

/// Writes a DICOM Structured Report (SR) file in Part 10 format.
///
/// Generates a valid DICOM SR file based on TID 2000 (Basic Diagnostic Imaging Report).
/// The output is Explicit VR Little Endian with standard DICOM preamble.
///
/// Usage:
/// ```swift
/// let template = SRTemplate()
/// template.findings = "Normal chest radiograph."
/// let writer = DICOMSRWriter()
/// let data = try writer.write(template: template)
/// try data.write(to: outputURL)
/// ```
struct DICOMSRWriter {

    // MARK: - Constants

    /// DICOM Transfer Syntax: Explicit VR Little Endian
    private let transferSyntaxUID = "1.2.840.10008.1.2.1"
    /// SOP Class: Basic Text SR Storage
    private let sopClassUID = "1.2.840.10008.5.1.4.1.1.88.11"
    /// Implementation Class UID (generated for VTKSwift)
    private let implementationClassUID = "1.2.826.0.1.3680043.8.498.99"
    /// Implementation Version Name
    private let implementationVersionName = "VTKSWIFT_SR_1"

    // MARK: - Public API

    /// Write an SR template to DICOM Part 10 binary data.
    /// - Parameter template: The SR template containing report content.
    /// - Returns: Complete DICOM file as Data.
    /// - Throws: `SRWriteError` if writing fails.
    func write(template: SRTemplate) throws -> Data {
        var data = Data()

        // 1. DICOM Preamble (128 bytes of 0x00) + "DICM" magic
        data.append(Data(count: 128))
        data.append("DICM".data(using: .ascii)!)

        // 2. File Meta Information (Group 0002)
        let metaInfo = buildFileMetaInformation()
        data.append(metaInfo)

        // 3. Dataset elements in ascending tag order
        //    DICOM requires tags sorted by (group, element)
        appendDataset(to: &data, template: template)

        return data
    }

    /// Write an SR template directly to a file URL.
    /// - Parameters:
    ///   - template: The SR template containing report content.
    ///   - url: Output file URL.
    /// - Throws: `SRWriteError` or file I/O errors.
    func write(template: SRTemplate, to url: URL) throws {
        let data = try write(template: template)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: url)
    }

    // MARK: - UID Generation

    /// Generate a unique DICOM UID based on a root + random suffix.
    private func generateUID() -> String {
        let root = "1.2.826.0.1.3680043.8.498"
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let random = Int.random(in: 1000...9999)
        return "\(root).\(timestamp).\(random)"
    }

    // MARK: - File Meta Information

    private func buildFileMetaInformation() -> Data {
        var meta = Data()
        let sopInstanceUID = generateUID()

        // We'll build meta content first, then prepend the group length

        var metaContent = Data()

        // (0002,0001) File Meta Information Version
        appendExplicitElement(to: &metaContent, group: 0x0002, element: 0x0001,
                              vr: "OB", value: Data([0x00, 0x01]))

        // (0002,0002) Media Storage SOP Class UID
        appendExplicitElement(to: &metaContent, group: 0x0002, element: 0x0002,
                              vr: "UI", stringValue: sopClassUID)

        // (0002,0003) Media Storage SOP Instance UID
        appendExplicitElement(to: &metaContent, group: 0x0002, element: 0x0003,
                              vr: "UI", stringValue: sopInstanceUID)

        // (0002,0010) Transfer Syntax UID
        appendExplicitElement(to: &metaContent, group: 0x0002, element: 0x0010,
                              vr: "UI", stringValue: transferSyntaxUID)

        // (0002,0012) Implementation Class UID
        appendExplicitElement(to: &metaContent, group: 0x0002, element: 0x0012,
                              vr: "UI", stringValue: implementationClassUID)

        // (0002,0013) Implementation Version Name
        appendExplicitElement(to: &metaContent, group: 0x0002, element: 0x0013,
                              vr: "SH", stringValue: implementationVersionName)

        // (0002,0000) File Meta Information Group Length (UL)
        appendExplicitElement(to: &meta, group: 0x0002, element: 0x0000,
                              vr: "UL", uint32Value: UInt32(metaContent.count))

        meta.append(metaContent)
        return meta
    }

    // MARK: - Dataset (Tags in Ascending Order)

    /// Write all dataset elements in proper DICOM ascending tag order.
    private func appendDataset(to data: inout Data, template: SRTemplate) {
        let studyDate = template.studyDate.isEmpty ? currentDICOMDate() : template.studyDate

        // ---- Group 0008: General / Study / Content ----

        // (0008,0005) Specific Character Set
        appendExplicitElement(to: &data, group: 0x0008, element: 0x0005,
                              vr: "CS", stringValue: "ISO_IR 192") // UTF-8

        // (0008,0016) SOP Class UID — Basic Text SR
        appendExplicitElement(to: &data, group: 0x0008, element: 0x0016,
                              vr: "UI", stringValue: sopClassUID)

        // (0008,0018) SOP Instance UID
        appendExplicitElement(to: &data, group: 0x0008, element: 0x0018,
                              vr: "UI", stringValue: generateUID())

        // (0008,0020) Study Date
        appendExplicitElement(to: &data, group: 0x0008, element: 0x0020,
                              vr: "DA", stringValue: studyDate)

        // (0008,0023) Content Date
        appendExplicitElement(to: &data, group: 0x0008, element: 0x0023,
                              vr: "DA", stringValue: currentDICOMDate())

        // (0008,0030) Study Time
        appendExplicitElement(to: &data, group: 0x0008, element: 0x0030,
                              vr: "TM", stringValue: currentDICOMTime())

        // (0008,0033) Content Time
        appendExplicitElement(to: &data, group: 0x0008, element: 0x0033,
                              vr: "TM", stringValue: currentDICOMTime())

        // (0008,0050) Accession Number
        appendExplicitElement(to: &data, group: 0x0008, element: 0x0050,
                              vr: "SH", stringValue: "")

        // (0008,0060) Modality — SR
        appendExplicitElement(to: &data, group: 0x0008, element: 0x0060,
                              vr: "CS", stringValue: "SR")

        // (0008,1030) Study Description
        if !template.studyDescription.isEmpty {
            appendExplicitElement(to: &data, group: 0x0008, element: 0x1030,
                                  vr: "LO", stringValue: template.studyDescription)
        }

        // ---- Group 0010: Patient ----

        // (0010,0010) Patient's Name
        appendExplicitElement(to: &data, group: 0x0010, element: 0x0010,
                              vr: "PN", stringValue: template.patientName)

        // (0010,0020) Patient ID
        appendExplicitElement(to: &data, group: 0x0010, element: 0x0020,
                              vr: "LO", stringValue: template.patientID.isEmpty ? "ANONYMOUS" : template.patientID)

        // ---- Group 0020: Study / Series / Instance ----

        // (0020,000D) Study Instance UID
        appendExplicitElement(to: &data, group: 0x0020, element: 0x000D,
                              vr: "UI", stringValue: generateUID())

        // (0020,000E) Series Instance UID
        appendExplicitElement(to: &data, group: 0x0020, element: 0x000E,
                              vr: "UI", stringValue: generateUID())

        // (0020,0010) Study ID
        appendExplicitElement(to: &data, group: 0x0020, element: 0x0010,
                              vr: "SH", stringValue: "1")

        // (0020,0011) Series Number
        appendExplicitElement(to: &data, group: 0x0020, element: 0x0011,
                              vr: "IS", stringValue: "1")

        // (0020,0013) Instance Number
        appendExplicitElement(to: &data, group: 0x0020, element: 0x0013,
                              vr: "IS", stringValue: "1")

        // ---- Group 0040: SR Document ----

        // (0040,A040) Value Type — root CONTAINER
        appendExplicitElement(to: &data, group: 0x0040, element: 0xA040,
                              vr: "CS", stringValue: "CONTAINER")

        // (0040,A043) Concept Name Code Sequence — "Imaging Report"
        appendCodeSequence(to: &data, tag: (0x0040, 0xA043),
                           designator: "DCM", value: "126000", meaning: "Imaging Report")

        // (0040,A050) Continuity of Content
        appendExplicitElement(to: &data, group: 0x0040, element: 0xA050,
                              vr: "CS", stringValue: "SEPARATE")

        // (0040,A491) Completion Flag
        appendExplicitElement(to: &data, group: 0x0040, element: 0xA491,
                              vr: "CS", stringValue: "COMPLETE")

        // (0040,A493) Verification Flag
        appendExplicitElement(to: &data, group: 0x0040, element: 0xA493,
                              vr: "CS", stringValue: "UNVERIFIED")

        // (0040,A730) Content Sequence — SR content tree
        let contentTree = template.buildContentTree()
        if !contentTree.children.isEmpty {
            var childItems: [Data] = []
            for child in contentTree.children {
                var childData = Data()
                appendContentSequence(to: &childData, item: child)
                childItems.append(childData)
            }
            appendSequence(to: &data, group: 0x0040, element: 0xA730, items: childItems)
        }
    }

    // MARK: - Content Tree Serialization

    /// Serialize a non-root SR content item and its children recursively.
    /// Tags within each item are written in ascending order.
    private func appendContentSequence(to data: inout Data, item: SRContentItem) {
        // (0040,A010) Relationship Type
        appendExplicitElement(to: &data, group: 0x0040, element: 0xA010,
                              vr: "CS", stringValue: item.relationship.rawValue)

        // (0040,A040) Value Type
        appendExplicitElement(to: &data, group: 0x0040, element: 0xA040,
                              vr: "CS", stringValue: item.valueType.rawValue)

        // (0040,A043) Concept Name Code Sequence
        if let cn = item.conceptName {
            appendCodeSequence(to: &data, tag: (0x0040, 0xA043),
                               designator: cn.designator, value: cn.value, meaning: cn.meaning)
        }

        // (0040,A050) Continuity of Content — for container children
        if item.valueType == .container {
            appendExplicitElement(to: &data, group: 0x0040, element: 0xA050,
                                  vr: "CS", stringValue: "SEPARATE")
        }

        // (0040,A160) Text Value — for TEXT items
        if item.valueType == .text, let text = item.textValue {
            appendExplicitElement(to: &data, group: 0x0040, element: 0xA160,
                                  vr: "UT", stringValue: text)
        }

        // (0040,A300) Measured Value Sequence — for NUM items
        if item.valueType == .num, let numVal = item.numericValue {
            var measContent = Data()

            // (0040,08EA) Measurement Units Code Sequence (within measured value)
            if let unit = item.unit {
                appendCodeSequence(to: &measContent, tag: (0x0040, 0x08EA),
                                   designator: unit.designator, value: unit.value, meaning: unit.meaning)
            }

            // (0040,A30A) Numeric Value — DS (Decimal String)
            appendExplicitElement(to: &measContent, group: 0x0040, element: 0xA30A,
                                  vr: "DS", stringValue: String(format: "%.6g", numVal))

            appendSequence(to: &data, group: 0x0040, element: 0xA300, items: [measContent])
        }

        // (0040,A730) Content Sequence — child items
        if !item.children.isEmpty {
            var childItems: [Data] = []
            for child in item.children {
                var childData = Data()
                appendContentSequence(to: &childData, item: child)
                childItems.append(childData)
            }
            appendSequence(to: &data, group: 0x0040, element: 0xA730, items: childItems)
        }
    }

    // MARK: - Low-Level DICOM Element Writers

    /// Write an Explicit VR element with raw Data value.
    private func appendExplicitElement(to data: inout Data, group: UInt16, element: UInt16,
                                       vr: String, value: Data) {
        // Tag
        appendUInt16LE(&data, group)
        appendUInt16LE(&data, element)

        // VR (2 bytes ASCII)
        data.append(vr.data(using: .ascii)!)

        let isExtended = ["OB", "OD", "OF", "OL", "OW", "SQ", "UC", "UN", "UR", "UT"].contains(vr)

        if isExtended {
            // 2 reserved bytes + 4 byte length
            appendUInt16LE(&data, 0x0000)
            appendUInt32LE(&data, UInt32(value.count))
        } else {
            // 2 byte length
            appendUInt16LE(&data, UInt16(value.count))
        }

        data.append(value)
    }

    /// Write an Explicit VR element with a string value (padded to even length).
    private func appendExplicitElement(to data: inout Data, group: UInt16, element: UInt16,
                                       vr: String, stringValue: String) {
        var encoded = stringValue.data(using: .utf8) ?? Data()

        // DICOM requires even-length values
        // UI VR pads with 0x00, others with 0x20 (space)
        if encoded.count % 2 != 0 {
            if vr == "UI" {
                encoded.append(0x00)
            } else {
                encoded.append(0x20) // space
            }
        }

        appendExplicitElement(to: &data, group: group, element: element, vr: vr, value: encoded)
    }

    /// Write an Explicit VR element with a UInt32 value.
    private func appendExplicitElement(to data: inout Data, group: UInt16, element: UInt16,
                                       vr: String, uint32Value: UInt32) {
        var val = uint32Value.littleEndian
        let valData = Data(bytes: &val, count: 4)
        appendExplicitElement(to: &data, group: group, element: element, vr: vr, value: valData)
    }

    /// Write a DICOM Sequence (SQ) with explicit-length items.
    private func appendSequence(to data: inout Data, group: UInt16, element: UInt16, items: [Data]) {
        // Build sequence content: each item wrapped in Item/ItemDelimitation
        var seqContent = Data()

        for itemData in items {
            // Item tag (FFFE,E000) + explicit length
            appendUInt16LE(&seqContent, 0xFFFE)
            appendUInt16LE(&seqContent, 0xE000)
            appendUInt32LE(&seqContent, UInt32(itemData.count))
            seqContent.append(itemData)
        }

        // Write SQ element with explicit length
        appendUInt16LE(&data, group)
        appendUInt16LE(&data, element)
        data.append("SQ".data(using: .ascii)!)
        appendUInt16LE(&data, 0x0000) // reserved
        appendUInt32LE(&data, UInt32(seqContent.count))
        data.append(seqContent)
    }

    /// Write a Code Sequence (scheme designator, code value, code meaning).
    private func appendCodeSequence(to data: inout Data, tag: (UInt16, UInt16),
                                    designator: String, value: String, meaning: String) {
        var itemData = Data()

        // (0008,0100) Code Value
        appendExplicitElement(to: &itemData, group: 0x0008, element: 0x0100,
                              vr: "SH", stringValue: value)

        // (0008,0102) Coding Scheme Designator
        appendExplicitElement(to: &itemData, group: 0x0008, element: 0x0102,
                              vr: "SH", stringValue: designator)

        // (0008,0104) Code Meaning
        appendExplicitElement(to: &itemData, group: 0x0008, element: 0x0104,
                              vr: "LO", stringValue: meaning)

        appendSequence(to: &data, group: tag.0, element: tag.1, items: [itemData])
    }

    // MARK: - Byte Helpers

    private func appendUInt16LE(_ data: inout Data, _ value: UInt16) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 2))
    }

    private func appendUInt32LE(_ data: inout Data, _ value: UInt32) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 4))
    }

    // MARK: - Date/Time Helpers

    private func currentDICOMDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }

    private func currentDICOMTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss.SSSSSS"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }
}

// MARK: - SR Write Errors

enum SRWriteError: LocalizedError {
    case serializationFailed(String)
    case invalidTemplate(String)
    case fileWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .serializationFailed(let detail):
            return "SR 직렬화 실패: \(detail)"
        case .invalidTemplate(let detail):
            return "잘못된 SR 템플릿: \(detail)"
        case .fileWriteFailed(let detail):
            return "SR 파일 쓰기 실패: \(detail)"
        }
    }
}

// MARK: - SR Export Helper

/// Convenience for exporting measurements + report as DICOM SR.
struct SRExportHelper {

    /// Create an SR template from measurement records and report text.
    static func createTemplate(
        patientName: String = "Anonymous",
        patientID: String = "",
        studyDate: String = "",
        modality: String = "",
        studyDescription: String = "",
        findings: String = "",
        impression: String = "",
        recommendation: String = "",
        measurements: [MeasurementRecord] = []
    ) -> SRTemplate {
        var template = SRTemplate()
        template.patientName = patientName
        template.patientID = patientID
        template.studyDate = studyDate
        template.modality = modality
        template.studyDescription = studyDescription
        template.findings = findings
        template.impression = impression
        template.recommendation = recommendation

        // Convert MeasurementRecords to SRMeasurements
        for record in measurements {
            switch record.type {
            case .distance:
                template.measurements.append(.distance(record.value))
            case .angle:
                template.measurements.append(.angle(record.value))
            case .none:
                break
            }
        }

        return template
    }

    /// Export measurements and report text directly to a DICOM SR file.
    static func exportToFile(
        url: URL,
        patientName: String = "Anonymous",
        findings: String = "",
        impression: String = "",
        recommendation: String = "",
        measurements: [MeasurementRecord] = []
    ) throws {
        let template = createTemplate(
            patientName: patientName,
            findings: findings,
            impression: impression,
            recommendation: recommendation,
            measurements: measurements
        )

        let writer = DICOMSRWriter()
        try writer.write(template: template, to: url)
    }
}
