import Foundation

/// DICOM 파일에서 메타데이터(Modality, Study Description 등)를 읽는 경량 파서
/// 픽셀 데이터는 건너뛰고 헤더 태그만 읽는다.
enum DICOMMetadataReader {

    /// DICOM 폴더에서 첫 번째 파일의 메타데이터 + 파일 수를 반환
    static func readFolder(at url: URL) -> DICOMFolderInfo? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return nil
        }

        var dicomFiles: [URL] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }

            let ext = fileURL.pathExtension.lowercased()
            let name = fileURL.lastPathComponent

            // DICOM 파일: .dcm 확장자이거나, 확장자 없는 파일
            if ext == "dcm" || ext == "dicom" || ext.isEmpty || name == "DICOMDIR" {
                // 매직 넘버 확인 (128 preamble + "DICM")
                if isDICOMFile(fileURL) {
                    dicomFiles.append(fileURL)
                }
            }
        }

        guard let firstFile = dicomFiles.first,
              let data = try? Data(contentsOf: firstFile, options: .mappedIfSafe) else {
            return nil
        }

        let tags = parseTags(from: data)

        return DICOMFolderInfo(
            modality: tags[TagKey.modality] ?? "Unknown",
            studyDescription: tags[TagKey.studyDescription] ?? "",
            seriesDescription: tags[TagKey.seriesDescription] ?? "",
            studyDate: tags[TagKey.studyDate] ?? "",
            patientAge: tags[TagKey.patientAge] ?? "",
            patientSex: tags[TagKey.patientSex] ?? "",
            imageCount: dicomFiles.count
        )
    }

    /// 단일 파일이 DICOM인지 확인
    private static func isDICOMFile(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { handle.closeFile() }
        let header = handle.readData(ofLength: 132)
        guard header.count >= 132 else { return false }
        // 128 preamble + "DICM"
        return header[128] == 0x44 && header[129] == 0x49
            && header[130] == 0x43 && header[131] == 0x4D
    }

    // MARK: - Tag Keys

    private enum TagKey: UInt32 {
        case modality           = 0x0008_0060
        case studyDescription   = 0x0008_1030
        case seriesDescription  = 0x0008_103E
        case studyDate          = 0x0008_0020
        case patientAge         = 0x0010_1010
        case patientSex         = 0x0010_0040
        case transferSyntaxUID  = 0x0002_0010
    }

    // MARK: - Lightweight Parser

    /// 필요한 태그만 빠르게 읽는다. Pixel Data(7FE0,0010) 도달 시 중단.
    private static func parseTags(from data: Data) -> [TagKey: String] {
        var result: [TagKey: String] = [:]
        var offset = 0
        let count = data.count

        // Skip 128-byte preamble + "DICM"
        if count >= 132,
           data[128] == 0x44, data[129] == 0x49,
           data[130] == 0x43, data[131] == 0x4D {
            offset = 132
        }

        // Detect transfer syntax from meta header (group 0002 is always Explicit VR LE)
        var isExplicitVR = true

        while offset + 8 <= count {
            let group = data.readUInt16LE(at: offset)
            let element = data.readUInt16LE(at: offset + 2)

            // Pixel Data — stop parsing
            if group == 0x7FE0 && element == 0x0010 { break }

            // Group 0002 (Meta Header): always Explicit VR LE
            if group == 0x0002 || isExplicitVR {
                guard offset + 8 <= count else { break }
                let vrByte1 = data[offset + 4]
                let vrByte2 = data[offset + 5]
                let vrStr = String(bytes: [vrByte1, vrByte2], encoding: .ascii) ?? "UN"

                let isExtended = ["OB","OD","OF","OL","OW","SQ","UC","UN","UR","UT"].contains(vrStr)
                let valueLength: Int
                let valueOffset: Int

                if isExtended {
                    guard offset + 12 <= count else { break }
                    valueLength = Int(data.readUInt32LE(at: offset + 8))
                    valueOffset = offset + 12
                } else {
                    guard offset + 8 <= count else { break }
                    valueLength = Int(data.readUInt16LE(at: offset + 6))
                    valueOffset = offset + 8
                }

                // Undefined length — skip this element
                if valueLength == 0xFFFFFFFF || valueLength < 0 {
                    offset = valueOffset
                    continue
                }

                // Check transfer syntax to detect Implicit VR after group 0002
                let tagKey32 = (UInt32(group) << 16) | UInt32(element)
                if let key = TagKey(rawValue: tagKey32) {
                    let str = readString(from: data, offset: valueOffset, length: valueLength)
                    result[key] = str

                    // Detect Implicit VR LE
                    if key == .transferSyntaxUID, str == "1.2.840.10008.1.2" {
                        isExplicitVR = false
                    }
                }

                offset = valueOffset + valueLength

                // After meta header ends, switch VR mode
                if group == 0x0002 && offset < count {
                    let nextGroup = data.readUInt16LE(at: offset)
                    if nextGroup > 0x0002 {
                        // Meta header finished — use detected transfer syntax
                    }
                }
            } else {
                // Implicit VR: tag(4) + length(4) + value
                guard offset + 8 <= count else { break }
                let valueLength = Int(data.readUInt32LE(at: offset + 4))
                let valueOffset = offset + 8

                if valueLength == 0xFFFFFFFF || valueLength < 0 {
                    offset = valueOffset
                    continue
                }

                let tagKey32 = (UInt32(group) << 16) | UInt32(element)
                if let key = TagKey(rawValue: tagKey32) {
                    result[key] = readString(from: data, offset: valueOffset, length: valueLength)
                }

                offset = valueOffset + valueLength
            }
        }

        return result
    }

    private static func readString(from data: Data, offset: Int, length: Int) -> String {
        guard offset + length <= data.count, length > 0 else { return "" }
        let sub = data[offset..<(offset + length)]
        return (String(data: sub, encoding: .utf8) ?? String(data: sub, encoding: .ascii) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    }
}

/// DICOM 폴더의 메타데이터 요약
struct DICOMFolderInfo {
    let modality: String
    let studyDescription: String
    let seriesDescription: String
    let studyDate: String          // YYYYMMDD
    let patientAge: String
    let patientSex: String
    let imageCount: Int

    var formattedStudyDate: String {
        guard studyDate.count == 8 else { return studyDate }
        let y = studyDate.prefix(4)
        let m = studyDate.dropFirst(4).prefix(2)
        let d = studyDate.dropFirst(6).prefix(2)
        return "\(y).\(m).\(d)"
    }

    var displayModality: String {
        switch modality.uppercased() {
        case "CT": return "CT"
        case "MR": return "MRI"
        case "US": return "Ultrasound"
        case "CR": return "CR"
        case "DX": return "X-Ray"
        case "PT": return "PET"
        case "NM": return "Nuclear"
        default: return modality
        }
    }
}

// MARK: - Data Extension

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
