import Foundation
import CryptoKit
import Testing
@testable import Drift

@MainActor
struct LaunchCacheRegressionTests {
    private struct CacheFiles {
        let body: URL
        let durableIndex: URL
        let legacyBody: URL
        let legacyIndex: URL

        func purgeDisposableFiles() throws {
            let fm = FileManager.default
            for url in Set([body, legacyBody, legacyIndex]) where fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
        }

        func removeFixtureFiles() {
            try? purgeDisposableFiles()
            try? FileManager.default.removeItem(at: durableIndex)
        }
    }

    private func cacheFiles(for folder: URL) throws -> CacheFiles {
        let fm = FileManager.default
        let caches = try fm.url(for: .cachesDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true)
            .appendingPathComponent("Drift/Catalogues", isDirectory: true)
        let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                 appropriateFor: nil, create: true)
            .appendingPathComponent("Drift/LaunchIndexes", isDirectory: true)
        let key = FolderIdentity.cacheKey(for: folder)
        let legacyKey = SHA256.hash(data: Data(folder.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return CacheFiles(body: caches.appendingPathComponent("\(key).json"),
                          durableIndex: support.appendingPathComponent("\(key).json"),
                          legacyBody: caches.appendingPathComponent("\(legacyKey).json"),
                          legacyIndex: caches.appendingPathComponent("\(legacyKey).index.json"))
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-launch-cache-regression-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test
    func bodyCacheWriteFailureDoesNotPreventTheNextLaunchIndex() async throws {
        let fm = FileManager.default
        let folder = try temporaryFolder()
        defer { try? fm.removeItem(at: folder) }
        let suite = "drift-launch-cache-regression-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let noteURL = folder.appendingPathComponent("Synthetic launch note.md")
        try "Synthetic launch note\nA disposable test fixture.".write(to: noteURL, atomically: true, encoding: .utf8)

        // A deterministic body-cache-only failure: its file destination is a
        // directory, while the independent launch index remains writable. The key
        // contains a fresh fixture UUID; no existing cache is touched.
        let files = try cacheFiles(for: folder)
        try fm.createDirectory(at: files.body, withIntermediateDirectories: true)
        defer { files.removeFixtureFiles() }

        let first = NoteStore(folderURL: folder, defaults: defaults)
        try await first.setFolder(folder)
        await first.flushCatalogueCache()
        #expect(first.notes.map(\.url) == [noteURL])

        // Every launch should have the lightweight rows even when the optional
        // body snapshot cannot be written. Do not yield before inspecting them.
        let second = NoteStore(defaults: defaults)
        #expect(second.hasLoadedCatalogue)
        #expect(second.notes.map(\.url) == [noteURL])
        await second.refresh()
        await second.flushCatalogueCache()
        let third = NoteStore(defaults: defaults)
        #expect(third.hasLoadedCatalogue)
        #expect(third.notes.map(\.url) == [noteURL])
        await third.refresh()
        await third.flushCatalogueCache()
    }

    @Test
    func purgingDisposableCachesKeepsRowsAvailableBeforeStartupWork() async throws {
        let fm = FileManager.default
        let folder = try temporaryFolder()
        defer { try? fm.removeItem(at: folder) }
        let files = try cacheFiles(for: folder)
        defer { files.removeFixtureFiles() }
        let suite = "drift-launch-cache-purge-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let noteURL = folder.appendingPathComponent("Synthetic cached row.md")
        try "Synthetic cached row\nA disposable fixture.".write(to: noteURL, atomically: true, encoding: .utf8)
        let first = NoteStore(folderURL: folder, defaults: defaults)
        try await first.setFolder(folder)
        await first.flushCatalogueCache()
        #expect(fm.fileExists(atPath: files.body.path))
        #expect(fm.fileExists(atPath: files.durableIndex.path))

        // Delete only this fixture's files beneath Caches. The opening index
        // must survive independently, just as it should survive an OS purge.
        try files.purgeDisposableFiles()
        #expect(!fm.fileExists(atPath: files.body.path))
        let second = NoteStore(defaults: defaults)
        #expect(second.hasLoadedCatalogue)
        #expect(second.notes.map(\.url) == [noteURL])
        #expect(!second.isLoading)
        await second.refresh()
        await second.flushCatalogueCache()
    }

    @Test
    func legacyOpeningIndexMigratesBeforeTheDisposableCacheIsPurged() async throws {
        let fm = FileManager.default
        let folder = try temporaryFolder()
        defer { try? fm.removeItem(at: folder) }
        let files = try cacheFiles(for: folder)
        defer { files.removeFixtureFiles() }
        let suite = "drift-launch-cache-migration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let noteURL = folder.appendingPathComponent("Synthetic legacy row.md")
        let note = Note(url: noteURL, modified: Date(timeIntervalSince1970: 1_700_000_000),
                        title: "Synthetic legacy row", preview: "A cached fixture, with no provider file.")
        let legacy = CachedCatalogue(folderURL: folder, notes: [note], bodies: [:], canUndoTrash: false)
        try fm.createDirectory(at: files.legacyIndex.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(legacy).write(to: files.legacyIndex, options: [.atomic])
        #expect(!fm.fileExists(atPath: files.durableIndex.path))
        FolderBookmark.save(Data("unresolved synthetic bookmark".utf8), folder: folder, in: defaults)

        // Upgrade reading must find the old URL-based cache without waiting for
        // bookmark resolution. Its normal local checkpoint performs migration.
        let first = NoteStore(defaults: defaults)
        #expect(first.hasLoadedCatalogue)
        #expect(first.notes.map(\.url) == [noteURL])
        await first.refresh()
        await first.flushCatalogueCache()
        #expect(first.requiresFolderSelection)
        #expect(fm.fileExists(atPath: files.durableIndex.path))

        try files.purgeDisposableFiles()
        let second = NoteStore(defaults: defaults)
        #expect(second.hasLoadedCatalogue)
        #expect(second.notes.map(\.url) == [noteURL])
        await second.refresh()
        await second.flushCatalogueCache()
    }

    @Test
    func selectingSlashlessFolderKeepsSavedNoteIdentityAcrossBookmarkRestart() async throws {
        let fm = FileManager.default
        let folder = try temporaryFolder()
        defer { try? fm.removeItem(at: folder) }
        let slashless = try #require(URL(string: String(folder.absoluteString.dropLast())))
        let files = try cacheFiles(for: folder)
        defer { files.removeFixtureFiles() }
        let suite = "drift-launch-slashless-selection-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let noteURL = folder.appendingPathComponent("Synthetic stable row.md")
        let original = "Synthetic stable row\nBefore a disposable edit."
        let edited = "Synthetic stable row\nAfter a disposable edit."
        try original.write(to: noteURL, atomically: true, encoding: .utf8)

        let first = NoteStore(defaults: defaults)
        try await first.setFolder(slashless)
        #expect(first.folderURL == folder)
        #expect(first.notes.map(\.url) == [noteURL])
        let opened = try await first.open(try #require(first.notes.first))
        let saved = try await first.save(edited, snapshot: opened)
        #expect(saved.snapshot.note.url == noteURL)
        #expect(first.notes.map(\.url) == [noteURL])
        #expect(try String(contentsOf: noteURL, encoding: .utf8) == edited)
        await first.flushCatalogueCache()

        // Use the selected folder's persisted bookmark, as a real cold launch
        // does. Directory spelling must not empty the list or replace row IDs.
        let second = NoteStore(defaults: defaults)
        #expect(second.hasLoadedCatalogue)
        #expect(second.folderURL == folder)
        #expect(second.notes.map(\.url) == [noteURL])
        let cached = try await second.openForEditing(try #require(second.notes.first))
        #expect(cached.note.url == noteURL)
        #expect(cached.text == edited)
        #expect(cached.baselineText == edited)
        await second.refresh()
        #expect(second.notes.map(\.url) == [noteURL])
        await second.flushCatalogueCache()
    }

    @Test
    func newerOpeningIndexCannotBeReplacedByAnOlderBodySnapshot() async throws {
        let fm = FileManager.default
        let folder = try temporaryFolder()
        defer { try? fm.removeItem(at: folder) }
        let files = try cacheFiles(for: folder)
        defer { files.removeFixtureFiles() }
        let suite = "drift-launch-cache-interrupted-write-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let aURL = folder.appendingPathComponent("Synthetic A.md")
        let bURL = folder.appendingPathComponent("Synthetic B.md")
        let cURL = folder.appendingPathComponent("Synthetic C.md")
        let oldA = Note(url: aURL, modified: Date(timeIntervalSince1970: 1_700_000_000),
                        title: "Synthetic A", preview: "Old text")
        let deletedB = Note(url: bURL, modified: Date(timeIntervalSince1970: 1_699_999_999),
                            title: "Synthetic B", preview: "Deleted later")
        let unchangedC = Note(url: cURL, modified: Date(timeIntervalSince1970: 1_699_999_998),
                              title: "Synthetic C", preview: "Unchanged text")
        let newA = Note(url: aURL, modified: Date(timeIntervalSince1970: 1_700_000_060),
                        title: "Synthetic A", preview: "New text")
        let old = CachedCatalogue(folderURL: folder, notes: [oldA, deletedB, unchangedC],
                                   bodies: [aURL: "Synthetic A\nOld text", bURL: "Synthetic B\nDeleted later",
                                            cURL: "Synthetic C\nUnchanged text"], canUndoTrash: false)
        try await CatalogueCache.shared.store(old, sequence: CatalogueCache.reserveSequence())
        let oldBodyData = try Data(contentsOf: files.body)
        let updated = CachedCatalogue(folderURL: folder, notes: [newA, unchangedC],
                                       bodies: [aURL: "Synthetic A\nNew text", cURL: "Synthetic C\nUnchanged text"],
                                       canUndoTrash: true)
        try await CatalogueCache.shared.store(updated, sequence: CatalogueCache.reserveSequence())
        // Model termination between the index and full-body writes: the index
        // is newest, while the previous complete body snapshot remains on disk.
        try oldBodyData.write(to: files.body, options: [.atomic])
        FolderBookmark.save(Data("unresolved synthetic bookmark".utf8), folder: folder, in: defaults)

        let restarted = NoteStore(defaults: defaults)
        #expect(restarted.notes == [newA, unchangedC])
        #expect(restarted.canUndoTrash)
        await restarted.refresh()
        #expect(restarted.requiresFolderSelection)
        #expect(restarted.notes == [newA, unchangedC])
        #expect(restarted.canUndoTrash)
        let unchanged = try await restarted.openForEditing(unchangedC)
        #expect(unchanged.text == "Synthetic C\nUnchanged text")
        do {
            _ = try await restarted.openForEditing(newA)
            Issue.record("An older cached body must not masquerade as the updated index row")
        } catch {
            // The provider is deliberately inaccessible and the updated body
            // was interrupted; the stale body must not be used for editing.
        }
        await restarted.flushCatalogueCache()
    }
}
