import SwiftUI
import UIKit

/// UITextView wrapper. Three responsibilities:
///   - True read-only mode (no keyboard, no selection, scroll-only).
///   - Style the first non-blank line as a heading (semibold, 1.618× body),
///     matching the desktop's `.first-line-title`.
///   - Host an inline menu button at the top of the content area so it
///     scrolls away with the text instead of floating fixed on screen.
struct EditorTextView: UIViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    var autoFocus: Bool = false
    var onToggleReadMode: () -> Void = {}
    var onDelete: () -> Void = {}

    func makeUIView(context: Context) -> StyledTextView {
        let tv = StyledTextView()
        tv.delegate = context.coordinator
        tv.font = Self.bodyFont
        tv.adjustsFontForContentSizeCategory = true
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 4, left: 12, bottom: 32, right: 12)
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.text = text
        tv.isEditable = isEditable
        tv.isSelectable = isEditable
        applyMenu(on: tv)
        Self.applyFirstLineHeading(to: tv)
        if autoFocus {
            // Run on the next tick so the view is in the window hierarchy by
            // the time we ask for first responder. The keyboard then animates
            // in alongside the navigation push.
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
        applyMenu(on: uiView)
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

    // MARK: - Menu

    private func applyMenu(on tv: StyledTextView) {
        let readToggle = UIAction(
            title: isEditable ? "Read Mode" : "Exit Read Mode",
            image: UIImage(systemName: isEditable ? "lock" : "lock.open")
        ) { _ in onToggleReadMode() }

        let delete = UIAction(
            title: "Delete",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { _ in onDelete() }

        tv.menuButton.menu = UIMenu(children: [readToggle, delete])
    }

    // MARK: - Styling

    private static var bodyFont: UIFont {
        UIFont.preferredFont(forTextStyle: .body)
    }

    private static var headingFont: UIFont {
        let body = UIFont.preferredFont(forTextStyle: .body).pointSize
        return UIFont.systemFont(ofSize: body * 1.618, weight: .semibold)
    }

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

/// UITextView with a menu button as a subview at the top of the content area.
/// Because it's a subview of the scroll view's content, it moves with the
/// content as you scroll (no fixed-position floating).
final class StyledTextView: UITextView {
    let menuButton = UIButton(type: .system)

    private let buttonSize = CGSize(width: 36, height: 36)
    private let buttonInsetTrailing: CGFloat = 16
    private let buttonInsetTop: CGFloat = 8

    init() {
        super.init(frame: .zero, textContainer: nil)
        configureButton()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func configureButton() {
        menuButton.setImage(
            UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(weight: .semibold)),
            for: .normal
        )
        menuButton.tintColor = .secondaryLabel
        menuButton.backgroundColor = .secondarySystemBackground
        menuButton.layer.cornerRadius = buttonSize.height / 2
        menuButton.layer.masksToBounds = true
        menuButton.frame.size = buttonSize
        menuButton.showsMenuAsPrimaryAction = true
        addSubview(menuButton)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        menuButton.frame.origin = CGPoint(
            x: bounds.width - buttonSize.width - buttonInsetTrailing,
            y: buttonInsetTop
        )
        // Carve the button area out of the text container so long first-line
        // titles wrap around it instead of running underneath.
        let buttonInContainer = menuButton.frame
            .offsetBy(dx: -textContainerInset.left, dy: -textContainerInset.top)
            .insetBy(dx: -8, dy: -4)
        textContainer.exclusionPaths = [UIBezierPath(rect: buttonInContainer)]
    }
}
