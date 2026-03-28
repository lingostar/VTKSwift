import SwiftUI

// MARK: - Measurement Mode

/// Active measurement tool mode.
enum MeasurementMode: String, CaseIterable, Identifiable {
    case none = "None"
    case distance = "Distance"
    case angle = "Angle"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .none: return "hand.point.up.left"
        case .distance: return "ruler"
        case .angle: return "angle"
        }
    }
}

// MARK: - Measurement Record

/// A single measurement result.
struct MeasurementRecord: Identifiable {
    let id = UUID()
    let type: MeasurementMode
    /// Points in normalized view coordinates (0...1).
    var points: [CGPoint]
    /// Computed value (mm for distance, degrees for angle).
    var value: Double
    /// Display string.
    var displayString: String
}

// MARK: - Measurement State

/// Observable state for measurement tools.
final class MeasurementState: ObservableObject {
    @Published var mode: MeasurementMode = .none
    @Published var measurements: [MeasurementRecord] = []
    @Published var currentPoints: [CGPoint] = []

    /// Pixel spacing from DICOM (mm per pixel).
    var pixelSpacingX: Double = 1.0
    var pixelSpacingY: Double = 1.0
    /// Image dimensions (pixels).
    var imageWidth: Int = 512
    var imageHeight: Int = 512

    func clearAll() {
        measurements.removeAll()
        currentPoints.removeAll()
    }

    func removeLast() {
        if !measurements.isEmpty {
            measurements.removeLast()
        }
    }
}

// MARK: - Measurement Toolbar

/// Toolbar for selecting measurement tools.
struct MeasurementToolbar: View {
    @ObservedObject var state: MeasurementState

    var body: some View {
        HStack(spacing: 12) {
            ForEach(MeasurementMode.allCases) { mode in
                Button {
                    state.mode = mode
                    state.currentPoints.removeAll()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: mode.icon)
                            .font(.title3)
                        Text(mode.rawValue)
                            .font(.caption2)
                    }
                    .frame(width: 56, height: 40)
                    .background(state.mode == mode ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(state.mode == mode ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 30)

            Button {
                state.removeLast()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title3)
            }
            .disabled(state.measurements.isEmpty)
            .buttonStyle(.plain)

            Button {
                state.clearAll()
            } label: {
                Image(systemName: "trash")
                    .font(.title3)
                    .foregroundStyle(.red)
            }
            .disabled(state.measurements.isEmpty)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Measurement Overlay View

/// Transparent overlay for drawing measurements on top of the DICOM view.
struct MeasurementOverlayView: View {
    @ObservedObject var state: MeasurementState

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Tap gesture area
                if state.mode != .none {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    handleTap(at: value.location, in: geometry.size)
                                }
                        )
                }

                // Draw completed measurements
                ForEach(state.measurements) { measurement in
                    MeasurementShape(measurement: measurement, viewSize: geometry.size)
                }

                // Draw in-progress measurement
                if !state.currentPoints.isEmpty {
                    InProgressMeasurementShape(
                        mode: state.mode,
                        points: state.currentPoints,
                        viewSize: geometry.size
                    )
                }
            }
        }
    }

    private func handleTap(at location: CGPoint, in viewSize: CGSize) {
        guard state.mode != .none else { return }

        // Normalize point to 0...1
        let normalized = CGPoint(
            x: location.x / viewSize.width,
            y: location.y / viewSize.height
        )

        state.currentPoints.append(normalized)

        let requiredPoints: Int
        switch state.mode {
        case .distance: requiredPoints = 2
        case .angle: requiredPoints = 3
        case .none: return
        }

        if state.currentPoints.count >= requiredPoints {
            finalizeMeasurement(viewSize: viewSize)
        }
    }

    private func finalizeMeasurement(viewSize: CGSize) {
        let points = state.currentPoints

        switch state.mode {
        case .distance:
            guard points.count >= 2 else { return }
            let distance = calculateDistance(from: points[0], to: points[1])
            let record = MeasurementRecord(
                type: .distance,
                points: Array(points.prefix(2)),
                value: distance,
                displayString: String(format: "%.1f mm", distance)
            )
            state.measurements.append(record)

        case .angle:
            guard points.count >= 3 else { return }
            let angle = calculateAngle(vertex: points[1], p1: points[0], p2: points[2])
            let record = MeasurementRecord(
                type: .angle,
                points: Array(points.prefix(3)),
                value: angle,
                displayString: String(format: "%.1f\u{00B0}", angle)
            )
            state.measurements.append(record)

        case .none:
            break
        }

        state.currentPoints.removeAll()
    }

    /// Calculate distance in mm using pixel spacing.
    private func calculateDistance(from p1: CGPoint, to p2: CGPoint) -> Double {
        let dx = (p2.x - p1.x) * Double(state.imageWidth) * state.pixelSpacingX
        let dy = (p2.y - p1.y) * Double(state.imageHeight) * state.pixelSpacingY
        return sqrt(dx * dx + dy * dy)
    }

    /// Calculate angle in degrees at vertex between two rays.
    private func calculateAngle(vertex: CGPoint, p1: CGPoint, p2: CGPoint) -> Double {
        let v1 = CGPoint(x: p1.x - vertex.x, y: p1.y - vertex.y)
        let v2 = CGPoint(x: p2.x - vertex.x, y: p2.y - vertex.y)

        let dot = v1.x * v2.x + v1.y * v2.y
        let mag1 = sqrt(v1.x * v1.x + v1.y * v1.y)
        let mag2 = sqrt(v2.x * v2.x + v2.y * v2.y)

        guard mag1 > 0, mag2 > 0 else { return 0 }

        let cosAngle = max(-1, min(1, dot / (mag1 * mag2)))
        return acos(cosAngle) * 180.0 / .pi
    }
}

// MARK: - Measurement Shape Drawing

struct MeasurementShape: View {
    let measurement: MeasurementRecord
    let viewSize: CGSize

    var body: some View {
        ZStack {
            switch measurement.type {
            case .distance:
                distanceLine
            case .angle:
                angleLines
            case .none:
                EmptyView()
            }
        }
    }

    private func toViewPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * viewSize.width, y: p.y * viewSize.height)
    }

    private var distanceLine: some View {
        let p1 = toViewPoint(measurement.points[0])
        let p2 = toViewPoint(measurement.points[1])
        let midpoint = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)

        return ZStack {
            // Line
            Path { path in
                path.move(to: p1)
                path.addLine(to: p2)
            }
            .stroke(Color.yellow, lineWidth: 2)

            // Endpoints
            Circle()
                .fill(Color.yellow)
                .frame(width: 8, height: 8)
                .position(p1)
            Circle()
                .fill(Color.yellow)
                .frame(width: 8, height: 8)
                .position(p2)

            // Label
            Text(measurement.displayString)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.7))
                .cornerRadius(4)
                .position(x: midpoint.x, y: midpoint.y - 16)
        }
    }

    private var angleLines: some View {
        let p1 = toViewPoint(measurement.points[0])
        let vertex = toViewPoint(measurement.points[1])
        let p2 = toViewPoint(measurement.points[2])

        return ZStack {
            // Lines
            Path { path in
                path.move(to: p1)
                path.addLine(to: vertex)
                path.addLine(to: p2)
            }
            .stroke(Color.cyan, lineWidth: 2)

            // Points
            Circle().fill(Color.cyan).frame(width: 8, height: 8).position(p1)
            Circle().fill(Color.cyan).frame(width: 10, height: 10).position(vertex)
            Circle().fill(Color.cyan).frame(width: 8, height: 8).position(p2)

            // Label
            Text(measurement.displayString)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.7))
                .cornerRadius(4)
                .position(x: vertex.x + 20, y: vertex.y - 16)
        }
    }
}

// MARK: - In-Progress Drawing

struct InProgressMeasurementShape: View {
    let mode: MeasurementMode
    let points: [CGPoint]
    let viewSize: CGSize

    var body: some View {
        let viewPoints = points.map { CGPoint(x: $0.x * viewSize.width, y: $0.y * viewSize.height) }

        ZStack {
            // Draw partial lines
            if viewPoints.count >= 1 {
                ForEach(0..<viewPoints.count, id: \.self) { i in
                    Circle()
                        .fill(mode == .distance ? Color.yellow.opacity(0.8) : Color.cyan.opacity(0.8))
                        .frame(width: 10, height: 10)
                        .position(viewPoints[i])
                }
            }
            if viewPoints.count >= 2 {
                Path { path in
                    path.move(to: viewPoints[0])
                    path.addLine(to: viewPoints[1])
                }
                .stroke(
                    mode == .distance ? Color.yellow.opacity(0.6) : Color.cyan.opacity(0.6),
                    style: StrokeStyle(lineWidth: 2, dash: [5, 5])
                )
            }
        }
    }
}

// MARK: - Measurement Results Panel

/// Displays all measurement results in a compact list.
struct MeasurementResultsPanel: View {
    @ObservedObject var state: MeasurementState

    var body: some View {
        if !state.measurements.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("측정 결과")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Text("참고용 측정값입니다")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                ForEach(state.measurements) { m in
                    HStack(spacing: 6) {
                        Image(systemName: m.type == .distance ? "ruler" : "angle")
                            .font(.caption2)
                            .foregroundStyle(m.type == .distance ? .yellow : .cyan)
                        Text(m.displayString)
                            .font(.caption)
                            .monospacedDigit()
                        Spacer()
                        Button {
                            state.measurements.removeAll { $0.id == m.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(8)
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            .frame(maxWidth: 200)
        }
    }
}
