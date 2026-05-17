import SwiftUI
import UIKit

/// Keeps the back-edge swipe-to-pop gesture alive while we hide SwiftUI's
/// default back button and supply our own subtle one. iOS disables the
/// interactive pop gesture when the default back button isn't visible;
/// taking over the gesture's delegate re-enables it.
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
