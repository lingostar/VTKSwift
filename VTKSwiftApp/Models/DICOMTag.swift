import Foundation

// MARK: - DICOM Tag

/// Represents a DICOM tag as (group, element) pair.
struct DICOMTag: Hashable, CustomStringConvertible {
    let group: UInt16
    let element: UInt16

    var description: String {
        String(format: "(%04X,%04X)", group, element)
    }

    // -- Patient Module (0010,xxxx) --
    static let patientName       = DICOMTag(group: 0x0010, element: 0x0010)
    static let patientID         = DICOMTag(group: 0x0010, element: 0x0020)
    static let patientBirthDate  = DICOMTag(group: 0x0010, element: 0x0030)
    static let patientSex        = DICOMTag(group: 0x0010, element: 0x0040)
    static let patientAge        = DICOMTag(group: 0x0010, element: 0x1010)
    static let patientWeight     = DICOMTag(group: 0x0010, element: 0x1030)
    static let patientAddress    = DICOMTag(group: 0x0010, element: 0x1040)
    static let patientPhone      = DICOMTag(group: 0x0010, element: 0x2154)

    // -- Study Module (0008,xxxx) --
    static let institutionName   = DICOMTag(group: 0x0008, element: 0x0080)
    static let institutionAddr   = DICOMTag(group: 0x0008, element: 0x0081)
    static let referringPhysician = DICOMTag(group: 0x0008, element: 0x0090)
    static let performingPhysician = DICOMTag(group: 0x0008, element: 0x1050)
    static let operatorName      = DICOMTag(group: 0x0008, element: 0x1070)
    static let stationName       = DICOMTag(group: 0x0008, element: 0x1010)
    static let studyDescription  = DICOMTag(group: 0x0008, element: 0x1030)
    static let seriesDescription = DICOMTag(group: 0x0008, element: 0x103E)
    static let studyDate         = DICOMTag(group: 0x0008, element: 0x0020)
    static let seriesDate        = DICOMTag(group: 0x0008, element: 0x0021)
    static let studyTime         = DICOMTag(group: 0x0008, element: 0x0030)
    static let modality          = DICOMTag(group: 0x0008, element: 0x0060)
    static let sopClassUID       = DICOMTag(group: 0x0008, element: 0x0016)
    static let sopInstanceUID    = DICOMTag(group: 0x0008, element: 0x0018)
    static let studyInstanceUID  = DICOMTag(group: 0x0020, element: 0x000D)
    static let seriesInstanceUID = DICOMTag(group: 0x0020, element: 0x000E)
    static let accessionNumber   = DICOMTag(group: 0x0008, element: 0x0050)

    // -- Burned-in annotation flag --
    static let burnedInAnnotation = DICOMTag(group: 0x0028, element: 0x0301)

    // -- Pixel Data --
    static let pixelData         = DICOMTag(group: 0x7FE0, element: 0x0010)

    // -- Transfer Syntax --
    static let transferSyntaxUID = DICOMTag(group: 0x0002, element: 0x0010)

    // -- Item/Sequence delimiters --
    static let item              = DICOMTag(group: 0xFFFE, element: 0xE000)
    static let itemDelimitation  = DICOMTag(group: 0xFFFE, element: 0xE00D)
    static let sequenceDelimitation = DICOMTag(group: 0xFFFE, element: 0xE0DD)
}

// MARK: - DICOM VR (Value Representation)

/// Common DICOM Value Representations relevant to anonymization.
enum DICOMVR: String {
    case AE, AS, AT, CS, DA, DS, DT, FL, FD, IS, LO, LT
    case OB, OD, OF, OL, OW, PN, SH, SL, SQ, SS, ST
    case TM, UC, UI, UL, UN, UR, US, UT

    /// Whether this VR uses a 4-byte length field (instead of 2-byte).
    var hasExtendedLength: Bool {
        switch self {
        case .OB, .OD, .OF, .OL, .OW, .SQ, .UC, .UN, .UR, .UT:
            return true
        default:
            return false
        }
    }
}

// MARK: - DICOM Parsed Element

/// A parsed DICOM data element with location info for in-place modification.
struct DICOMElement {
    let tag: DICOMTag
    let vr: DICOMVR?
    /// Byte offset of the value in the file data.
    let valueOffset: Int
    /// Length of the value in bytes.
    let valueLength: Int
    /// Byte offset of the entire element (tag start).
    let elementOffset: Int
    /// Total element length (tag + VR + length + value).
    let elementLength: Int

    /// Read the raw value bytes from data.
    func value(in data: Data) -> Data {
        guard valueLength > 0, valueOffset + valueLength <= data.count else {
            return Data()
        }
        return data[valueOffset..<(valueOffset + valueLength)]
    }

    /// Read value as a trimmed string (for text VRs).
    func stringValue(in data: Data) -> String? {
        let raw = value(in: data)
        guard !raw.isEmpty else { return nil }
        return String(data: raw, encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    }
}
