import Foundation
import CryptoKit

/// The UI owns this small in-memory model. Note-file and provider operations run
/// away from the main actor; only the small local launch index loads synchronously.
/// Catalogue scans have their own worker so
/// an unrelated iCloud file cannot hold up opening or saving the selected note.
@MainActor
final class NoteStore {
    static let didChange = Notification.Name("Drift.NoteStore.didChange")

    private(set) var folderURL: URL?
    private(set) var notes: [Note] = []
    private(set) var isLoading = false
    private(set) var hasLoadedCatalogue = false
    private(set) var requiresFolderSelection = false
    var errorMessage: String?
    private(set) var canUndoTrash = false

    private let drafts = DraftJournal()
    private let worker: FileWorker
    private let listingWorker: FileWorker
    private var bodies: [URL: String] = [:]
    // Presentation only: retain the actual catalogue until conditional cleanup
    // succeeds. A new composer with an empty current buffer can still be saving;
    // its token follows only that session's own successful snapshot/rename.
    private var emptyComposerReturns: [UUID: NoteSnapshot] = [:]
    private var revision = 0
    private var initialization: Task<Void, Never>?
    private var catalogueRestoration: Task<Void, Never>?
    private var folderIsReady = false
    private var refreshTask: Task<Void, Never>?
    private var refreshID: UUID?
    private var refreshingFolder: URL?
    private var refreshingRevision: Int?
    private var catalogueWriteTask: Task<Void, Never>?
    private var pendingCatalogue: (value: CachedCatalogue, sequence: UInt64)?

    init(folderURL: URL? = nil, defaults: UserDefaults = .standard) {
        worker = FileWorker(drafts: drafts, defaults: defaults)
        listingWorker = FileWorker(drafts: drafts, defaults: defaults)
        let environment = ProcessInfo.processInfo.environment
        let testPath = environment["DRIFT_TEST_FOLDER"]
        let explicitURL: URL?
        if let folderURL {
            explicitURL = FolderIdentity.directoryURL(folderURL)
        } else if let testPath {
            explicitURL = testPath == "__APP_TEMP__"
                ? FileManager.default.temporaryDirectory.appendingPathComponent("drift-ui-tests", isDirectory: true)
                : FolderIdentity.directoryURL(URL(fileURLWithPath: testPath, isDirectory: true))
        } else {
            explicitURL = nil
        }
        let resetTestFolder = folderURL == nil && testPath == "__APP_TEMP__"
            && environment["DRIFT_RESET_TEST_FOLDER"] == "1"
        let cachedFolder = explicitURL ?? FolderBookmark.cachedFolder(in: defaults)
        self.folderURL = cachedFolder
        if let cachedFolder, !resetTestFolder {
            if let index = CatalogueCache.loadIndex(folder: cachedFolder) {
                notes = index.notes.sorted(by: Note.orderedForList)
                canUndoTrash = index.canUndoTrash
                hasLoadedCatalogue = true
            }
            catalogueRestoration = Task { [weak self] in
                await self?.restoreCatalogue(folder: cachedFolder)
                self?.changed()
            }
        }
        LaunchDiagnostics.record("initial_index", counts: ["rows": notes.count],
                                 flags: ["folder_known": cachedFolder != nil,
                                         "index_loaded": hasLoadedCatalogue])
        initialization = Task { [weak self, worker] in
            do {
                // Restore local text and recovery before touching the provider.
                // A cached note can open while bookmark resolution is pending.
                await self?.catalogueRestoration?.value
                let restored = try await worker.initialize(explicitURL: explicitURL,
                                                           preferredFolder: cachedFolder,
                                                           prepareTestFolder: folderURL == nil && testPath != nil,
                                                           resetTestFolder: resetTestFolder)
                guard let self else { return }
                LaunchDiagnostics.record("bookmark_restored", counts: ["rows": self.notes.count],
                                         flags: ["same_cached_folder": restored == self.folderURL])
                if restored != self.folderURL {
                    self.notes = []
                    self.bodies = [:]
                    self.hasLoadedCatalogue = false
                    self.canUndoTrash = false
                }
                self.folderURL = restored
                self.folderIsReady = restored != nil
                if let restored, cachedFolder != restored {
                    await self.restoreCatalogue(folder: restored)
                }
                self.changed()
            } catch {
                self?.requiresFolderSelection = true
                self?.errorMessage = StoreError.folderAccessRequired(self?.folderURL?.lastPathComponent).localizedDescription
                self?.changed()
            }
        }
    }

    func setFolder(_ url: URL) async throws {
        await initialized()
        do {
            let selected = try await worker.selectFolder(url)
            folderIsReady = true
            requiresFolderSelection = false
            revision += 1
            folderURL = selected
            notes = []
            bodies = [:]
            hasLoadedCatalogue = false
            canUndoTrash = false
            errorMessage = nil
            await restoreCatalogue(folder: selected)
            changed()
            await refresh()
        } catch {
            report(error)
            throw error
        }
    }

    func refresh() async {
        await initialized()
        guard folderIsReady, let folderURL else { return }
        // Appearance, activation, and pull-to-refresh can arrive together. Join
        // the scan already in progress instead of queuing another whole folder.
        if refreshingFolder == folderURL, let refreshTask {
            await refreshTask.value
            return
        }
        revision += 1
        let request = revision
        let id = UUID()
        refreshID = id
        refreshingFolder = folderURL
        refreshingRevision = request
        isLoading = true
        changed()
        let task = Task {
            var scanRevision = request
            while refreshID == id, self.folderURL == folderURL, !Task.isCancelled {
                do {
                    let previous = CachedCatalogue(folderURL: folderURL, notes: notes, bodies: bodies,
                                                   canUndoTrash: canUndoTrash)
                    let currentRevision = scanRevision
                    let listing = try await listingWorker.list(folder: folderURL, previous: previous) { [weak self] partial in
                        guard let self else { return false }
                        return await self.acceptCatalogue(partial, refreshID: id, folder: folderURL,
                                                          revision: currentRevision)
                    }
                    guard refreshID == id, self.folderURL == folderURL else { return }
                    if scanRevision == revision {
                        acceptCatalogue(listing)
                        break
                    }
                } catch {
                    guard refreshID == id, self.folderURL == folderURL else { return }
                    if scanRevision == revision {
                        recordError(error)
                        break
                    }
                }
                // A mutation raced the scan. Run one replacement for the
                // latest revision; concurrent refresh calls join this task.
                // Scanning itself never increments revision, so it cannot
                // invalidate or repeatedly restart its own replacement.
                scanRevision = revision
                refreshingRevision = scanRevision
            }
            guard refreshID == id else { return }
            refreshTask = nil
            refreshingFolder = nil
            refreshingRevision = nil
            isLoading = false
            changed()
            await flushCatalogueCache()
        }
        refreshTask = task
        await task.value
    }

    /// Present the text already loaded for the list, then let the visible editor
    /// check the provider after its opening animation. Local recovery still wins
    /// over the cache, and saves always compare the retained baseline with disk.
    func openForEditing(_ note: Note) async throws -> NoteSnapshot {
        await catalogueRestoration?.value
        guard let text = bodies[note.url], let cachedNote = notes.first(where: { $0.url == note.url }) else {
            return try await open(note)
        }
        let cached = NoteSnapshot(note: cachedNote, text: text)
        do {
            return try await Task.detached(priority: .userInitiated) { [drafts] in
                guard let draft = try drafts.readAll(for: note.url).first else { return cached }
                let derived = Note.derive(from: draft.text)
                let recovered = Note(url: note.url, modified: max(cachedNote.modified, draft.savedAt),
                                     title: derived.title, preview: derived.preview, isUnsaved: draft.isUnsaved == true)
                return NoteSnapshot(note: recovered, text: draft.text, baselineText: draft.baseline,
                                    recoveredDraft: true, documentID: draft.documentID)
            }.value
        } catch {
            report(error)
            throw error
        }
    }

    func open(_ note: Note) async throws -> NoteSnapshot {
        try await requireFolderAccess()
        do {
            let snapshot = try await worker.open(note)
            apply(snapshot)
            errorMessage = nil
            changed()
            return snapshot
        } catch {
            report(error)
            throw error
        }
    }

    func createNote() async throws -> NoteSnapshot {
        try await requireFolderAccess()
        guard let folderURL else { throw StoreError.noFolder }
        do {
            let snapshot = try await worker.create(folder: folderURL)
            apply(snapshot)
            errorMessage = nil
            changed()
            return snapshot
        } catch {
            report(error)
            throw error
        }
    }

    /// A blank page is only an editing session. Its unique identity is used for
    /// local recovery; no file or catalogue row is created until meaningful text.
    func makeUnsavedNote() async throws -> NoteSnapshot {
        if folderURL == nil { await initialized() }
        guard let folderURL else { throw StoreError.noFolder }
        let documentID = UUID()
        let identity = folderURL.appendingPathComponent(".drift-unsaved-\(documentID.uuidString).md")
        let note = Note(url: identity, modified: Date(), title: Note.untitled, preview: "", isUnsaved: true)
        return NoteSnapshot(note: note, text: "", documentID: documentID)
    }

    /// Durably journals an edit in Application Support, without touching the shared file.
    func persistDraft(_ text: String, snapshot: NoteSnapshot) async throws {
        do {
            let sequence = drafts.reserveSequence()
            try await Task.detached(priority: .userInitiated) { [drafts] in
                try drafts.persist(text, snapshot: snapshot, sequence: sequence)
            }.value
        } catch {
            report(error)
            throw error
        }
    }

    /// Clears a reverted edit without changing the document or its saved baseline.
    func discardDraft(snapshot: NoteSnapshot) async throws {
        do {
            let sequence = drafts.reserveSequence()
            try await Task.detached(priority: .userInitiated) { [drafts] in
                try drafts.discard(snapshot: snapshot, sequence: sequence)
            }.value
        } catch {
            report(error)
            throw error
        }
    }

    func save(_ text: String, snapshot: NoteSnapshot) async throws -> NoteSaveResult {
        let resolved = drafts.materializedSnapshot(for: snapshot)
        let sourceURL = resolved?.note.url ?? snapshot.note.url
        let alreadyMaterialized = snapshot.isUnsaved && resolved != nil
        if snapshot.isUnsaved, !alreadyMaterialized, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try await discardDraft(snapshot: snapshot)
            return NoteSaveResult(snapshot: NoteSnapshot(note: snapshot.note, text: text, baselineText: "",
                                                         documentID: snapshot.documentID), preservedConflict: false)
        }
        do {
            try await Task.detached(priority: .userInitiated) { [drafts] in
                try drafts.ensure(text, snapshot: snapshot)
            }.value
            try await requireFolderAccess()
            let result = try await worker.save(text, snapshot: snapshot)
            if !result.preservedConflict {
                let savedSourceURL = result.sourceURL ?? sourceURL
                notes.removeAll { $0.url == snapshot.note.url || $0.url == savedSourceURL }
                bodies.removeValue(forKey: snapshot.note.url)
                bodies.removeValue(forKey: savedSourceURL)
            }
            for (token, returning) in emptyComposerReturns where returning.documentID == snapshot.documentID {
                // A conflict belongs in the notebook. Never suppress its external
                // version or keep an old URL hidden after a divergent save.
                if result.preservedConflict { emptyComposerReturns.removeValue(forKey: token) }
                else { emptyComposerReturns[token] = result.snapshot }
            }
            apply(result.snapshot)
            errorMessage = nil
            changed()
            // The external version of a conflict remains a distinct note in the list.
            if result.preservedConflict { await refresh() }
            await flushCatalogueCache()
            return result
        } catch {
            report(error)
            throw error
        }
    }

    /// Pins are a filename property, so the provider syncs them with the note.
    /// No body download or shared index is needed to change a saved note's pin.
    @discardableResult
    func setPinned(_ pinned: Bool, for note: Note) async throws -> Note {
        try await requireFolderAccess()
        do {
            guard note.url.deletingLastPathComponent().standardizedFileURL == folderURL?.standardizedFileURL,
                  notes.contains(where: { $0.url == note.url }) else { throw StoreError.changedNote }
            var target = note
            if note.isUnsaved {
                let recovered = try await worker.open(note)
                guard !recovered.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw StoreError.changedNote
                }
                target = try await save(recovered.text, snapshot: recovered).snapshot.note
            }
            let updated = try await worker.setPinned(pinned, for: target)
            guard target.url.deletingLastPathComponent().standardizedFileURL == folderURL?.standardizedFileURL else {
                return updated
            }
            revision += 1
            let body = bodies.removeValue(forKey: target.url)
            notes.removeAll { $0.url == note.url || $0.url == target.url }
            notes.append(updated)
            notes.sort(by: Note.orderedForList)
            if let body { bodies[updated.url] = body }
            errorMessage = nil
            changed()
            await flushCatalogueCache()
            return updated
        } catch {
            report(error)
            throw error
        }
    }

    /// Prepare the returning list synchronously, without waiting on a provider.
    /// The caller owns a new composer whose current buffer is empty. Its last
    /// saved snapshot may still contain the just-deleted character. Only that
    /// exact version is omitted while its normal asynchronous save completes.
    func beginEmptyComposerReturn(_ snapshot: NoteSnapshot, currentText: String) -> UUID? {
        guard !snapshot.recoveredDraft,
              currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              snapshot.isUnsaved || (bodies[snapshot.note.url] == snapshot.text && notes.contains(snapshot.note)) else { return nil }
        let token = UUID()
        emptyComposerReturns[token] = snapshot
        changed()
        return token
    }

    func cancelEmptyComposerReturn(_ token: UUID) {
        guard emptyComposerReturns.removeValue(forKey: token) != nil else { return }
        changed()
    }

    /// Only an abandoned new composer uses this path. The worker compares disk
    /// bytes under the move's coordination and leaves all recovery untouched.
    @discardableResult
    func trashUnchangedEmptyComposer(_ snapshot: NoteSnapshot) async throws -> Bool {
        guard !snapshot.isUnsaved, !snapshot.recoveredDraft,
              snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              snapshot.text == snapshot.baselineText else { return false }
        try await requireFolderAccess()
        do {
            guard try await worker.trash(snapshot.note, ifUnchangedEmpty: snapshot.text) else {
                // A concurrent edit must become visible instead of remaining
                // hidden behind the abandoned composer's old empty snapshot.
                await refresh()
                return false
            }
            guard snapshot.note.url.deletingLastPathComponent().standardizedFileURL == folderURL?.standardizedFileURL else { return true }
            revision += 1
            // An open/refresh may have published a competing recovery while
            // the worker moved the empty file. Do not remove that newer row.
            if notes.contains(snapshot.note), bodies[snapshot.note.url] == snapshot.text {
                notes.removeAll { $0.url == snapshot.note.url }
                bodies.removeValue(forKey: snapshot.note.url)
            }
            canUndoTrash = true
            errorMessage = nil
            changed()
            // Journals stay at their active URL. A recovery arriving during
            // the move is still discoverable even when its empty file moved.
            await refresh()
            await flushCatalogueCache()
            return true
        } catch {
            report(error)
            throw error
        }
    }

    private func isReturningEmptyComposer(_ note: Note) -> Bool {
        emptyComposerReturns.values.contains {
            $0.note == note && bodies[note.url] == $0.text
        }
    }

    func trash(_ note: Note) async throws {
        try await requireFolderAccess()
        do {
            var target = note
            if note.isUnsaved {
                let recovered = try await worker.open(note)
                if recovered.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try await discardDraft(snapshot: recovered)
                    guard note.url.deletingLastPathComponent().standardizedFileURL == folderURL?.standardizedFileURL else { return }
                    revision += 1
                    notes.removeAll { $0.url == note.url }
                    bodies.removeValue(forKey: note.url)
                    errorMessage = nil
                    changed()
                    return
                }
                // The recovery row has no file to move yet. Materialize through
                // the same exclusive first-save path, then use ordinary trash
                // so Undo restores the user's text with its proper title.
                // If moving fails, save() has already published the durable
                // real note in the catalogue, and its content remains intact.
                target = try await save(recovered.text, snapshot: recovered).snapshot.note
            }
            try await worker.trash(target)
            guard target.url.deletingLastPathComponent().standardizedFileURL == folderURL?.standardizedFileURL else { return }
            revision += 1
            notes.removeAll { $0.url == note.url || $0.url == target.url }
            bodies.removeValue(forKey: note.url)
            bodies.removeValue(forKey: target.url)
            canUndoTrash = true
            errorMessage = nil
            changed()
            await flushCatalogueCache()
        } catch {
            report(error)
            throw error
        }
    }

    func undoTrash() async throws {
        try await requireFolderAccess()
        guard let folderURL else { throw StoreError.noFolder }
        do {
            try await worker.undoTrash(folder: folderURL)
            guard folderURL == self.folderURL else { return }
            revision += 1
            errorMessage = nil
            await refresh()
        } catch {
            report(error)
            throw error
        }
    }

    func search(_ query: String) -> [NoteSearchHit] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleNotes = notes.filter { !isReturningEmptyComposer($0) }
        guard !query.isEmpty else { return visibleNotes.map { NoteSearchHit(note: $0, snippet: nil) } }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return visibleNotes.sorted(by: Note.orderedByRecency).compactMap { note in
            let body = bodies[note.url] ?? note.preview
            let match = body.range(of: query, options: options)
            guard note.title.range(of: query, options: options) != nil || match != nil else { return nil }
            guard let match else { return NoteSearchHit(note: note, snippet: note.preview) }
            let start = body.index(match.lowerBound, offsetBy: -65, limitedBy: body.startIndex) ?? body.startIndex
            let end = body.index(match.upperBound, offsetBy: 100, limitedBy: body.endIndex) ?? body.endIndex
            let excerpt = body[start..<end].split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return NoteSearchHit(note: note, snippet: (start > body.startIndex ? "…" : "")
                                 + excerpt + (end < body.endIndex ? "…" : ""))
        }
    }

    private func initialized() async {
        await initialization?.value
        initialization = nil
    }

    private func requireFolderAccess() async throws {
        await initialized()
        guard folderIsReady else {
            throw folderURL == nil && !requiresFolderSelection
                ? StoreError.noFolder : StoreError.folderAccessRequired(folderURL?.lastPathComponent)
        }
    }

    private func restoreCatalogue(folder: URL) async {
        LaunchDiagnostics.record("body_cache_start", once: true)
        let cached = await CatalogueCache.shared.load(folder: folder)
        let pending = (try? await Task.detached(priority: .userInitiated) { [drafts] in
            try drafts.pending(in: folder)
        }.value) ?? []
        guard folderURL == folder else { return }
        if let cached {
            if hasLoadedCatalogue {
                // The index checkpoints first and can be newer than the body
                // snapshot after an interrupted/failed write. Never replace its
                // rows with older metadata or resurrect a removed note.
                let cachedNotes = Dictionary(uniqueKeysWithValues: cached.notes.map { ($0.url, $0) })
                for note in notes where cachedNotes[note.url] == note {
                    bodies[note.url] = cached.bodies[note.url]
                }
            } else {
                notes = cached.notes
                bodies = cached.bodies
                canUndoTrash = cached.canUndoTrash
            }
            hasLoadedCatalogue = true
        }
        var known = Set(notes.map(\.url))
        for draft in pending where !(draft.isUnsaved == true && draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            guard known.insert(draft.sourceURL).inserted else {
                // The launch index can survive a purged body cache. Retain a
                // saved baseline so openForEditing can recover this journal
                // locally even when the folder bookmark no longer resolves.
                if bodies[draft.sourceURL] == nil { bodies[draft.sourceURL] = draft.baseline }
                continue
            }
            let derived = Note.derive(from: draft.text)
            notes.append(Note(url: draft.sourceURL, modified: draft.savedAt, title: derived.title,
                              preview: derived.preview, isUnsaved: draft.isUnsaved == true))
            bodies[draft.sourceURL] = draft.text
        }
        notes.sort(by: Self.sortNotes)
        if !notes.isEmpty { hasLoadedCatalogue = true }
        LaunchDiagnostics.record("body_cache_restored", counts: ["rows": notes.count, "bodies": bodies.count],
                                 flags: ["body_cache_loaded": cached != nil], once: true)
    }

    private func acceptCatalogue(_ listing: FolderListing, refreshID: UUID, folder: URL, revision: Int) -> Bool {
        guard self.refreshID == refreshID, folderURL == folder, self.revision == revision else { return false }
        acceptCatalogue(listing)
        return true
    }

    private func acceptCatalogue(_ listing: FolderListing) {
        notes = listing.notes
        bodies = listing.bodies
        canUndoTrash = listing.canUndoTrash
        errorMessage = listing.warning
        requiresFolderSelection = false
        hasLoadedCatalogue = true
        changed()
    }

    /// A local checkpoint only; never waits for the selected file provider.
    func flushCatalogueCache() async {
        while let task = catalogueWriteTask { await task.value }
    }

    private func queueCataloguePersistence() {
        guard hasLoadedCatalogue, let folderURL else { return }
        pendingCatalogue = (CachedCatalogue(folderURL: folderURL, notes: notes, bodies: bodies,
                                            canUndoTrash: canUndoTrash), CatalogueCache.reserveSequence())
        guard catalogueWriteTask == nil else { return }
        catalogueWriteTask = Task {
            while let pending = pendingCatalogue {
                pendingCatalogue = nil
                // This cache is disposable. A failed cache write must not turn
                // an otherwise successful note save into an error.
                do {
                    try await CatalogueCache.shared.store(pending.value, sequence: pending.sequence)
                    LaunchDiagnostics.record("catalogue_persisted", counts: ["rows": pending.value.notes.count], once: true)
                } catch {
                    LaunchDiagnostics.record("catalogue_write_failed", counts: ["error_code": (error as NSError).code], once: true)
                }
            }
            catalogueWriteTask = nil
        }
    }

    private func apply(_ snapshot: NoteSnapshot) {
        guard snapshot.note.url.deletingLastPathComponent().standardizedFileURL == folderURL?.standardizedFileURL else { return }
        // Recovered unsaved text is discoverable, but a blank composer isn't a note.
        guard !snapshot.isUnsaved || !snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // A completed read/write invalidates any older directory listing in flight.
        revision += 1
        notes.removeAll { $0.url == snapshot.note.url }
        notes.append(snapshot.note)
        notes.sort(by: Self.sortNotes)
        bodies[snapshot.note.url] = snapshot.text
    }

    private static func sortNotes(_ lhs: Note, _ rhs: Note) -> Bool {
        Note.orderedForList(lhs, rhs)
    }

    private func report(_ error: Error) {
        recordError(error)
        changed()
    }

    private func recordError(_ error: Error) {
        if FolderBookmark.isPermissionError(error) {
            requiresFolderSelection = true
            errorMessage = StoreError.folderAccessRequired(folderURL?.lastPathComponent).localizedDescription
        } else {
            errorMessage = error.localizedDescription
        }
    }

    private func changed() {
        queueCataloguePersistence()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

/// A remembered path is only a cache lookup key, never an access grant. Pair it
/// with the exact bookmark so a replaced/stale preference cannot show another
/// notebook's cached rows before bookmark resolution finishes.
enum FolderBookmark {
    static let key = "drift.folderBookmark"
    private static let cacheIdentityKey = "drift.folderCacheIdentity"

    private struct CacheIdentity: Codable {
        let folder: URL
        let bookmarkDigest: String
    }

    static func cachedFolder(in defaults: UserDefaults) -> URL? {
        guard let bookmark = defaults.data(forKey: key),
              let data = defaults.data(forKey: cacheIdentityKey),
              let identity = try? JSONDecoder().decode(CacheIdentity.self, from: data),
              identity.folder.isFileURL,
              identity.bookmarkDigest == digest(bookmark) else { return nil }
        return FolderIdentity.directoryURL(identity.folder)
    }

    static func save(_ bookmark: Data, folder: URL, in defaults: UserDefaults) {
        defaults.set(bookmark, forKey: key)
        saveCacheIdentity(bookmark, folder: folder, in: defaults)
    }

    static func saveCacheIdentity(_ bookmark: Data, folder: URL, in defaults: UserDefaults) {
        let identity = CacheIdentity(folder: FolderIdentity.directoryURL(folder), bookmarkDigest: digest(bookmark))
        if let data = try? JSONEncoder().encode(identity) { defaults.set(data, forKey: cacheIdentityKey) }
    }

    static func isPermissionError(_ error: Error) -> Bool {
        var current = error as NSError
        // File providers frequently wrap the actual sandbox/permission failure.
        for _ in 0..<8 {
            if current.domain == NSCocoaErrorDomain,
               [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(current.code) { return true }
            if current.domain == NSPOSIXErrorDomain, [Int(EACCES), Int(EPERM)].contains(current.code) { return true }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
            current = underlying
        }
        return false
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private enum StoreError: LocalizedError {
    case noFolder
    case invalidFolder
    case unreadable(String)
    case unavailable(String)
    case nothingToUndo
    case coordinationFailed
    case folderAccessRequired(String?)
    case changedNote

    var errorDescription: String? {
        switch self {
        case .noFolder: return "Choose a notes folder first."
        case .invalidFolder: return "That location is not a folder. Choose your notes folder again."
        case .unreadable(let name): return "“\(name)” could not be read as UTF-8 text. Its contents have not been changed."
        case .unavailable(let name): return "“\(name)” is downloading from iCloud. Try opening it again shortly."
        case .nothingToUndo: return "There are no recently deleted notes to restore."
        case .coordinationFailed: return "The file provider did not allow access. Please try again."
        case .folderAccessRequired(let name):
            let folder = name.map { "“\($0)”" } ?? "your notes folder"
            return "Choose \(folder) again to restore access. In Files, browse to iCloud Drive and select the folder used on your Mac. If access is disabled, allow Drift in Settings → Privacy & Security → Files and Folders. Your notes and local recovery drafts have not been removed."
        case .changedNote: return "That note has moved or is no longer available. Refresh your notes and try again."
        }
    }
}

private struct FolderListing: Sendable {
    let notes: [Note]
    let bodies: [URL: String]
    let canUndoTrash: Bool
    let warning: String?
}

/// Each worker serializes its coordinated operations. The document worker owns
/// bookmark access and mutations; a separate instance handles catalogue scans.
/// Compare-and-write never suspends, so conflict checks and saves remain atomic.
private actor FileWorker {
    private let defaults: UserDefaults
    private let fm = FileManager.default
    private let coordinator = NSFileCoordinator()
    private var scopedURL: URL?

    private let drafts: DraftJournal
    private struct CachedRead {
        let modified: Date
        let size: Int
        let snapshot: NoteSnapshot
    }
    private var cache: [URL: CachedRead] = [:]

    init(drafts: DraftJournal, defaults: UserDefaults) {
        self.drafts = drafts
        self.defaults = defaults
    }

    private struct TrashRecord: Codable {
        let originalName: String
        let trashedName: String
        let deletedAt: Date
    }

    deinit { scopedURL?.stopAccessingSecurityScopedResource() }

    func initialize(explicitURL: URL?, preferredFolder: URL?, prepareTestFolder: Bool, resetTestFolder: Bool) throws -> URL? {
        if let explicitURL {
            if resetTestFolder, fm.fileExists(atPath: explicitURL.path) { try fm.removeItem(at: explicitURL) }
            if prepareTestFolder { try fm.createDirectory(at: explicitURL, withIntermediateDirectories: true) }
            return explicitURL
        }
        guard let bookmark = defaults.data(forKey: FolderBookmark.key) else { return nil }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        if url.startAccessingSecurityScopedResource() { scopedURL = url }
        // Keep stable note/draft identities when bookmark resolution returns
        // another lexical spelling of the same directory. The original URL
        // above still owns the security-scoped grant.
        let stableFolder = preferredFolder.flatMap {
            FolderIdentity.sameFolder($0, url) ? FolderIdentity.directoryURL($0) : nil
        } ?? FolderIdentity.directoryURL(url)
        // Restoring the bookmark must not enumerate/download the provider before
        // the local catalogue is visible. The subsequent metadata scan validates
        // access and reports any actual provider error.
        // A stale bookmark may still resolve and grant access. Renewal is
        // housekeeping; a provider refusing it must not hide the notebook.
        if stale, let renewed = try? url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil) {
            FolderBookmark.save(renewed, folder: stableFolder, in: defaults)
        } else {
            FolderBookmark.saveCacheIdentity(bookmark, folder: stableFolder, in: defaults)
        }
        return stableFolder
    }

    func selectFolder(_ url: URL) throws -> URL {
        let hasScope = url.startAccessingSecurityScopedResource()
        do {
            try validateFolder(url)
            let bookmark = try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
            FolderBookmark.save(bookmark, folder: url, in: defaults)
            scopedURL?.stopAccessingSecurityScopedResource()
            scopedURL = hasScope ? url : nil
            return FolderIdentity.directoryURL(url)
        } catch {
            if hasScope { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    func list(folder: URL, previous: CachedCatalogue,
              progress: @Sendable (FolderListing) async -> Bool) async throws -> FolderListing {
        // Names and immediately available attributes must not request the
        // contents of every iCloud document just to show the notebook.
        let urls = try coordinatedRead(folder, options: [.withoutChanges, .immediatelyAvailableMetadataOnly]) { coordinated in
            try fm.contentsOfDirectory(at: coordinated,
                                       includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey,
                                                                    .ubiquitousItemDownloadingStatusKey],
                                       options: [.skipsHiddenFiles])
        }
        struct FileEntry {
            let url: URL
            let modified: Date?
            let size: Int?
            let needsDownload: Bool
        }
        var entries: [FileEntry] = []
        var notes: [URL: Note] = [:]
        var bodies: [URL: String] = [:]
        let previousNotes = Dictionary(uniqueKeysWithValues: previous.notes.map { ($0.url, $0) })
        var unreadable = 0
        for rawURL in urls where rawURL.pathExtension.lowercased() == "md" {
            guard FolderIdentity.sameFolder(rawURL.deletingLastPathComponent(), folder) else { continue }
            let url = folder.appendingPathComponent(rawURL.lastPathComponent).standardizedFileURL
            // Use the enumerated URL to retain prefetched provider metadata.
            let values = try? rawURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey,
                                                         .ubiquitousItemDownloadingStatusKey])
            guard values?.isRegularFile != false else { continue }
            entries.append(FileEntry(url: url, modified: values?.contentModificationDate, size: values?.fileSize,
                                     needsDownload: values?.ubiquitousItemDownloadingStatus == .notDownloaded))
            if let cached = cache[url], cached.modified == values?.contentModificationDate,
               cached.size == values?.fileSize {
                notes[url] = cached.snapshot.note
                bodies[url] = cached.snapshot.text
            } else if let previousNote = previousNotes[url] {
                // This is explicitly a last-known text baseline. It may be
                // shown/opened now, but only a coordinated read verifies it.
                var note = previousNote
                note.modified = values?.contentModificationDate ?? note.modified
                notes[url] = note
                bodies[url] = previous.bodies[url]
            } else {
                notes[url] = fallbackNote(url, modified: values?.contentModificationDate)
            }
        }
        let liveURLs = Set(notes.keys)
        cache = cache.filter { liveURLs.contains($0.key) }
        // Local recovery must be discoverable even when its provider file moved
        // or a new composer had not yet written its first shared file.
        for draft in try drafts.pending(in: folder)
        where !(draft.isUnsaved == true && draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && notes[draft.sourceURL] == nil {
            let derived = Note.derive(from: draft.text)
            notes[draft.sourceURL] = Note(url: draft.sourceURL, modified: draft.savedAt, title: derived.title,
                                         preview: derived.preview, isUnsaved: draft.isUnsaved == true)
            bodies[draft.sourceURL] = draft.text
        }
        func listing(canUndo: Bool) -> FolderListing {
            let sorted = notes.values.sorted(by: Note.orderedForList)
            return FolderListing(notes: sorted, bodies: bodies, canUndoTrash: canUndo,
                                 warning: unreadable > 0 ? "\(unreadable) note\(unreadable == 1 ? "" : "s") could not be read. Pull to refresh to try again." : nil)
        }
        guard await progress(listing(canUndo: previous.canUndoTrash)) else { throw CancellationError() }

        // Enrich the most recent, visible notes first. Slow individual bodies
        // can no longer hold the initial rows hostage.
        entries.sort {
            if Note.isPinned($0.url) != Note.isPinned($1.url) { return Note.isPinned($0.url) }
            let lhsDate = notes[$0.url]?.modified ?? .distantPast
            let rhsDate = notes[$1.url]?.modified ?? .distantPast
            return lhsDate == rhsDate
                ? $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
                : lhsDate > rhsDate
        }
        var lastPublication = ContinuousClock.now
        var earlyChanges = 0
        var hasPendingChanges = false
        for (index, entry) in entries.enumerated() {
            try Task.checkCancellation()
            let url = entry.url
            if entry.needsDownload {
                try? fm.startDownloadingUbiquitousItem(at: url)
                continue
            }
            var publishVisibleChange = false
            do {
                let snapshot: NoteSnapshot
                if let cached = cache[url], cached.modified == entry.modified, cached.size == entry.size {
                    snapshot = cached.snapshot
                } else {
                    snapshot = try readSnapshot(url, fallbackModified: notes[url]?.modified ?? .distantPast)
                    if let modified = entry.modified, let size = entry.size {
                        cache[url] = CachedRead(modified: modified, size: size, snapshot: snapshot)
                    }
                }
                if notes[url] != snapshot.note || bodies[url] != snapshot.text {
                    notes[url] = snapshot.note
                    bodies[url] = snapshot.text
                    hasPendingChanges = true
                    if earlyChanges < 8 {
                        earlyChanges += 1
                        publishVisibleChange = true
                    }
                }
            } catch {
                unreadable += 1
                hasPendingChanges = true
            }
            // Publish ready previews near the top before the next body read can
            // stall. Later rows remain batched, and unchanged scans stay quiet.
            if hasPendingChanges && (publishVisibleChange || index % 32 == 31
                                     || lastPublication.duration(to: .now) >= .milliseconds(200)) {
                guard await progress(listing(canUndo: previous.canUndoTrash)) else { throw CancellationError() }
                lastPublication = .now
                hasPendingChanges = false
            }
        }
        return listing(canUndo: !(try trashRecords(in: folder)).isEmpty)
    }

    func open(_ note: Note) throws -> NoteSnapshot {
        let pendingDrafts = try drafts.readAll(for: note.url)
        let disk: NoteSnapshot
        do {
            disk = try readSnapshot(note.url)
        } catch {
            guard let draft = pendingDrafts.first else { throw error }
            // Keep the original baseline even if iCloud or a deletion prevents reading it.
            let derived = Note.derive(from: draft.text)
            let recovered = Note(url: note.url, modified: draft.savedAt, title: derived.title,
                                 preview: derived.preview, isUnsaved: draft.isUnsaved == true)
            return NoteSnapshot(note: recovered, text: draft.text, baselineText: draft.baseline, recoveredDraft: true, documentID: draft.documentID)
        }
        if let draft = pendingDrafts.first(where: { $0.text != disk.text }) {
            let derived = Note.derive(from: draft.text)
            let recovered = Note(url: disk.note.url, modified: max(disk.note.modified, draft.savedAt),
                                 title: derived.title, preview: derived.preview, isUnsaved: draft.isUnsaved == true)
            return NoteSnapshot(note: recovered, text: draft.text, baselineText: draft.baseline, recoveredDraft: true, documentID: draft.documentID)
        }
        return disk
    }

    func create(folder: URL) throws -> NoteSnapshot {
        try createFile(text: "", base: Note.untitled, folder: folder)
    }

    func save(_ text: String, snapshot submitted: NoteSnapshot) throws -> NoteSaveResult {
        // A first save or pin rename may already have moved this session while
        // another caller waited. Follow its alias instead of creating a second file.
        let resolved = drafts.materializedSnapshot(for: submitted)
        let baseline: NoteSnapshot
        if submitted.isUnsaved {
            baseline = resolved ?? submitted
        } else if let resolved, resolved.note.url != submitted.note.url {
            // A rename changes location, never the text this caller last saw.
            // Retain that baseline so a delayed save cannot overwrite newer writing.
            baseline = NoteSnapshot(note: resolved.note, text: submitted.text, baselineText: submitted.baselineText,
                                    recoveredDraft: submitted.recoveredDraft, documentID: submitted.documentID)
        } else {
            baseline = submitted
        }
        if baseline.isUnsaved {
            let created = try createFile(text: text, base: Note.derive(from: text).title,
                                         folder: baseline.note.url.deletingLastPathComponent(),
                                         documentID: baseline.documentID)
            try? drafts.completeSave(from: baseline, snapshot: created)
            return NoteSaveResult(snapshot: created, preservedConflict: false, sourceURL: baseline.note.url)
        }
        // The main model journals before enqueuing provider work. Do not replace
        // it here: a newer edit may have reached the journal while this save waited.
        let sourceURL = baseline.note.url
        let folder = sourceURL.deletingLastPathComponent()
        let conflict = try coordinatedWrite(sourceURL) { coordinated in
            let external: String?
            do {
                external = try readUTF8(coordinated)
            } catch where isMissing(error) {
                external = nil
            }
            if external == text { return false }
            if external != baseline.baselineText { return true }
            try Data(text.utf8).write(to: coordinated, options: [.atomic])
            return false
        }
        let result: NoteSaveResult
        let derived = Note.derive(from: text)
        if conflict {
            // Leave the external version untouched. Coordinate the new file itself,
            // because a directory coordination alone does not protect its children.
            let stamp = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
            let recovered = try createFile(text: text, base: "\(derived.title) (Recovered \(stamp))", folder: folder,
                                           pinned: baseline.note.isPinned, documentID: baseline.documentID)
            result = NoteSaveResult(snapshot: recovered, preservedConflict: true, sourceURL: sourceURL)
        } else {
            var destination = sourceURL
            // Compare titles, not filenames: a collision suffix stays stable on body edits.
            if derived.title != Note.derive(from: baseline.baselineText).title {
                let target = uniqueURL(base: derived.title, folder: folder, pinned: baseline.note.isPinned,
                                       excluding: sourceURL)
                if target != sourceURL {
                    do {
                        destination = try coordinatedMove(from: sourceURL, to: target, expectedText: text)
                    } catch {
                        // Text was saved successfully; a refused cosmetic rename keeps the old URL.
                        destination = sourceURL
                    }
                }
            }
            result = NoteSaveResult(snapshot: snapshot(url: destination, text: text, documentID: baseline.documentID),
                                    preservedConflict: false, sourceURL: sourceURL)
        }
        // A newer edit can be journaled while a file provider is saving this one.
        // Rebase it onto the just-saved version and carry it across any rename.
        try? drafts.completeSave(from: baseline, snapshot: result.snapshot)
        cache.removeValue(forKey: sourceURL)
        cache.removeValue(forKey: result.snapshot.note.url)
        return result
    }

    func setPinned(_ pinned: Bool, for note: Note) throws -> Note {
        let source = note.url
        if note.isPinned == pinned {
            // An old menu action must not resurrect a deleted catalogue row.
            try coordinatedRead(source, options: [.withoutChanges, .immediatelyAvailableMetadataOnly]) {
                guard try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                    throw StoreError.changedNote
                }
            }
            return note
        }
        for _ in 0..<10 {
            let target = uniqueURL(base: Note.filenameTitle(source), folder: source.deletingLastPathComponent(),
                                   pinned: pinned, excluding: source)
            do {
                let destination = try coordinatedMove(from: source, to: target, relocateDrafts: true)
                cache.removeValue(forKey: source)
                cache.removeValue(forKey: destination)
                return Note(url: destination, modified: note.modified, title: note.title, preview: note.preview)
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                continue
            } catch where isMissing(error) {
                throw StoreError.changedNote
            }
        }
        throw StoreError.coordinationFailed
    }

    @discardableResult
    func trash(_ note: Note, ifUnchangedEmpty expectedText: String? = nil) throws -> Bool {
        if let expectedText, !expectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        let folder = note.url.deletingLastPathComponent()
        let trashFolder = folder.appendingPathComponent(".drift-trash", isDirectory: true)
        try fm.createDirectory(at: trashFolder, withIntermediateDirectories: true)
        let identifier = UUID().uuidString
        let record = TrashRecord(originalName: note.url.lastPathComponent,
                                 trashedName: "\(identifier).md", deletedAt: Date())
        let recordURL = trashFolder.appendingPathComponent("\(identifier).json")
        let trashedURL = trashFolder.appendingPathComponent(record.trashedName)
        // Record first: interruption can leave harmless metadata, never an untraceable deleted file.
        try coordinatedWrite(recordURL) { try JSONEncoder().encode(record).write(to: $0, options: [.atomic]) }
        do {
            let moved = try coordinatedMove(from: note.url, to: trashedURL,
                                            expectedText: expectedText, expectedModified: expectedText == nil ? nil : note.modified,
                                            requireNoDrafts: expectedText != nil)
            guard moved == trashedURL else {
                try? fm.removeItem(at: recordURL)
                return false
            }
            if expectedText == nil { try? drafts.move(from: note.url, to: trashedURL) }
            cache.removeValue(forKey: note.url)
            return true
        } catch {
            try? fm.removeItem(at: recordURL)
            throw error
        }
    }

    func undoTrash(folder: URL) throws {
        guard let entry = try trashRecords(in: folder).first else { throw StoreError.nothingToUndo }
        let originalURL = folder.appendingPathComponent(entry.record.originalName)
        let targetURL = uniqueURL(base: Note.filenameTitle(originalURL), folder: folder,
                                  pinned: Note.isPinned(originalURL))
        // Relocate recovery first. If journaling fails, the file and Undo record
        // remain together in trash; if moving the file then fails, the draft is
        // already discoverable at its visible destination.
        try drafts.move(from: entry.fileURL, to: targetURL)
        _ = try coordinatedMove(from: entry.fileURL, to: targetURL)
        try? fm.removeItem(at: entry.metadataURL)
    }

    private func createFile(text: String, base: String, folder: URL, pinned: Bool = false,
                            documentID: UUID = UUID()) throws -> NoteSnapshot {
        // Another device may claim the chosen filename between listing and coordination.
        // An exclusive create protects it; retry the next available name in that case.
        for _ in 0..<10 {
            let url = uniqueURL(base: base, folder: folder, pinned: pinned)
            do {
                return try coordinatedWrite(url) { coordinated in
                    try Data(text.utf8).write(to: coordinated, options: [.withoutOverwriting])
                    return snapshot(url: url, text: text, documentID: documentID)
                }
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                continue
            }
        }
        throw StoreError.coordinationFailed
    }

    private func coordinatedMove(from source: URL, to destination: URL, expectedText: String? = nil,
                                  expectedModified: Date? = nil,
                                  relocateDrafts: Bool = false, requireNoDrafts: Bool = false) throws -> URL {
        var coordinationError: NSError?
        var result: Result<URL, Error>?
        coordinator.coordinate(writingItemAt: source, options: .forMoving,
                               writingItemAt: destination, options: .forReplacing, error: &coordinationError) { from, to in
            result = Result {
                // A device may edit between the content save and its optional title rename.
                if let expectedText, try readUTF8(from) != expectedText { return source }
                if let expectedModified,
                   try from.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate != expectedModified { return source }
                // Check existing recovery here, but never hold its lock over
                // provider I/O. A later journal stays at the active URL; this
                // conditional path never moves, discards, or aliases it.
                if requireNoDrafts, try !drafts.readAll(for: source).isEmpty { return source }
                var movedDraftIDs: Set<UUID> = []
                if relocateDrafts {
                    guard try from.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                        throw StoreError.changedNote
                    }
                    guard !fm.fileExists(atPath: to.path) else {
                        throw CocoaError(.fileWriteFileExists)
                    }
                    // Never move a file away from a recovery journal we could not relocate.
                    movedDraftIDs = Set(try drafts.readAll(for: source).map(\.documentID))
                }
                do {
                    if relocateDrafts { try drafts.move(from: source, to: destination) }
                    coordinator.item(at: from, willMoveTo: to)
                    try fm.moveItem(at: from, to: to)
                } catch {
                    if relocateDrafts {
                        try? drafts.move(from: destination, to: source, documentIDs: movedDraftIDs)
                    }
                    throw error
                }
                coordinator.item(at: from, didMoveTo: to)
                return destination
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw StoreError.coordinationFailed }
        return try result.get()
    }

    private func validateFolder(_ url: URL) throws {
        // Selection only needs to validate the directory. A normal coordinated
        // read can wait for every child to download before the notebook opens.
        try coordinatedRead(url, options: [.withoutChanges, .immediatelyAvailableMetadataOnly]) { coordinated in
            let values = try coordinated.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { throw StoreError.invalidFolder }
            _ = try fm.contentsOfDirectory(at: coordinated, includingPropertiesForKeys: nil)
        }
    }

    private func readSnapshot(_ url: URL, fallbackModified: Date? = nil) throws -> NoteSnapshot {
        let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        if values.ubiquitousItemDownloadingStatus == .notDownloaded {
            try fm.startDownloadingUbiquitousItem(at: url)
            throw StoreError.unavailable(url.lastPathComponent)
        }
        return try coordinatedRead(url) { coordinated in
            snapshot(url: url, text: try readUTF8(coordinated), fallbackModified: fallbackModified)
        }
    }

    private func readUTF8(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { throw StoreError.unreadable(url.lastPathComponent) }
        return text
    }

    private func snapshot(url: URL, text: String, documentID: UUID = UUID(), fallbackModified: Date? = nil) -> NoteSnapshot {
        let derived = Note.derive(from: text)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? fallbackModified ?? Date()
        return NoteSnapshot(note: Note(url: url.standardizedFileURL, modified: modified,
                                      title: derived.title, preview: derived.preview), text: text, documentID: documentID)
    }

    private func fallbackNote(_ url: URL, modified: Date?) -> Note {
        Note(url: url, modified: modified ?? .distantPast,
             title: Note.filenameTitle(url), preview: "")
    }

    private func uniqueURL(base: String, folder: URL, pinned: Bool = false, excluding: URL? = nil) -> URL {
        // A leading dot would hide an otherwise ordinary note from both apps.
        let visibleBase = base.hasPrefix(".") ? String(base.drop(while: { $0 == "." })) : base
        let safeBase = visibleBase.isEmpty ? Note.untitled : visibleBase
        let reservedEnding = !pinned && safeBase.lowercased().hasSuffix(".pinned")
        var index = 1
        while true {
            let name = index == 1 && !reservedEnding ? safeBase : "\(safeBase) \(index)"
            let suffix = pinned ? ".pinned.md" : ".md"
            let url = folder.appendingPathComponent("\(name)\(suffix)").standardizedFileURL
            if url == excluding?.standardizedFileURL || !fm.fileExists(atPath: url.path) { return url }
            index += 1
        }
    }

    private func trashRecords(in folder: URL) throws -> [(record: TrashRecord, fileURL: URL, metadataURL: URL)] {
        let trashFolder = folder.appendingPathComponent(".drift-trash", isDirectory: true)
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(at: trashFolder, includingPropertiesForKeys: nil)
        } catch where isMissing(error) { return [] }
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url), let record = try? JSONDecoder().decode(TrashRecord.self, from: data),
                  record.originalName == URL(fileURLWithPath: record.originalName).lastPathComponent,
                  record.trashedName == URL(fileURLWithPath: record.trashedName).lastPathComponent else { return nil }
            let file = trashFolder.appendingPathComponent(record.trashedName)
            guard fm.fileExists(atPath: file.path) else { return nil }
            return (record, file, url)
        }.sorted { $0.record.deletedAt > $1.record.deletedAt }
    }

    private func isMissing(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain
            && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError)
    }

    private func coordinatedRead<T>(_ url: URL, options: NSFileCoordinator.ReadingOptions = [],
                                    operation: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(readingItemAt: url, options: options, error: &coordinationError) { coordinated in
            result = Result { try operation(coordinated) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw StoreError.coordinationFailed }
        return try result.get()
    }

    private func coordinatedWrite<T>(_ url: URL, operation: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { coordinated in
            result = Result { try operation(coordinated) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw StoreError.coordinationFailed }
        return try result.get()
    }
}


private struct StoredDraft: Codable, Sendable {
    let sourceURL: URL
    let documentID: UUID
    let text: String
    let baseline: String
    let savedAt: Date
    // Optional for journals written by earlier app versions.
    var isUnsaved: Bool? = nil
}

/// Local journaling has a separate execution path from coordinated provider access.
/// Each editing session owns a journal; one session cannot clear or rebase another
/// session's unsaved branch, even if both began with the same URL and contents.
private final class DraftJournal: @unchecked Sendable {
    private let lock = NSLock()
    private let fm = FileManager.default
    private var nextSequence: UInt64 = 0
    private var lastSequence: [UUID: UInt64] = [:]

    private struct Identity: Hashable {
        let url: URL
        let baseline: String
        let documentID: UUID
        let isUnsaved: Bool
    }
    private var aliases: [Identity: Identity] = [:]

    func reserveSequence() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        nextSequence += 1
        return nextSequence
    }

    func persist(_ text: String, snapshot: NoteSnapshot, sequence: UInt64) throws {
        lock.lock()
        defer { lock.unlock() }
        let identity = resolve(snapshot)
        guard sequence >= lastSequence[identity.documentID, default: 0] else { return }
        try write(StoredDraft(sourceURL: identity.url, documentID: identity.documentID, text: text,
                              baseline: identity.baseline, savedAt: Date(), isUnsaved: identity.isUnsaved))
        lastSequence[identity.documentID] = sequence
    }

    func discard(snapshot: NoteSnapshot, sequence: UInt64) throws {
        lock.lock()
        defer { lock.unlock() }
        let identity = resolve(snapshot)
        guard sequence >= lastSequence[identity.documentID, default: 0] else { return }
        if try readUnlocked(for: identity.url, documentID: identity.documentID) != nil {
            try fm.removeItem(at: url(for: identity.url, documentID: identity.documentID))
        }
        lastSequence[identity.documentID] = sequence
    }

    /// A direct API save still gets a journal without replacing its newer edits.
    func ensure(_ text: String, snapshot: NoteSnapshot) throws {
        lock.lock()
        defer { lock.unlock() }
        let identity = resolve(snapshot)
        guard try readUnlocked(for: identity.url, documentID: identity.documentID) == nil else { return }
        try write(StoredDraft(sourceURL: identity.url, documentID: identity.documentID, text: text,
                              baseline: identity.baseline, savedAt: Date(), isUnsaved: identity.isUnsaved))
    }

    private func resolve(_ snapshot: NoteSnapshot) -> Identity {
        var identity = Identity(url: snapshot.note.url, baseline: snapshot.baselineText,
                                documentID: snapshot.documentID, isUnsaved: snapshot.isUnsaved)
        var seen: Set<Identity> = []
        while let next = aliases[identity], seen.insert(identity).inserted { identity = next }
        return identity
    }

    func materializedSnapshot(for snapshot: NoteSnapshot) -> NoteSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        let identity = resolve(snapshot)
        guard !identity.isUnsaved else { return nil }
        let derived = Note.derive(from: identity.baseline)
        let note = Note(url: identity.url, modified: snapshot.note.modified, title: derived.title, preview: derived.preview)
        return NoteSnapshot(note: note, text: identity.baseline, documentID: identity.documentID)
    }

    func readAll(for sourceURL: URL) throws -> [StoredDraft] {
        lock.lock()
        defer { lock.unlock() }
        return try allUnlocked().filter { $0.sourceURL == sourceURL }
    }

    func pending(in folder: URL) throws -> [StoredDraft] {
        lock.lock()
        defer { lock.unlock() }
        return try allUnlocked().filter {
            $0.sourceURL.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL
        }
    }

    func completeSave(from baseline: NoteSnapshot, snapshot: NoteSnapshot) throws {
        lock.lock()
        defer { lock.unlock() }
        let sourceURL = baseline.note.url
        let target = Identity(url: snapshot.note.url, baseline: snapshot.text, documentID: snapshot.documentID, isUnsaved: snapshot.isUnsaved)
        let origin = Identity(url: sourceURL, baseline: baseline.baselineText, documentID: baseline.documentID, isUnsaved: baseline.isUnsaved)
        aliases.removeValue(forKey: target)
        if origin != target { aliases[origin] = target }
        guard let draft = try readUnlocked(for: sourceURL, documentID: baseline.documentID) else { return }
        let draftOrigin = Identity(url: sourceURL, baseline: draft.baseline, documentID: draft.documentID, isUnsaved: draft.isUnsaved == true)
        if draftOrigin != target { aliases[draftOrigin] = target }
        if draft.text != snapshot.text {
            try write(StoredDraft(sourceURL: snapshot.note.url, documentID: draft.documentID, text: draft.text,
                                  baseline: snapshot.text, savedAt: draft.savedAt, isUnsaved: snapshot.isUnsaved))
        }
        if draft.text == snapshot.text || snapshot.note.url != sourceURL {
            try fm.removeItem(at: url(for: sourceURL, documentID: baseline.documentID))
        }
    }

    func move(from sourceURL: URL, to targetURL: URL, documentIDs: Set<UUID>? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        guard sourceURL != targetURL else { return }
        let affected = try allUnlocked().filter {
            $0.sourceURL == sourceURL && (documentIDs?.contains($0.documentID) ?? true)
        }
        for draft in affected {
            try write(StoredDraft(sourceURL: targetURL, documentID: draft.documentID, text: draft.text,
                                  baseline: draft.baseline, savedAt: draft.savedAt, isUnsaved: draft.isUnsaved))
            let origin = Identity(url: sourceURL, baseline: draft.baseline, documentID: draft.documentID, isUnsaved: draft.isUnsaved == true)
            aliases[origin] = Identity(url: targetURL, baseline: draft.baseline, documentID: draft.documentID, isUnsaved: draft.isUnsaved == true)
            try fm.removeItem(at: url(for: sourceURL, documentID: draft.documentID))
        }
        for (origin, target) in aliases where target.url == sourceURL
            && (documentIDs?.contains(target.documentID) ?? true) {
            aliases[origin] = Identity(url: targetURL, baseline: target.baseline, documentID: target.documentID, isUnsaved: target.isUnsaved)
        }
    }

    private func allUnlocked() throws -> [StoredDraft] {
        let urls = try fm.contentsOfDirectory(at: directory(), includingPropertiesForKeys: nil)
        return urls.compactMap { url in
            guard url.pathExtension == "json", let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(StoredDraft.self, from: data)
        }.sorted { $0.savedAt > $1.savedAt }
    }

    private func readUnlocked(for sourceURL: URL, documentID: UUID) throws -> StoredDraft? {
        do {
            return try JSONDecoder().decode(StoredDraft.self, from: Data(contentsOf: url(for: sourceURL, documentID: documentID)))
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) {
            return nil
        }
    }

    private func write(_ draft: StoredDraft) throws {
        try JSONEncoder().encode(draft).write(to: url(for: draft.sourceURL, documentID: draft.documentID), options: [.atomic])
    }

    private func directory() throws -> URL {
        let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                 appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("Drift/Drafts", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func url(for noteURL: URL, documentID: UUID) throws -> URL {
        let hash = SHA256.hash(data: Data(noteURL.standardizedFileURL.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return try directory().appendingPathComponent("\(hash).\(documentID.uuidString).json")
    }
}
