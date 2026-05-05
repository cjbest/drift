import SwiftUI

@main
struct DriftApp: App {
    @State private var store = NoteStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.loadNotes()
                    }
                }
        }
    }
}
