import SwiftUI

struct NoteEditorView: View {
    @Environment(NoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let note: Note
    @State private var workingNote: Note
    @State private var text: String = ""
    @State private var initialText: String = ""
    @State private var saveTask: Task<Void, Never>?

    init(note: Note) {
        self.note = note
        self._workingNote = State(initialValue: note)
    }

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .default))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .navigationTitle(workingNote.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            store.delete(workingNote)
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
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
            }
    }
}
