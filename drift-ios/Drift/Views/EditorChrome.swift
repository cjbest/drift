import SwiftUI
import UIKit

/// Background hook for NoteEditorView that:
///  - Keeps the back-edge swipe-to-pop alive even when the nav bar is hidden
///    (UIKit disables it by default once the bar goes away).
///  - Restores the nav bar to visible on the way out so the list view always
///    starts with a clean slate.
struct EditorChrome: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Host { Host() }
    func updateUIViewController(_ uiViewController: Host, context: Context) {}

    final class Host: UIViewController, UIGestureRecognizerDelegate {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.delegate = self
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.setNavigationBarHidden(false, animated: animated)
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }

        // Only override the decision for the back-edge pop gesture; defer for
        // anything else. Returning true here is what re-enables the gesture
        // while the nav bar is hidden.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard recognizer == navigationController?.interactivePopGestureRecognizer else {
                return true
            }
            return (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}
