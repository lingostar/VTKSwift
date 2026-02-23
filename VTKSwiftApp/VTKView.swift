//
//  VTKView.swift
//  VTKSwiftApp
//
//  SwiftUI wrapper for VTK rendering view.
//  Uses UIViewRepresentable on iOS/iPadOS, NSViewRepresentable on macOS.
//

import SwiftUI

#if os(iOS)
// MARK: - iOS / iPadOS

struct VTKView: UIViewRepresentable {
    typealias UIViewType = UIView

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let bridge = VTKBridge(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        bridge.setupSphere()
        context.coordinator.bridge = bridge

        let view = bridge.renderView

        // First render after view enters hierarchy
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

    class Coordinator {
        var bridge: VTKBridge?
    }
}

#elseif os(macOS)
// MARK: - macOS

struct VTKView: NSViewRepresentable {
    typealias NSViewType = NSView

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let bridge = VTKBridge(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        bridge.setupSphere()
        context.coordinator.bridge = bridge

        // Return VTK's container view directly (VTK adds its GL view inside it)
        let view = bridge.renderView

        // First render after view enters window hierarchy.
        // VTK's CreateAWindow() is invoked during the first Render() call,
        // which creates the vtkCocoaView as a subview of our container.
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

    class Coordinator {
        var bridge: VTKBridge?
    }
}
#endif
