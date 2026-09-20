import XCTest
@testable import Drift

@MainActor
final class EmptyComposerCleanupTests: XCTestCase {
    private var folder: URL!
    private var store: NoteStore!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("empty-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        store = NoteStore(folderURL: folder)
        await store.refresh()
    }

    override func tearDown() async throws {
        await store.flushCatalogueCache()
        try? FileManager.default.removeItem(at: folder)
    }

    private func savedEmpty() async throws -> NoteSnapshot {
        let session = EditorDocumentSession(store: store, snapshot: try await store.makeUnsavedNote())
        session.changed("A passing thought")
        await session.flush()
        session.changed("")
        await session.flush()
        XCTAssertFalse(session.isDirty)
        XCTAssertEqual(session.status, .saved)
        return session.snapshot
    }

    func testCancellationRestoresExactRowAndLeavesOtherEmptyNotesVisible() async throws {
        let existing = try await store.createNote()
        let candidate = try await savedEmpty()
        let token = try XCTUnwrap(store.beginEmptyComposerReturn(candidate, currentText: ""))
        XCTAssertEqual(store.notes.count, 2, "Projection must not mutate the durable catalogue")
        XCTAssertEqual(store.search("").map(\.note.url), [existing.note.url])
        store.cancelEmptyComposerReturn(token)
        XCTAssertEqual(Set(store.search("").map(\.note.url)), Set([candidate.note.url, existing.note.url]))
        XCTAssertEqual(try String(contentsOf: candidate.note.url, encoding: .utf8), "")
    }

    func testPendingLastDeletionFollowsOwnSaveRenameWithoutHidingAnotherNote() async throws {
        let existing = try await store.createNote()
        let session = EditorDocumentSession(store: store, snapshot: try await store.makeUnsavedNote())
        session.changed("Original title")
        await session.flush()
        let titledURL = session.snapshot.note.url
        session.changed("")
        let token = try XCTUnwrap(store.beginEmptyComposerReturn(session.snapshot, currentText: session.text))
        XCTAssertEqual(store.search("").map(\.note.url), [existing.note.url])
        await session.flush()
        XCTAssertNotEqual(session.snapshot.note.url, titledURL)
        XCTAssertEqual(store.search("").map(\.note.url), [existing.note.url], "Omission must follow this session's title rename")
        let removed = try await store.trashUnchangedEmptyComposer(session.snapshot)
        XCTAssertTrue(removed)
        store.cancelEmptyComposerReturn(token)
        XCTAssertEqual(store.notes.map(\.url), [existing.note.url])
        XCTAssertTrue(FileManager.default.fileExists(atPath: existing.note.url.path))
    }

    func testNonemptyExternalChangeRestoresRowAndCannotBeTrashed() async throws {
        let candidate = try await savedEmpty()
        let token = try XCTUnwrap(store.beginEmptyComposerReturn(candidate, currentText: ""))
        defer { store.cancelEmptyComposerReturn(token) }
        try "Another device's thought".write(to: candidate.note.url, atomically: true, encoding: .utf8)
        let removed = try await store.trashUnchangedEmptyComposer(candidate)
        XCTAssertFalse(removed)
        XCTAssertEqual(try String(contentsOf: candidate.note.url, encoding: .utf8), "Another device's thought")
        XCTAssertEqual(store.search("").map(\.note.url), [candidate.note.url])
        XCTAssertFalse(store.canUndoTrash)
    }

    func testReplacementEmptyVersionIsPreserved() async throws {
        let candidate = try await savedEmpty()
        try "".write(to: candidate.note.url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: candidate.note.modified.addingTimeInterval(10)], ofItemAtPath: candidate.note.url.path)
        let removed = try await store.trashUnchangedEmptyComposer(candidate)
        XCTAssertFalse(removed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: candidate.note.url.path))
        XCTAssertEqual(store.notes.count, 1)
    }

    func testPendingRecoveryPreventsAutomaticTrash() async throws {
        let candidate = try await savedEmpty()
        let otherSession = NoteSnapshot(note: candidate.note, text: candidate.text)
        try await store.persistDraft("Unfinished writing in another editor", snapshot: otherSession)
        let removed = try await store.trashUnchangedEmptyComposer(candidate)
        XCTAssertFalse(removed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: candidate.note.url.path))
        let recovered = try await store.open(candidate.note)
        XCTAssertEqual(recovered.text, "Unfinished writing in another editor")
        XCTAssertTrue(recovered.recoveredDraft)
        try await store.discardDraft(snapshot: otherSession)
    }

    func testRecoveredEmptyOverlayCannotDeleteNonemptyDisk() async throws {
        let candidate = try await savedEmpty()
        try "Shared writing".write(to: candidate.note.url, atomically: true, encoding: .utf8)
        try await store.persistDraft("", snapshot: candidate)
        let recovered = try await store.open(candidate.note)
        XCTAssertTrue(recovered.recoveredDraft)
        XCTAssertEqual(recovered.text, "")
        XCTAssertNil(store.beginEmptyComposerReturn(recovered, currentText: ""))
        let removed = try await store.trashUnchangedEmptyComposer(recovered)
        XCTAssertFalse(removed)
        XCTAssertEqual(try String(contentsOf: candidate.note.url, encoding: .utf8), "Shared writing")
        try await store.discardDraft(snapshot: candidate)
    }

    func testConflictWhileDeletionSavesPreservesBothBranchesAndRestoresProjection() async throws {
        let session = EditorDocumentSession(store: store, snapshot: try await store.makeUnsavedNote())
        session.changed("A first thought")
        await session.flush()
        let originalURL = session.snapshot.note.url
        session.changed("")
        let token = try XCTUnwrap(store.beginEmptyComposerReturn(session.snapshot, currentText: ""))
        defer { store.cancelEmptyComposerReturn(token) }
        try "Collaborator's writing".write(to: originalURL, atomically: true, encoding: .utf8)
        await session.flush()
        XCTAssertEqual(session.status, .conflict)
        XCTAssertEqual(store.search("").count, 2, "A conflict invalidates optimistic omission")
        XCTAssertEqual(try String(contentsOf: originalURL, encoding: .utf8), "Collaborator's writing")
        XCTAssertEqual(try String(contentsOf: session.snapshot.note.url, encoding: .utf8), "")
        XCTAssertFalse(store.canUndoTrash)
    }

    func testFirstSaveInFlightFollowsMaterializationAndLastDeletion() async throws {
        let session = EditorDocumentSession(store: store, snapshot: try await store.makeUnsavedNote())
        session.changed("In flight")
        let blockedURL = folder.appendingPathComponent("In flight.md")
        let barrier = EmptyComposerWriteBarrier(url: blockedURL)
        defer { barrier.release() }
        await barrier.waitUntilHolding()
        XCTAssertTrue(barrier.isHolding)
        let saving = Task { await session.flush() }
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(session.isSaving)
        XCTAssertTrue(session.snapshot.isUnsaved)
        session.changed("")
        let token = try XCTUnwrap(store.beginEmptyComposerReturn(session.snapshot, currentText: session.text))
        defer { store.cancelEmptyComposerReturn(token) }
        var visibleCounts: [Int] = []
        let observer = NotificationCenter.default.addObserver(forName: NoteStore.didChange, object: store, queue: .main) { [store] _ in
            MainActor.assumeIsolated { visibleCounts.append(store!.search("").count) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        barrier.release()
        await saving.value
        XCTAssertFalse(session.snapshot.isUnsaved)
        XCTAssertEqual(session.status, .saved)
        XCTAssertEqual(session.text, "")
        XCTAssertFalse(visibleCounts.isEmpty)
        XCTAssertEqual(Set(visibleCounts), [0], "Neither the transient title nor renamed empty file may be published during this return")
        let removed = try await store.trashUnchangedEmptyComposer(session.snapshot)
        XCTAssertTrue(removed)
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: blockedURL.path))
    }

    func testCleanupReadFailureRestoresPresentationAndPreservesFile() async throws {
        let candidate = try await savedEmpty()
        let token = try XCTUnwrap(store.beginEmptyComposerReturn(candidate, currentText: ""))
        let archived = folder.appendingPathComponent("Still safe.md")
        try FileManager.default.moveItem(at: candidate.note.url, to: archived)
        try FileManager.default.createDirectory(at: candidate.note.url, withIntermediateDirectories: false)
        do {
            _ = try await store.trashUnchangedEmptyComposer(candidate)
            XCTFail("Reading a directory as a note must fail, not establish emptiness")
        } catch {}
        store.cancelEmptyComposerReturn(token)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archived.path))
        XCTAssertEqual(store.search("").count, 1, "Failure rolls back the optimistic row omission")
        XCTAssertFalse(store.canUndoTrash)
    }

    func testRecoveryArrivingWhileCleanupWaitsForCoordinationPreventsMove() async throws {
        let candidate = try await savedEmpty()
        let competing = NoteSnapshot(note: candidate.note, text: candidate.text)
        let barrier = EmptyComposerWriteBarrier(url: candidate.note.url)
        defer { barrier.release() }
        await barrier.waitUntilHolding()
        XCTAssertTrue(barrier.isHolding)
        let cleanup = Task { try await store.trashUnchangedEmptyComposer(candidate) }
        try await Task.sleep(for: .milliseconds(80))
        // Journaling must remain independent while provider coordination waits.
        try await store.persistDraft("Writing during cleanup", snapshot: competing)
        barrier.release()
        let removed = try await cleanup.value
        XCTAssertFalse(removed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: candidate.note.url.path))
        let recovered = try await store.open(candidate.note)
        XCTAssertEqual(recovered.text, "Writing during cleanup")
        XCTAssertEqual(store.search("").count, 1)
        try await store.discardDraft(snapshot: competing)
    }

    func testLateRecoveryRemainsAtActiveURLAfterEmptyFileMovedAndCanBeSaved() async throws {
        let candidate = try await savedEmpty()
        let competing = NoteSnapshot(note: candidate.note, text: candidate.text)
        let removed = try await store.trashUnchangedEmptyComposer(candidate)
        XCTAssertTrue(removed)
        // Deterministically exercise the late side of the race: another editor
        // journals after the empty-file decision, using its original identity.
        try await store.persistDraft("A late thought worth keeping", snapshot: competing)
        await store.refresh()
        let row = try XCTUnwrap(store.search("").first?.note)
        XCTAssertEqual(row.url, candidate.note.url, "No journal/alias may follow automatic cleanup into hidden trash")
        let recovered = try await store.open(row)
        XCTAssertTrue(recovered.recoveredDraft)
        XCTAssertEqual(recovered.text, "A late thought worth keeping")
        let result = try await store.save(recovered.text, snapshot: recovered)
        XCTAssertEqual(try String(contentsOf: result.snapshot.note.url, encoding: .utf8), "A late thought worth keeping")
        XCTAssertEqual(result.snapshot.note.url.deletingLastPathComponent(), folder)
        XCTAssertTrue(store.search("").contains(where: { $0.note.url == result.snapshot.note.url }))
    }

    func testUntouchedFastTypeDeleteRemainsUnmaterialized() async throws {
        let session = EditorDocumentSession(store: store, snapshot: try await store.makeUnsavedNote())
        session.changed("x")
        session.changed("")
        let token = try XCTUnwrap(store.beginEmptyComposerReturn(session.snapshot, currentText: ""))
        await session.flush()
        store.cancelEmptyComposerReturn(token)
        XCTAssertTrue(session.snapshot.isUnsaved)
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.snapshot.note.url.path))
    }
}

private final class EmptyComposerWriteBarrier: @unchecked Sendable {
    private let signal = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var holding = false
    init(url: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &error) { _ in
                lock.lock(); holding = true; lock.unlock()
                _ = signal.wait(timeout: .now() + 5)
                lock.lock(); holding = false; lock.unlock()
            }
        }
    }
    var isHolding: Bool { lock.lock(); defer { lock.unlock() }; return holding }
    func release() { signal.signal() }
    func waitUntilHolding() async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !isHolding && ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
    }
}
