import Foundation
import CoreGraphics
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Pure Swift DICOM pixel renderer — generates CGImage from DICOM files without VTK
enum DICOMSliceRenderer {

    /// Returns CGImage for a specific slice from DICOM directory
    static func renderSlice(
        directoryURL: URL,
        sliceIndex: Int,
        windowCenter: Double? = nil,
        windowWidth: Double? = nil
    ) -> CGImage? {
        let files = sortedDICOMFiles(in: directoryURL)
        guard sliceIndex >= 0, sliceIndex < files.count else { return nil }
        return renderFile(files[sliceIndex], windowCenter: windowCenter, windowWidth: windowWidth)
    }

    /// Returns middle slice CGImage from DICOM directory (for thumbnails)
    static func renderMiddleSlice(directoryURL: URL) -> CGImage? {
        let files = sortedDICOMFiles(in: directoryURL)
        guard !files.isEmpty else { return nil }
        let mid = files.count / 2
        return renderFile(files[mid])
    }

    /// Sorted file list from DICOM directory
    static func sortedDICOMFiles(in directoryURL: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directoryURL, includingPropertiesForKeys: nil,
                                              options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            if isDICOMFile(url) {
                files.append(url)
            }
        }
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Generate CGImage from a single DICOM file
    static func renderFile(
        _ url: URL,
        windowCenter: Double? = nil,
        windowWidth: Double? = nil
    ) -> CGImage? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return renderData(data, windowCenter: windowCenter, windowWidth: windowWidth)
    }

    // MARK: - Core Renderer

    static func renderData(
        _ data: Data,
        windowCenter: Double? = nil,
        windowWidth: Double? = nil
    ) -> CGImage? {
        let parser = DICOMPixelParser(data: data)
        guard parser.parse() else { return nil }

        let rows = parser.rows
        let cols = parser.columns
        guard rows > 0, cols > 0 else { return nil }

        let wc = windowCenter ?? parser.windowCenter
        let ww = windowWidth ?? parser.windowWidth
        let slope = parser.rescaleSlope
        let intercept = parser.rescaleIntercept

        // Window/Level → 8-bit grayscale
        let pixelCount = rows * cols
        var grayPixels = [UInt8](repeating: 0, count: pixelCount)

        let halfWindow = ww / 2.0
        let minHU = wc - halfWindow
        let maxHU = wc + halfWindow

        if parser.bitsAllocated == 16 {
            let pixelData = parser.pixelData
            pixelData.withUnsafeBytes { rawPtr in
                let ptr = rawPtr.baseAddress!
                for i in 0..<pixelCount {
                    let rawValue: Double
                    if parser.pixelRepresentation == 1 {
                        // Signed
                        let val = ptr.loadUnaligned(fromByteOffset: i * 2, as: Int16.self).littleEndian
                        rawValue = Double(val)
                    } else {
                        let val = ptr.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self).littleEndian
                        rawValue = Double(val)
                    }

                    let hu = rawValue * slope + intercept
                    let normalized = (hu - minHU) / (maxHU - minHU)
                    let clamped = min(max(normalized, 0), 1)
                    grayPixels[i] = UInt8(clamped * 255)
                }
            }
        } else if parser.bitsAllocated == 8 {
            let pixelData = parser.pixelData
            for i in 0..<min(pixelCount, pixelData.count) {
                let hu = Double(pixelData[i]) * slope + intercept
                let normalized = (hu - minHU) / (maxHU - minHU)
                let clamped = min(max(normalized, 0), 1)
                grayPixels[i] = UInt8(clamped * 255)
            }
        } else {
            return nil
        }

        // Create CGImage
        return grayPixels.withUnsafeBufferPointer { buf -> CGImage? in
            guard let context = CGContext(
                data: UnsafeMutableRawPointer(mutating: buf.baseAddress!),
                width: cols,
                height: rows,
                bitsPerComponent: 8,
                bytesPerRow: cols,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return nil }
            return context.makeImage()
        }
    }

    private static func isDICOMFile(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { handle.closeFile() }
        let header = handle.readData(ofLength: 132)
        guard header.count >= 132 else { return false }
        return header[128] == 0x44 && header[129] == 0x49
            && header[130] == 0x43 && header[131] == 0x4D
    }
}

// MARK: - DICOM Pixel Data Parser

private class DICOMPixelParser {
    let data: Data
    var rows: Int = 0
    var columns: Int = 0
    var bitsAllocated: Int = 16
    var bitsStored: Int = 16
    var pixelRepresentation: Int = 1  // 0=unsigned, 1=signed
    var windowCenter: Double = 40
    var windowWidth: Double = 400
    var rescaleSlope: Double = 1.0
    var rescaleIntercept: Double = 0.0
    var pixelData: Data = Data()

    init(data: Data) {
        self.data = data
    }

    func parse() -> Bool {
        var offset = 0
        let count = data.count

        // Skip preamble + "DICM"
        if count >= 132,
           data[128] == 0x44, data[129] == 0x49,
           data[130] == 0x43, data[131] == 0x4D {
            offset = 132
        }

        var isExplicitVR = true

        while offset + 4 <= count {
            let group = data.readU16(at: offset)
            let element = data.readU16(at: offset + 2)
            let tag = (UInt32(group) << 16) | UInt32(element)

            if group == 0x0002 || isExplicitVR {
                guard offset + 6 <= count else { break }
                let vrByte1 = data[offset + 4]
                let vrByte2 = data[offset + 5]
                let vrStr = String(bytes: [vrByte1, vrByte2], encoding: .ascii) ?? "UN"

                let isExtended = ["OB","OD","OF","OL","OW","SQ","UC","UN","UR","UT"].contains(vrStr)
                let valueLength: Int
                let valueOffset: Int

                if isExtended {
                    guard offset + 12 <= count else { break }
                    let rawLen = data.readU32(at: offset + 8)
                    if rawLen == 0xFFFFFFFF {
                        // Pixel data with undefined length (encapsulated)
                        if tag == 0x7FE00010 {
                            // Try to read encapsulated pixel data
                            return false // Not supported in basic renderer
                        }
                        offset += 12
                        continue
                    }
                    valueLength = Int(rawLen)
                    valueOffset = offset + 12
                } else {
                    guard offset + 8 <= count else { break }
                    valueLength = Int(data.readU16(at: offset + 6))
                    valueOffset = offset + 8
                }

                if valueLength < 0 { break }
                guard valueOffset + valueLength <= count else { break }

                processTag(tag, valueOffset: valueOffset, valueLength: valueLength)

                // Check transfer syntax
                if tag == 0x00020010 {
                    let ts = readString(at: valueOffset, length: valueLength)
                    if ts == "1.2.840.10008.1.2" { isExplicitVR = false }
                }

                // Pixel data — we're done after extraction
                if tag == 0x7FE00010 {
                    pixelData = data[valueOffset..<(valueOffset + valueLength)]
                    return rows > 0 && columns > 0
                }

                offset = valueOffset + valueLength
            } else {
                // Implicit VR
                guard offset + 8 <= count else { break }
                let rawLen = data.readU32(at: offset + 4)
                if rawLen == 0xFFFFFFFF {
                    offset += 8
                    continue
                }
                let valueLength = Int(rawLen)
                let valueOffset = offset + 8

                guard valueOffset + valueLength <= count else { break }
                processTag(tag, valueOffset: valueOffset, valueLength: valueLength)

                if tag == 0x7FE00010 {
                    pixelData = data[valueOffset..<(valueOffset + valueLength)]
                    return rows > 0 && columns > 0
                }

                offset = valueOffset + valueLength
            }
        }

        return rows > 0 && columns > 0 && !pixelData.isEmpty
    }

    private func processTag(_ tag: UInt32, valueOffset: Int, valueLength: Int) {
        switch tag {
        case 0x00280010: // Rows
            rows = Int(data.readU16(at: valueOffset))
        case 0x00280011: // Columns
            columns = Int(data.readU16(at: valueOffset))
        case 0x00280100: // Bits Allocated
            bitsAllocated = Int(data.readU16(at: valueOffset))
        case 0x00280101: // Bits Stored
            bitsStored = Int(data.readU16(at: valueOffset))
        case 0x00280103: // Pixel Representation
            pixelRepresentation = Int(data.readU16(at: valueOffset))
        case 0x00281050: // Window Center
            if let val = Double(readString(at: valueOffset, length: valueLength).components(separatedBy: "\\").first ?? "") {
                windowCenter = val
            }
        case 0x00281051: // Window Width
            if let val = Double(readString(at: valueOffset, length: valueLength).components(separatedBy: "\\").first ?? "") {
                windowWidth = val
            }
        case 0x00281052: // Rescale Intercept
            if let val = Double(readString(at: valueOffset, length: valueLength)) {
                rescaleIntercept = val
            }
        case 0x00281053: // Rescale Slope
            if let val = Double(readString(at: valueOffset, length: valueLength)) {
                rescaleSlope = val
            }
        default:
            break
        }
    }

    private func readString(at offset: Int, length: Int) -> String {
        guard offset + length <= data.count, length > 0 else { return "" }
        let sub = data[offset..<(offset + length)]
        return (String(data: sub, encoding: .utf8) ?? String(data: sub, encoding: .ascii) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    }
}

// MARK: - Data Extension

private extension Data {
    func readU16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian }
    }

    func readU32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian }
    }
}
