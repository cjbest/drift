import SwiftUI

struct NoteListView: View {
    @EnvironmentObject var noteStore: NoteStore
    @Binding var isPresented: Bool
    @State private var searchQuery = ""
    @FocusState private var isSearchFocused: Bool

    var filteredNotes: [Note] {
        let notes = noteStore.notes.filter { $0.path != noteStore.currentNote?.path }
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return notes }
        let q = searchQuery.lowercased()
        return notes.filter {
            $0.title.lowercased().contains(q) || $0.preview.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredNotes.isEmpty {
                    Text("No notes found")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredNotes) { note in
                        Button {
                            noteStore.openNote(note)
                            isPresented = false
                        } label: {
                            NoteRow(note: note)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                noteStore.deleteNote(note)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search notes")
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        noteStore.newNote()
                        isPresented = false
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
        .onAppear {
            noteStore.refreshNotes()
        }
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title)
                .font(.body)
                .fontWeight(.medium)
                .lineLimit(1)

            HStack(spacing: 8) {
                if let date = note.modifiedAt ?? note.createdAt {
                    Text(formatRelativeDate(date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !note.preview.isEmpty {
                    Text(note.preview)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let now = Date()
        let diff = now.timeIntervalSince(date)

        if diff < 60 { return "\(Int(diff))s ago" }
        if diff < 3600 { return "\(Int(diff / 60)) min ago" }

        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "h a"
            return f.string(from: date).lowercased()
        }
        if cal.isDateInYesterday(date) { return "yesterday" }
        if diff < 7 * 86400 {
            let f = DateFormatter()
            f.dateFormat = "EEE"
            return f.string(from: date)
        }
        if cal.component(.year, from: date) == cal.component(.year, from: now) {
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return f.string(from: date)
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }
}
