import SwiftUI
import UniformTypeIdentifiers

/// Displays a VTK-rendered molecular structure from PDB files.
/// Uses vtkPDBReader + vtkMoleculeMapper (macOS only).
struct MolecularView: View {
    @State private var pdbPath: String? = nil
    @State private var showFilePicker = false
    @State private var moleculeName: String = "Caffeine"

    var body: some View {
        #if os(macOS)
        moleculeContent
            .navigationTitle("Molecular Viewer")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Open PDB...", systemImage: "doc")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        loadSampleMolecule()
                    } label: {
                        Label("Sample", systemImage: "atom")
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [
                    UTType(filenameExtension: "pdb") ?? .data
                ],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .onAppear {
                if pdbPath == nil {
                    loadSampleMolecule()
                }
            }
        #else
        // iOS placeholder
        VStack(spacing: 16) {
            Image(systemName: "atom")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Molecular Viewer")
                .font(.title2)
            Text("This feature requires macOS.\nVTK chemistry libraries are not available on iOS.")
                .foregroundStyle(.secondary)
                .font(.callout)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Molecular Viewer")
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private var moleculeContent: some View {
        if let path = pdbPath {
            VStack(spacing: 0) {
                VTKView(mode: .molecule(pdbPath: path))
                    .id(path)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()

                // Info bar
                HStack {
                    Image(systemName: "atom")
                        .foregroundStyle(.secondary)
                    Text(moleculeName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
            }
        } else {
            VStack(spacing: 16) {
                ProgressView()
                Text("Loading molecule...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadSampleMolecule() {
        if let path = Bundle.main.path(forResource: "caffeine", ofType: "pdb") {
            moleculeName = "Caffeine (C\u{2088}H\u{2081}\u{2080}N\u{2084}O\u{2082})"
            pdbPath = path
        } else {
            NSLog("[MolecularView] caffeine.pdb not found in bundle")
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didStart = url.startAccessingSecurityScopedResource()
            let path = url.path
            moleculeName = url.deletingPathExtension().lastPathComponent
            pdbPath = path
            if didStart {
                // Keep access alive for VTK to read the file
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    url.stopAccessingSecurityScopedResource()
                }
            }
        case .failure(let error):
            NSLog("[MolecularView] File selection error: \(error)")
        }
    }
    #endif
}
