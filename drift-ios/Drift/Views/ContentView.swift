import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let notebook = NotebookViewController(store: NoteStore())
        return PaperNavigationController(rootViewController: notebook)
    }
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

@MainActor
final class NotebookViewController: UIViewController, UITableViewDelegate, UITextFieldDelegate, UIDocumentPickerDelegate, UIGestureRecognizerDelegate {
    private enum Section: Int { case notes }
    private let store: NoteStore
    private let table = UITableView(frame: .zero, style: .plain)
    private let search = UITextField()
    private let chrome = UIStackView()
    private let searchGlass = UIVisualEffectView()
    private var chromeHeightConstraint: NSLayoutConstraint!
    private var searchHeightConstraint: NSLayoutConstraint!
    private let composeButton = PaperIconButton(symbol: "plus", accessibilityLabel: "New Note")
    private let cancelButton = PaperIconButton(symbol: "xmark", accessibilityLabel: "Cancel Search")
    private let folderButton = PaperIconButton(symbol: "ellipsis", accessibilityLabel: "Notebook Options")
    private var showsSearchCancel = false
    private let emptyView = NotebookEmptyView()
    private let activity = UIActivityIndicatorView(style: .medium)
    private let refreshControl = UIRefreshControl()
    private var source: UITableViewDiffableDataSource<Section, URL>!
    private var hitsByURL: [URL: NoteSearchHit] = [:]
    private var renderedQuery = ""
    private var observers: [NSObjectProtocol] = []
    private var opening = false
    private var switchingFolder = false
    private var folderSelection: (id: UUID, url: URL)?
    private var needsRender = false
    private var hasLoaded = false
    private let launchPreferences = LaunchPreferences()
    private var launchPending = true
    private var launchOverride: LaunchDestination?
    private var launchSession = LaunchSessionPolicy.configured()
    private var preparingLaunchTransition = false
    private var messageView: UIView?
    private var messageTask: Task<Void, Never>?
    private lazy var newNoteCommand = UIKeyCommand(title: "New Note", action: #selector(createNote), input: "n", modifierFlags: .command)
    private lazy var searchNotesCommand = UIKeyCommand(title: "Search Notes", action: #selector(focusSearch), input: "f", modifierFlags: .command)
    private var query: String { search.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }

    init(store: NoteStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        (navigationController as? PaperNavigationController)?.onDidShow = { [weak self] in
            // UIKit finishes clearing the transition coordinator after didShow.
            Task { @MainActor in self?.applyLaunchDestinationIfReady() }
        }
        view.backgroundColor = Theme.paperUIColor
        view.tintColor = Theme.accentUIColor
        definesPresentationContext = true
        composeButton.addTarget(self, action: #selector(createNote), for: .touchUpInside)
        composeButton.accessibilityIdentifier = "new-note"
        cancelButton.addTarget(self, action: #selector(cancelSearch), for: .touchUpInside)
        cancelButton.accessibilityIdentifier = "search-cancel"
        cancelButton.alpha = 0
        cancelButton.isHidden = true
        // Keep the presented menu (including its active submenu) intact while
        // background catalogue updates render the list. Resolve current options
        // synchronously each time it opens instead of replacing it on refresh.
        folderButton.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] completion in
            completion(self?.folderMenu().children ?? [])
        }])
        folderButton.showsMenuAsPrimaryAction = true
        search.delegate = self
        search.placeholder = "Search notes"
        search.accessibilityLabel = "Search notes"
        search.accessibilityIdentifier = "note-search"
        search.font = .preferredFont(forTextStyle: .subheadline)
        search.adjustsFontForContentSizeCategory = true
        search.tintColor = Theme.accentUIColor
        search.textColor = Theme.inkUIColor
        search.backgroundColor = .clear
        search.borderStyle = .none
        search.autocapitalizationType = .none
        search.autocorrectionType = .no
        search.returnKeyType = .search
        search.clearButtonMode = .whileEditing
        search.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        search.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        search.attributedPlaceholder = NSAttributedString(string: "Search notes", attributes: [.foregroundColor: Theme.secondaryInkUIColor])
        table.backgroundColor = Theme.paperUIColor
        table.separatorColor = Theme.hairlineUIColor
        table.separatorInset = .zero
        table.layoutMargins = .zero
        table.cellLayoutMarginsFollowReadableWidth = false
        table.contentInsetAdjustmentBehavior = .never
        table.automaticallyAdjustsScrollIndicatorInsets = false
        table.delaysContentTouches = false
        // Every note has one title and one metadata line, even before its
        // preview arrives. Exact metrics avoid self-sizing corrections during
        // hydration or while scrolling through a large notebook.
        table.estimatedRowHeight = 0
        table.sectionHeaderTopPadding = 0
        table.rowHeight = NotebookCell.rowHeight(for: traitCollection)
        table.keyboardDismissMode = .interactive
        table.delegate = self
        let blankDoubleTap = UITapGestureRecognizer(target: self, action: #selector(createNoteFromBlankSpace))
        blankDoubleTap.numberOfTapsRequired = 2
        blankDoubleTap.delegate = self
        table.addGestureRecognizer(blankDoubleTap)
        table.accessibilityIdentifier = "notes-list"
        table.register(NotebookCell.self, forCellReuseIdentifier: "note")
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)
        view.keyboardLayoutGuide.usesBottomSafeArea = false
        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor), table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.topAnchor.constraint(equalTo: view.topAnchor), table.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
        configureChrome()
        refreshControl.tintColor = Theme.accentUIColor
        refreshControl.addTarget(self, action: #selector(refreshRequested), for: .valueChanged)
        table.refreshControl = refreshControl
        source = UITableViewDiffableDataSource<Section, URL>(tableView: table) { [weak self] table, indexPath, url in
            guard let self, let hit = self.hitsByURL[url], let cell = table.dequeueReusableCell(withIdentifier: "note", for: indexPath) as? NotebookCell else { return UITableViewCell() }
            cell.configure(hit: hit, query: self.query, traits: table.traitCollection)
            return cell
        }
        source.defaultRowAnimation = .fade
        activity.hidesWhenStopped = true
        activity.tintColor = Theme.accentUIColor
        activity.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activity)
        NSLayoutConstraint.activate([activity.centerXAnchor.constraint(equalTo: view.centerXAnchor), activity.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        observers.append(NotificationCenter.default.addObserver(forName: NoteStore.didChange, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.storeChanged() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let scene = notification.object as? UIScene,
                      scene === self.notebookScene else { return }
                self.launchSession.enteredBackground()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let scene = notification.object as? UIScene,
                      scene === self.notebookScene else { return }
                if self.launchSession.becameActive() { self.launchPending = true }
                self.applyLaunchDestinationIfReady()
                if self.navigationController?.topViewController === self {
                    Task { await self.refresh() }
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: QuickNoteAction.didRequestNewNote, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyLaunchDestinationIfReady()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { self.table.rowHeight = NotebookCell.rowHeight(for: self.traitCollection) }
                self?.table.reloadData()
                self?.view.setNeedsLayout()
            }
        })
        render()
        Task { await refresh() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let selected = table.indexPathForSelectedRow { table.deselectRow(at: selected, animated: animated) }
        if needsRender { render() }
        if hasLoaded || store.hasLoadedCatalogue { Task { await refresh() } }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        LaunchDiagnostics.record("first_notebook_frame", counts: ["rows": store.notes.count],
                                 flags: ["spinner": activity.isAnimating,
                                         "catalogue_loaded": store.hasLoadedCatalogue], once: true)
        applyLaunchDestinationIfReady()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let rowHeight = NotebookCell.rowHeight(for: traitCollection)
        if table.rowHeight != rowHeight { table.rowHeight = rowHeight }
        let searchFont = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection)
        let chromeHeight = max(48, ceil(searchFont.lineHeight) + 12)
        chromeHeightConstraint.constant = chromeHeight
        searchHeightConstraint.constant = chromeHeight
        searchGlass.layer.cornerRadius = chromeHeight / 2
        let top = view.safeAreaInsets.top + (chrome.isHidden ? 0 : chromeHeight + 24)
        let previousTop = table.contentInset.top
        let wasAtTop = table.contentOffset.y <= -previousTop + 1
        table.contentInset = UIEdgeInsets(top: top, left: 0, bottom: table.safeAreaInsets.bottom + 12, right: 0)
        // The thumb follows the screen edge, not the space reserved for chrome.
        table.verticalScrollIndicatorInsets = table.safeAreaInsets
        if wasAtTop, previousTop != top { table.contentOffset.y = -top }
    }

    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }

    private func configureChrome() {
        let fade = PaperEdgeFade(edge: .top)
        fade.strength = 1.2
        fade.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fade)
        NSLayoutConstraint.activate([
            fade.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fade.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fade.topAnchor.constraint(equalTo: view.topAnchor),
            fade.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
        ])

        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: .regular)
            glass.isInteractive = true
            searchGlass.effect = glass
        } else {
            searchGlass.effect = UIBlurEffect(style: .systemThinMaterial)
        }
        searchGlass.layer.cornerRadius = 24
        searchGlass.clipsToBounds = true
        let magnifier = UIImageView(image: UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)))
        magnifier.tintColor = Theme.accentUIColor
        magnifier.contentMode = .scaleAspectFit
        magnifier.translatesAutoresizingMaskIntoConstraints = false
        search.translatesAutoresizingMaskIntoConstraints = false
        searchGlass.contentView.addSubview(magnifier)
        searchGlass.contentView.addSubview(search)
        NSLayoutConstraint.activate([
            magnifier.leadingAnchor.constraint(equalTo: searchGlass.contentView.leadingAnchor, constant: 15),
            magnifier.centerYAnchor.constraint(equalTo: searchGlass.contentView.centerYAnchor),
            magnifier.widthAnchor.constraint(equalToConstant: 19), magnifier.heightAnchor.constraint(equalToConstant: 22),
            search.leadingAnchor.constraint(equalTo: magnifier.trailingAnchor, constant: 9),
            search.trailingAnchor.constraint(equalTo: searchGlass.contentView.trailingAnchor, constant: -12),
            search.topAnchor.constraint(equalTo: searchGlass.contentView.topAnchor),
            search.bottomAnchor.constraint(equalTo: searchGlass.contentView.bottomAnchor),
        ])

        let trailingControl = UIView()
        for button in [composeButton, cancelButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            trailingControl.addSubview(button)
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: trailingControl.leadingAnchor),
                button.trailingAnchor.constraint(equalTo: trailingControl.trailingAnchor),
                button.topAnchor.constraint(equalTo: trailingControl.topAnchor),
                button.bottomAnchor.constraint(equalTo: trailingControl.bottomAnchor),
            ])
        }
        chrome.axis = .horizontal
        chrome.alignment = .center
        chrome.spacing = 10
        chrome.translatesAutoresizingMaskIntoConstraints = false
        chrome.addArrangedSubview(folderButton)
        chrome.addArrangedSubview(searchGlass)
        chrome.addArrangedSubview(trailingControl)
        view.addSubview(chrome)
        chromeHeightConstraint = chrome.heightAnchor.constraint(equalToConstant: 48)
        searchHeightConstraint = searchGlass.heightAnchor.constraint(equalToConstant: 48)
        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            chrome.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            chrome.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            chromeHeightConstraint,
            folderButton.widthAnchor.constraint(equalToConstant: 44), folderButton.heightAnchor.constraint(equalToConstant: 44),
            trailingControl.widthAnchor.constraint(equalToConstant: 44), trailingControl.heightAnchor.constraint(equalToConstant: 44),
            searchHeightConstraint,
        ])
    }

    private func refresh() async {
        let selectionID = folderSelection?.id
        await store.refresh()
        guard folderSelection?.id == selectionID else { return }
        refreshControl.endRefreshing()
        hasLoaded = true
        render()
        applyLaunchDestinationIfReady()
        if let message = store.errorMessage {
            showMessage(message)
        }
        #if DEBUG
        if let title = ProcessInfo.processInfo.environment["DRIFT_AUTO_OPEN"],
           navigationController?.topViewController === self,
           let note = store.notes.first(where: { $0.title == title }),
           !opening {
            open(note)
        }
        #endif
    }

    @objc private func refreshRequested() { Task { await refresh() } }

    private func storeChanged() {
        if let selection = folderSelection,
           store.folderURL?.standardizedFileURL == selection.url,
           store.hasLoadedCatalogue {
            switchingFolder = false
            hasLoaded = true
        }
        guard !opening, navigationController?.topViewController === self else { needsRender = true; return }
        render()
        applyLaunchDestinationIfReady()
    }

    private var notebookScene: UIWindowScene? {
        navigationController?.viewIfLoaded?.window?.windowScene
    }

    private func clearLaunchRequest() {
        launchPending = false
        launchOverride = nil
    }

    private func applyLaunchDestinationIfReady() {
        guard isViewLoaded, let navigationController, let scene = notebookScene,
              scene.activationState == .foregroundActive else { return }
        if QuickNoteAction.shared.consumePendingRequest(for: scene.session.persistentIdentifier) {
            launchOverride = .newNote
            launchPending = true
        }
        guard launchPending, !opening, !switchingFolder, !preparingLaunchTransition else { return }
        // didShow retries after either a completed or cancelled transition.
        guard navigationController.transitionCoordinator == nil else { return }
        guard let folder = store.folderURL else {
            // An explicit New Note action survives first-use folder selection.
            if hasLoaded, launchOverride == nil { clearLaunchRequest() }
            return
        }
        let destination = launchOverride ?? launchPreferences.destination
        if let editor = navigationController.topViewController as? NoteEditorViewController {
            if destination == .openLast {
                clearLaunchRequest()
                return
            }
            if destination == .newNote, editor.isEmptyComposer {
                clearLaunchRequest()
                editor.focusEmptyComposer()
                return
            }
            preparingLaunchTransition = true
            Task { [weak self] in
                let preserved = await editor.prepareForLaunchTransition()
                guard let self else { return }
                self.preparingLaunchTransition = false
                guard preserved else { self.clearLaunchRequest(); return }
                guard self.launchPending, scene.activationState == .foregroundActive,
                      navigationController.topViewController === editor else { return }
                self.returnToNotebookForLaunch()
            }
            return
        }
        guard navigationController.topViewController === self else { return }
        if navigationController.presentedViewController != nil {
            navigationController.dismiss(animated: false) { [weak self] in
                self?.applyLaunchDestinationIfReady()
            }
            return
        }
        switch destination {
        case .notesList:
            clearLaunchRequest()
            search.text = ""
            search.resignFirstResponder()
            render()
        case .newNote:
            clearLaunchRequest()
            createNote()
        case .openLast:
            guard let url = launchPreferences.lastNote(in: folder) else { clearLaunchRequest(); return }
            if let note = store.notes.first(where: { $0.url == url }) {
                clearLaunchRequest()
                open(note, resuming: true)
            } else if hasLoaded && !store.isLoading {
                // Deleted or unavailable notes leave the notebook usable.
                clearLaunchRequest()
            }
        }
    }

    private func returnToNotebookForLaunch() {
        guard let navigationController else { return }
        if navigationController.presentedViewController != nil {
            navigationController.dismiss(animated: false) { [weak self] in
                self?.returnToNotebookForLaunch()
            }
            return
        }
        preparingLaunchTransition = true
        navigationController.popToRootViewController(animated: false)
        preparingLaunchTransition = false
        applyLaunchDestinationIfReady()
    }

    private func render() {
        guard isViewLoaded else { return }
        guard !opening, navigationController?.topViewController === self else { needsRender = true; return }
        needsRender = false
        let hasFolder = store.folderURL != nil
        chrome.isHidden = !hasFolder
        composeButton.isEnabled = hasFolder && !opening && !switchingFolder
        cancelButton.isEnabled = !opening && !switchingFolder
        folderButton.isEnabled = !opening && !switchingFolder
        updateSearchChrome()
        view.setNeedsLayout()
        let currentQuery = query
        let hits = store.search(currentQuery)
        let currentSnapshot = source.snapshot()
        let existing = Set(currentSnapshot.itemIdentifiers)
        let ids = hits.map { $0.note.url }
        let changedIDs = hits.compactMap { hit -> URL? in
            guard existing.contains(hit.note.url) else { return nil }
            guard let previous = hitsByURL[hit.note.url] else { return hit.note.url }
            return previous.note != hit.note || previous.snippet != hit.snippet || renderedQuery != currentQuery
                ? hit.note.url : nil
        }
        hitsByURL = Dictionary(uniqueKeysWithValues: hits.map { ($0.note.url, $0) })
        renderedQuery = currentQuery
        if currentSnapshot.sectionIdentifiers != [.notes] || currentSnapshot.itemIdentifiers != ids || !changedIDs.isEmpty {
            var snapshot = NSDiffableDataSourceSnapshot<Section, URL>()
            snapshot.appendSections([.notes])
            snapshot.appendItems(ids, toSection: .notes)
            snapshot.reconfigureItems(changedIDs)
            source.apply(snapshot, animatingDifferences: hasLoaded && !store.isLoading && !switchingFolder && !search.isFirstResponder)
        }
        let cataloguePending = !hasLoaded && !store.hasLoadedCatalogue && store.notes.isEmpty
        if cataloguePending && store.isLoading {
            if !activity.isAnimating {
                LaunchDiagnostics.record("spinner_started", counts: ["rows": store.notes.count],
                                         flags: ["catalogue_loaded": store.hasLoadedCatalogue])
            }
            activity.startAnimating()
        }
        else { activity.stopAnimating() }
        if cataloguePending {
            // Metadata is enough to show the notebook; body indexing may continue.
            // Until then, avoid presenting a false onboarding or empty state.
            table.backgroundView = nil
        } else if !hasFolder {
            let detail = store.errorMessage ?? "Choose the same iCloud Drive folder on iPhone and Mac."
            emptyView.configure(artwork: .none, title: "Drift", detail: detail,
                                emphasizedDetail: store.errorMessage == nil ? "same iCloud Drive folder" : nil,
                                action: "Choose Shared Folder")
            emptyView.onAction = { [weak self] in self?.chooseFolder() }
            table.backgroundView = emptyView
        } else if hits.isEmpty {
            if let error = store.errorMessage, query.isEmpty {
                emptyView.configure(artwork: .symbol("arrow.clockwise"), title: "Let's try that again.", detail: error, action: store.requiresFolderSelection ? "Choose Folder" : "Retry")
                emptyView.onAction = { [weak self] in
                    guard let self else { return }
                    if self.store.requiresFolderSelection { self.chooseFolder() } else { self.refreshRequested() }
                }
            } else if query.isEmpty {
                emptyView.configure(artwork: .symbol("square.and.pencil"), title: "No notes yet", detail: "Tap + or double-tap this page to start one.", action: nil)
                emptyView.onAction = { [weak self] in self?.createNote() }
            } else {
                emptyView.configure(artwork: .symbol("magnifyingglass"), title: "No matching notes", detail: "Try another word or a shorter phrase.", action: nil)
            }
            table.backgroundView = emptyView
        } else {
            table.backgroundView = nil
        }
    }

    @objc private func searchChanged() { clearLaunchRequest(); render() }
    func textFieldDidBeginEditing(_ textField: UITextField) { updateSearchChrome() }
    func textFieldDidEndEditing(_ textField: UITextField) { updateSearchChrome() }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder(); return true }

    @objc private func cancelSearch() {
        search.text = ""
        search.resignFirstResponder()
        render()
    }

    private func updateSearchChrome() {
        let searching = search.isFirstResponder || !query.isEmpty
        guard searching != showsSearchCancel else { return }
        showsSearchCancel = searching
        let entering = searching ? cancelButton : composeButton
        let leaving = searching ? composeButton : cancelButton
        entering.isHidden = false
        entering.isUserInteractionEnabled = true
        leaving.isUserInteractionEnabled = false
        entering.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.22, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut], animations: {
            entering.alpha = 1
            entering.transform = .identity
            leaving.alpha = 0
            leaving.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }, completion: { [weak self] _ in
            guard self?.showsSearchCancel == searching else { return }
            leaving.isHidden = true
        })
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { .leastNormalMagnitude }
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { .leastNormalMagnitude }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let url = source.itemIdentifier(for: indexPath), let hit = hitsByURL[url] else { return }
        open(hit.note)
    }

    private func open(_ note: Note, resuming: Bool = false) {
        guard !opening, !switchingFolder else { return }
        clearLaunchRequest()
        opening = true
        composeButton.isEnabled = false
        cancelButton.isEnabled = false
        folderButton.isEnabled = false
        Task {
            defer { finishOpening() }
            do {
                let document = try await store.openForEditing(note)
                showEditor(document, isNew: false, resuming: resuming)
            } catch { showError(error) }
        }
    }

    @objc private func createNote() {
        guard !opening, !switchingFolder, store.folderURL != nil else { return }
        clearLaunchRequest()
        opening = true
        composeButton.isEnabled = false
        cancelButton.isEnabled = false
        folderButton.isEnabled = false
        Task {
            defer { finishOpening() }
            do {
                let document = try await store.makeUnsavedNote()
                search.text = ""
                showEditor(document, isNew: true)
            } catch { showError(error) }
        }
    }

    @objc private func createNoteFromBlankSpace() { createNote() }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard !opening, !switchingFolder, store.folderURL != nil,
              query.isEmpty, !search.isFirstResponder, store.errorMessage == nil else { return false }
        let point = touch.location(in: table)
        guard point.y >= 0, table.indexPathForRow(at: point) == nil else { return false }
        let rows = table.numberOfRows(inSection: 0)
        return rows == 0 || point.y > table.rectForRow(at: IndexPath(row: rows - 1, section: 0)).maxY
    }

    private func showEditor(_ document: NoteSnapshot, isNew: Bool, resuming: Bool = false) {
        guard navigationController?.topViewController === self,
              document.note.url.deletingLastPathComponent().standardizedFileURL == store.folderURL?.standardizedFileURL else { return }
        let searchQuery = query
        let editor = NoteEditorViewController(store: store, snapshot: document, isNew: isNew, resuming: resuming)
        if let folder = store.folderURL { launchPreferences.remember(document.note, in: folder) }
        if !searchQuery.isEmpty { editor.revealMatch(searchQuery) }
        editor.onNoteChange = { [weak self] in self?.storeChanged() }
        search.text = ""
        search.resignFirstResponder()
        needsRender = true
        editor.loadViewIfNeeded()
        navigationController?.pushViewController(editor, animated: !resuming)
    }

    private func finishOpening() {
        opening = false
        composeButton.isEnabled = store.folderURL != nil
        cancelButton.isEnabled = true
        folderButton.isEnabled = true
        if navigationController?.topViewController === self, needsRender { render() }
        if navigationController?.topViewController === self,
           let selected = table.indexPathForSelectedRow {
            table.deselectRow(at: selected, animated: true)
        }
        applyLaunchDestinationIfReady()
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard !opening, !switchingFolder, let url = source.itemIdentifier(for: indexPath), let note = hitsByURL[url]?.note else { return nil }
        return UIContextMenuConfiguration(identifier: url as NSURL, previewProvider: nil) { [weak self] _ in
            guard let self else { return UIMenu() }
            return UIMenu(children: [
                UIAction(title: note.isPinned ? "Unpin Note" : "Pin Note", image: UIImage(systemName: note.isPinned ? "pin.slash" : "pin")) { [weak self] _ in
                    guard let self, !self.opening, !self.switchingFolder else { return }
                    self.opening = true
                    self.composeButton.isEnabled = false
                    self.cancelButton.isEnabled = false
                    self.folderButton.isEnabled = false
                    Task {
                        defer { self.finishOpening() }
                        do {
                            let updated = try await self.store.setPinned(!note.isPinned, for: note)
                            if let folder = self.store.folderURL { self.launchPreferences.relocate(from: note.url, to: updated, in: folder) }
                            self.render()
                        } catch { self.showError(error) }
                    }
                },
                UIAction(title: "Copy Note", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in self?.copy(note) },
                UIAction(title: "Share Note", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in self?.share(note) },
                UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    guard let self else { return }
                    Task {
                        do { try await self.store.trash(note); self.render(); self.showUndo() }
                        catch { self.showError(error) }
                    }
                },
            ])
        }
    }

    private func copy(_ note: Note) {
        Task {
            do { UIPasteboard.general.string = try await store.open(note).text }
            catch { showError(error) }
        }
    }

    private func share(_ note: Note) {
        Task {
            do {
                let snapshot = try await store.open(note)
                let controller = UIActivityViewController(activityItems: [snapshot.text], applicationActivities: nil)
                controller.popoverPresentationController?.sourceView = folderButton
                controller.popoverPresentationController?.sourceRect = folderButton.bounds
                present(controller, animated: true)
            } catch { showError(error) }
        }
    }

    private func folderMenu() -> UIMenu {
        var actions: [UIMenuElement] = []
        if store.folderURL != nil {
            actions.append(UIAction(title: "Refresh Notes", image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in self?.refreshRequested() })
            if store.canUndoTrash {
                actions.append(UIAction(title: "Undo Last Delete", image: UIImage(systemName: "arrow.uturn.backward")) { [weak self] _ in self?.undoDelete() })
            }
        }
        let folderAction = store.requiresFolderSelection ? "Reconnect Folder…" : (store.folderURL == nil ? "Choose Folder" : "Change Folder…")
        actions.append(UIAction(title: folderAction, image: UIImage(systemName: "folder.badge.plus")) { [weak self] _ in self?.chooseFolder() })
        let destinations = LaunchDestination.allCases.map { destination in
            UIAction(title: destination.title, state: launchPreferences.destination == destination ? .on : .off) { [weak self] _ in
                guard let self else { return }
                self.launchPreferences.destination = destination
            }
        }
        actions.append(UIMenu(title: "On Launch", image: UIImage(systemName: "arrow.up.forward.app"), children: destinations))
        actions.append(UIMenu(options: .displayInline, children: [
            UIAction(title: "Privacy Policy", image: UIImage(systemName: "hand.raised")) { _ in
                UIApplication.shared.open(URL(string: "https://github.com/cjbest/drift/blob/main/docs/PRIVACY.md")!)
            },
            UIAction(title: "Help & Support", image: UIImage(systemName: "questionmark.circle")) { _ in
                UIApplication.shared.open(URL(string: "https://github.com/cjbest/drift/blob/main/docs/SUPPORT.md")!)
            },
        ]))
        return UIMenu(children: actions)
    }

    private func chooseFolder() {
        guard !opening, !switchingFolder else { return }
        if launchOverride == nil { clearLaunchRequest() }
        // iPad exposes Locations directly in the picker's sidebar; the Browse
        // tab and its illustration are specific to the phone picker.
        if traitCollection.userInterfaceIdiom == .pad {
            presentFolderPicker()
            return
        }
        let guide = FolderPickerGuideViewController()
        guide.modalPresentationStyle = .formSheet
        if let sheet = guide.sheetPresentationController {
            sheet.detents = [.custom { min(430, $0.maximumDetentValue) }, .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 28
        }
        guide.onContinue = { [weak self] in self?.presentFolderPicker() }
        present(guide, animated: true)
    }

    private func presentFolderPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        if let folder = store.folderURL { picker.directoryURL = folder }
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let selectionID = UUID()
        folderSelection = (selectionID, url.standardizedFileURL)
        switchingFolder = true
        hasLoaded = false
        search.text = ""
        messageTask?.cancel()
        messageView?.removeFromSuperview()
        render()
        Task {
            defer {
                if folderSelection?.id == selectionID {
                    switchingFolder = false
                    folderSelection = nil
                    render()
                }
            }
            do {
                try await store.setFolder(url)
                guard folderSelection?.id == selectionID else { return }
                hasLoaded = true
            } catch {
                guard folderSelection?.id == selectionID else { return }
                hasLoaded = true
                showError(error)
            }
        }
    }

    private func undoDelete() {
        Task {
            do { try await store.undoTrash(); render(); showMessage("Note restored") }
            catch { showError(error) }
        }
    }

    private func showUndo() {
        showMessage("Note deleted", undo: true)
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: "Couldn't finish that", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func showMessage(_ text: String, undo: Bool = false) {
        messageTask?.cancel()
        messageView?.removeFromSuperview()
        let notice = UIView()
        notice.backgroundColor = Theme.inkUIColor
        notice.layer.cornerRadius = 18
        notice.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = text
        label.textColor = Theme.paperUIColor
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textAlignment = .center
        label.numberOfLines = 3
        let stack = UIStackView(arrangedSubviews: [label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        if undo {
            let button = UIButton(type: .system)
            button.setTitle("Undo", for: .normal)
            button.setTitleColor(Theme.paperUIColor, for: .normal)
            button.titleLabel?.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13, weight: .semibold))
            button.accessibilityLabel = "Undo Delete"
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.addAction(UIAction { [weak self] _ in self?.undoDelete() }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        notice.addSubview(stack)
        view.addSubview(notice)
        let aboveKeyboard = notice.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -18)
        aboveKeyboard.priority = .defaultHigh
        NSLayoutConstraint.activate([
            notice.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            notice.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            notice.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            aboveKeyboard,
            notice.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            notice.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            stack.leadingAnchor.constraint(equalTo: notice.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: notice.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: notice.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: notice.bottomAnchor, constant: -8),
        ])
        messageView = notice
        UIAccessibility.post(notification: .announcement, argument: text)
        messageTask = Task { [weak notice] in
            try? await Task.sleep(for: .seconds(undo ? 5 : 4))
            guard !Task.isCancelled else { return }
            UIView.animate(withDuration: 0.2, animations: { notice?.alpha = 0 }) { _ in notice?.removeFromSuperview() }
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        [newNoteCommand, searchNotesCommand]
    }

    override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .main else { return }
        builder.insertChild(UIMenu(title: "", identifier: UIMenu.Identifier("com.drift.new-note"), options: .displayInline, children: [newNoteCommand]), atStartOfMenu: .file)
        let searchParent: UIMenu.Identifier = builder.menu(for: .find) == nil ? .edit : .find
        builder.insertChild(UIMenu(title: "", identifier: UIMenu.Identifier("com.drift.search-notes"), options: .displayInline, children: [searchNotesCommand]), atStartOfMenu: searchParent)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(createNote) || action == #selector(focusSearch) {
            return store.folderURL != nil && !opening && !switchingFolder
        }
        return super.canPerformAction(action, withSender: sender)
    }

    @objc private func focusSearch() {
        guard store.folderURL != nil, !opening, !switchingFolder else { return }
        search.becomeFirstResponder()
    }
}

private final class NotebookCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let pinIndicator = UIImageView()
    private let previewLabel = UILabel()
    private let dateLabel = UILabel()
    private var metadataHeightConstraint: NSLayoutConstraint!
    private var representedURL: URL?

    private static func metadataHeight(for traits: UITraitCollection) -> CGFloat {
        ceil(max(UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits).lineHeight,
                 UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traits).lineHeight))
    }

    static func rowHeight(for traits: UITraitCollection) -> CGFloat {
        ceil(Theme.rowTitleUIFont(compatibleWith: traits).lineHeight)
            + metadataHeight(for: traits) + 4 + 18 + 19 + 1 / max(1, traits.displayScale)
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = Theme.paperUIColor
        let selected = UIView(); selected.backgroundColor = Theme.accentUIColor.withAlphaComponent(0.22); selectedBackgroundView = selected
        separatorInset = .zero
        layoutMargins = .zero
        preservesSuperviewLayoutMargins = false
        titleLabel.textColor = Theme.inkUIColor
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontForContentSizeCategory = true
        pinIndicator.tintColor = Theme.secondaryInkUIColor
        pinIndicator.contentMode = .center
        pinIndicator.isHidden = true
        pinIndicator.isAccessibilityElement = false
        pinIndicator.accessibilityIdentifier = "note-pin-indicator"
        pinIndicator.setContentHuggingPriority(.required, for: .horizontal)
        pinIndicator.setContentCompressionResistancePriority(.required, for: .horizontal)
        let titleRow = UIStackView(arrangedSubviews: [titleLabel, pinIndicator])
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 8
        previewLabel.textColor = Theme.secondaryInkUIColor
        previewLabel.numberOfLines = 1
        previewLabel.adjustsFontForContentSizeCategory = true
        dateLabel.textColor = Theme.secondaryInkUIColor
        dateLabel.adjustsFontForContentSizeCategory = true
        let meta = UIStackView(arrangedSubviews: [dateLabel, previewLabel])
        meta.axis = .horizontal; meta.spacing = 6
        // Reserve the final line height while only the smaller date is known.
        metadataHeightConstraint = meta.heightAnchor.constraint(equalToConstant: Self.metadataHeight(for: traitCollection))
        metadataHeightConstraint.isActive = true
        dateLabel.setContentHuggingPriority(.required, for: .horizontal)
        dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        previewLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [titleRow, meta])
        stack.axis = .vertical; stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -19),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: false)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedURL = nil
        pinIndicator.isHidden = true
        accessibilityLabel = nil
        previewLabel.layer.removeAllAnimations()
        previewLabel.alpha = 1
    }

    func configure(hit: NoteSearchHit, query: String, traits: UITraitCollection) {
        titleLabel.font = Theme.rowTitleUIFont(compatibleWith: traits)
        previewLabel.font = .preferredFont(forTextStyle: .subheadline, compatibleWith: traits)
        dateLabel.font = .preferredFont(forTextStyle: .caption1, compatibleWith: traits)
        metadataHeightConstraint.constant = Self.metadataHeight(for: traits)
        titleLabel.text = hit.note.title
        pinIndicator.image = UIImage(systemName: "pin.fill", withConfiguration: UIImage.SymbolConfiguration(
            font: .preferredFont(forTextStyle: .caption1, compatibleWith: traits), scale: .small))
        pinIndicator.isHidden = !hit.note.isPinned
        let bodyPreview = hit.snippet ?? hit.note.preview
        let preview = bodyPreview.isEmpty ? "" : "· " + bodyPreview
        let revealsPreview = representedURL == hit.note.url && previewLabel.isHidden && !preview.isEmpty
            && window != nil && query.isEmpty && !UIAccessibility.isReduceMotionEnabled
        if representedURL != hit.note.url || preview.isEmpty {
            previewLabel.layer.removeAllAnimations()
            previewLabel.alpha = 1
        }
        representedURL = hit.note.url
        previewLabel.isHidden = preview.isEmpty
        let attributed = NSMutableAttributedString(string: preview)
        if !query.isEmpty, let range = preview.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed.addAttributes([.foregroundColor: Theme.inkUIColor, .backgroundColor: Theme.accentUIColor.withAlphaComponent(0.12)], range: NSRange(range, in: preview))
        }
        previewLabel.attributedText = attributed
        if revealsPreview {
            previewLabel.alpha = 0
            UIView.animate(withDuration: 0.16, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.previewLabel.alpha = 1
            }
        }
        dateLabel.text = Self.dateLabel(hit.note.modified)
        accessibilityLabel = [hit.note.title, hit.note.isPinned ? "Pinned" : nil,
                              dateLabel.text, bodyPreview.isEmpty ? nil : bodyPreview]
            .compactMap { $0 }.joined(separator: ", ")
        accessibilityIdentifier = "note-row-\(hit.note.url.lastPathComponent)"
    }
    private static func dateLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day,
           days > 0 && days < 7 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
