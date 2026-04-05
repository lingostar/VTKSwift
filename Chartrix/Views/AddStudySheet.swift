import SwiftUI

/// Add new Study (DICOM) to existing patient
struct AddStudySheet: View {
    let chart: Chart

    @Environment(\.dismiss) private var dismiss

    @State private var showFolderPicker = false
    @State private var dicomInfo: DICOMFolderInfo?
    @State private var selectedFolderURL: URL?
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Metadata field selection
    @State private var includeStudyDescription = true
    @State private var includeStudyDate = true
    @State private var includePatientAge = true
    @State private var includePatientSex = true

    let onSave: (Study, URL) -> Void

    var body: some View {
        NavigationStack {
            Form {
                // Patient info (read-only)
                Section {
                    HStack {
                        Label {
                            Text(chart.alias)
                                .font(.body)
                                .fontWeight(.medium)
                        } icon: {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                        Spacer()
                        Text(chart.studySummary)
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Patient")
                }

                // DICOM selection
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

                // Metadata selection
                if let info = dicomInfo {
                    Section {
                        metadataFixedRow("Modality", value: info.displayModality, icon: modalityIcon(info.modality))
                        metadataFixedRow("Images", value: "\(info.imageCount)", icon: "photo.stack")

                        if !info.studyDescription.isEmpty {
                            metadataToggleRow("Study", value: info.studyDescription, icon: "doc.text", isOn: $includeStudyDescription)
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

                // Error
                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Study")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addStudy() }
                        .disabled(dicomInfo == nil || selectedFolderURL == nil)
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
            .frame(width: 460, height: dicomInfo != nil ? 520 : 300)
            #endif
        }
    }

    // MARK: - Helpers

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

    private func addStudy() {
        guard let info = dicomInfo, let folderURL = selectedFolderURL else { return }

        let study = Study(
            modality: info.displayModality,
            imageCount: info.imageCount,
            studyDescription: includeStudyDescription ? info.studyDescription : "",
            studyDate: includeStudyDate ? info.studyDate : ""
        )

        onSave(study, folderURL)
        folderURL.stopAccessingSecurityScopedResource()
        dismiss()
    }
}
