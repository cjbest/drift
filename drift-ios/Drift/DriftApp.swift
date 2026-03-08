import SwiftUI

@main
struct DriftApp: App {
    @StateObject private var noteStore = NoteStore()
    @AppStorage("drift-theme") private var themeMode: String = "system"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(noteStore)
                .preferredColorScheme(colorScheme)
        }
    }

    private var colorScheme: ColorScheme? {
        switch themeMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
