import SwiftData
import Foundation
import CoreGraphics

/// Measurement result on DICOM slice (distance/angle) — persisted per Study
@Model
final class Measurement {
    // CloudKit: all attributes must have default values
    /// "distance" or "angle"
    var measureType: String = "distance"

    /// Slice index where measurement was performed
    var sliceIndex: Int = 0

    /// JSON-encoded array of normalized coordinates (0…1)
    var pointsData: Data = Data()

    /// Measurement value (mm or degrees)
    var value: Double = 0.0

    var createdDate: Date = Date()

    var study: Study?

    init(
        measureType: String,
        sliceIndex: Int,
        points: [CGPoint],
        value: Double
    ) {
        self.measureType = measureType
        self.sliceIndex = sliceIndex
        self.pointsData = Self.encode(points)
        self.value = value
        self.createdDate = Date()
    }

    // MARK: - CGPoint Encoding

    /// [CGPoint] → Data (JSON)
    static func encode(_ points: [CGPoint]) -> Data {
        let pairs = points.map { [Double($0.x), Double($0.y)] }
        return (try? JSONEncoder().encode(pairs)) ?? Data()
    }

    /// Data → [CGPoint]
    static func decode(_ data: Data) -> [CGPoint] {
        guard let pairs = try? JSONDecoder().decode([[Double]].self, from: data) else {
            return []
        }
        return pairs.compactMap { pair in
            guard pair.count == 2 else { return nil }
            return CGPoint(x: pair[0], y: pair[1])
        }
    }

    /// Decoded point array
    var points: [CGPoint] {
        Self.decode(pointsData)
    }

    /// Corresponds to MeasureMode
    var mode: MeasureMode {
        switch measureType {
        case "distance": return .distance
        case "angle": return .angle
        default: return .none
        }
    }

    /// Formatted display value
    var formattedValue: String {
        switch measureType {
        case "distance": return String(format: "%.1f mm", value)
        case "angle": return String(format: "%.1f°", value)
        default: return ""
        }
    }
}
