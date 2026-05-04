import SwiftUI

struct NoteListView: View {
    @Environment(NoteStore.self) private var store
    @State private var selectedNote: Note?
    @State private var query = ""

    private var filteredNotes: [Note] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.notes }
        return store.notes.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.notes.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Drift")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search notes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Refresh", systemImage: "arrow.clockwise") { store.loadNotes() }
                        Button("Change Folder…", systemImage: "folder") { store.clearFolder() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let note = store.createNote() {
                            selectedNote = note
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .navigationDestination(item: $selectedNote) { note in
                NoteEditorView(note: note)
            }
            .refreshable { store.loadNotes() }
            .onAppear { store.loadNotes() }
        }
    }

    private var list: some View {
        List {
            ForEach(filteredNotes) { note in
                Button {
                    selectedNote = note
                } label: {
                    NoteRow(note: note, store: store)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        store.delete(note)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No notes yet")
                .font(.headline)
            Text("Tap the pencil to start one.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NoteRow: View {
    let note: Note
    let store: NoteStore

    private var preview: String {
        let raw = (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
        let firstLine = raw
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            let body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? "Empty note" : String(body.prefix(80))
        }
        return trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title)
                .font(.body.weight(.medium))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(note.modified, style: .date)
                Text("·")
                Text(preview)
                    .lineLimit(1)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
