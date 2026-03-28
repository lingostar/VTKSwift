import Foundation
import CryptoKit

// MARK: - Anonymization Policy

/// Action to take for a specific DICOM tag during anonymization.
enum AnonymizationAction {
    /// Remove the tag entirely.
    case remove
    /// Replace value with a fixed string.
    case replace(String)
    /// Replace value with a hashed version (deterministic pseudonym).
    case hash
    /// Keep the tag unchanged.
    case keep
}

// MARK: - Anonymization Profile

/// Defines which tags to anonymize and how.
struct AnonymizationProfile {
    /// Custom alias to use as patient name.
    var patientAlias: String = "Anonymous"
    /// Whether to preserve patient age (useful for clinical reference).
    var keepAge: Bool = true
    /// Whether to preserve study/series descriptions.
    var keepDescriptions: Bool = true
    /// Whether to preserve study date (useful for timeline).
    var keepStudyDate: Bool = false

    /// Tag-level actions. Tags not listed here are passed through unchanged.
    var tagActions: [DICOMTag: AnonymizationAction] {
        var actions: [DICOMTag: AnonymizationAction] = [
            // Always anonymize
            .patientName:        .replace(patientAlias),
            .patientID:          .hash,
            .patientBirthDate:   .remove,
            .patientAddress:     .remove,
            .patientPhone:       .remove,
            .institutionName:    .remove,
            .institutionAddr:    .remove,
            .referringPhysician: .remove,
            .performingPhysician: .remove,
            .operatorName:       .remove,
            .stationName:        .remove,
            .accessionNumber:    .hash,
        ]

        // Conditional
        if !keepAge {
            actions[.patientAge] = .remove
        }
        if !keepDescriptions {
            actions[.studyDescription] = .remove
            actions[.seriesDescription] = .remove
        }
        if !keepStudyDate {
            actions[.studyDate] = .remove
            actions[.studyTime] = .remove
            actions[.seriesDate] = .remove
        }

        return actions
    }
}

// MARK: - Anonymization Result

/// Result of anonymizing a single DICOM file.
struct AnonymizationFileResult {
    let sourceURL: URL
    let outputURL: URL
    let tagsModified: Int
    let tagsRemoved: Int
    let hasBurnedInAnnotation: Bool
}

/// Result of anonymizing an entire DICOM directory.
struct AnonymizationResult {
    let files: [AnonymizationFileResult]
    let outputDirectory: URL
    var totalFiles: Int { files.count }
    var totalTagsModified: Int { files.reduce(0) { $0 + $1.tagsModified } }
    var totalTagsRemoved: Int { files.reduce(0) { $0 + $1.tagsRemoved } }
    var hasBurnedInAnnotations: Bool { files.contains { $0.hasBurnedInAnnotation } }
}

// MARK: - DICOM Anonymizer

/// Engine for anonymizing DICOM files by modifying/removing PHI tags.
///
/// The anonymizer operates non-destructively: it reads the original file,
/// modifies a copy in memory, and writes to a separate output directory.
/// The original files are never modified.
///
/// Usage:
/// ```swift
/// let anonymizer = DICOMAnonymizer()
/// var profile = AnonymizationProfile()
/// profile.patientAlias = "Case-001"
/// let result = try anonymizer.anonymizeDirectory(at: sourceURL,
///                                                outputDirectory: outputURL,
///                                                profile: profile)
/// ```
final class DICOMAnonymizer {

    /// A stable hash salt to ensure deterministic but non-reversible pseudonyms.
    private let hashSalt: String

    init(hashSalt: String = "VTKSwift-Anonymizer-2026") {
        self.hashSalt = hashSalt
    }

    // MARK: - Public API

    /// Anonymize all DICOM files in a directory.
    /// - Parameters:
    ///   - sourceDirectory: URL of the directory containing .dcm files.
    ///   - outputDirectory: URL where anonymized copies will be written.
    ///   - profile: Anonymization profile defining actions per tag.
    /// - Returns: Anonymization result with per-file details.
    func anonymizeDirectory(
        at sourceDirectory: URL,
        outputDirectory: URL,
        profile: AnonymizationProfile = AnonymizationProfile()
    ) throws -> AnonymizationResult {
        // Create output directory
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        // Find all DICOM files (common extensions)
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: sourceDirectory, includingPropertiesForKeys: nil)
        let dicomFiles = contents.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "dcm" || ext == "dicom" || ext == "" || ext == "ima"
        }.filter { url in
            // Also accept files without extension if they look like DICOM (have DICM magic)
            if url.pathExtension.isEmpty {
                return isDICOMFile(at: url)
            }
            return true
        }

        var results: [AnonymizationFileResult] = []

        for sourceFile in dicomFiles {
            let outputFile = outputDirectory.appendingPathComponent(sourceFile.lastPathComponent)
            let result = try anonymizeFile(at: sourceFile, outputURL: outputFile, profile: profile)
            results.append(result)
        }

        return AnonymizationResult(files: results, outputDirectory: outputDirectory)
    }

    /// Anonymize a single DICOM file.
    func anonymizeFile(
        at sourceURL: URL,
        outputURL: URL,
        profile: AnonymizationProfile = AnonymizationProfile()
    ) throws -> AnonymizationFileResult {
        var data = try Data(contentsOf: sourceURL)
        let actions = profile.tagActions

        // Parse elements and collect modifications
        let elements = parseDICOMElements(data: data)

        var tagsModified = 0
        var tagsRemoved = 0
        var hasBurnedIn = false

        // Check burned-in annotation flag
        if let burnedInElement = elements.first(where: { $0.tag == .burnedInAnnotation }) {
            let value = burnedInElement.stringValue(in: data)
            if value?.uppercased() == "YES" {
                hasBurnedIn = true
            }
        }

        // Process elements in reverse order (so offsets remain valid after modification)
        let sortedElements = elements.sorted { $0.elementOffset > $1.elementOffset }

        for element in sortedElements {
            guard let action = actions[element.tag] else { continue }

            // Skip pixel data and other huge elements
            if element.tag == .pixelData { continue }

            switch action {
            case .remove:
                // Remove the entire element
                let range = element.elementOffset..<(element.elementOffset + element.elementLength)
                if range.upperBound <= data.count {
                    data.removeSubrange(range)
                    tagsRemoved += 1
                }

            case .replace(let newValue):
                replaceElementValue(in: &data, element: element, with: newValue)
                tagsModified += 1

            case .hash:
                let originalValue = element.stringValue(in: data) ?? ""
                let hashedValue = pseudonymize(originalValue)
                replaceElementValue(in: &data, element: element, with: hashedValue)
                tagsModified += 1

            case .keep:
                break
            }
        }

        // Write output
        try data.write(to: outputURL)

        return AnonymizationFileResult(
            sourceURL: sourceURL,
            outputURL: outputURL,
            tagsModified: tagsModified,
            tagsRemoved: tagsRemoved,
            hasBurnedInAnnotation: hasBurnedIn
        )
    }

    // MARK: - DICOM Metadata Extraction

    /// Extract basic DICOM metadata from a file without full anonymization.
    /// Useful for displaying info before anonymization.
    func extractMetadata(from url: URL) -> DICOMMetadata? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let elements = parseDICOMElements(data: data)

        func stringFor(_ tag: DICOMTag) -> String? {
            elements.first(where: { $0.tag == tag })?.stringValue(in: data)
        }

        return DICOMMetadata(
            patientName: stringFor(.patientName),
            patientID: stringFor(.patientID),
            patientBirthDate: stringFor(.patientBirthDate),
            patientAge: stringFor(.patientAge),
            patientSex: stringFor(.patientSex),
            institutionName: stringFor(.institutionName),
            studyDate: stringFor(.studyDate),
            modality: stringFor(.modality),
            studyDescription: stringFor(.studyDescription),
            seriesDescription: stringFor(.seriesDescription),
            hasBurnedInAnnotation: stringFor(.burnedInAnnotation)?.uppercased() == "YES"
        )
    }

    // MARK: - Private: DICOM Parser

    /// Check if a file is DICOM by looking for "DICM" magic at offset 128.
    private func isDICOMFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { handle.closeFile() }
        handle.seek(toFileOffset: 128)
        let magic = handle.readData(ofLength: 4)
        return magic == Data("DICM".utf8)
    }

    /// Parse DICOM data elements from binary data.
    /// Supports both Explicit and Implicit VR Little Endian.
    private func parseDICOMElements(data: Data) -> [DICOMElement] {
        var elements: [DICOMElement] = []
        var offset = 0

        // Check for DICOM preamble (128 bytes + "DICM")
        if data.count > 132 {
            let magic = data[128..<132]
            if magic == Data("DICM".utf8) {
                offset = 132
            }
        }

        // Detect transfer syntax: parse File Meta Information group (0002,xxxx)
        // which is always Explicit VR Little Endian
        var isExplicitVR = true
        var inMetaGroup = true

        while offset + 8 <= data.count {
            let group = data.readUInt16LE(at: offset)
            let element = data.readUInt16LE(at: offset + 2)
            let tag = DICOMTag(group: group, element: element)

            // Stop at pixel data to avoid huge scans
            if tag == .pixelData { break }

            // Sequence delimiters
            if group == 0xFFFE {
                let length = data.readUInt32LE(at: offset + 4)
                let totalLen = 8 + (length == 0xFFFFFFFF ? 0 : Int(length))
                offset += max(totalLen, 8)
                continue
            }

            // After meta group ends, check transfer syntax for VR mode
            if inMetaGroup && group > 0x0002 {
                inMetaGroup = false
                // Default to Explicit VR for modern DICOM; most files are Explicit VR LE
            }

            if inMetaGroup || isExplicitVR {
                // Explicit VR: 2-byte VR code after tag
                guard offset + 8 <= data.count else { break }
                let vrByte0 = data[offset + 4]
                let vrByte1 = data[offset + 5]

                // Check if VR looks valid (two uppercase ASCII letters)
                let isValidVR = (vrByte0 >= 0x41 && vrByte0 <= 0x5A) &&
                                (vrByte1 >= 0x41 && vrByte1 <= 0x5A)

                if !isValidVR && !inMetaGroup {
                    // Likely Implicit VR — switch mode
                    isExplicitVR = false
                    // Re-parse this element as implicit VR
                    let length = data.readUInt32LE(at: offset + 4)
                    if length == 0xFFFFFFFF {
                        // Undefined length — skip
                        offset += 8
                        continue
                    }
                    let valueLen = Int(length)
                    let elemLen = 8 + valueLen

                    if offset + elemLen > data.count { break }

                    elements.append(DICOMElement(
                        tag: tag,
                        vr: nil,
                        valueOffset: offset + 8,
                        valueLength: valueLen,
                        elementOffset: offset,
                        elementLength: elemLen
                    ))
                    offset += elemLen
                    continue
                }

                let vrString = String(bytes: [vrByte0, vrByte1], encoding: .ascii) ?? "UN"
                let vr = DICOMVR(rawValue: vrString)

                let valueOffset: Int
                let valueLength: Int
                let elementLength: Int

                if vr?.hasExtendedLength == true {
                    // 2 bytes VR + 2 bytes reserved + 4 bytes length
                    guard offset + 12 <= data.count else { break }
                    let length = data.readUInt32LE(at: offset + 8)
                    if length == 0xFFFFFFFF {
                        // Undefined length sequence — skip carefully
                        offset += 12
                        continue
                    }
                    valueLength = Int(length)
                    valueOffset = offset + 12
                    elementLength = 12 + valueLength
                } else {
                    // 2 bytes VR + 2 bytes length
                    let length = data.readUInt16LE(at: offset + 6)
                    valueLength = Int(length)
                    valueOffset = offset + 8
                    elementLength = 8 + valueLength
                }

                if offset + elementLength > data.count { break }

                elements.append(DICOMElement(
                    tag: tag,
                    vr: vr,
                    valueOffset: valueOffset,
                    valueLength: valueLength,
                    elementOffset: offset,
                    elementLength: elementLength
                ))
                offset += elementLength

                // Check transfer syntax to determine VR mode for dataset
                if tag == .transferSyntaxUID {
                    let tsUID = elements.last?.stringValue(in: data) ?? ""
                    // 1.2.840.10008.1.2 = Implicit VR Little Endian
                    if tsUID == "1.2.840.10008.1.2" {
                        isExplicitVR = false
                    }
                }
            } else {
                // Implicit VR: no VR field, 4-byte length after tag
                guard offset + 8 <= data.count else { break }
                let length = data.readUInt32LE(at: offset + 4)
                if length == 0xFFFFFFFF {
                    offset += 8
                    continue
                }
                let valueLen = Int(length)
                let elemLen = 8 + valueLen

                if offset + elemLen > data.count { break }

                elements.append(DICOMElement(
                    tag: tag,
                    vr: nil,
                    valueOffset: offset + 8,
                    valueLength: valueLen,
                    elementOffset: offset,
                    elementLength: elemLen
                ))
                offset += elemLen
            }
        }

        return elements
    }

    // MARK: - Private: Value Replacement

    /// Replace a DICOM element's value in-place, padding to original length.
    /// For text VRs (PN, LO, SH, etc.), pads with spaces.
    private func replaceElementValue(in data: inout Data, element: DICOMElement, with newValue: String) {
        let valueLength = element.valueLength
        guard valueLength > 0, element.valueOffset + valueLength <= data.count else { return }

        // Encode new value, truncate if longer than original
        var encoded = Array(newValue.utf8.prefix(valueLength))
        // Pad with spaces to fill original length (DICOM text padding)
        while encoded.count < valueLength {
            encoded.append(0x20) // space
        }

        let range = element.valueOffset..<(element.valueOffset + valueLength)
        data.replaceSubrange(range, with: encoded)
    }

    /// Generate a deterministic pseudonym from an input string.
    private func pseudonymize(_ input: String) -> String {
        let combined = hashSalt + input
        let digest = SHA256.hash(data: Data(combined.utf8))
        // Take first 8 bytes → 16 hex chars
        let hex = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }
}

// MARK: - DICOM Metadata

/// Basic metadata extracted from a DICOM file (pre-anonymization display).
struct DICOMMetadata {
    var patientName: String?
    var patientID: String?
    var patientBirthDate: String?
    var patientAge: String?
    var patientSex: String?
    var institutionName: String?
    var studyDate: String?
    var modality: String?
    var studyDescription: String?
    var seriesDescription: String?
    var hasBurnedInAnnotation: Bool = false
}

// MARK: - Data Extension for Little-Endian Reads

private extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian
        }
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
    }
}
