import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

/// Add new patient — enter Alias + select DICOM folder → confirm metadata and save
struct NewChartSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var alias = ""
    @State private var notes = ""
    @State private var showFolderPicker = false
    @State private var dicomInfo: DICOMFolderInfo?
    @State private var selectedFolderURL: URL?
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Metadata field selection state
    @State private var includeStudyDescription = true
    @State private var includeSeriesDescription = true
    @State private var includeStudyDate = true
    @State private var includePatientAge = true
    @State private var includePatientSex = true

    let onSave: (Chart, Study, URL) -> Void

    var body: some View {
        NavigationStack {
            Form {
                patientSection
                dicomSection

                if let info = dicomInfo {
                    metadataSelectionSection(info)
                }

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Patient")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { createChart() }
                        .disabled(!canCreate)
                }
            }
            .fileImporter(
                isPresented: $showFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleFolderSelection(result)
            }
            #if os(macOS)
            .frame(width: 460, height: dicomInfo != nil ? 560 : 340)
            #endif
        }
    }

    private var canCreate: Bool {
        !alias.trimmingCharacters(in: .whitespaces).isEmpty
            && dicomInfo != nil
            && selectedFolderURL != nil
    }

    // MARK: - Patient Section

    private var patientSection: some View {
        Section {
            TextField("Pretty Kitty Foot", text: $alias)
                .textFieldStyle(.plain)
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif
            TextField("Notes (optional)", text: $notes)
                .textFieldStyle(.plain)
        } header: {
            Text("Alias Name")
        } footer: {
            Text("For privacy, use a custom alias instead of the real name.")
        }
    }

    // MARK: - DICOM Section

    private var dicomSection: some View {
        Section {
            Button {
                showFolderPicker = true
            } label: {
                HStack {
                    Label("DICOM", systemImage: "folder")
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else if dicomInfo != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let url = selectedFolderURL {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(url.lastPathComponent)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        } header: {
            Text("DICOM Data")
        } footer: {
            Text("Select a folder containing DICOM files (.dcm).")
        }
    }

    // MARK: - Metadata Selection

    private func metadataSelectionSection(_ info: DICOMFolderInfo) -> some View {
        Section {
            metadataFixedRow("Modality", value: info.displayModality, icon: modalityIcon(info.modality))
            metadataFixedRow("Images", value: "\(info.imageCount)", icon: "photo.stack")

            if !info.studyDescription.isEmpty {
                metadataToggleRow("Study", value: info.studyDescription, icon: "doc.text", isOn: $includeStudyDescription)
            }
            if !info.seriesDescription.isEmpty {
                metadataToggleRow("Series", value: info.seriesDescription, icon: "list.bullet", isOn: $includeSeriesDescription)
            }
            if !info.studyDate.isEmpty {
                metadataToggleRow("Date", value: info.formattedStudyDate, icon: "calendar", isOn: $includeStudyDate)
            }
            if !info.patientAge.isEmpty {
                metadataToggleRow("Age", value: info.patientAge, icon: "person", isOn: $includePatientAge)
            }
            if !info.patientSex.isEmpty {
                metadataToggleRow("Sex", value: info.patientSex, icon: "person.fill", isOn: $includePatientSex)
            }
        } header: {
            Text("Study Info (from DICOM)")
        } footer: {
            Text("Toggle which metadata to include with the study.")
        }
    }

    private func metadataFixedRow(_ label: String, value: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundColor(.secondary)
                .font(.callout)
            Spacer()
            Text(value)
                .font(.callout)
                .fontWeight(.medium)
        }
    }

    private func metadataToggleRow(_ label: String, value: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack {
                Label(label, systemImage: icon)
                    .foregroundColor(.secondary)
                    .font(.callout)
                Spacer()
                Text(value)
                    .font(.callout)
                    .fontWeight(.medium)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private func modalityIcon(_ modality: String) -> String {
        switch modality.uppercased() {
        case "CT": return "ct.scan"
        case "MR", "MRI": return "brain.head.profile"
        case "US": return "waveform.path.ecg"
        default: return "doc.text"
        }
    }

    // MARK: - Actions

    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        errorMessage = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Cannot access the selected folder."
                return
            }

            selectedFolderURL = url
            isLoading = true

            DispatchQueue.global(qos: .userInitiated).async {
                let info = DICOMMetadataReader.readFolder(at: url)
                DispatchQueue.main.async {
                    isLoading = false
                    if let info {
                        dicomInfo = info
                    } else {
                        errorMessage = "No DICOM files found in the selected folder."
                        selectedFolderURL = nil
                    }
                }
            }

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func createChart() {
        guard let info = dicomInfo, let folderURL = selectedFolderURL else { return }

        let chart = Chart(
            alias: alias.trimmingCharacters(in: .whitespaces),
            notes: notes
        )

        let study = Study(
            modality: info.displayModality,
            imageCount: info.imageCount,
            studyDescription: includeStudyDescription ? info.studyDescription : "",
            studyDate: includeStudyDate ? info.studyDate : ""
        )

        onSave(chart, study, folderURL)
        folderURL.stopAccessingSecurityScopedResource()
        dismiss()
    }
}
