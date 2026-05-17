import SwiftUI

struct NoteEditorView: View {
    @Environment(NoteStore.self) private var store

    let note: Note
    let autoFocus: Bool
    /// Called when the user taps the back chevron. The parent clears its
    /// selection state so the NavigationSplitView pops back to the list on
    /// iPhone and shows `detailEmpty` on iPad.
    let onDismiss: () -> Void
    @State private var workingNote: Note
    @State private var text: String = ""
    @State private var initialText: String = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var isReadMode: Bool = false

    init(note: Note, autoFocus: Bool = false, onDismiss: @escaping () -> Void) {
        self.note = note
        self.autoFocus = autoFocus
        self.onDismiss = onDismiss
        self._workingNote = State(initialValue: note)
    }

    var body: some View {
        EditorTextView(
            text: $text,
            isEditable: !isReadMode,
            autoFocus: autoFocus,
            onToggleReadMode: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isReadMode.toggle()
                }
            }
        )
        .background(Theme.paper.ignoresSafeArea())
        .background(EditorChrome())
        .navigationTitle(workingNote.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // Suppress the inline title text — the document's own large
                // italic title sits at the top of the body and carries the name.
                Color.clear.frame(width: 1, height: 1)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("Back")
            }
        }
        .navigationBarBackButtonHidden(true)
        .overlay(alignment: .topTrailing) {
            if isReadMode {
                Image(systemName: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.accent.opacity(0.45))
                    .padding(.trailing, 16)
                    .padding(.top, 12)
            }
        }
        .onAppear {
            let loaded = store.readContents(of: workingNote)
            text = loaded
            initialText = loaded
        }
        .onChange(of: text) { _, newValue in
            guard newValue != initialText else { return }
            saveTask?.cancel()
            saveTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                if Task.isCancelled { return }
                workingNote = store.saveContents(newValue, for: workingNote)
                initialText = newValue
            }
        }
        .onDisappear {
            saveTask?.cancel()
            if text != initialText {
                workingNote = store.saveContents(text, for: workingNote)
            }
            isReadMode = false
        }
    }
}
