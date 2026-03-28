import SwiftUI
import SwiftData

// MARK: - Sidebar Item

enum SidebarItem: Hashable {
    case sphere
    case molecularViewer
    case dicomViewer
    case volumeViewer
    case dicomUSDZ
    case terrainViewer
    case caseList
    case reportEditor
    case reportHistory

    var title: String {
        switch self {
        case .sphere:           return "Sphere"
        case .molecularViewer:  return "Molecular Viewer"
        case .dicomViewer:      return "DICOM Viewer"
        case .volumeViewer:     return "3D Volume"
        case .dicomUSDZ:        return "DICOM USDZ"
        case .terrainViewer:    return "Terrain Viewer"
        case .caseList:         return "Cases"
        case .reportEditor:     return "Report"
        case .reportHistory:    return "Report History"
        }
    }

    var icon: String {
        switch self {
        case .sphere:           return "globe"
        case .molecularViewer:  return "atom"
        case .dicomViewer:      return "doc.text.image"
        case .volumeViewer:     return "cube.transparent"
        case .dicomUSDZ:        return "rotate.3d"
        case .terrainViewer:    return "mountain.2"
        case .caseList:         return "folder.badge.person.crop"
        case .reportEditor:     return "doc.badge.gearshape"
        case .reportHistory:    return "clock.arrow.circlepath"
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @State private var selectedItem: SidebarItem? = .sphere
    @StateObject private var dicomState = DICOMViewState()
    @StateObject private var volumeState = VolumeViewState()
    @StateObject private var usdzState = USDZViewState()
    @StateObject private var terrainState = TerrainViewState()

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                Section("Cases") {
                    Label(SidebarItem.caseList.title,
                          systemImage: SidebarItem.caseList.icon)
                        .tag(SidebarItem.caseList)
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

                Section("Report") {
                    Label(SidebarItem.reportEditor.title,
                          systemImage: SidebarItem.reportEditor.icon)
                        .tag(SidebarItem.reportEditor)
                    Label(SidebarItem.reportHistory.title,
                          systemImage: SidebarItem.reportHistory.icon)
                        .tag(SidebarItem.reportHistory)
                }

                Section("Export") {
                    Label(SidebarItem.dicomUSDZ.title,
                          systemImage: SidebarItem.dicomUSDZ.icon)
                        .tag(SidebarItem.dicomUSDZ)
                }

                Section("Terrain") {
                    Label(SidebarItem.terrainViewer.title,
                          systemImage: SidebarItem.terrainViewer.icon)
                        .tag(SidebarItem.terrainViewer)
                }

                Section("Samples") {
                    Label(SidebarItem.sphere.title,
                          systemImage: SidebarItem.sphere.icon)
                        .tag(SidebarItem.sphere)
                    Label(SidebarItem.molecularViewer.title,
                          systemImage: SidebarItem.molecularViewer.icon)
                        .tag(SidebarItem.molecularViewer)
                }
            }
            .navigationTitle("VTKSwift")
        } detail: {
            switch selectedItem {
            case .caseList:
                CaseListView(dicomState: dicomState, volumeState: volumeState)
            case .sphere:
                SphereView()
            case .molecularViewer:
                MolecularView()
            case .reportEditor:
                ReportEditorView()
            case .reportHistory:
                ReportListView()
            case .dicomViewer:
                DICOMView(state: dicomState)
            case .volumeViewer:
                VolumeView(state: volumeState)
            case .dicomUSDZ:
                USDZView(state: usdzState)
            case .terrainViewer:
                TerrainView(state: terrainState)
            case nil:
                Text("Select an item from the sidebar")
                    .foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchSidebarItem)) { notification in
            if let item = notification.object as? SidebarItem {
                selectedItem = item
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [CaseRecord.self, ReportRecord.self], inMemory: true)
}
