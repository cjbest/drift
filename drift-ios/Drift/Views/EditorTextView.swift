import SwiftUI
import UIKit

/// UITextView wrapper that exposes scroll-direction callbacks and a true
/// "read-only" mode where the keyboard never opens and selection is disabled.
struct EditorTextView: UIViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    var onScrollDirection: (ScrollDirection) -> Void

    enum ScrollDirection {
        case up, down
    }

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
            // Preserve cursor position when SwiftUI rebroadcasts the binding.
            let clamped = NSRange(
                location: min(selectedRange.location, (uiView.text as NSString).length),
                length: 0
            )
            uiView.selectedRange = clamped
        }
        if uiView.isEditable != isEditable {
            uiView.isEditable = isEditable
        }
        // Setting isSelectable=false also prevents the keyboard and the
        // long-press callout. That's exactly read mode.
        if uiView.isSelectable != isEditable {
            uiView.isSelectable = isEditable
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var parent: EditorTextView
        private var lastReportedY: CGFloat = 0
        private var isUserScrolling = false
        private let deadZone: CGFloat = 6

        init(_ parent: EditorTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
        }

        // Only react to user-driven scrolling — programmatic offset changes
        // (keyboard insets, initial layout) shouldn't fire the toolbar toggle.

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isUserScrolling = true
            lastReportedY = scrollView.contentOffset.y
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { isUserScrolling = false }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            isUserScrolling = false
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard isUserScrolling else { return }
            let y = scrollView.contentOffset.y
            let diff = y - lastReportedY
            if diff > deadZone {
                parent.onScrollDirection(.down)
                lastReportedY = y
            } else if diff < -deadZone {
                parent.onScrollDirection(.up)
                lastReportedY = y
            }
        }
    }
}
