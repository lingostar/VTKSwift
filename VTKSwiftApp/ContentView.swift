import SwiftUI

// MARK: - Sidebar Item

enum SidebarItem: Hashable {
    case sphere
    case dicomViewer
    case volumeViewer

    var title: String {
        switch self {
        case .sphere: return "Sphere"
        case .dicomViewer: return "DICOM Viewer"
        case .volumeViewer: return "3D Volume"
        }
    }

    var icon: String {
        switch self {
        case .sphere: return "globe"
        case .dicomViewer: return "doc.text.image"
        case .volumeViewer: return "cube.transparent"
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @State private var selectedItem: SidebarItem? = .sphere
    @StateObject private var dicomState = DICOMViewState()
    @StateObject private var volumeState = VolumeViewState()

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                Section("Primitives") {
                    Label(SidebarItem.sphere.title,
                          systemImage: SidebarItem.sphere.icon)
                        .tag(SidebarItem.sphere)
                }

                Section("DICOM Reader") {
                    Label(SidebarItem.dicomViewer.title,
                          systemImage: SidebarItem.dicomViewer.icon)
                        .tag(SidebarItem.dicomViewer)
                }

                Section("Volume Rendering") {
                    Label(SidebarItem.volumeViewer.title,
                          systemImage: SidebarItem.volumeViewer.icon)
                        .tag(SidebarItem.volumeViewer)
                }
            }
            .navigationTitle("VTKSwift")
        } detail: {
            switch selectedItem {
            case .sphere:
                SphereView()
            case .dicomViewer:
                DICOMView(state: dicomState)
            case .volumeViewer:
                VolumeView(state: volumeState)
            case nil:
                Text("Select an item from the sidebar")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ContentView()
}
