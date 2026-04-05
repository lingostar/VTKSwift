import SwiftUI
import SwiftData

/// Patient notes list sheet — add/edit/delete notes
struct NotesListView: View {
    let chart: Chart

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showNewNote = false
    @State private var editingNote: Note?

    var sortedNotes: [Note] {
        (chart.doctorNotes ?? []).sorted { $0.updatedDate > $1.updatedDate }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sortedNotes.isEmpty {
                    ContentUnavailableView {
                        Label("No Notes", systemImage: "note.text")
                    } description: {
                        Text("Tap + to add your first note.")
                    } actions: {
                        Button("New Note") { showNewNote = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    notesList
                }
            }
            .navigationTitle("Notes")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewNote = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewNote) {
                NoteEditorView(chart: chart)
            }
            .sheet(item: $editingNote) { note in
                NoteEditorView(chart: chart, note: note)
            }
            #if os(macOS)
            .frame(width: 540, height: 500)
            #endif
        }
    }

    // MARK: - Notes List

    private var notesList: some View {
        List {
            ForEach(sortedNotes) { note in
                Button {
                    editingNote = note
                } label: {
                    NoteRowView(note: note)
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteNotes)
        }
        .listStyle(.plain)
    }

    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            let note = sortedNotes[index]
            modelContext.delete(note)
        }
        chart.updatedDate = Date()
        try? modelContext.save()
    }
}

// MARK: - Note Row

private struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if !note.title.isEmpty {
                    Text(note.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                } else {
                    Text("Untitled")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(note.formattedUpdatedDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(note.preview)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            if let study = note.study {
                HStack(spacing: 4) {
                    Image(systemName: study.modalityIcon)
                        .font(.caption2)
                    Text("\(study.modality) \(study.formattedStudyDate)")
                        .font(.caption2)
                }
                .foregroundColor(study.modalityColor)
            }
        }
        .padding(.vertical, 4)
    }
}
