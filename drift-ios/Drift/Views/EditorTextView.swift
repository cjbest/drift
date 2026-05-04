import SwiftUI
import UIKit

/// UITextView wrapper. Two responsibilities:
///   - True read-only mode (no keyboard, no selection, scroll-only) when
///     `isEditable == false`.
///   - Style the first non-blank line as a heading (semibold, 1.618× body),
///     matching the desktop's `.first-line-title`.
struct EditorTextView: UIViewRepresentable {
    @Binding var text: String
    let isEditable: Bool

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = Self.bodyFont
        tv.adjustsFontForContentSizeCategory = true
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 60, left: 12, bottom: 32, right: 12)
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.text = text
        tv.isEditable = isEditable
        tv.isSelectable = isEditable
        Self.applyFirstLineHeading(to: tv)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            let cursor = uiView.selectedRange
            uiView.text = text
            uiView.selectedRange = NSRange(
                location: min(cursor.location, (uiView.text as NSString).length),
                length: 0
            )
            Self.applyFirstLineHeading(to: uiView)
        }
        if uiView.isEditable != isEditable {
            uiView.isEditable = isEditable
        }
        if uiView.isSelectable != isEditable {
            uiView.isSelectable = isEditable
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var parent: EditorTextView

        init(_ parent: EditorTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            EditorTextView.applyFirstLineHeading(to: textView)
        }
    }

    // MARK: - Styling

    private static var bodyFont: UIFont {
        UIFont.preferredFont(forTextStyle: .body)
    }

    private static var headingFont: UIFont {
        let body = UIFont.preferredFont(forTextStyle: .body).pointSize
        return UIFont.systemFont(ofSize: body * 1.618, weight: .semibold)
    }

    /// Re-applies font attributes against the text storage in place — no text
    /// replacement, so selection/cursor positions are preserved automatically.
    static func applyFirstLineHeading(to textView: UITextView) {
        let storage = textView.textStorage
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }

        storage.beginEditing()
        storage.addAttribute(.font, value: bodyFont, range: full)
        if let firstLine = firstNonBlankLineRange(in: textView.text ?? "") {
            storage.addAttribute(.font, value: headingFont, range: firstLine)
        }
        storage.endEditing()
    }

    private static func firstNonBlankLineRange(in text: String) -> NSRange? {
        let ns = text as NSString
        var loc = 0
        while loc < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
            let lineText = ns.substring(with: lineRange)
            if !lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Drop trailing newline so the heading doesn't visually
                // include the line break.
                var endLoc = lineRange.location + lineRange.length
                if endLoc > lineRange.location {
                    let last = ns.character(at: endLoc - 1)
                    if last == 10 || last == 13 { endLoc -= 1 }
                }
                return NSRange(location: lineRange.location, length: endLoc - lineRange.location)
            }
            if lineRange.length == 0 { break }
            loc = lineRange.location + lineRange.length
        }
        return nil
    }
}
