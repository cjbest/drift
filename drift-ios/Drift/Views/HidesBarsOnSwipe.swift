import SwiftUI
import UIKit

/// Background hook that turns on `UINavigationController.hidesBarsOnSwipe`
/// while this view is on screen and resets it on the way out. Standard iOS
/// behavior: the nav bar slides off proportional to the swipe and comes
/// back the same way (much smoother than toggling visibility manually).
struct HidesNavigationBarOnSwipe: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Host { Host() }
    func updateUIViewController(_ uiViewController: Host, context: Context) {}

    final class Host: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationController?.hidesBarsOnSwipe = true
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            // Make sure the bar is visible again before we leave so the list
            // view inherits a clean state.
            navigationController?.hidesBarsOnSwipe = false
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
    }
}
