import SwiftUI

struct ContentView: View {
    @Environment(NoteStore.self) private var store

    var body: some View {
        if store.folderURL != nil {
            NoteListView()
        } else {
            FolderPickerView()
        }
    }
}

#Preview {
    ContentView()
        .environment(NoteStore())
}
