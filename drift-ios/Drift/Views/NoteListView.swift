import SwiftUI

struct NoteListView: View {
    @Environment(NoteStore.self) private var store
    @State private var selectedNote: Note?
    @State private var query = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// Note ID to auto-focus on appear — set when the user taps the compose
    /// button so the keyboard rises during the navigation push. Cleared as
    /// soon as the editor consumes it.
    @State private var pendingFocusID: Note.ID?

    private var hits: [NoteStore.SearchHit] {
        store.search(query)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            if let selectedNote {
                NoteEditorView(
                    note: selectedNote,
                    autoFocus: pendingFocusID == selectedNote.id
                )
                .id(selectedNote.id)
                .onAppear { pendingFocusID = nil }
            } else {
                detailEmpty
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { store.loadNotes() }
    }

    private var sidebar: some View {
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
                        pendingFocusID = note.id
                        selectedNote = note
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .refreshable { store.loadNotes() }
    }

    private var list: some View {
        SearchableNoteList(hits: hits, selectedNote: $selectedNote)
    }

    private var detailEmpty: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Select a note")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// The list of search results. Lives inside the `.searchable` modifier so it
/// can read `dismissSearch` from the environment — without dismissing search
/// when a note is selected, the search bar persists into the editor's chrome
/// and the editor's `.toolbar(.hidden)` doesn't take effect.
private struct SearchableNoteList: View {
    let hits: [NoteStore.SearchHit]
    @Binding var selectedNote: Note?
    @Environment(\.dismissSearch) private var dismissSearch

    var body: some View {
        List(selection: $selectedNote) {
            ForEach(hits) { hit in
                NavigationLink(value: hit.note) {
                    NoteRow(note: hit.note, searchSnippet: hit.snippet)
                }
            }
        }
        .listStyle(.plain)
        .onChange(of: selectedNote) { _, newValue in
            if newValue != nil { dismissSearch() }
        }
    }
}

private struct NoteRow: View {
    let note: Note
    /// When non-nil, replaces the regular preview with the line where the
    /// search query matched in the body.
    var searchSnippet: String? = nil

    private var contextLine: String {
        searchSnippet ?? note.preview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title)
                .font(.body.weight(.medium))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(note.modified, style: .date)
                if !contextLine.isEmpty {
                    Text("·")
                    Text(contextLine)
                        .lineLimit(1)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
