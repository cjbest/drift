import SwiftUI

struct ContentView: View {
    @EnvironmentObject var noteStore: NoteStore
    @State private var showNoteList = false
    @AppStorage("drift-theme") private var themeMode: String = "system"

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            EditorView(
                content: $noteStore.currentContent,
                onContentChange: { content in
                    noteStore.saveContent(content)
                }
            )
            .ignoresSafeArea(.container, edges: .bottom)

            // Floating toolbar at bottom
            VStack {
                Spacer()
                toolbar
            }
        }
        .sheet(isPresented: $showNoteList) {
            NoteListView(isPresented: $showNoteList)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            noteStore.saveNow()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 24) {
            Button {
                showNoteList = true
            } label: {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 18))
            }

            Button {
                noteStore.saveNow()
                noteStore.newNote()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18))
            }

            Spacer()

            Menu {
                Section("Theme") {
                    Button {
                        themeMode = "system"
                    } label: {
                        Label("System", systemImage: themeMode == "system" ? "checkmark" : "")
                    }
                    Button {
                        themeMode = "light"
                    } label: {
                        Label("Light", systemImage: themeMode == "light" ? "checkmark" : "")
                    }
                    Button {
                        themeMode = "dark"
                    } label: {
                        Label("Dark", systemImage: themeMode == "dark" ? "checkmark" : "")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}
