import SwiftUI

// MARK: - Sidebar Item

enum SidebarItem: Hashable {
    case sphere
    case dicomViewer

    var title: String {
        switch self {
        case .sphere: return "Sphere"
        case .dicomViewer: return "DICOM Viewer"
        }
    }

    var icon: String {
        switch self {
        case .sphere: return "globe"
        case .dicomViewer: return "doc.text.image"
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @State private var selectedItem: SidebarItem? = .sphere

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
            }
            .navigationTitle("VTKSwift")
        } detail: {
            switch selectedItem {
            case .sphere:
                SphereView()
            case .dicomViewer:
                DICOMView()
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
