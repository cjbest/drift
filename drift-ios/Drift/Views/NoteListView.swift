import SwiftUI

struct NoteListView: View {
    @Environment(NoteStore.self) private var store
    @State private var selectedNote: Note?
    @State private var query = ""
    @State private var isSearchPresented = false
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
        // Force-collapse the search field when navigating to a note. Without
        // this, the .searchable bar stays in the navigation chrome and shows
        // on top of the editor — its `.toolbar(.hidden)` doesn't override the
        // search field, only the bar itself.
        .onChange(of: selectedNote) { _, newValue in
            if newValue != nil {
                isSearchPresented = false
            }
        }
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
        .searchable(
            text: $query,
            isPresented: $isSearchPresented,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search notes"
        )
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
        List(selection: $selectedNote) {
            ForEach(hits) { hit in
                NavigationLink(value: hit.note) {
                    NoteRow(note: hit.note, searchSnippet: hit.snippet, query: query)
                }
            }
        }
        .listStyle(.plain)
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

private struct NoteRow: View {
    let note: Note
    /// When non-nil, the line of body content where the search query matched.
    /// Replaces the regular preview line.
    var searchSnippet: String? = nil
    /// Active search query — used to bold the matching span in the snippet.
    var query: String = ""

    private var contextText: AttributedString {
        if let snippet = searchSnippet {
            var attr = AttributedString(snippet)
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               let r = attr.range(of: trimmed, options: .caseInsensitive) {
                attr[r].font = .footnote.weight(.semibold)
                attr[r].foregroundColor = .primary
            }
            return attr
        }
        return AttributedString(note.preview)
    }

    private var hasContext: Bool {
        searchSnippet?.isEmpty == false || (searchSnippet == nil && !note.preview.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title)
                .font(.body.weight(.medium))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(note.modified, style: .date)
                if hasContext {
                    Text("·")
                    Text(contextText)
                        .lineLimit(1)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
