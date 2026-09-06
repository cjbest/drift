import SwiftUI

@main
struct DriftApp: App {
    init() { FontLoader.registerAll() }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea()
                .tint(Theme.accent)
        }
    }
}
