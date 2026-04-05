import SwiftUI
import SwiftData

/// Note editor sheet — create new note or edit existing note
struct NoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let chart: Chart
    let note: Note?          // nil = create new note
    let studies: [Study]     // For selecting Study reference

    @State private var title: String = ""
    @State private var content: String = ""
    @State private var selectedStudy: Study?

    init(chart: Chart, note: Note? = nil) {
        self.chart = chart
        self.note = note
        self.studies = chart.sortedStudies
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Note title", text: $title)
                        .textFieldStyle(.plain)
                }

                Section("Related Study") {
                    Picker("Study", selection: $selectedStudy) {
                        Text("None").tag(nil as Study?)
                        ForEach(studies) { study in
                            Text("\(study.modality) — \(study.formattedStudyDate)")
                                .tag(study as Study?)
                        }
                    }
                }

                Section("Content") {
                    TextEditor(text: $content)
                        .frame(minHeight: 200)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(note == nil ? "New Note" : "Edit Note")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveNote() }
                        .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let note {
                    title = note.title
                    content = note.content
                    selectedStudy = note.study
                }
            }
            #if os(macOS)
            .frame(width: 500, height: 480)
            #endif
        }
    }

    private func saveNote() {
        if let note {
            // Edit existing note
            note.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            note.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
            note.study = selectedStudy
            note.updatedDate = Date()
        } else {
            // Create new note
            let newNote = Note(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                study: selectedStudy
            )
            modelContext.insert(newNote)
            if chart.doctorNotes == nil { chart.doctorNotes = [] }
            chart.doctorNotes?.append(newNote)
        }
        chart.updatedDate = Date()
        try? modelContext.save()
        dismiss()
    }
}
