import SwiftUI
import UIKit

struct NoteListView: View {
    @Environment(NoteStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedNote: Note?
    @State private var compactPath: [Note] = []
    @State private var query = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @FocusState private var searchFocused: Bool
    @State private var deleteCandidate: Note?
    @State private var openingNoteID: Note.ID?
    /// Note ID to auto-focus on appear — set when the user taps the compose
    /// button so the keyboard rises during the navigation push. Cleared as
    /// soon as the editor consumes it.
    @State private var pendingFocusID: Note.ID?
    @State private var discardIfEmptyIDs: Set<Note.ID> = []

    private var hits: [Note] {
        store.search(query)
    }

    var body: some View {
        if horizontalSizeClass == .compact {
            compactStack
        } else {
            splitView
        }
    }

    private var deleteDialogPresented: Binding<Bool> {
        Binding {
            deleteCandidate != nil
        } set: { isPresented in
            if !isPresented {
                deleteCandidate = nil
            }
        }
    }

    private var compactStack: some View {
        NavigationStack(path: $compactPath) {
            compactHome
                .navigationDestination(for: Note.self) { note in
                    editor(for: note, usesSystemDismiss: true)
                }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            store.loadNotes()
            autoOpenIfRequested()
        }
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            if let selectedNote {
                editor(for: selectedNote)
            } else {
                detailEmpty
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            store.loadNotes()
            autoOpenIfRequested()
        }
    }

    private func editor(for selectedNote: Note, usesSystemDismiss: Bool = false) -> some View {
        NoteEditorView(
            note: selectedNote,
            autoFocus: pendingFocusID == selectedNote.id,
            deleteIfEmptyOnClose: discardIfEmptyIDs.contains(selectedNote.id),
            onDismiss: usesSystemDismiss ? nil : closeEditor,
            onDiscardEmpty: { discarded in
                discardEmptyCreatedNote(discarded, originalID: selectedNote.id)
            }
        )
        .id(selectedNote.id)
        .onAppear { pendingFocusID = nil }
    }

    private func open(_ note: Note) {
        let focusOnOpen = shouldAutofocus(note)
        latchOpeningState(for: note)

        if focusOnOpen {
            pendingFocusID = note.id
        } else if pendingFocusID == note.id {
            pendingFocusID = nil
        }

        let navigate = {
            if horizontalSizeClass == .compact {
                compactPath.append(note)
            } else {
                selectedNote = note
            }
        }

        if focusOnOpen, horizontalSizeClass == .compact, KeyboardTransitionPrimer.shared.primeForEditor() {
            DispatchQueue.main.async(execute: navigate)
            return
        }

        navigate()
    }

    private func latchOpeningState(for note: Note) {
        openingNoteID = note.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            if openingNoteID == note.id {
                openingNoteID = nil
            }
        }
    }

    private func shouldAutofocus(_ note: Note) -> Bool {
        if pendingFocusID == note.id {
            return true
        }

        return store.readContents(of: note)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private func closeEditor() {
        if horizontalSizeClass == .compact {
            if !compactPath.isEmpty {
                compactPath.removeLast()
            }
        } else {
            selectedNote = nil
        }
    }

    private func markCreatedNote(_ note: Note) {
        pendingFocusID = note.id
        discardIfEmptyIDs.insert(note.id)
    }

    private func discardEmptyCreatedNote(_ note: Note, originalID: Note.ID) {
        discardIfEmptyIDs.remove(originalID)
        discardIfEmptyIDs.remove(note.id)
        store.delete(note)
    }

    private func delete(_ note: Note) {
        discardIfEmptyIDs.remove(note.id)
        compactPath.removeAll { $0.id == note.id }
        if selectedNote?.id == note.id {
            selectedNote = nil
        }
        store.delete(note)
    }

    private func requestDelete(_ note: Note) {
        if store.readContents(of: note).count > 5 {
            deleteCandidate = note
        } else {
            delete(note)
        }
    }

    private func copyContents(of note: Note) {
        UIPasteboard.general.string = store.readContents(of: note)
    }

    private var compactHome: some View {
        GeometryReader { proxy in
            let topInset = windowSafeAreaTop(for: proxy)
            let searching = searchFocused || !query.isEmpty

            ZStack(alignment: .top) {
                Group {
                    if store.notes.isEmpty {
                        emptyState
                    } else {
                        list
                    }
                }
                .padding(.top, topInset + 78)
                .scrollEdgeEffectStyle(.soft, for: .top)

                LinearGradient(
                    stops: [
                        .init(color: Theme.paper.opacity(0.52), location: 0),
                        .init(color: Theme.paper.opacity(0.18), location: 0.70),
                        .init(color: Theme.paper.opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: topInset + 20)
                .ignoresSafeArea(.container, edges: .top)
                .allowsHitTesting(false)

                compactChrome(topInset: topInset, searching: searching)
            }
            .background(Theme.paper.ignoresSafeArea())
            .ignoresSafeArea(.container, edges: .top)
        }
    }

    private func compactChrome(topInset: CGFloat, searching: Bool) -> some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                menuButton

                searchField
                    .frame(maxWidth: .infinity)

                if searching {
                    Button {
                        query = ""
                        searchFocused = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.ink.opacity(0.82))
                    }
                    .accessibilityLabel("Cancel Search")
                    .floatingGlassIconButton()
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                } else {
                    newNoteButton
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, topInset + 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.smooth(duration: 0.22), value: searching)
    }

    private var menuButton: some View {
        Menu {
            Button("Refresh", systemImage: "arrow.clockwise") { store.loadNotes() }
            Button("Change Folder…", systemImage: "folder") { store.clearFolder() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .accessibilityLabel("More")
        .floatingGlassIconButton()
    }

    private var newNoteButton: some View {
        Button {
            if let note = store.createNote() {
                markCreatedNote(note)
                searchFocused = false
                query = ""
                open(note)
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.accent)
        }
        .accessibilityLabel("New Note")
        .keyboardShortcut("n", modifiers: .command)
        .floatingGlassIconButton()
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Theme.accent)

            TextField("Search notes", text: $query)
                .font(Theme.searchPlaceholder())
                .foregroundStyle(Theme.ink)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink.opacity(0.38))
                }
                .accessibilityLabel("Clear Search")
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .contentShape(Capsule())
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    private func windowSafeAreaTop(for proxy: GeometryProxy) -> CGFloat {
        if let windowInset = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first?
            .safeAreaInsets
            .top,
           windowInset > 0 {
            return windowInset
        }

        if proxy.safeAreaInsets.top > 0 {
            return proxy.safeAreaInsets.top
        }

        return 59
    }

    private func autoOpenIfRequested() {
        #if DEBUG
        guard selectedNote == nil,
              compactPath.isEmpty,
              let target = ProcessInfo.processInfo.environment["DRIFT_AUTO_OPEN"]
        else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let note = store.notes.first(where: { $0.title == target }) {
                open(note)
            }
        }
        #endif
    }

    private var sidebar: some View {
        Group {
            if store.notes.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Drift")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search notes")
        .toolbar {
            ToolbarItem(placement: .principal) {
                // Explicit Text rendering avoids the brief flash where the
                // title appears in the system font before the
                // UINavigationBar.appearance() titleTextAttributes take effect.
                Text("Drift")
                    .font(.custom("Newsreader16pt-Italic", size: 22))
                    .foregroundStyle(Theme.ink)
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Refresh", systemImage: "arrow.clockwise") { store.loadNotes() }
                    Button("Change Folder…", systemImage: "folder") { store.clearFolder() }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Theme.accent)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let note = store.createNote() {
                        markCreatedNote(note)
                        open(note)
                    }
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("New Note")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .refreshable { store.loadNotes() }
    }

    private var list: some View {
        List {
            ForEach(hits) { note in
                SearchableNoteRow(
                    note: note,
                    isOpening: openingNoteID == note.id,
                    onPick: { picked in
                        query = ""
                        searchFocused = false
                        open(picked)
                    },
                    onDeleteRequest: requestDelete,
                    onCopy: { picked in
                        copyContents(of: picked)
                    }
                )
                .listRowBackground(Theme.paper)
                .listRowSeparatorTint(Theme.hairline)
                .listRowSeparator(.hidden, edges: .top)
                .listRowInsets(EdgeInsets())
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .alert("Delete Note?", isPresented: deleteDialogPresented) {
            Button("Delete", role: .destructive) {
                if let note = deleteCandidate {
                    delete(note)
                }
                deleteCandidate = nil
            }
            Button("Cancel", role: .cancel) {
                deleteCandidate = nil
            }
        } message: {
            if let note = deleteCandidate {
                Text("Delete \"\(note.title)\" from your notes folder. This cannot be undone.")
            }
        }
    }

    private var detailEmpty: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.35))
            Text("Select a note")
                .font(Theme.rowTitle())
                .foregroundStyle(Theme.ink.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.ignoresSafeArea())
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.35))
            Text("No notes yet")
                .font(Theme.rowTitle())
                .foregroundStyle(Theme.ink)
            Text("Tap the plus to start one.")
                .font(Theme.rowSub())
                .foregroundStyle(Theme.ink.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title)
                .font(Theme.rowTitle())
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(Self.compactDate(note.modified))
                if !note.preview.isEmpty {
                    Text("·")
                    Text(note.preview)
                        .lineLimit(1)
                }
            }
            .font(Theme.rowSub())
            .foregroundStyle(Theme.ink.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Smart-compact relative date label, à la Mail / Notes.
    /// - Today → "3:01 PM"
    /// - Yesterday → "Yesterday"
    /// - Within the last week → "Mon"
    /// - Within this year → "Apr 10"
    /// - Older → "Apr 10, 2025"
    private static func compactDate(_ date: Date) -> String {
        let cal = Calendar.current
        let now = Date()
        if cal.isDateInToday(date) {
            return timeFormatter.string(from: date)
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday"
        }
        if let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day,
           days > 0, days < 7 {
            return weekdayFormatter.string(from: date)
        }
        if cal.component(.year, from: date) == cal.component(.year, from: now) {
            return monthDayFormatter.string(from: date)
        }
        return monthDayYearFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let monthDayYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}

/// Row that dismisses the search controller in the same action as setting
/// the selected note — important because if dismiss happens *after* the
/// navigation push (e.g. via onChange), the detail view's safe-area inset
/// is computed while search is still active, and the H1 ends up rendered
/// higher than the back chevron.
private struct SearchableNoteRow: View {
    let note: Note
    let isOpening: Bool
    let onPick: (Note) -> Void
    let onDeleteRequest: (Note) -> Void
    let onCopy: (Note) -> Void
    @Environment(\.dismissSearch) private var dismissSearch

    var body: some View {
        Button {
            dismissSearch()
            onPick(note)
        } label: {
            NoteRow(note: note)
        }
        .buttonStyle(InstantRowButtonStyle(isLatched: isOpening))
        .contextMenu {
            Button("Copy Note", systemImage: "doc.on.doc") {
                onCopy(note)
            }

            Button("Delete", systemImage: "trash", role: .destructive) {
                onDeleteRequest(note)
            }
        }
    }
}

private struct InstantRowButtonStyle: ButtonStyle {
    let isLatched: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((configuration.isPressed || isLatched) ? Theme.accent.opacity(0.22) : Color.clear)
            .contentShape(Rectangle())
            .animation(nil, value: configuration.isPressed)
            .animation(nil, value: isLatched)
    }
}

private final class KeyboardTransitionPrimer {
    static let shared = KeyboardTransitionPrimer()

    private weak var activeInputView: KeyboardPrimerInputView?

    @discardableResult
    func primeForEditor() -> Bool {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first
        else { return false }

        let inputView = KeyboardPrimerInputView()
        inputView.frame = CGRect(x: -1000, y: -1000, width: 1, height: 1)
        window.addSubview(inputView)
        inputView.configureForEditor()
        inputView.becomeFirstResponder()
        activeInputView = inputView

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self, weak inputView] in
            if inputView?.isFirstResponder == true {
                inputView?.resignFirstResponder()
            }
            inputView?.removeFromSuperview()
            if self?.activeInputView === inputView {
                self?.activeInputView = nil
            }
        }

        return true
    }
}

private final class KeyboardPrimerInputView: UIView, UIKeyInput, UITextInputTraits {
    var hasText: Bool { false }
    var keyboardType: UIKeyboardType = .default
    var keyboardAppearance: UIKeyboardAppearance = .default
    var returnKeyType: UIReturnKeyType = .default
    var textContentType: UITextContentType?
    var autocapitalizationType: UITextAutocapitalizationType = .sentences
    var autocorrectionType: UITextAutocorrectionType = .default
    var spellCheckingType: UITextSpellCheckingType = .default
    var smartQuotesType: UITextSmartQuotesType = .yes
    var smartDashesType: UITextSmartDashesType = .yes
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .yes
    var enablesReturnKeyAutomatically: Bool = false

    @available(iOS 17.0, *)
    var inlinePredictionType: UITextInlinePredictionType {
        get { storedInlinePredictionType }
        set { storedInlinePredictionType = newValue }
    }

    @available(iOS 17.0, *)
    private var storedInlinePredictionType: UITextInlinePredictionType = .default

    init() {
        super.init(frame: .zero)
        configureForEditor()
        backgroundColor = .clear
        accessibilityElementsHidden = true
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        configureForEditor()
    }

    func insertText(_ text: String) {}

    func deleteBackward() {}

    func configureForEditor() {
        keyboardType = .default
        returnKeyType = .default
        textContentType = nil
        autocapitalizationType = .sentences
        autocorrectionType = .default
        spellCheckingType = .default
        smartQuotesType = .yes
        smartDashesType = .yes
        smartInsertDeleteType = .yes
        enablesReturnKeyAutomatically = false
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
        if #available(iOS 17.0, *) {
            inlinePredictionType = .default
        }
        keyboardAppearance = (window?.traitCollection ?? traitCollection).userInterfaceStyle == .dark
            ? .dark
            : .light
    }
}
