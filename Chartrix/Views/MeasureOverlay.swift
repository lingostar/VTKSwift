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
    let points: [CGPoint]   // Normalized coordinates 0...1 within the IMAGE (not the container)
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

/// Tap overlay for distance/angle measurement on DICOM images.
/// All normalized coordinates (0…1) are relative to the **image display rect**,
/// not the full container, to handle `.scaledToFit()` letterboxing correctly.
struct MeasureOverlay: View {
    let mode: MeasureMode
    @Binding var currentPoints: [CGPoint]
    let results: [MeasureResult]
    let viewSize: CGSize
    let sliceImage: CGImage?
    let onComplete: (MeasureResult) -> Void

    // Magnifier state
    @State private var isDragging = false
    @State private var dragScreenPosition: CGPoint = .zero

    private let magnifierSize: CGFloat = 120
    private let magnifierZoom: CGFloat = 2.5

    /// The actual rect where the image is displayed within the container,
    /// accounting for `.scaledToFit()` letterboxing.
    private var imageRect: CGRect {
        guard let cgImage = sliceImage else {
            return CGRect(origin: .zero, size: viewSize)
        }
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        let imageAspect = imgW / imgH
        let containerAspect = viewSize.width / viewSize.height

        let displaySize: CGSize
        if imageAspect > containerAspect {
            // Image wider than container → fit to width, letterbox top/bottom
            displaySize = CGSize(width: viewSize.width,
                                 height: viewSize.width / imageAspect)
        } else {
            // Image taller than container → fit to height, letterbox left/right
            displaySize = CGSize(width: viewSize.height * imageAspect,
                                 height: viewSize.height)
        }
        let origin = CGPoint(
            x: (viewSize.width - displaySize.width) / 2,
            y: (viewSize.height - displaySize.height) / 2
        )
        return CGRect(origin: origin, size: displaySize)
    }

    var body: some View {
        ZStack {
            // Tap gesture area
            if mode != .none {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                dragScreenPosition = value.location
                            }
                            .onEnded { value in
                                isDragging = false
                                let loc = value.location
                                let rect = imageRect

                                // Clamp tap to image bounds
                                let clampedX = min(max(loc.x, rect.minX), rect.maxX)
                                let clampedY = min(max(loc.y, rect.minY), rect.maxY)

                                // Normalize relative to image rect (0…1)
                                let normalized = CGPoint(
                                    x: (clampedX - rect.minX) / rect.width,
                                    y: (clampedY - rect.minY) / rect.height
                                )
                                handleTap(normalized)
                            }
                    )
            }

            // Draw existing measurements
            ForEach(results) { result in
                drawResult(result)
            }

            // Points in progress
            ForEach(Array(currentPoints.enumerated()), id: \.offset) { _, pt in
                let screen = screenPoint(pt)
                Circle()
                    .fill(mode == .distance ? Color.yellow : Color.cyan)
                    .frame(width: 10, height: 10)
                    .position(screen)
            }

            // Magnifier loupe during drag
            if isDragging && mode != .none {
                MagnifierLoupe(
                    screenPosition: dragScreenPosition,
                    viewSize: viewSize,
                    imageRect: imageRect,
                    sliceImage: sliceImage,
                    loupeSize: magnifierSize,
                    zoom: magnifierZoom,
                    crosshairColor: mode == .distance ? .yellow : .cyan
                )
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
        let rect = imageRect
        switch mode {
        case .distance:
            // Convert normalized to actual screen pixels for distance
            let dx = (points[1].x - points[0].x) * rect.width
            let dy = (points[1].y - points[0].y) * rect.height
            return sqrt(dx * dx + dy * dy) * 0.5
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

    // MARK: - Coordinate Conversion

    /// Convert normalized image coordinate (0…1) to screen coordinate
    private func screenPoint(_ normalized: CGPoint) -> CGPoint {
        let rect = imageRect
        return CGPoint(
            x: rect.minX + normalized.x * rect.width,
            y: rect.minY + normalized.y * rect.height
        )
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
}

// MARK: - Magnifier Loupe

/// Circular magnifier showing zoomed portion of the DICOM slice image.
/// Uses direct CGImage cropping to avoid SwiftUI offset/frame layout issues.
struct MagnifierLoupe: View {
    let screenPosition: CGPoint
    let viewSize: CGSize
    let imageRect: CGRect
    let sliceImage: CGImage?
    let loupeSize: CGFloat
    let zoom: CGFloat
    let crosshairColor: Color

    /// Loupe is offset above the touch point on iOS so the finger doesn't block it
    private var loupeOffset: CGFloat {
        #if os(macOS)
        return 0
        #else
        return -(loupeSize / 2 + 40)
        #endif
    }

    /// Final center of the loupe circle on screen
    private var loupeCenter: CGPoint {
        var center = CGPoint(
            x: screenPosition.x,
            y: screenPosition.y + loupeOffset
        )
        // Clamp so loupe stays within view bounds
        let r = loupeSize / 2
        center.x = max(r, min(center.x, viewSize.width - r))
        center.y = max(r, min(center.y, viewSize.height - r))
        return center
    }

    /// Crop the source CGImage to the region around the touch point
    private var croppedImage: CGImage? {
        guard let cgImage = sliceImage,
              imageRect.width > 0, imageRect.height > 0 else { return nil }

        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)

        // Touch position normalized within image (0…1)
        let normX = min(max((screenPosition.x - imageRect.minX) / imageRect.width, 0), 1)
        let normY = min(max((screenPosition.y - imageRect.minY) / imageRect.height, 0), 1)

        // Image pixels per screen point (same for X/Y since aspect is preserved)
        let pxPerPt = imgW / imageRect.width

        // Diameter of the source region in image pixels
        let cropSize = loupeSize / zoom * pxPerPt

        // Crop rect centered on touch point (in image pixel coordinates)
        var cropX = normX * imgW - cropSize / 2
        var cropY = normY * imgH - cropSize / 2

        // Clamp to image bounds
        cropX = min(max(cropX, 0), imgW - cropSize)
        cropY = min(max(cropY, 0), imgH - cropSize)

        let cropRect = CGRect(x: cropX, y: cropY,
                              width: min(cropSize, imgW),
                              height: min(cropSize, imgH))

        return cgImage.cropping(to: cropRect)
    }

    var body: some View {
        ZStack {
            // Zoomed image inside circle (cropped from source)
            if let cropped = croppedImage {
                Image(decorative: cropped, scale: 1.0)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: loupeSize, height: loupeSize)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.black.opacity(0.8))
                    .frame(width: loupeSize, height: loupeSize)
            }

            // Crosshair
            Path { path in
                let center = loupeSize / 2
                let armLen: CGFloat = 12
                path.move(to: CGPoint(x: center - armLen, y: center))
                path.addLine(to: CGPoint(x: center + armLen, y: center))
                path.move(to: CGPoint(x: center, y: center - armLen))
                path.addLine(to: CGPoint(x: center, y: center + armLen))
            }
            .stroke(crosshairColor, lineWidth: 1.5)
            .frame(width: loupeSize, height: loupeSize)

            // Center dot
            Circle()
                .fill(crosshairColor)
                .frame(width: 4, height: 4)

            // Border ring
            Circle()
                .stroke(Color.white.opacity(0.8), lineWidth: 2)
                .frame(width: loupeSize, height: loupeSize)

            Circle()
                .stroke(Color.black.opacity(0.3), lineWidth: 1)
                .frame(width: loupeSize + 2, height: loupeSize + 2)
        }
        .frame(width: loupeSize, height: loupeSize)
        .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
        .position(loupeCenter)
        .allowsHitTesting(false)
    }
}
