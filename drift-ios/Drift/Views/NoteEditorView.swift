import UIKit

/// Serializes each document's journal and save operations. A completing save
/// advances only its own baseline; text entered while it runs stays dirty.
@MainActor
final class EditorDocumentSession {
    enum Status: Equatable {
        case saved, saving, recovered, conflict
        case failed(String)
    }

    struct RefreshRequest {
        let snapshot: NoteSnapshot
        let revision: Int
    }

    private let store: NoteStore
    private(set) var snapshot: NoteSnapshot
    private(set) var text: String
    private(set) var status: Status
    private var needsRecoverySave: Bool
    private var debounceTask: Task<Void, Never>?
    private var saveTask: Task<Bool, Never>?
    private var providerWriteInFlight = false
    private var journalTask: Task<Void, Never>?
    private var editRevision = 0
    private var journalRevision = 0
    private var journalFailed = false
    var onUpdate: (() -> Void)?
    var isDirty: Bool {
        if snapshot.isUnsaved, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return text != snapshot.text || needsRecoverySave
    }
    var isSaving: Bool { saveTask != nil }

    init(store: NoteStore, snapshot: NoteSnapshot) {
        self.store = store
        self.snapshot = snapshot
        text = snapshot.text
        needsRecoverySave = snapshot.recoveredDraft
        status = snapshot.recoveredDraft ? .recovered : .saved
        if snapshot.recoveredDraft { editRevision = 1 }
    }

    func changed(_ text: String) {
        self.text = text
        editRevision += 1
        startJournal()
        debounceTask?.cancel()
        if isDirty {
            if case .failed = status {} else { status = .saving }
            debounceTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                guard let self else { return }
                await self.flush()
            }
        } else if !isSaving {
            status = .saved
        }
        onUpdate?()
    }

    func flush() async {
        debounceTask?.cancel()
        debounceTask = nil
        while true {
            let task: Task<Bool, Never>
            if let existing = saveTask {
                task = existing
            } else {
                guard isDirty || journalRevision != editRevision else { return }
                task = Task { [self] in
                    // Task ownership includes local cleanup, not just the
                    // provider write. Every caller awaits the same full flush.
                    defer { saveTask = nil }
                    while true {
                        guard await journalLatest() else { return false }
                        guard isDirty else { return true }
                        let savingText = text
                        let savingSnapshot = snapshot
                        status = .saving
                        onUpdate?()
                        providerWriteInFlight = true
                        do {
                            let result = try await store.save(savingText, snapshot: savingSnapshot)
                            providerWriteInFlight = false
                            snapshot = result.snapshot
                            needsRecoverySave = false
                            status = result.preservedConflict ? .conflict : .saved
                            // Rebase a newer draft, or discard a clean one,
                            // after every local write that raced the provider.
                            editRevision += 1
                            startJournal()
                            onUpdate?()
                        } catch {
                            providerWriteInFlight = false
                            status = .failed(error.localizedDescription)
                            onUpdate?()
                            // Finish journaling text typed during the failed
                            // provider request before a background flush ends.
                            // If it was undone, clear its now-clean draft too.
                            editRevision += 1
                            startJournal()
                            _ = await journalLatest()
                            return false
                        }
                    }
                }
                saveTask = task
            }
            guard await task.value else { return }
            // Another edit can arrive while an awaiting caller is resumed.
            // Recheck instead of cancelling its debounce and returning early.
        }
    }

    /// Independent from provider writes, so a slow iCloud request cannot block
    /// recovery of text that the user is still entering.
    private func startJournal() {
        guard journalTask == nil, journalRevision != editRevision else { return }
        journalFailed = false
        journalTask = Task { [self] in
            try? await Task.sleep(for: .milliseconds(80))
            while journalRevision != editRevision {
                let revision = editRevision
                let currentText = text
                let currentSnapshot = snapshot
                do {
                    let emptyComposer = currentSnapshot.isUnsaved
                        && currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if !providerWriteInFlight && (emptyComposer || (currentText == currentSnapshot.text && !needsRecoverySave)) {
                        try await store.discardDraft(snapshot: currentSnapshot)
                    } else {
                        try await store.persistDraft(currentText, snapshot: currentSnapshot)
                    }
                    journalRevision = revision
                    if !isDirty, !providerWriteInFlight, case .failed = status {
                        status = .saved
                        onUpdate?()
                    }
                } catch {
                    journalFailed = true
                    status = .failed(error.localizedDescription)
                    onUpdate?()
                    break
                }
            }
            journalTask = nil
        }
    }

    private func journalLatest() async -> Bool {
        while journalRevision != editRevision {
            startJournal()
            await journalTask?.value
            if journalFailed { return false }
        }
        return true
    }

    func makeRefreshRequest() -> RefreshRequest? {
        guard !snapshot.isUnsaved, !isDirty, !isSaving, journalTask == nil, journalRevision == editRevision else { return nil }
        return RefreshRequest(snapshot: snapshot, revision: editRevision)
    }

    func acceptCleanRefresh(_ fresh: NoteSnapshot, request: RefreshRequest) -> Bool {
        guard let current = makeRefreshRequest(), current.revision == request.revision,
              text == request.snapshot.text, snapshot.note.url == request.snapshot.note.url else { return false }
        snapshot = fresh
        text = fresh.text
        needsRecoverySave = fresh.recoveredDraft
        if fresh.recoveredDraft { editRevision += 1 }
        status = fresh.recoveredDraft ? .recovered : .saved
        onUpdate?()
        return true
    }
}

@MainActor
final class NoteEditorViewController: UIViewController, UITextViewDelegate {
    var onNoteChange: (() -> Void)?
    var currentNote: Note { session.snapshot.note }

    private let store: NoteStore
    private let session: EditorDocumentSession
    private let isNew: Bool
    private let editor = EditorTextView()
    private let messageButton = UIButton(type: .system)
    private let backChrome = EditorBackChrome()
    private let backButton = PaperIconButton(symbol: "chevron.left", accessibilityLabel: "Back")
    private let readIndicator = UIImageView(image: UIImage(systemName: "lock.fill"))
    private let topFade = PaperEdgeFade(edge: .top)
    private let bottomFade = PaperEdgeFade(edge: .bottom)
    private var isReadMode = false
    private var readingSelection: NSRange?
    private var didRequestInitialFocus = false
    private var didRestorePosition = false
    private var didAppearOnce = false
    private var initialSearchQuery: String?
    private var deleting = false
    private var lastSavedURL: URL
    private var rememberedConflict = false
    private var renderedStatus: EditorDocumentSession.Status?
    private var isContinuingList = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var refreshTask: Task<Void, Never>?

    init(store: NoteStore, snapshot: NoteSnapshot, isNew: Bool = false) {
        self.store = store
        self.session = EditorDocumentSession(store: store, snapshot: snapshot)
        self.isNew = isNew
        self.lastSavedURL = snapshot.note.url
        super.init(nibName: nil, bundle: nil)
        session.onUpdate = { [weak self] in self?.sessionChanged() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func revealMatch(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        initialSearchQuery = query
        if didAppearOnce { revealInitialMatch() }
    }

    private func revealInitialMatch() {
        guard let query = initialSearchQuery else { return }
        initialSearchQuery = nil
        let range = (editor.text as NSString).range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
        guard range.location != NSNotFound else { return }
        editor.selectedRange = range
        editor.scrollRangeToVisible(range)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.paperUIColor
        view.tintColor = Theme.accentUIColor
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.title = ""

        editor.delegate = self
        editor.loadText(session.text)
        editor.onPullReadMode = { [weak self] in self?.toggleReadMode() }
        editor.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(editor)
        view.keyboardLayoutGuide.usesBottomSafeArea = false
        NSLayoutConstraint.activate([
            editor.topAnchor.constraint(equalTo: view.topAnchor),
            editor.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            editor.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])

        topFade.translatesAutoresizingMaskIntoConstraints = true
        bottomFade.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(topFade)
        view.addSubview(bottomFade)
        backButton.translatesAutoresizingMaskIntoConstraints = true
        backButton.accessibilityIdentifier = "editor-back"
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        backChrome.clipsToBounds = true
        backChrome.addSubview(backButton)
        view.addSubview(backChrome)
        readIndicator.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .footnote)
        readIndicator.tintColor = Theme.accentUIColor.withAlphaComponent(0.45)
        readIndicator.contentMode = .scaleAspectFit
        readIndicator.isAccessibilityElement = true
        readIndicator.accessibilityLabel = "Read Mode"
        readIndicator.accessibilityIdentifier = "read-mode-indicator"
        readIndicator.isHidden = true
        view.addSubview(readIndicator)
        configureAccessibleActions()

        messageButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .footnote)
        messageButton.titleLabel?.adjustsFontForContentSizeCategory = true
        messageButton.titleLabel?.numberOfLines = 0
        messageButton.contentHorizontalAlignment = .leading
        var messageConfiguration = UIButton.Configuration.plain()
        messageConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 20, bottom: 7, trailing: 20)
        messageConfiguration.baseForegroundColor = Theme.accentUIColor
        messageConfiguration.titleLineBreakMode = .byWordWrapping
        messageConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.preferredFont(forTextStyle: .footnote)
            return attributes
        }
        messageButton.configuration = messageConfiguration
        messageButton.backgroundColor = Theme.accentUIColor.withAlphaComponent(0.08)
        messageButton.setTitleColor(Theme.accentUIColor, for: .normal)
        messageButton.addTarget(self, action: #selector(messageTapped), for: .touchUpInside)
        messageButton.isHidden = true
        view.addSubview(messageButton)

        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(contentSizeChanged), name: UIContentSizeCategory.didChangeNotification, object: nil)
        sessionChanged()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let readableInset: CGFloat = view.bounds.width > 700 ? max(24, (view.bounds.width - 700) / 2) : 20
        let horizontalInset = max(readableInset, max(view.safeAreaInsets.left, view.safeAreaInsets.right) + 20)
        let top = view.safeAreaInsets.top
        let bottom = keyboardIsVisible ? 0 : view.safeAreaInsets.bottom
        editor.configurePageInsets(top: top + 70, horizontal: horizontalInset, bottom: bottom + 24,
                                   allowsOverscroll: !keyboardIsVisible && !editor.isFirstResponder)
        // The thumb follows the viewport edge, independently of the title
        // padding and retreating Back control. The viewport ends at the keyboard.
        editor.verticalScrollIndicatorInsets = editor.safeAreaInsets
        topFade.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: top + 18)
        bottomFade.frame = CGRect(x: 0, y: editor.frame.maxY - bottom - 24, width: view.bounds.width, height: bottom + 24)
        bottomFade.isHidden = keyboardIsVisible || editor.isFirstResponder
        // Reset the transform before positioning so scrolling never influences
        // the next layout pass's resting frame.
        backChrome.frame = CGRect(x: 0, y: top, width: view.bounds.width, height: 96)
        backButton.transform = .identity
        backButton.frame = CGRect(x: view.safeAreaInsets.left + 18, y: 4, width: 44, height: 44)
        readIndicator.frame = CGRect(x: view.bounds.width - view.safeAreaInsets.right - 36, y: top + 17, width: 16, height: 18)
        let messageWidth = view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right
        let messageHeight = messageButton.sizeThatFits(CGSize(width: messageWidth, height: .greatestFiniteMagnitude)).height
        messageButton.frame = CGRect(x: view.safeAreaInsets.left, y: editor.frame.maxY - bottom - messageHeight, width: messageWidth, height: messageHeight)
        updateRetreatingChrome()
        if !didRestorePosition, editor.bounds.height > 0 {
            didRestorePosition = true
            restorePosition()
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        guard !didRequestInitialFocus else { return }
        didRequestInitialFocus = true
        if isNew || session.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            editor.becomeFirstResponder()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !didAppearOnce {
            didAppearOnce = true
            let openingQuery = initialSearchQuery
            revealInitialMatch()
            if session.snapshot.recoveredDraft {
                Task { await session.flush() }
            } else {
                // A cached snapshot is ready for the push. Check its provider
                // version only after that opening animation has finished.
                refreshIfClean(revealQuery: openingQuery)
            }
        } else {
            refreshIfClean()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        refreshTask?.cancel()
        savePosition()
        if !deleting { Task { await session.flush() } }
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        guard parent == nil, didAppearOnce, !deleting else { return }
        refreshTask?.cancel()
        savePosition()
        // A cancelled back swipe never removes this controller from its parent.
        Task { [self] in
            await session.flush()
            if isNew, !session.snapshot.isUnsaved, session.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                do {
                    let fresh = try await store.open(session.snapshot.note)
                    if fresh.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        try await store.trash(fresh.note)
                    }
                } catch {
                    // Keep the empty document if safe removal cannot be verified.
                }
            }
            onNoteChange?()
        }
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        view.setNeedsLayout()
        editor.keepCaretVisibleAfterLayout()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        view.setNeedsLayout()
    }

    func textViewDidChange(_ textView: UITextView) {
        editor.styleChangedText()
        session.changed(editor.text ?? "")
        editor.keepCaretVisibleAfterLayout()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        if editor.markedTextRange == nil { editor.styleChangedText() }
        editor.updateTypingStyle()
        editor.keepCaretVisibleAfterLayout()
    }

    private var keyboardIsVisible: Bool {
        view.keyboardLayoutGuide.layoutFrame.height > view.safeAreaInsets.bottom + 20
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        editor.beginPull(keyboardIsVisible: keyboardIsVisible || editor.isFirstResponder)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        editor.updatePullFeedback()
        updateRetreatingChrome()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        editor.finishPull()
    }

    private func updateRetreatingChrome() {
        let distance = max(0, editor.contentOffset.y)
        let opacity = max(0, min(1, 1 - (distance - 8) / 68))
        backButton.alpha = opacity
        backButton.transform = CGAffineTransform(translationX: 0, y: -min(90, distance))
        let isVisible = opacity > 0.05 && backButton.frame.maxY > 0
        backButton.isUserInteractionEnabled = isVisible
        backButton.accessibilityElementsHidden = !isVisible
    }

    @objc private func goBack() { navigationController?.popViewController(animated: true) }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard !isContinuingList else { return true }
        isContinuingList = true
        defer { isContinuingList = false }
        if editor.continueList(for: range, replacement: text) {
            // UITextInput replacement normally delivers didChange itself;
            // explicitly synchronizing here is harmless and covers providers
            // that deliver only a selection change for programmatic edits.
            textViewDidChange(editor)
            return false
        }
        return true
    }

    private func sessionChanged() {
        guard isViewLoaded else { return }
        defer { view.setNeedsLayout() }
        if lastSavedURL != session.snapshot.note.url {
            UserDefaults.standard.removeObject(forKey: positionKey(lastSavedURL))
            lastSavedURL = session.snapshot.note.url
            savePosition()
        }
        guard renderedStatus != session.status else { return }
        renderedStatus = session.status
        switch session.status {
        case .saved:
            onNoteChange?()
            if rememberedConflict {
                messageButton.setTitle("Saved as a separate copy. Both versions are safe.", for: .normal)
            } else { messageButton.isHidden = true }
        case .saving:
            break
        case .recovered:
            messageButton.setTitle("Recovered your unsaved changes.", for: .normal)
            messageButton.isHidden = false
        case .conflict:
            rememberedConflict = true
            onNoteChange?()
            messageButton.setTitle("Saved as a separate copy. Both versions are safe.", for: .normal)
            messageButton.isHidden = false
            UIAccessibility.post(notification: .announcement, argument: "A newer version was found. Both versions have been saved.")
        case .failed:
            messageButton.setTitle("Couldn’t save. Tap to retry.", for: .normal)
            messageButton.isHidden = false
        }
    }

    @objc private func retrySave() { Task { await session.flush() } }

    @objc private func messageTapped() {
        if case .failed(let detail) = session.status {
            let alert = UIAlertController(title: "Couldn’t Save", message: detail, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in self?.retrySave() })
            alert.addAction(UIAlertAction(title: "Share a Copy", style: .default) { [weak self] _ in self?.shareNote() })
            alert.addAction(UIAlertAction(title: "Keep Editing", style: .cancel))
            present(alert, animated: true)
        } else {
            rememberedConflict = false
            messageButton.isHidden = true
        }
    }

    @objc private func toggleReadMode() {
        isReadMode.toggle()
        if isReadMode {
            readingSelection = editor.selectedRange
            editor.resignFirstResponder()
        }
        editor.isEditable = !isReadMode
        editor.isSelectable = !isReadMode
        editor.isFindInteractionEnabled = !isReadMode
        editor.isReading = isReadMode
        if !isReadMode, let selection = readingSelection { editor.restoreSelection(selection) }
        readIndicator.isHidden = !isReadMode
        configureAccessibleActions()
        UIAccessibility.post(notification: .announcement, argument: isReadMode ? "Read Mode" : "Read Mode off")
    }

    private func configureAccessibleActions() {
        editor.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: isReadMode ? "Exit Read Mode" : "Read Mode", target: self, selector: #selector(accessibleToggleReadMode)),
            UIAccessibilityCustomAction(name: "Back to Notes", target: self, selector: #selector(accessibleGoBack)),
            UIAccessibilityCustomAction(name: "Share Note", target: self, selector: #selector(accessibleShare)),
        ]
    }

    @objc private func accessibleToggleReadMode() -> Bool { toggleReadMode(); return true }
    @objc private func accessibleGoBack() -> Bool { goBack(); return true }
    @objc private func accessibleShare() -> Bool { shareNote(); return true }

    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        // Secondary actions live with the system selection menu. The page
        // itself has no permanent menu or editing toolbar.
        UIMenu(children: suggestedActions + [makeDocumentMenu()])
    }

    private func makeDocumentMenu() -> UIMenu {
        UIMenu(title: "Note", children: [
            UIAction(title: "Read Mode", image: UIImage(systemName: "lock")) { [weak self] _ in
                self?.toggleReadMode()
            },
            UIAction(title: "Find in Note", image: UIImage(systemName: "magnifyingglass")) { [weak self] _ in
                self?.findInNote()
            },
            UIAction(title: "Share Note", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in self?.shareNote() },
            UIAction(title: "Move to Trash", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.confirmTrash() },
        ])
    }

    @objc private func findInNote() {
        guard !isReadMode else { return }
        editor.findInteraction?.presentFindNavigator(showingReplace: false)
    }

    private func shareNote() {
        let sheet = UIActivityViewController(activityItems: [session.text], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.safeAreaInsets.top + 48, width: 1, height: 1)
        present(sheet, animated: true)
    }

    private func confirmTrash() {
        let alert = UIAlertController(title: "Move Note to Trash?", message: "You can undo this from the notebook’s options menu.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Move to Trash", style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.session.flush()
                guard !self.session.isDirty else { self.messageTapped(); return }
                if self.session.snapshot.isUnsaved {
                    // Flushing a blank composer only discards its local draft;
                    // it has never created a shared file that could be trashed.
                    self.deleting = true
                    self.onNoteChange?()
                    self.navigationController?.popViewController(animated: true)
                    return
                }
                do {
                    try await self.store.trash(self.session.snapshot.note)
                    self.deleting = true
                    self.onNoteChange?()
                    self.navigationController?.popViewController(animated: true)
                } catch {
                    let failure = UIAlertController(title: "Couldn’t Move Note", message: error.localizedDescription, preferredStyle: .alert)
                    failure.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(failure, animated: true)
                }
            }
        })
        present(alert, animated: true)
    }

    @objc private func contentSizeChanged() { editor.restyleAll() }

    @objc private func applicationWillResignActive() {
        guard !deleting else { return }
        savePosition()
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save Note") { [weak self] in
                Task { @MainActor in self?.endBackgroundTask() }
            }
        }
        Task { [self] in
            await session.flush()
            endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    @objc private func applicationDidBecomeActive() {
        guard viewIfLoaded?.window != nil, !deleting else { return }
        if session.isDirty { Task { await session.flush() } } else { refreshIfClean() }
    }

    private func refreshIfClean(revealQuery: String? = nil) {
        guard editor.markedTextRange == nil, !deleting,
              let request = session.makeRefreshRequest() else { return }
        let selectionWhenRequested = editor.selectedRange
        let offsetWhenRequested = editor.contentOffset
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let fresh = try await self.store.open(request.snapshot.note)
                guard !Task.isCancelled, !self.deleting, self.editor.markedTextRange == nil,
                      self.viewIfLoaded?.window != nil,
                      self.navigationController?.topViewController === self else { return }
                if self.session.acceptCleanRefresh(fresh, request: request) {
                    if self.editor.text != fresh.text {
                        let hasStayedAtOpeningMatch = self.editor.selectedRange == selectionWhenRequested
                            && abs(self.editor.contentOffset.y - offsetWhenRequested.y) < 1
                        self.editor.loadText(fresh.text, preservingPosition: true)
                        if let revealQuery, hasStayedAtOpeningMatch {
                            self.revealMatch(revealQuery)
                        }
                        UIAccessibility.post(notification: .announcement, argument: "Note updated from your folder.")
                    }
                    if fresh.recoveredDraft { await self.session.flush() }
                }
            } catch {
                guard !Task.isCancelled, !self.deleting, self.editor.markedTextRange == nil,
                      self.viewIfLoaded?.window != nil,
                      self.navigationController?.topViewController === self,
                      let current = self.session.makeRefreshRequest(),
                      current.revision == request.revision,
                      current.snapshot.note.url == request.snapshot.note.url else { return }
                // A read failure cannot replace an open document with empty text.
                self.messageButton.setTitle("Couldn’t check for updates.", for: .normal)
                self.messageButton.isHidden = false
                self.view.setNeedsLayout()
            }
        }
    }

    private func positionKey(_ url: URL) -> String { "drift.editor.position." + url.absoluteString }

    private func savePosition() {
        guard isViewLoaded, !session.snapshot.isUnsaved else { return }
        UserDefaults.standard.set([
            "location": editor.selectedRange.location,
            "length": editor.selectedRange.length,
            "offset": max(0, editor.contentOffset.y),
        ], forKey: positionKey(session.snapshot.note.url))
    }

    private func restorePosition() {
        guard let values = UserDefaults.standard.dictionary(forKey: positionKey(session.snapshot.note.url)),
              let location = values["location"] as? Int else { return }
        let length = values["length"] as? Int ?? 0
        editor.restoreSelection(NSRange(location: max(0, location), length: max(0, length)))
        editor.layoutIfNeeded()
        let maximum = max(0, editor.contentSize.height - editor.bounds.height)
        let offset = min(maximum, max(0, values["offset"] as? Double ?? 0))
        editor.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
    }
}

/// Clip only at the system edge while letting touches outside Back reach the
/// paper. The button may retreat behind the status area, never over its clock.
private final class EditorBackChrome: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let target = super.hitTest(point, with: event)
        return target === self ? nil : target
    }
}
