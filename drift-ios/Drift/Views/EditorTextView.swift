import SwiftUI
import UIKit

/// UITextView wrapper. Three responsibilities:
///   - True read-only mode (no keyboard, no selection, scroll-only).
///   - Style the first non-blank line as a heading (Newsreader italic, large),
///     with breathing room before the body.
///   - Hide all chrome from the visible area; expose a single Read Mode
///     toggle by overscrolling above the top of content (pull-to-toggle).
struct EditorTextView: UIViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    var autoFocus: Bool = false
    var onToggleReadMode: () -> Void = {}

    func makeUIView(context: Context) -> StyledTextView {
        let tv = StyledTextView()
        tv.delegate = context.coordinator
        tv.font = Self.bodyFont
        tv.textColor = Theme.inkUIColor
        tv.tintColor = Theme.accentUIColor
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 16, bottom: 40, right: 16)
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.text = text
        tv.isEditable = isEditable
        tv.isSelectable = isEditable
        configurePull(on: tv)
        Self.applyFirstLineHeading(to: tv)
        if autoFocus {
            DispatchQueue.main.async { tv.becomeFirstResponder() }
        }
        return tv
    }

    func updateUIView(_ uiView: StyledTextView, context: Context) {
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
        configurePull(on: uiView)
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

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            (scrollView as? StyledTextView)?.handleScroll()
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            (scrollView as? StyledTextView)?.handleEndDragging()
        }
    }

    // MARK: - Pull config

    private func configurePull(on tv: StyledTextView) {
        tv.pullTitle = isEditable ? "Read Mode" : "Exit Read Mode"
        tv.onPullTrigger = onToggleReadMode
    }

    // MARK: - Styling

    private static var bodyFont: UIFont {
        Theme.bodyUIFont()
    }

    private static var headingFont: UIFont {
        Theme.editorTitleUIFont()
    }

    private static var headingParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 16
        return style
    }

    static func applyFirstLineHeading(to textView: UITextView) {
        let storage = textView.textStorage
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }

        storage.beginEditing()
        storage.removeAttribute(.paragraphStyle, range: full)
        storage.addAttribute(.font, value: bodyFont, range: full)
        storage.addAttribute(.foregroundColor, value: Theme.inkUIColor, range: full)
        if let firstLine = firstNonBlankLineRange(in: textView.text ?? "") {
            storage.addAttribute(.font, value: headingFont, range: firstLine)
            storage.addAttribute(.paragraphStyle, value: headingParagraphStyle, range: firstLine)
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

/// UITextView with a pull-down-to-toggle affordance: a small label sitting
/// above the top of content (in the rubber-band region). User pulls down
/// past `triggerThreshold`, releases, and `onPullTrigger` fires.
final class StyledTextView: UITextView {
    private let pullLabel = UILabel()

    /// Title shown in the overscroll area (e.g. "Read Mode" / "Exit Read Mode").
    var pullTitle: String = "" {
        didSet {
            pullLabel.text = pullTitle
            setNeedsLayout()
        }
    }

    /// Callback invoked when the user releases past the trigger threshold.
    var onPullTrigger: () -> Void = {}

    private let pullLabelY: CGFloat = -38
    private let triggerThreshold: CGFloat = 78

    init() {
        super.init(frame: .zero, textContainer: nil)
        pullLabel.textColor = Theme.accentUIColor.withAlphaComponent(0.4)
        pullLabel.font = UIFont(name: "JetBrainsMono-Regular", size: 12)
            ?? UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        pullLabel.textAlignment = .center
        addSubview(pullLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let fitting = pullLabel.sizeThatFits(CGSize(width: bounds.width, height: 32))
        pullLabel.frame = CGRect(
            x: (bounds.width - fitting.width) / 2,
            y: pullLabelY,
            width: fitting.width,
            height: fitting.height
        )
    }

    func handleScroll() {
        // Visual cue: label brightens once past the trigger threshold so the
        // user knows releasing now will fire the action.
        let primed = contentOffset.y <= -triggerThreshold
        pullLabel.textColor = primed
            ? Theme.accentUIColor
            : Theme.accentUIColor.withAlphaComponent(0.4)
    }

    func handleEndDragging() {
        if contentOffset.y <= -triggerThreshold {
            onPullTrigger()
        }
    }
}
