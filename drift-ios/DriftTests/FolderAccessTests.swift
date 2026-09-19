import Foundation
import CryptoKit
import Testing
import UIKit
@testable import Drift

@MainActor
struct FolderAccessTests {
    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-folder-access-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }

    @Test
    func cachedRowsExistBeforeAnyAsynchronousStartupWork() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "drift-folder-startup-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var notes: [Note] = []
        var bodies: [URL: String] = [:]
        let body = String(repeating: "A locally cached paragraph, available before iCloud responds.\n", count: 80)
        for index in 0..<1_000 {
            let title = String(format: "Cached thought %04d", index)
            let url = folder.appendingPathComponent(title + ".md")
            notes.append(Note(url: url, modified: Date(timeIntervalSince1970: 1_700_000_000 - Double(index)),
                              title: title, preview: "A locally cached paragraph"))
            bodies[url] = title + "\n" + body
        }
        try await CatalogueCache.shared.store(CachedCatalogue(folderURL: folder, notes: notes,
                                                               bodies: bodies, canUndoTrash: false),
                                                sequence: CatalogueCache.reserveSequence())
        // Seed only local cache files. There are no note files to read, and an
        // unresolved bookmark keeps provider reconciliation out of this check.
        FolderBookmark.save(Data("unresolved provider bookmark".utf8), folder: folder, in: defaults)

        let start = ContinuousClock.now
        let restarted = NoteStore(defaults: defaults)
        let indexDuration = start.duration(to: .now)
        // Do not yield: these rows must exist before a UI's first render.
        #expect(restarted.hasLoadedCatalogue)
        #expect(!restarted.isLoading)
        #expect(restarted.folderURL == folder)
        #expect(restarted.notes.map(\.url) == notes.map(\.url))
        let notebook = NotebookViewController(store: restarted)
        let navigation = PaperNavigationController(rootViewController: notebook)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = navigation
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        notebook.loadViewIfNeeded()
        window.layoutIfNeeded()
        notebook.view.layoutIfNeeded()
        let table = try #require(notebook.view.subviews.compactMap { $0 as? UITableView }.first)
        table.layoutIfNeeded()
        #expect(table.numberOfRows(inSection: 0) == 1_000)
        #expect(!table.visibleCells.isEmpty)
        #expect(table.backgroundView == nil)
        let indicators = notebook.view.subviews.compactMap { $0 as? UIActivityIndicatorView }
        #expect(!indicators.isEmpty)
        #expect(indicators.allSatisfy { !$0.isAnimating && $0.isHidden })
        print("Cached 1,000-note launch: synchronous index \(indexDuration); first laid-out notebook \(start.duration(to: .now)); no asynchronous yield or provider access")
        let opened = try await restarted.openForEditing(try #require(restarted.notes.first))
        #expect(opened.text == bodies[notes[0].url])
        #expect(opened.baselineText == bodies[notes[0].url])
        await restarted.refresh()
        await restarted.flushCatalogueCache()
    }

    @Test
    func cacheRemainsReadableButCannotGrantProviderAccessWhenBookmarkFails() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "drift-folder-invalid-bookmark-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let text = "Keep writing\nThe last saved baseline."
        let edited = text + " A local recovery edit."
        let url = folder.appendingPathComponent("Keep writing.md")
        try text.write(to: url, atomically: true, encoding: .utf8)
        let initial = NoteStore(folderURL: folder, defaults: defaults)
        await initial.refresh()
        await initial.flushCatalogueCache()
        // Even a paired cached path is not a permission grant. The deliberately
        // unusable bookmark must prevent reads/writes to this real local file.
        FolderBookmark.save(Data("invalid bookmark".utf8), folder: folder, in: defaults)
        let restarted = NoteStore(defaults: defaults)
        #expect(restarted.hasLoadedCatalogue)
        let opened = try await restarted.openForEditing(try #require(restarted.notes.first))
        #expect(opened.text == text)
        await restarted.refresh()
        #expect(restarted.requiresFolderSelection)
        #expect(restarted.notes.count == 1)
        #expect(restarted.errorMessage?.contains("Choose") == true)
        try await restarted.persistDraft(edited, snapshot: opened)
        do {
            _ = try await restarted.save(edited, snapshot: opened)
            Issue.record("A cached folder path must not authorize a provider write")
        } catch {
            #expect(try String(contentsOf: url, encoding: .utf8) == text)
        }
        let recovered = try await restarted.openForEditing(opened.note)
        #expect(recovered.text == edited)
        #expect(recovered.baselineText == text)
        #expect(recovered.recoveredDraft)

        // Reselecting the real folder restores access and retains local edits.
        try await restarted.setFolder(folder)
        #expect(!restarted.requiresFolderSelection)
        let saved = try await restarted.save(edited, snapshot: recovered)
        #expect(try String(contentsOf: saved.snapshot.note.url, encoding: .utf8) == edited)
        await restarted.flushCatalogueCache()
    }

    @Test
    func rejectedFolderSelectionPreservesCurrentNotebookAndBookmark() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "drift-folder-rejected-selection-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = folder.appendingPathComponent("A note.md")
        try "A note\nStill here.".write(to: url, atomically: true, encoding: .utf8)
        let store = NoteStore(folderURL: folder, defaults: defaults)
        try await store.setFolder(folder)
        let bookmark = defaults.data(forKey: FolderBookmark.key)
        do {
            try await store.setFolder(url)
            Issue.record("A regular file must not replace the notes folder")
        } catch {
            #expect(store.folderURL == folder)
            #expect(store.notes.map(\.url) == [url])
            #expect(defaults.data(forKey: FolderBookmark.key) == bookmark)
        }
        #expect(try await store.open(try #require(store.notes.first)).text == "A note\nStill here.")
        await store.flushCatalogueCache()
    }

    @Test
    func cachedFolderIdentityCannotOutliveItsPermissionBookmark() throws {
        let suite = "drift-folder-identity-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = URL(fileURLWithPath: "/a/local/cache/key", isDirectory: true)
        FolderBookmark.save(Data("first bookmark".utf8), folder: folder, in: defaults)
        #expect(FolderBookmark.cachedFolder(in: defaults) == folder)
        defaults.set(Data("different bookmark".utf8), forKey: FolderBookmark.key)
        #expect(FolderBookmark.cachedFolder(in: defaults) == nil)
        defaults.removeObject(forKey: FolderBookmark.key)
        #expect(FolderBookmark.cachedFolder(in: defaults) == nil)
    }

    @Test
    func permissionRecoveryRecognizesProviderWrappedPermissionFailures() {
        let underlying = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        let wrapped = NSError(domain: "FileProvider", code: 1,
                              userInfo: [NSUnderlyingErrorKey: underlying])
        #expect(FolderBookmark.isPermissionError(wrapped))
        #expect(!FolderBookmark.isPermissionError(NSError(domain: NSCocoaErrorDomain,
                                                         code: NSFileReadNoSuchFileError)))
    }

    @Test
    func localDraftOpensWhenOnlyTheLaunchIndexSurvivesAndBookmarkFails() async throws {
        let fm = FileManager.default
        let folder = try temporaryFolder()
        defer { try? fm.removeItem(at: folder) }
        let suite = "drift-folder-index-draft-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = "Keep writing\nThe saved baseline."
        let pending = "Keep writing\nThe local recovery edit."
        let url = folder.appendingPathComponent("Keep writing.md")
        try original.write(to: url, atomically: true, encoding: .utf8)
        let initial = NoteStore(folderURL: folder, defaults: defaults)
        await initial.refresh()
        let snapshot = try await initial.open(try #require(initial.notes.first))
        try await initial.persistDraft(pending, snapshot: snapshot)
        await initial.flushCatalogueCache()

        // iOS may purge individual cache files while retaining the launch index.
        let caches = try fm.url(for: .cachesDirectory, in: .userDomainMask,
                                 appropriateFor: nil, create: false)
        let key = FolderIdentity.cacheKey(for: folder)
        let bodyCache = caches.appendingPathComponent("Drift/Catalogues", isDirectory: true)
            .appendingPathComponent("\(key).json")
        try fm.removeItem(at: bodyCache)
        #expect(CatalogueCache.loadIndex(folder: folder)?.notes.map(\.url) == [url])
        FolderBookmark.save(Data("invalid bookmark".utf8), folder: folder, in: defaults)

        let restarted = NoteStore(defaults: defaults)
        #expect(restarted.hasLoadedCatalogue)
        #expect(restarted.notes.map(\.url) == [url])
        await restarted.refresh()
        #expect(restarted.requiresFolderSelection)
        let recovered = try await restarted.openForEditing(try #require(restarted.notes.first))
        #expect(recovered.text == pending)
        #expect(recovered.baselineText == original)
        #expect(recovered.documentID == snapshot.documentID)
        #expect(recovered.recoveredDraft)
        #expect(try String(contentsOf: url, encoding: .utf8) == original)
        await restarted.flushCatalogueCache()

        try await restarted.setFolder(folder)
        let saved = try await restarted.save(recovered.text, snapshot: recovered)
        #expect(!saved.preservedConflict)
        #expect(try String(contentsOf: saved.snapshot.note.url, encoding: .utf8) == pending)
        await restarted.flushCatalogueCache()
    }
}
