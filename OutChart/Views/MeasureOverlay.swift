import SwiftUI

// MARK: - Measure Mode

enum MeasureMode: CaseIterable {
    case none
    case distance
    case angle

    var label: String {
        switch self {
        case .none: return "None"
        case .distance: return "Distance"
        case .angle: return "Angle"
        }
    }

    var icon: String {
        switch self {
        case .none: return "hand.point.up.left"
        case .distance: return "ruler"
        case .angle: return "angle"
        }
    }

    var requiredPoints: Int {
        switch self {
        case .none: return 0
        case .distance: return 2
        case .angle: return 3
        }
    }
}

// MARK: - Measure Result

struct MeasureResult: Identifiable {
    let id = UUID()
    let type: MeasureMode
    let points: [CGPoint]   // 정규화 좌표 0...1
    let value: Double        // mm or degrees

    var formattedValue: String {
        switch type {
        case .distance: return String(format: "%.1f mm", value)
        case .angle: return String(format: "%.1f°", value)
        case .none: return ""
        }
    }
}

// MARK: - Measure Overlay

/// DICOM 이미지 위에 거리/각도 측정을 위한 탭 오버레이
struct MeasureOverlay: View {
    let mode: MeasureMode
    @Binding var currentPoints: [CGPoint]
    let results: [MeasureResult]
    let viewSize: CGSize
    let onComplete: (MeasureResult) -> Void

    var body: some View {
        ZStack {
            // 탭 제스처 영역
            if mode != .none {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                let normalized = CGPoint(
                                    x: value.location.x / viewSize.width,
                                    y: value.location.y / viewSize.height
                                )
                                handleTap(normalized)
                            }
                    )
            }

            // 기존 측정 결과 그리기
            ForEach(results) { result in
                drawResult(result)
            }

            // 진행 중인 포인트
            ForEach(Array(currentPoints.enumerated()), id: \.offset) { idx, pt in
                let screen = screenPoint(pt)
                Circle()
                    .fill(mode == .distance ? Color.yellow : Color.cyan)
                    .frame(width: 10, height: 10)
                    .position(screen)
            }

            // 진행 중인 선
            if mode == .distance, currentPoints.count == 1 {
                // 첫 번째 점만 표시 (두 번째 대기)
            }
        }
    }

    private func handleTap(_ normalized: CGPoint) {
        guard mode != .none else { return }
        var points = currentPoints
        points.append(normalized)

        if points.count >= mode.requiredPoints {
            let value = calculateValue(mode: mode, points: points)
            let result = MeasureResult(type: mode, points: points, value: value)
            onComplete(result)
        } else {
            currentPoints = points
        }
    }

    private func calculateValue(mode: MeasureMode, points: [CGPoint]) -> Double {
        // 간이 계산 — pixelSpacing 없이 픽셀 단위 (추후 DICOM에서 읽기)
        switch mode {
        case .distance:
            let dx = (points[1].x - points[0].x) * viewSize.width
            let dy = (points[1].y - points[0].y) * viewSize.height
            return sqrt(dx * dx + dy * dy) * 0.5 // 대략적 mm 환산
        case .angle:
            let v1 = CGPoint(x: points[0].x - points[1].x, y: points[0].y - points[1].y)
            let v2 = CGPoint(x: points[2].x - points[1].x, y: points[2].y - points[1].y)
            let dot = v1.x * v2.x + v1.y * v2.y
            let mag1 = sqrt(v1.x * v1.x + v1.y * v1.y)
            let mag2 = sqrt(v2.x * v2.x + v2.y * v2.y)
            guard mag1 > 0, mag2 > 0 else { return 0 }
            let cosAngle = min(max(dot / (mag1 * mag2), -1), 1)
            return acos(cosAngle) * 180 / .pi
        case .none:
            return 0
        }
    }

    // MARK: - Drawing

    @ViewBuilder
    private func drawResult(_ result: MeasureResult) -> some View {
        let color: Color = result.type == .distance ? .yellow : .cyan

        switch result.type {
        case .distance:
            if result.points.count >= 2 {
                let p1 = screenPoint(result.points[0])
                let p2 = screenPoint(result.points[1])
                let mid = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)

                Path { path in
                    path.move(to: p1)
                    path.addLine(to: p2)
                }
                .stroke(color, lineWidth: 2)

                Circle().fill(color).frame(width: 8, height: 8).position(p1)
                Circle().fill(color).frame(width: 8, height: 8).position(p2)

                Text(result.formattedValue)
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(color.opacity(0.8))
                    .cornerRadius(4)
                    .position(CGPoint(x: mid.x, y: mid.y - 14))
            }

        case .angle:
            if result.points.count >= 3 {
                let p1 = screenPoint(result.points[0])
                let vertex = screenPoint(result.points[1])
                let p2 = screenPoint(result.points[2])

                Path { path in
                    path.move(to: p1)
                    path.addLine(to: vertex)
                    path.addLine(to: p2)
                }
                .stroke(color, lineWidth: 2)

                Circle().fill(color).frame(width: 8, height: 8).position(p1)
                Circle().fill(color).frame(width: 12, height: 12).position(vertex)
                Circle().fill(color).frame(width: 8, height: 8).position(p2)

                Text(result.formattedValue)
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(color.opacity(0.8))
                    .cornerRadius(4)
                    .position(CGPoint(x: vertex.x + 20, y: vertex.y - 14))
            }

        case .none:
            EmptyView()
        }
    }

    private func screenPoint(_ normalized: CGPoint) -> CGPoint {
        CGPoint(x: normalized.x * viewSize.width, y: normalized.y * viewSize.height)
    }
}
