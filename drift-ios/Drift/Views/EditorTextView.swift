import UIKit

/// A native plain-text editor. Formatting changes attributes in place; text,
/// selection, marked text, undo, and scrolling remain owned by UIKit.
@MainActor
final class EditorTextView: UITextView, @preconcurrency NSTextStorageDelegate {
    private let pullLabel = UILabel()
    private var headingRange: NSRange?
    private var changedRange: NSRange?
    private var isApplyingStyle = false
    private var pageTopInset: CGFloat = 12
    private var pageHorizontalInset: CGFloat = 20
    private var pageBottomInset: CGFloat = 32
    private var pageHeight: CGFloat?
    private var textContentSize = CGSize.zero
    private var extraPaperHeight: CGFloat = 0
    private var pendingCaretUpdate = false
    private var pullIsPrimed = false
    private var pullCanToggle = true
    var onPullReadMode: (() -> Void)?
    var isReading = false {
        didSet {
            pullLabel.text = isReading ? "Exit Read Mode" : "Read Mode"
            accessibilityHint = isReading ? "Pull down to exit Read Mode." : "Pull down for Read Mode."
            updatePullFeedback()
            setNeedsLayout()
        }
    }

    init() {
        // Select TextKit 1 before loading text. Switching engines on first
        // focus resets the scroll position; TextKit 2 also blanks lower lines
        // ahead of the rising keyboard on iOS 26.2.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        backgroundColor = Theme.paperUIColor
        textColor = Theme.inkUIColor
        tintColor = Theme.accentUIColor
        font = Theme.bodyUIFont()
        adjustsFontForContentSizeCategory = true
        keyboardDismissMode = .interactive
        alwaysBounceVertical = true
        contentInsetAdjustmentBehavior = .never
        automaticallyAdjustsScrollIndicatorInsets = false
        textContainer.lineFragmentPadding = 0
        textContainerInset = UIEdgeInsets(top: 12, left: 20, bottom: 32, right: 20)
        allowsEditingTextAttributes = false
        isFindInteractionEnabled = true
        autocorrectionType = .yes
        spellCheckingType = .yes
        smartQuotesType = .yes
        smartDashesType = .yes
        accessibilityIdentifier = "note-editor"
        accessibilityLabel = "Note"
        textStorage.delegate = self

        pullLabel.text = "Read Mode"
        pullLabel.font = Theme.mono(12, style: .caption1)
        pullLabel.textColor = Theme.accentUIColor.withAlphaComponent(0.4)
        pullLabel.textAlignment = .center
        pullLabel.isUserInteractionEnabled = false
        pullLabel.accessibilityIdentifier = "pull-mode-label"
        pullLabel.accessibilityElementsHidden = true
        pullLabel.alpha = 0
        addSubview(pullLabel)
        accessibilityHint = "Pull down for Read Mode."
        updatePaperAppearance()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (textView: EditorTextView, _) in
            textView.updatePaperAppearance()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var contentSize: CGSize {
        get { super.contentSize }
        set {
            textContentSize = newValue
            super.contentSize = CGSize(width: newValue.width, height: newValue.height + extraPaperHeight)
        }
    }

    func recordSelectionAudit(_ event: String) {
        #if DEBUG
        guard let path = ProcessInfo.processInfo.environment["DRIFT_SELECTION_AUDIT_LOG"] else { return }
        let entry: [String: Any] = ["event": event, "time": CACurrentMediaTime(),
            "offset": contentOffset.y, "location": selectedRange.location, "length": selectedRange.length,
            "activeGesture": (gestureRecognizers ?? []).contains { $0.state == .began || $0.state == .changed }]
        guard var data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        data.append(10)
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        guard let file = FileHandle(forWritingAtPath: path) else { return }
        defer { try? file.close() }
        _ = try? file.seekToEnd()
        try? file.write(contentsOf: data)
        #endif
    }

    #if DEBUG
    override var contentOffset: CGPoint {
        didSet {
            if abs(contentOffset.y - oldValue.y) > 0.1 { recordSelectionAudit("offset") }
        }
    }
    #endif

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePaperAppearance()
    }

    private func updatePaperAppearance() {
        keyboardAppearance = (window?.traitCollection ?? traitCollection).userInterfaceStyle == .dark ? .dark : .light
        backgroundColor = Theme.paperUIColor
        updatePullFeedback()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyPageInsets()
        let hintWidth = max(0, bounds.width - pageHorizontalInset * 2)
        let size = pullLabel.sizeThatFits(CGSize(width: hintWidth, height: 40))
        // Reveal the hint above the title, below the status area, rather than
        // placing it behind the Dynamic Island at the release threshold.
        pullLabel.frame = CGRect(x: (bounds.width - size.width) / 2, y: pageTopInset - 42, width: size.width, height: size.height)
    }

    func configurePageInsets(top: CGFloat, horizontal: CGFloat, bottom: CGFloat, pageHeight: CGFloat) {
        pageTopInset = top
        pageHorizontalInset = horizontal
        pageBottomInset = bottom
        self.pageHeight = pageHeight
        applyPageInsets()
    }

    private func applyPageInsets() {
        // The extra space is after the document, allowing a short note to
        // move upward into a reading position. Never insert space into text.
        // Even a single-line note gets the complete 76-point retreat. The
        // compact type otherwise leaves a short note unable to hide Back.
        // Keep document space tied to the full page while the keyboard changes
        // only its visible viewport, preserving the chosen reading position.
        let pageSpace = max(0, (pageHeight ?? bounds.height) - pageTopInset - Theme.editorTitleUIFont().lineHeight + 76)
        // A blank composer has no reading position to preserve. Extra space
        // lets UIKit scroll its empty insertion point out of view during focus.
        let extraPaper = textStorage.length == 0 ? 0 : max(0, pageSpace - pageBottomInset)
        let inset = UIEdgeInsets(top: pageTopInset, left: pageHorizontalInset, bottom: pageBottomInset, right: pageHorizontalInset)
        // TextKit uses the text-container inset as its selection-autoscroll
        // boundary. A page-sized bottom inset puts even an interior long press
        // in that boundary and scrolls the entire document under the finger.
        // A large scroll-view content inset also obscures native caret reveal.
        // Extend the scrollable paper instead, keeping TextKit's natural size
        // separate so repeated layout never accumulates the extra space.
        if extraPaper > extraPaperHeight {
            extraPaperHeight = extraPaper
            super.contentSize = CGSize(width: textContentSize.width, height: textContentSize.height + extraPaperHeight)
        }
        if textContainerInset != inset { textContainerInset = inset }
        if extraPaperHeight != extraPaper {
            extraPaperHeight = extraPaper
            super.contentSize = CGSize(width: textContentSize.width, height: textContentSize.height + extraPaperHeight)
        }
    }

    func updatePullFeedback() {
        let isPrimed = pullCanToggle && contentOffset.y <= -78
        pullIsPrimed = isPrimed
        let depth = max(0, -contentOffset.y)
        pullLabel.alpha = pullCanToggle ? min(1, max(0, (depth - 12) / 24)) : 0
        pullLabel.textColor = Theme.accentUIColor.withAlphaComponent(isPrimed ? 1 : 0.4)
        pullLabel.accessibilityElementsHidden = !pullCanToggle || depth < 20
        pullLabel.accessibilityValue = isPrimed ? "Release to \(isReading ? "exit" : "enter") Read Mode" : nil
    }

    func beginPull(keyboardIsVisible: Bool) {
        // A downward drag dismissing the keyboard must not also switch modes.
        pullCanToggle = !keyboardIsVisible
        updatePullFeedback()
    }

    func finishPull() {
        guard pullIsPrimed, contentOffset.y <= -78 else { return }
        pullIsPrimed = false
        onPullReadMode?()
    }

    func keepCaretVisibleAfterLayout(animated: Bool = false) {
        guard isFirstResponder, isEditable, !pendingCaretUpdate else { return }
        pendingCaretUpdate = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingCaretUpdate = false
            self.recordSelectionAudit("caretRun")
            guard self.isFirstResponder, self.isEditable, !self.isDragging,
                  let selection = self.selectedTextRange, selection.isEmpty else { return }
            // A range's end is its larger document offset, not necessarily the
            // handle being dragged. UIKit owns selection autoscroll; revealing
            // that ordered end here pulls a long selection away from its start.
            self.layoutManager.ensureLayout(for: self.textContainer)
            let caret = self.caretRect(for: selection.end)
            guard !caret.isNull, caret.height > 0 else { return }
            let visibleBottom = self.bounds.maxY - 18
            let visibleTop = self.bounds.minY + (self.window?.safeAreaInsets.top ?? 0) + 18
            var offset = self.contentOffset
            if caret.maxY > visibleBottom { offset.y += caret.maxY - visibleBottom }
            else if caret.minY < visibleTop { offset.y -= visibleTop - caret.minY }
            else { return }
            let maximum = max(0, self.contentSize.height - self.bounds.height)
            offset.y = min(maximum, max(0, offset.y))
            guard abs(offset.y - self.contentOffset.y) > 0.5 else { return }
            if animated && !UIAccessibility.isReduceMotionEnabled {
                // Commit the focus destination while animating its presentation,
                // so immediate typing cannot snap the remaining caret clearance.
                UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                    self.setContentOffset(offset, animated: false)
                }
            } else {
                self.setContentOffset(offset, animated: false)
            }
        }
    }

    /// Used only when opening a document or accepting a clean external refresh.
    func loadText(_ newText: String, preservingPosition: Bool = false) {
        let selection = selectedRange
        let offset = contentOffset
        text = newText
        headingRange = nil
        restyleAll()
        if preservingPosition {
            restoreSelection(selection)
            setContentOffset(offset, animated: false)
        } else {
            selectedRange = NSRange(location: 0, length: 0)
        }
        undoManager?.removeAllActions()
    }

    func restoreSelection(_ selection: NSRange) {
        let length = textStorage.length
        let location = min(selection.location, length)
        selectedRange = NSRange(location: location, length: min(selection.length, length - location))
    }

    func restyleAll() {
        guard markedTextRange == nil else { return }
        changedRange = NSRange(location: 0, length: textStorage.length)
        styleChangedText()
        pullLabel.font = Theme.mono(12, style: .caption1)
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard !isApplyingStyle, editedMask.contains(.editedCharacters) else { return }
        changedRange = changedRange.map { NSUnionRange($0, editedRange) } ?? editedRange
    }

    func styleChangedText() {
        // Restyling a composition can prematurely commit Chinese/Japanese input.
        guard !isApplyingStyle else { return }
        guard markedTextRange == nil else { return }
        guard let editRange = changedRange else { updateTypingStyle(); return }
        let string = textStorage.string as NSString
        let length = string.length
        let newHeading = firstNonblankLine(in: string)
        isApplyingStyle = true
        let manager = undoManager
        let wasUndoEnabled = manager?.isUndoRegistrationEnabled == true
        if wasUndoEnabled { manager?.disableUndoRegistration() }
        textStorage.beginEditing()

        if length > 0 {
            let location = min(editRange.location, length)
            let range = NSRange(location: location, length: min(editRange.length, length - location))
            let changedParagraph = string.paragraphRange(for: range)
            applyBodyStyle(to: changedParagraph)
            // Distant body edits must not invalidate layout back to the title.
            // Restyle the heading only when it changed or its paragraph was edited.
            if headingRange != newHeading || newHeading.map({ NSIntersectionRange(changedParagraph, $0).length > 0 }) == true {
                let prefixEnd = min(length, max(NSMaxRange(headingRange ?? NSRange()), NSMaxRange(newHeading ?? NSRange())))
                if prefixEnd > 0 { applyBodyStyle(to: NSRange(location: 0, length: prefixEnd)) }
                if let newHeading { textStorage.addAttributes(headingAttributes, range: newHeading) }
            }
        }
        textStorage.endEditing()
        if wasUndoEnabled { manager?.enableUndoRegistration() }
        isApplyingStyle = false
        headingRange = newHeading
        changedRange = nil
        // Refresh text-dependent spacing after styling, before caret scrolling.
        applyPageInsets()
        updateTypingStyle()
    }

    func updateTypingStyle() {
        guard markedTextRange == nil else { return }
        let location = selectedRange.location
        let heading = headingRange
        let isHeading = textStorage.length == 0 || heading.map {
            location >= $0.location && location <= NSMaxRange($0)
        } == true
        typingAttributes = isHeading ? headingAttributes : bodyAttributes
    }

    private var bodyAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 0
        paragraph.paragraphSpacing = 0
        return [.font: Theme.bodyUIFont(), .foregroundColor: Theme.inkUIColor, .paragraphStyle: paragraph]
    }

    private var headingAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 8
        paragraph.lineSpacing = 0
        return [.font: Theme.editorTitleUIFont(), .foregroundColor: Theme.inkUIColor, .paragraphStyle: paragraph]
    }

    private func applyBodyStyle(to range: NSRange) {
        guard range.length > 0, NSMaxRange(range) <= textStorage.length else { return }
        textStorage.setAttributes(bodyAttributes, range: range)
    }

    private func firstNonblankLine(in string: NSString) -> NSRange? {
        var location = 0
        while location < string.length {
            let line = string.lineRange(for: NSRange(location: location, length: 0))
            var end = NSMaxRange(line)
            while end > line.location && (string.character(at: end - 1) == 10 || string.character(at: end - 1) == 13) { end -= 1 }
            let contents = NSRange(location: line.location, length: end - line.location)
            if !string.substring(with: contents).trimmingCharacters(in: .whitespaces).isEmpty { return contents }
            location = NSMaxRange(line)
        }
        return nil
    }

    override func paste(_ sender: Any?) {
        // Files remain plain Markdown even when pasting styled web content.
        guard let string = UIPasteboard.general.string else { super.paste(sender); return }
        insertText(string)
    }

    /// List continuation goes through UITextInput so one undo restores the
    /// original line. Returning on an empty item ends the list.
    func continueList(for range: NSRange, replacement: String) -> Bool {
        guard replacement == "\n", range.length == 0, markedTextRange == nil else { return false }
        let string = textStorage.string as NSString
        guard range.location <= string.length else { return false }
        let line = string.lineRange(for: NSRange(location: range.location, length: 0))
        let prefixRange = NSRange(location: line.location, length: range.location - line.location)
        let beforeCursor = string.substring(with: prefixRange)
        let pattern = #"^(\s*)(?:([-*+])\s+(?:\[([ xX])\]\s+)?|(\d+)([.)])\s+)(.*)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: beforeCursor, range: NSRange(location: 0, length: (beforeCursor as NSString).length))
        else { return false }
        let source = beforeCursor as NSString
        func capture(_ index: Int) -> String {
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : source.substring(with: range)
        }
        let indentation = capture(1)
        let content = capture(6)
        let tailRange = NSRange(location: range.location, length: NSMaxRange(line) - range.location)
        let hasTextAfterCursor = !string.substring(with: tailRange).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if content.trimmingCharacters(in: .whitespaces).isEmpty && !hasTextAfterCursor {
            let start = position(from: beginningOfDocument, offset: line.location)!
            let end = position(from: beginningOfDocument, offset: range.location)!
            if let selection = textRange(from: start, to: end) { replace(selection, withText: indentation) }
        } else {
            let marker: String
            if let number = Int(capture(4)), number < Int.max {
                marker = "\(number + 1)\(capture(5)) "
            } else if match.range(at: 3).location != NSNotFound {
                marker = "\(capture(2)) [ ] "
            } else {
                marker = "\(capture(2)) "
            }
            insertText("\n" + indentation + marker)
        }
        return true
    }

    func insertListMarker(_ marker: String) {
        guard isEditable, markedTextRange == nil else { return }
        let string = textStorage.string as NSString
        let line = string.lineRange(for: NSRange(location: min(selectedRange.location, string.length), length: 0))
        guard let start = position(from: beginningOfDocument, offset: line.location),
              let insertion = textRange(from: start, to: start) else { return }
        let oldSelection = selectedRange
        replace(insertion, withText: marker)
        restoreSelection(NSRange(location: oldSelection.location + (marker as NSString).length, length: oldSelection.length))
        becomeFirstResponder()
    }
}
