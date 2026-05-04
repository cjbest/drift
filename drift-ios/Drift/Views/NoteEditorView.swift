import SwiftUI

struct NoteEditorView: View {
    @Environment(NoteStore.self) private var store

    let note: Note
    let autoFocus: Bool
    @State private var workingNote: Note
    @State private var text: String = ""
    @State private var initialText: String = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var isReadMode: Bool = false

    init(note: Note, autoFocus: Bool = false) {
        self.note = note
        self.autoFocus = autoFocus
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
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(EditorChrome())
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle(workingNote.title)
        .overlay(alignment: .topLeading) {
            if isReadMode {
                Image(systemName: "lock.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(.leading, 16)
                    .padding(.top, 8)
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
