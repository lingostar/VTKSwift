import SwiftData
import Foundation
import CoreGraphics

/// DICOM 슬라이스 위의 측정 결과 (거리/각도) — Study별 영구 저장
@Model
final class Measurement {
    /// "distance" or "angle"
    var measureType: String

    /// 측정이 수행된 슬라이스 인덱스
    var sliceIndex: Int

    /// 정규화 좌표 (0…1) 배열을 JSON 인코딩한 데이터
    var pointsData: Data

    /// 측정 값 (mm 또는 degrees)
    var value: Double

    var createdDate: Date

    @Relationship(inverse: \Study.measurements)
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

    /// 디코딩된 포인트 배열
    var points: [CGPoint] {
        Self.decode(pointsData)
    }

    /// MeasureMode에 대응
    var mode: MeasureMode {
        switch measureType {
        case "distance": return .distance
        case "angle": return .angle
        default: return .none
        }
    }

    /// 포맷된 표시 값
    var formattedValue: String {
        switch measureType {
        case "distance": return String(format: "%.1f mm", value)
        case "angle": return String(format: "%.1f°", value)
        default: return ""
        }
    }
}
