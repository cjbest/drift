import SwiftUI

@main
struct DriftApp: App {
    init() {
        LaunchDiagnostics.record("app_init", once: true)
        FontLoader.registerAll()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea()
                .tint(Theme.accent)
        }
    }
}
