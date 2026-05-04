import SwiftUI
import UIKit

/// UITextView wrapper with a true read-only mode (no keyboard, no selection,
/// scroll-only) and a manual nav-bar hide/show driven by scroll direction:
/// any upward scroll reveals the bar, downward scroll past the top hides it.
struct EditorTextView: UIViewRepresentable {
    @Binding var text: String
    let isEditable: Bool

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.adjustsFontForContentSizeCategory = true
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 32, right: 12)
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.text = text
        tv.isEditable = isEditable
        tv.isSelectable = isEditable
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            let selectedRange = uiView.selectedRange
            uiView.text = text
            let clamped = NSRange(
                location: min(selectedRange.location, (uiView.text as NSString).length),
                length: 0
            )
            uiView.selectedRange = clamped
        }
        if uiView.isEditable != isEditable {
            uiView.isEditable = isEditable
        }
        if uiView.isSelectable != isEditable {
            uiView.isSelectable = isEditable
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var parent: EditorTextView
        private var lastY: CGFloat = 0

        init(_ parent: EditorTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            lastY = scrollView.contentOffset.y
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let y = scrollView.contentOffset.y
            defer { lastY = y }

            // Only react to user-driven scrolling (drag or its deceleration).
            // Skip large jumps — those are layout/keyboard insets shifting the
            // offset, not scrolling.
            guard scrollView.isDragging || scrollView.isDecelerating else { return }
            let diff = y - lastY
            guard abs(diff) < 60 else { return }
            guard let nav = scrollView.findNavigationController() else { return }

            if diff < 0 {
                // ANY upward scroll → show. setNavigationBarHidden is a no-op
                // when already in the requested state, so this is cheap.
                if nav.isNavigationBarHidden {
                    nav.setNavigationBarHidden(false, animated: true)
                }
            } else if diff > 4 && y > 40 {
                // Downward, past the top, more than the dead zone → hide.
                if !nav.isNavigationBarHidden {
                    nav.setNavigationBarHidden(true, animated: true)
                }
            }
        }
    }
}

private extension UIView {
    func findNavigationController() -> UINavigationController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let nav = r as? UINavigationController { return nav }
            if let vc = r as? UIViewController { return vc.navigationController }
            responder = r.next
        }
        return nil
    }
}
