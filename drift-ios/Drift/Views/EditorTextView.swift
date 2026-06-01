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
    var topContentInset: CGFloat = 8
    var bottomContentInset: CGFloat = 40
    var onToggleReadMode: () -> Void = {}
    var onScroll: (CGFloat) -> Void = { _ in }

    func makeUIView(context: Context) -> StyledTextView {
        let tv = StyledTextView()
        tv.delegate = context.coordinator
        tv.font = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.headingFont
            : Self.bodyFont
        tv.textColor = Theme.inkUIColor
        tv.tintColor = Theme.accentUIColor
        tv.applyPaperChrome()
        tv.setBaseTextContainerInset(
            UIEdgeInsets(top: topContentInset, left: 16, bottom: bottomContentInset, right: 16)
        )
        tv.contentInsetAdjustmentBehavior = .never
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.text = text
        tv.isEditable = isEditable
        tv.isSelectable = isEditable
        configurePull(on: tv)
        Self.applyFirstLineHeading(to: tv, force: true)
        tv.selectedRange = NSRange(location: 0, length: 0)
        Self.updateTypingAttributes(for: tv)
        tv.setContentOffset(.zero, animated: false)
        if autoFocus {
            tv.focusWhenReady()
        }
        return tv
    }

    func updateUIView(_ uiView: StyledTextView, context: Context) {
        context.coordinator.update(self)
        if uiView.contentInsetAdjustmentBehavior != .never {
            uiView.contentInsetAdjustmentBehavior = .never
        }
        uiView.applyPaperChrome()
        uiView.setBaseTextContainerInset(
            UIEdgeInsets(top: topContentInset, left: 16, bottom: bottomContentInset, right: 16)
        )
        if uiView.text != text {
            let cursor = uiView.selectedRange
            uiView.text = text
            uiView.selectedRange = NSRange(
                location: min(cursor.location, (uiView.text as NSString).length),
                length: 0
            )
            Self.applyFirstLineHeading(to: uiView, force: true)
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
        private var restingOffsetY: CGFloat?
        private var lastReportedScrollY: CGFloat?

        init(_ parent: EditorTextView) {
            self.parent = parent
        }

        func update(_ parent: EditorTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            EditorTextView.applyFirstLineHeading(to: textView)
            (textView as? StyledTextView)?.scheduleCaretVisibilityUpdate()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            EditorTextView.updateTypingAttributes(for: textView)
            (textView as? StyledTextView)?.scheduleCaretVisibilityUpdate()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            (scrollView as? StyledTextView)?.handleScroll()
            if restingOffsetY == nil, scrollView.contentOffset.y >= 0 {
                restingOffsetY = scrollView.contentOffset.y
            }
            let relativeY = max(0, scrollView.contentOffset.y - (restingOffsetY ?? 0))
            let clampedY = min(relativeY, 76)
            if lastReportedScrollY.map({ abs($0 - clampedY) > 2 }) ?? true {
                lastReportedScrollY = clampedY
                parent.onScroll(clampedY)
            }
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

    static func applyFirstLineHeading(to textView: UITextView, force: Bool = false) {
        let storage = textView.textStorage
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else {
            (textView as? StyledTextView)?.lastStyledHeadingKey = nil
            updateTypingAttributes(for: textView)
            return
        }

        let firstLine = firstNonBlankLineRange(in: textView.text ?? "")
        let headingKey = firstLine.map { range in
            let ns = (textView.text ?? "") as NSString
            return "\(range.location):\(range.length):\(ns.substring(with: range))"
        } ?? "none"

        if !force,
           (textView as? StyledTextView)?.lastStyledHeadingKey == headingKey {
            updateTypingAttributes(for: textView)
            return
        }

        storage.beginEditing()
        storage.removeAttribute(.paragraphStyle, range: full)
        storage.addAttribute(.font, value: bodyFont, range: full)
        storage.addAttribute(.foregroundColor, value: Theme.inkUIColor, range: full)
        if let firstLine {
            storage.addAttribute(.font, value: headingFont, range: firstLine)
            storage.addAttribute(.paragraphStyle, value: headingParagraphStyle, range: firstLine)
        }
        storage.endEditing()
        (textView as? StyledTextView)?.lastStyledHeadingKey = headingKey
        updateTypingAttributes(for: textView)
    }

    static func updateTypingAttributes(for textView: UITextView) {
        let text = textView.text ?? ""
        let selectedLocation = textView.selectedRange.location
        let headingRange = firstNonBlankLineRange(in: text)
        let useHeading: Bool

        if text.isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            useHeading = true
        } else if let headingRange {
            useHeading = selectedLocation <= headingRange.location + headingRange.length
        } else {
            useHeading = false
        }

        var attributes: [NSAttributedString.Key: Any] = [
            .font: useHeading ? headingFont : bodyFont,
            .foregroundColor: Theme.inkUIColor,
        ]
        if useHeading {
            attributes[.paragraphStyle] = headingParagraphStyle
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textView.font = headingFont
        }
        textView.typingAttributes = attributes
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
    private var userInterfaceStyleRegistration: (any UITraitChangeRegistration)?
    private var keyboardObservers: [NSObjectProtocol] = []
    private var baseTextContainerInset = UIEdgeInsets(top: 8, left: 16, bottom: 40, right: 16)
    private var keyboardOverlap: CGFloat = 0
    private var keyboardTopInWindow: CGFloat?
    private var pendingCaretVisibilityUpdate = false
    var lastStyledHeadingKey: String?

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
        applyPaperChrome()
        pullLabel.textColor = Theme.accentUIColor.withAlphaComponent(0.4)
        pullLabel.font = UIFont(name: "JetBrainsMono-Regular", size: 12)
            ?? UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        pullLabel.textAlignment = .center
        addSubview(pullLabel)
        userInterfaceStyleRegistration = registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (textView: StyledTextView, _) in
            textView.applyPaperChrome()
        }
        observeKeyboard()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        for observer in keyboardObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyPaperChrome()
        window?.backgroundColor = Theme.paperUIColor
        window?.rootViewController?.view.backgroundColor = Theme.paperUIColor
    }

    func applyPaperChrome() {
        let interfaceStyle: UIUserInterfaceStyle = (window?.traitCollection ?? traitCollection).userInterfaceStyle == .dark
            ? .dark
            : .light
        backgroundColor = Theme.paperUIColor
        isOpaque = true
        keyboardAppearance = interfaceStyle == .dark ? .dark : .light
    }

    func setBaseTextContainerInset(_ inset: UIEdgeInsets) {
        guard abs(baseTextContainerInset.top - inset.top) > 0.5
            || abs(baseTextContainerInset.left - inset.left) > 0.5
            || abs(baseTextContainerInset.bottom - inset.bottom) > 0.5
            || abs(baseTextContainerInset.right - inset.right) > 0.5
        else {
            applyEffectiveInsets()
            return
        }

        baseTextContainerInset = inset
        applyEffectiveInsets()
    }

    private func observeKeyboard() {
        let center = NotificationCenter.default
        keyboardObservers = [
            center.addObserver(
                forName: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.updateKeyboardOverlap(from: notification)
            },
            center.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.keyboardOverlap = 0
                self?.keyboardTopInWindow = nil
                self?.animateInsets(with: notification)
            },
        ]
    }

    private func updateKeyboardOverlap(from notification: Notification) {
        guard let window,
              let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else {
            keyboardOverlap = 0
            keyboardTopInWindow = nil
            animateInsets(with: notification)
            return
        }

        let keyboardInWindow = window.convert(keyboardFrame, from: nil)
        let textViewInWindow = convert(bounds, to: window)
        let overlap = max(0, textViewInWindow.maxY - keyboardInWindow.minY)
        keyboardOverlap = min(bounds.height, overlap)
        keyboardTopInWindow = keyboardOverlap > 0 ? keyboardInWindow.minY : nil
        animateInsets(with: notification)
    }

    private func animateInsets(with notification: Notification) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0
        let curveRaw = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 0
        var options = UIView.AnimationOptions(rawValue: curveRaw << 16)
        options.insert(.beginFromCurrentState)

        guard duration > 0 else {
            applyEffectiveInsets()
            keepCaretVisible(animated: false)
            return
        }

        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.applyEffectiveInsets()
            self.layoutIfNeeded()
            self.keepCaretVisible(animated: false)
        } completion: { _ in
            self.keepCaretVisible(animated: false)
        }
    }

    private func applyEffectiveInsets() {
        let lineHeight = max(font?.lineHeight ?? 0, typingAttributes[.font].flatMap { ($0 as? UIFont)?.lineHeight } ?? 0, 24)
        let effectiveInset = Self.effectiveTextContainerInset(
            baseInset: baseTextContainerInset,
            boundsHeight: bounds.height,
            lineHeight: lineHeight,
            keyboardOverlap: keyboardOverlap
        )

        if abs(textContainerInset.top - effectiveInset.top) > 0.5
            || abs(textContainerInset.left - effectiveInset.left) > 0.5
            || abs(textContainerInset.bottom - effectiveInset.bottom) > 0.5
            || abs(textContainerInset.right - effectiveInset.right) > 0.5 {
            textContainerInset = effectiveInset
        }

        scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: keyboardOverlap, right: 0)
    }

    static func effectiveTextContainerInset(
        baseInset: UIEdgeInsets,
        boundsHeight: CGFloat,
        lineHeight: CGFloat,
        keyboardOverlap: CGFloat
    ) -> UIEdgeInsets {
        let keyboardBottom = baseInset.bottom + keyboardOverlap
        let pageOverscroll = max(0, boundsHeight - baseInset.top - lineHeight)
        let effectiveBottom = keyboardOverlap > 0
            ? keyboardBottom
            : max(keyboardBottom, pageOverscroll)

        return UIEdgeInsets(
            top: baseInset.top,
            left: baseInset.left,
            bottom: effectiveBottom,
            right: baseInset.right
        )
    }

    func scheduleCaretVisibilityUpdate(animated: Bool = false) {
        guard !pendingCaretVisibilityUpdate else { return }
        pendingCaretVisibilityUpdate = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingCaretVisibilityUpdate = false
            self.keepCaretVisible(animated: animated)
        }
    }

    private func keepCaretVisible(animated: Bool) {
        guard isEditable,
              isFirstResponder,
              keyboardOverlap > 0,
              let window,
              let selectedTextRange
        else { return }

        layoutManager.ensureLayout(for: textContainer)
        layoutIfNeeded()

        let caret = caretRect(for: selectedTextRange.end)
        guard !caret.isNull, !caret.isInfinite, caret.height > 0 else { return }

        let textViewInWindow = convert(bounds, to: window)
        let caretInWindow = convert(caret, to: window)
        let bottomLimit = min(keyboardTopInWindow ?? window.bounds.maxY, textViewInWindow.maxY) - 18
        let topLimit = textViewInWindow.minY + 18

        var nextOffset = contentOffset
        if caretInWindow.maxY > bottomLimit {
            nextOffset.y += caretInWindow.maxY - bottomLimit
        } else if caretInWindow.minY < topLimit {
            nextOffset.y -= topLimit - caretInWindow.minY
        } else {
            return
        }

        let minOffsetY = -contentInset.top
        let maxOffsetY = max(minOffsetY, contentSize.height - bounds.height + contentInset.bottom)
        nextOffset.y = min(max(nextOffset.y, minOffsetY), maxOffsetY)

        guard abs(nextOffset.y - contentOffset.y) > 0.5 else { return }
        setContentOffset(nextOffset, animated: animated)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyEffectiveInsets()
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

    func focusWhenReady(attempt: Int = 0) {
        let configuredDelay = ProcessInfo.processInfo.environment["DRIFT_FOCUS_DELAY_MS"]
            .flatMap(Double.init)
            .map { max(0, $0) / 1000 } ?? 0
        let delay = attempt == 0 ? configuredDelay : 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isEditable else { return }
            if self.window != nil {
                self.applyPaperChrome()
                self.becomeFirstResponder()
            } else if attempt < 10 {
                self.focusWhenReady(attempt: attempt + 1)
            }
        }
    }
}
