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
        // Read file contents synchronously here so `text` is populated before
        // the push transition begins. Loading in `.onAppear` causes a visible
        // pop-in: the body and large italic title only render after the slide
        // settles, instead of riding in with the rest of the view.
        let initial = (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
        self._text = State(initialValue: initial)
        self._initialText = State(initialValue: initial)
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
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 32, height: 32)
                        .overlay(Circle().stroke(Theme.backOutline, lineWidth: 0.5))
                }
                .accessibilityLabel("Back")
                .buttonStyle(.plain)

                Spacer()

                if isReadMode {
                    Image(systemName: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.accent.opacity(0.45))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .frame(height: 52, alignment: .top)
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
