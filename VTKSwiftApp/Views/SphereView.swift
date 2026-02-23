import SwiftUI

/// Displays a VTK-rendered 3D sphere with trackball camera interaction.
struct SphereView: View {
    var body: some View {
        VTKView(mode: .sphere)
            .ignoresSafeArea()
            .navigationTitle("Sphere")
    }
}
