import SwiftUI
import UIKit

@main
struct DriftApp: App {
    @State private var store = NoteStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FontLoader.registerAll()
        configureNavigationBarAppearance()
        configureSearchBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .tint(Theme.accent)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.loadNotes()
                    }
                }
        }
    }

    private func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Theme.paperUIColor
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [
            .font: Theme.navTitleUIFont(),
            .foregroundColor: Theme.inkUIColor,
        ]
        appearance.largeTitleTextAttributes = [
            .font: Theme.navTitleUIFont(),
            .foregroundColor: Theme.inkUIColor,
        ]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().tintColor = Theme.accentUIColor
    }

    private func configureSearchBarAppearance() {
        let bar = UISearchBar.appearance()
        bar.tintColor = Theme.accentUIColor

        // Tint the leading magnifier glyph sepia. iOS keeps a stock template
        // image for the icon — recolor it with the accent so it stops reading
        // as default system gray inside a paper-and-sepia palette.
        let magnifier = UIImage(systemName: "magnifyingglass")?
            .withTintColor(Theme.accentUIColor, renderingMode: .alwaysOriginal)
        UISearchBar.appearance().setImage(magnifier, for: .search, state: .normal)

        let field = UISearchTextField.appearance()
        field.tintColor = Theme.accentUIColor
        field.textColor = Theme.inkUIColor
    }
}
