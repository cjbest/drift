import SwiftUI

struct NoteEditorView: View {
    @Environment(NoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let note: Note
    @State private var workingNote: Note
    @State private var text: String = ""
    @State private var initialText: String = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var isReadMode: Bool = false

    init(note: Note) {
        self.note = note
        self._workingNote = State(initialValue: note)
    }

    var body: some View {
        EditorTextView(text: $text, isEditable: !isReadMode)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .background(HidesNavigationBarOnSwipe())
            .navigationTitle(workingNote.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isReadMode {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(workingNote.title)
                                .font(.headline)
                                .lineLimit(1)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isReadMode.toggle()
                            }
                        } label: {
                            Label(
                                isReadMode ? "Exit Read Mode" : "Read Mode",
                                systemImage: isReadMode ? "lock.open" : "lock"
                            )
                        }
                        Divider()
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
                // Read mode is per-session; leaving the note ends it.
                isReadMode = false
            }
    }
}
