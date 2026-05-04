import SwiftUI
import UIKit

/// UITextView wrapper with a true read-only mode (no keyboard, no selection,
/// scroll-only). The nav-bar hide-on-scroll behavior is handled separately
/// by UINavigationController.hidesBarsOnSwipe — see HidesBarsOnSwipe.
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
        // isSelectable=false also kills the keyboard, the cursor, and the
        // long-press callout — that's exactly read mode.
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
    }
}
