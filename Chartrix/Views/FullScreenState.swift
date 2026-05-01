import SwiftUI

/// App-level fullscreen state shared between ContentView (which owns the
/// NavigationSplitView and sidebar) and ChartDetailView (which owns the
/// fullscreen toggle and the immersive panel UI).
@MainActor
final class FullScreenState: ObservableObject {
    @Published var isFullScreen: Bool = false
}
