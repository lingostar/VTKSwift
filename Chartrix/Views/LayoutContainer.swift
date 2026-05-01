import SwiftUI

// MARK: - Resize Divider

/// Draggable divider that updates a ratio binding (0..1).
/// Use `.horizontal` to drag up/down (changes vertical proportions).
/// Use `.vertical` to drag left/right (changes horizontal proportions).
struct ResizeDivider: View {
    enum Axis { case horizontal, vertical }

    let axis: Axis
    @Binding var ratio: Double
    let totalSize: CGFloat
    var minRatio: Double = 0.2
    var maxRatio: Double = 0.8

    @State private var startRatio: Double?

    private let thickness: CGFloat = 8
    private let handleLength: CGFloat = 32
    private let handleThickness: CGFloat = 3

    var body: some View {
        Group {
            switch axis {
            case .horizontal:
                ZStack {
                    Color.clear
                    Capsule()
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: handleLength, height: handleThickness)
                }
                .frame(maxWidth: .infinity)
                .frame(height: thickness)
            case .vertical:
                ZStack {
                    Color.clear
                    Capsule()
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: handleThickness, height: handleLength)
                }
                .frame(width: thickness)
                .frame(maxHeight: .infinity)
            }
        }
        .contentShape(Rectangle())
        #if os(macOS)
        .onHover { inside in
            if inside {
                switch axis {
                case .horizontal: NSCursor.resizeUpDown.push()
                case .vertical: NSCursor.resizeLeftRight.push()
                }
            } else {
                NSCursor.pop()
            }
        }
        #endif
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    if startRatio == nil { startRatio = ratio }
                    let translation = axis == .horizontal
                        ? value.translation.height
                        : value.translation.width
                    let delta = totalSize > 0 ? Double(translation) / Double(totalSize) : 0
                    let new = (startRatio ?? ratio) + delta
                    ratio = max(minRatio, min(maxRatio, new))
                }
                .onEnded { _ in
                    startRatio = nil
                }
        )
    }
}

// MARK: - Layout Container

/// Renders the viewer grid with resize dividers between rows/columns.
struct LayoutContainer: View {
    @ObservedObject var manager: ViewerLayoutManager
    let allStudies: [Study]

    var body: some View {
        GeometryReader { geo in
            let dividerThickness: CGFloat = 8
            let totalWidth = geo.size.width
            let totalHeight = geo.size.height

            // Horizontal (col) sizing
            let colDividerSpace = manager.cols == 2 ? dividerThickness : 0
            let availableWidth = max(0, totalWidth - colDividerSpace)
            let leftWidth = manager.cols == 2
                ? availableWidth * manager.colRatio
                : availableWidth
            let rightWidth = availableWidth - leftWidth

            // Vertical (row) sizing
            let rowDividerSpace = manager.rows == 2 ? dividerThickness : 0
            let availableHeight = max(0, totalHeight - rowDividerSpace)
            let topHeight = manager.rows == 2
                ? availableHeight * manager.rowRatio
                : availableHeight
            let bottomHeight = availableHeight - topHeight

            VStack(spacing: 0) {
                // Top row
                rowView(
                    rowIndex: 0,
                    leftWidth: leftWidth,
                    rightWidth: rightWidth,
                    height: topHeight
                )

                // Horizontal divider + bottom row
                if manager.rows == 2 {
                    ResizeDivider(
                        axis: .horizontal,
                        ratio: $manager.rowRatio,
                        totalSize: availableHeight
                    )

                    rowView(
                        rowIndex: 1,
                        leftWidth: leftWidth,
                        rightWidth: rightWidth,
                        height: bottomHeight
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(rowIndex: Int, leftWidth: CGFloat, rightWidth: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            panelView(row: rowIndex, col: 0)
                .frame(width: leftWidth, height: height)

            if manager.cols == 2 {
                ResizeDivider(
                    axis: .vertical,
                    ratio: $manager.colRatio,
                    totalSize: leftWidth + rightWidth
                )

                panelView(row: rowIndex, col: 1)
                    .frame(width: rightWidth, height: height)
            }
        }
    }

    private func panelView(row r: Int, col c: Int) -> some View {
        let panel = manager.panels[r][c]
        return ViewerPanel(
            state: panel,
            manager: manager,
            allStudies: allStudies,
            canSplitHorizontal: manager.canSplitHorizontal,
            canSplitVertical: manager.canSplitVertical,
            canClose: manager.canClose,
            onSplitHorizontal: { manager.splitHorizontal() },
            onSplitVertical: { manager.splitVertical() },
            onClose: { manager.close(panel: panel) }
        )
    }
}
