import SwiftUI
import SwiftData

/// 노트 편집 시트 — 새 노트 작성 또는 기존 노트 수정
struct NoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let chart: Chart
    let note: Note?          // nil이면 새 노트 생성
    let studies: [Study]     // Study 참조 선택용

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
            // 기존 노트 수정
            note.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            note.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
            note.study = selectedStudy
            note.updatedDate = Date()
        } else {
            // 새 노트 생성
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
