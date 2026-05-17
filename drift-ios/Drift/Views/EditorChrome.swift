import SwiftUI
import UIKit

/// Keeps the back-edge swipe-to-pop gesture alive while the editor hides the
/// navigation bar and supplies its own manuscript-style back button.
struct EditorChrome: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Host { Host() }
    func updateUIViewController(_ uiViewController: Host, context: Context) {}

    final class Host: UIViewController, UIGestureRecognizerDelegate {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationController?.setNavigationBarHidden(true, animated: animated)
            navigationController?.interactivePopGestureRecognizer?.delegate = self
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.setNavigationBarHidden(false, animated: animated)
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard recognizer == navigationController?.interactivePopGestureRecognizer else {
                return true
            }
            return (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}
