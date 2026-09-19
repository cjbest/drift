import UIKit

/// Keeps an action until its own notebook can handle it, including when UIKit
/// delivers a cold-launch shortcut before SwiftUI has created the notebook.
@MainActor
final class QuickNoteAction {
    static let shared = QuickNoteAction()
    static let shortcutType = "best.christopher.drift.new-note"
    static let didRequestNewNote = Notification.Name("Drift.QuickNoteAction.didRequestNewNote")

    private var pendingSceneIdentifiers: Set<String> = []

    @discardableResult
    func handle(_ shortcutItem: UIApplicationShortcutItem, for sessionIdentifier: String) -> Bool {
        guard shortcutItem.type == Self.shortcutType else { return false }
        if pendingSceneIdentifiers.insert(sessionIdentifier).inserted {
            NotificationCenter.default.post(name: Self.didRequestNewNote, object: self)
        }
        return true
    }

    func consumePendingRequest(for sessionIdentifier: String) -> Bool {
        pendingSceneIdentifiers.remove(sessionIdentifier) != nil
    }
}

/// SwiftUI continues to own its windows; UIKit only supplies shortcut callbacks.
@MainActor
final class DriftApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = DriftSceneDelegate.self
        }
        return configuration
    }
}

@MainActor
final class DriftSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        // Cold shortcuts arrive only here, never also in app configuration.
        guard let shortcutItem = connectionOptions.shortcutItem else { return }
        QuickNoteAction.shared.handle(shortcutItem, for: session.persistentIdentifier)
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let accepted = QuickNoteAction.shared.handle(shortcutItem,
                                                     for: windowScene.session.persistentIdentifier)
        completionHandler(accepted)
    }
}
