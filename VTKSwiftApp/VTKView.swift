import SwiftUI

/// Rendering mode for the VTK view.
enum VTKViewMode {
    case sphere
    case molecule(pdbPath: String)
}

#if os(iOS)
// MARK: - iOS / iPadOS

struct VTKView: UIViewRepresentable {
    var mode: VTKViewMode = .sphere

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let bridge = VTKBridge(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        configureBridge(bridge)
        context.coordinator.bridge = bridge

        let view = bridge.renderView
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            bridge.render()
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let bridge = context.coordinator.bridge else { return }
        let size = uiView.bounds.size
        if size.width > 0 && size.height > 0 {
            bridge.resize(to: size)
        }
    }

    private func configureBridge(_ bridge: VTKBridge) {
        switch mode {
        case .sphere:
            bridge.setupSphere()
        case .molecule(let pdbPath):
            bridge.loadPDBFile(pdbPath)
        }
    }

    class Coordinator { var bridge: VTKBridge? }
}

#elseif os(macOS)
// MARK: - macOS

struct VTKView: NSViewRepresentable {
    var mode: VTKViewMode = .sphere

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let bridge = VTKBridge(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        configureBridge(bridge)
        context.coordinator.bridge = bridge

        let view = bridge.renderView
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            bridge.render()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let bridge = context.coordinator.bridge else { return }
        let size = nsView.bounds.size
        if size.width > 0 && size.height > 0 {
            bridge.resize(to: size)
        }
    }

    private func configureBridge(_ bridge: VTKBridge) {
        switch mode {
        case .sphere:
            bridge.setupSphere()
        case .molecule(let pdbPath):
            bridge.loadPDBFile(pdbPath)
        }
    }

    class Coordinator { var bridge: VTKBridge? }
}
#endif
