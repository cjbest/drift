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

    private var hits: [Note] {
        store.search(query)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            if let selectedNote {
                NoteEditorView(
                    note: selectedNote,
                    autoFocus: pendingFocusID == selectedNote.id,
                    onDismiss: { self.selectedNote = nil }
                )
                .id(selectedNote.id)
                .onAppear { pendingFocusID = nil }
            } else {
                detailEmpty
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            store.loadNotes()
            autoOpenIfRequested()
        }
    }

    private func autoOpenIfRequested() {
        #if DEBUG
        guard selectedNote == nil,
              let target = ProcessInfo.processInfo.environment["DRIFT_AUTO_OPEN"]
        else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            selectedNote = store.notes.first { $0.title == target }
        }
        #endif
    }

    private var sidebar: some View {
        Group {
            if store.notes.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Drift")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search notes")
        .toolbar {
            ToolbarItem(placement: .principal) {
                // Explicit Text rendering avoids the brief flash where the
                // title appears in the system font before the
                // UINavigationBar.appearance() titleTextAttributes take effect.
                Text("Drift")
                    .font(.custom("Newsreader16pt-Italic", size: 22))
                    .foregroundStyle(Theme.ink)
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Refresh", systemImage: "arrow.clockwise") { store.loadNotes() }
                    Button("Change Folder…", systemImage: "folder") { store.clearFolder() }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Theme.accent)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let note = store.createNote() {
                        pendingFocusID = note.id
                        selectedNote = note
                    }
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Theme.accent)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .refreshable { store.loadNotes() }
    }

    private var list: some View {
        List(selection: $selectedNote) {
            ForEach(hits) { note in
                Button {
                    selectedNote = note
                } label: {
                    NoteRow(note: note)
                }
                .buttonStyle(RowPressStyle())
                .listRowBackground(Theme.paper)
                .listRowSeparatorTint(Theme.hairline)
                .listRowSeparator(.hidden, edges: .top)
                .listRowInsets(EdgeInsets())
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
    }

    private var detailEmpty: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.35))
            Text("Select a note")
                .font(Theme.rowTitle())
                .foregroundStyle(Theme.ink.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.ignoresSafeArea())
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.35))
            Text("No notes yet")
                .font(Theme.rowTitle())
                .foregroundStyle(Theme.ink)
            Text("Tap the plus to start one.")
                .font(Theme.rowSub())
                .foregroundStyle(Theme.ink.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title)
                .font(Theme.rowTitle())
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(note.modified, style: .date)
                if !note.preview.isEmpty {
                    Text("·")
                    Text(note.preview)
                        .lineLimit(1)
                }
            }
            .font(Theme.rowSub())
            .foregroundStyle(Theme.ink.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Button style for list rows: stretches the hit area to the full row,
/// applies the visual padding the List would normally add, and tints
/// sepia-on-press so users get tap feedback (the default `.plain` style
/// strips it).
private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(configuration.isPressed ? Theme.accent.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
    }
}
