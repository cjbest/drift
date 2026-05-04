import SwiftUI
import UIKit

/// UITextView wrapper with a true read-only mode (no keyboard, no selection,
/// scroll-only). Auto-shows the host navigation bar when the user reaches
/// the top of the content — a reliable way out when the bar has been hidden
/// by `hidesBarsOnSwipe`, especially on notes too short to scroll.
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

        init(_ parent: EditorTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // Only react to user-driven scrolling (drag or its deceleration)
            // so initial layout / keyboard insets don't trigger this.
            guard scrollView.isDragging || scrollView.isDecelerating else { return }
            // When the user reaches the top (or pulls into rubber-band above),
            // force the nav bar back. Covers short notes where there's nowhere
            // to scroll up to.
            if scrollView.contentOffset.y <= 0 {
                scrollView.findNavigationController()?.setNavigationBarHidden(false, animated: true)
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
