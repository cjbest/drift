import SwiftUI
import UIKit

/// Background hook that turns on `UINavigationController.hidesBarsOnSwipe`
/// while this view is on screen. Also keeps the interactive back-edge swipe
/// working — by default UIKit disables it whenever the nav bar is hidden.
struct HidesNavigationBarOnSwipe: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Host { Host() }
    func updateUIViewController(_ uiViewController: Host, context: Context) {}

    final class Host: UIViewController, UIGestureRecognizerDelegate {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationController?.hidesBarsOnSwipe = true
            // Without this, the edge-swipe-to-go-back gesture is disabled
            // whenever the nav bar is hidden.
            navigationController?.interactivePopGestureRecognizer?.delegate = self
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.hidesBarsOnSwipe = false
            navigationController?.setNavigationBarHidden(false, animated: animated)
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }

        // Only allow the pop gesture when there's somewhere to pop to.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}
