import Foundation
import CryptoKit
import Testing
@testable import Drift

@MainActor
struct PinTests {
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-pin-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func seed(_ text: String, name: String, folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func load(_ folder: URL) async -> NoteStore {
        let store = NoteStore(folderURL: folder)
        await store.refresh()
        return store
    }

    @Test
    func filenamePinsAreCaseInsensitiveAndHiddenFromFallbackTitles() {
        let url = URL(fileURLWithPath: "/notebook/A thought.PINNED.MD")
        #expect(Note.isPinned(url))
        #expect(Note.filenameTitle(url) == "A thought")
        #expect(!Note.isPinned(URL(fileURLWithPath: "/notebook/A thought.pinned 1.md")))
        #expect(!Note.isPinned(URL(fileURLWithPath: "/notebook/A thought.pinned.txt")))
    }

    @Test
    func pinAndUnpinMoveTheFileWithoutChangingTextOrModificationDate() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let text = "# A thought\nA shared thought.\n"
        let source = try seed(text, name: "A thought.md", folder: folder)
        let date = Date(timeIntervalSince1970: 1_000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: source.path)
        let store = await load(folder)
        let original = try #require(store.notes.first)

        let pinned = try await store.setPinned(true, for: original)
        #expect(pinned.url.lastPathComponent == "A thought.pinned.md")
        #expect(pinned.isPinned)
        #expect(pinned.modified == original.modified)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try String(contentsOf: pinned.url, encoding: .utf8) == text)
        #expect(try pinned.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == date)
        let restarted = await load(folder)
        #expect(restarted.notes.first?.isPinned == true)
        #expect(restarted.notes.first?.title == "A thought")

        let unpinned = try await restarted.setPinned(false, for: try #require(restarted.notes.first))
        #expect(unpinned.url == source)
        #expect(!unpinned.isPinned)
        #expect(try String(contentsOf: source, encoding: .utf8) == text)
        #expect(restarted.notes.count == 1)
    }

    @Test
    func collisionsNeverOverwriteAndKeepTheMarkerAtTheEnd() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try seed("Thought\nMine", name: "Thought.md", folder: folder)
        let occupied = try seed("Thought\nThe other note", name: "Thought.pinned.md", folder: folder)
        let store = await load(folder)
        let pinned = try await store.setPinned(true, for: try #require(store.notes.first { $0.url == source }))
        #expect(pinned.url.lastPathComponent == "Thought 2.pinned.md")
        #expect(try String(contentsOf: occupied, encoding: .utf8) == "Thought\nThe other note")

        let occupiedUnpinned = try seed("Keep me", name: "Thought 2.md", folder: folder)
        let unpinned = try await store.setPinned(false, for: pinned)
        #expect(unpinned.url.lastPathComponent == "Thought 2 2.md")
        #expect(!unpinned.isPinned)
        #expect(try String(contentsOf: occupiedUnpinned, encoding: .utf8) == "Keep me")
    }

    @Test
    func titleEditsAndConflictRecoveryRetainThePin() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try seed("Original\nFirst body", name: "Original.pinned.md", folder: folder)
        _ = try seed("Renamed\nOther note", name: "Renamed.pinned.md", folder: folder)
        let store = await load(folder)
        let original = try await store.open(try #require(store.notes.first { $0.url == source }))
        let renamed = try await store.save("Renamed\nSecond body", snapshot: original)
        #expect(renamed.snapshot.note.url.lastPathComponent == "Renamed 2.pinned.md")
        let bodyEdited = try await store.save("Renamed\nThird body", snapshot: renamed.snapshot)
        #expect(bodyEdited.snapshot.note.url == renamed.snapshot.note.url)

        try "Renamed\nExternal writing".write(to: bodyEdited.snapshot.note.url, atomically: true, encoding: .utf8)
        let recovered = try await store.save("Renamed\nMy writing", snapshot: bodyEdited.snapshot)
        #expect(recovered.preservedConflict)
        #expect(recovered.snapshot.note.isPinned)
        #expect(recovered.snapshot.note.url.lastPathComponent.contains(" (Recovered "))
        #expect(try String(contentsOf: bodyEdited.snapshot.note.url, encoding: .utf8) == "Renamed\nExternal writing")
    }

    @Test
    func literalPinMarkerInATitleDoesNotPinAnOrdinaryNote() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = await load(folder)
        let composer = try await store.makeUnsavedNote()
        let saved = try await store.save("A literal.pinned\nSome text", snapshot: composer)
        #expect(saved.snapshot.note.url.lastPathComponent == "A literal.pinned 1.md")
        #expect(!saved.snapshot.note.isPinned)
        #expect(saved.snapshot.note.title == "A literal.pinned")
        let renamed = try await store.save("Another.PINNED\nSome text", snapshot: saved.snapshot)
        #expect(!renamed.snapshot.note.isPinned)
        #expect(renamed.snapshot.note.url.lastPathComponent == "Another.PINNED 1.md")
    }

    @Test
    func pinsOrderTheListButDoNotChangeSearchRecency() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try seed("Earlier\nCommon phrase", name: "Earlier.pinned.md", folder: folder)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: source.path)
        _ = try seed("Later\nCommon phrase", name: "Later.md", folder: folder)
        let store = await load(folder)
        #expect(store.notes.map(\.title) == ["Earlier", "Later"])
        #expect(store.search("").map(\.note.title) == ["Earlier", "Later"])
        #expect(store.search("Common").map(\.note.title) == ["Later", "Earlier"])
        await store.flushCatalogueCache()
        let cache = try #require(await CatalogueCache.shared.load(folder: folder))
        #expect(cache.notes.first?.isPinned == true)

        let unpinned = folder.appendingPathComponent("Earlier.md")
        try FileManager.default.moveItem(at: source, to: unpinned)
        await store.refresh()
        #expect(store.notes.map(\.title) == ["Later", "Earlier"])
        #expect(store.notes.allSatisfy { !$0.isPinned })
    }

    @Test
    func pinIsAvailableWithoutAReadableNoteBody() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("An offline thought.pinned.md")
        let bytes = Data([0xff, 0xfe])
        try bytes.write(to: source)
        let store = await load(folder)
        let note = try #require(store.notes.first)
        #expect(note.isPinned)
        #expect(note.title == "An offline thought")
        let unpinned = try await store.setPinned(false, for: note)
        #expect(!unpinned.isPinned)
        #expect(try Data(contentsOf: unpinned.url) == bytes)
    }

    @Test
    func pendingDraftAndLateSaveFollowThePinRename() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try seed("Original\nSaved text", name: "Original.md", folder: folder)
        let store = await load(folder)
        let original = try await store.open(try #require(store.notes.first))
        try await store.persistDraft("Changed\nPending writing", snapshot: original)
        let pinned = try await store.setPinned(true, for: original.note)
        let restarted = await load(folder)
        let recovered = try await restarted.open(try #require(restarted.notes.first))
        #expect(recovered.recoveredDraft)
        #expect(recovered.documentID == original.documentID)
        #expect(recovered.text == "Changed\nPending writing")
        #expect(recovered.baselineText == original.text)
        #expect(recovered.note.url == pinned.url)

        let saved = try await store.save("Changed\nPending writing", snapshot: original)
        #expect(!saved.preservedConflict)
        #expect(saved.snapshot.note.url.lastPathComponent == "Changed.pinned.md")
        #expect(store.notes.count == 1)
        #expect(!FileManager.default.fileExists(atPath: pinned.url.path))
    }

    @Test
    func staleSaveAfterPinningStillPreservesANewerSavedVersion() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try seed("Thought\nOriginal", name: "Thought.md", folder: folder)
        let store = await load(folder)
        let original = try await store.open(try #require(store.notes.first))
        try await store.persistDraft("Thought\nFirst edit", snapshot: original)
        _ = try await store.setPinned(true, for: original.note)
        let saved = try await store.save("Thought\nFirst edit", snapshot: original)
        let stale = try await store.save("Thought\nA stale branch", snapshot: original)
        #expect(stale.preservedConflict)
        #expect(stale.snapshot.note.isPinned)
        #expect(stale.snapshot.note.url != saved.snapshot.note.url)
        #expect(try String(contentsOf: saved.snapshot.note.url, encoding: .utf8) == "Thought\nFirst edit")
    }

    @Test
    func failedDraftRelocationLeavesPinRetryableAndTheWritingRecoverable() async throws {
        let fm = FileManager.default
        let folder = try makeFolder()
        defer { try? fm.removeItem(at: folder) }
        let source = try seed("Thought\nSaved", name: "Thought.md", folder: folder)
        let destination = folder.appendingPathComponent("Thought.pinned.md")
        let store = await load(folder)
        let snapshot = try await store.open(try #require(store.notes.first))
        try await store.persistDraft("Thought\nNew writing", snapshot: snapshot)
        let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                 appropriateFor: nil, create: true)
        let hash = SHA256.hash(data: Data(destination.standardizedFileURL.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let obstruction = support.appendingPathComponent("Drift/Drafts", isDirectory: true)
            .appendingPathComponent("\(hash).\(snapshot.documentID.uuidString).json")
        try fm.createDirectory(at: obstruction, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: obstruction) }
        do {
            _ = try await store.setPinned(true, for: snapshot.note)
            Issue.record("Pinning must fail when recovery cannot move safely")
        } catch { }
        #expect(fm.fileExists(atPath: source.path))
        #expect(!fm.fileExists(atPath: destination.path))
        let restarted = await load(folder)
        let recovered = try await restarted.open(try #require(restarted.notes.first))
        #expect(recovered.text == "Thought\nNew writing")
        #expect(recovered.baselineText == "Thought\nSaved")
        #expect(recovered.documentID == snapshot.documentID)
        try fm.removeItem(at: obstruction)
        let pinned = try await restarted.setPinned(true, for: recovered.note)
        #expect(pinned.isPinned)
        #expect(try await restarted.open(pinned).text == "Thought\nNew writing")
    }

    @Test
    func trashUndoPreservesPinsThroughFilenameCollisions() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try seed("Thought\nOriginal", name: "Thought.pinned.md", folder: folder)
        let store = await load(folder)
        try await store.trash(try #require(store.notes.first))
        let occupied = try seed("Thought\nDifferent", name: "Thought.pinned.md", folder: folder)
        try await store.undoTrash()
        #expect(store.notes.count == 2)
        #expect(store.notes.allSatisfy { $0.isPinned })
        #expect(store.notes.contains { $0.url.lastPathComponent == "Thought 2.pinned.md" })
        #expect(try String(contentsOf: occupied, encoding: .utf8) == "Thought\nDifferent")
    }

    @Test
    func stalePinActionsDoNotRecreateMovedOrMissingFiles() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try seed("Thought", name: "Thought.md", folder: folder)
        let store = await load(folder)
        let original = try #require(store.notes.first)
        let pinned = try await store.setPinned(true, for: original)
        do {
            _ = try await store.setPinned(true, for: original)
            Issue.record("A stale menu target must fail after its file moves")
        } catch { }
        #expect(store.notes.count == 1)
        #expect(!FileManager.default.fileExists(atPath: original.url.path))
        try FileManager.default.removeItem(at: pinned.url)
        do {
            _ = try await store.setPinned(false, for: pinned)
            Issue.record("A missing file must not be recreated by unpinning")
        } catch { }
        #expect(try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).isEmpty)
    }
}
