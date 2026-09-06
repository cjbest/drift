import Foundation
import CryptoKit
import Testing
import UIKit
import XCTest
@testable import Drift

/// Exercises real files rather than substituting a filesystem that could conceal
/// failed writes, title collisions, or another device changing the same note.
@MainActor
struct NoteStoreTests {
    private func makeTempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func seed(_ text: String, named name: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func store(in folder: URL) async -> NoteStore {
        let store = NoteStore(folderURL: folder)
        await store.refresh()
        return store
    }

    private func contents(in folder: URL) throws -> [URL: String] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        var result: [URL: String] = [:]
        for url in urls where url.pathExtension.lowercased() == "md" {
            result[url] = try String(contentsOf: url, encoding: .utf8)
        }
        return result
    }

    private func cataloguePublishes(_ store: NoteStore, count: Int,
                                    while barrier: CoordinatedWriteBarrier) async -> Bool {
        while barrier.isHolding && (!store.hasLoadedCatalogue || store.notes.count != count) {
            await Task.yield()
        }
        return barrier.isHolding && store.hasLoadedCatalogue && store.notes.count == count
    }

    @Test
    func titlesFollowDesktopFilenameConvention() {
        #expect(Note.derive(from: "\n\n### A clear thought\n\nThe body.").title == "A clear thought")
        #expect(Note.derive(from: "a/b\\c:d?e").title == "abcde")
        #expect(Note.derive(from: String(repeating: "x", count: 80)).title.count == 50)
        #expect(Note.derive(from: "\n  \n").title == "Untitled")
        #expect(Note.derive(from: "###  ").title == "Untitled")
        #expect(Note.derive(from: "# Title\n\nThe body.\nMore.").preview == "The body.")
    }

    @Test
    func refreshLoadsMarkdownAndOrdersByModificationDate() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let older = try seed("# Earlier\nA first thought.", named: "a.md", in: folder)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: older.path
        )
        _ = try seed("# Later\nA new thought.", named: "b.MD", in: folder)
        _ = try seed("Ignored text file", named: "ignored.txt", in: folder)
        _ = try seed("Hidden draft", named: ".hidden.md", in: folder)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("directory.md"), withIntermediateDirectories: true
        )

        let store = await store(in: folder)

        #expect(store.notes.map(\.title) == ["Later", "Earlier"])
        #expect(store.notes.first?.preview == "A new thought.")
        #expect(!store.isLoading)
        #expect(store.errorMessage == nil)
    }

    @Test
    func creatingNotesNeverOverwritesAnExistingUntitledNote() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = await store(in: folder)
        let first = try await store.createNote()
        let second = try await store.createNote()

        #expect(first.note.url != second.note.url)
        #expect(first.text.isEmpty)
        #expect(second.text.isEmpty)
        #expect(store.notes.count == 2)
        #expect(try contents(in: folder).count == 2)
    }

    @Test
    func saveRoundTripsTextAndPersistsClearingTheEntireNote() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = await store(in: folder)
        let created = try await store.createNote()
        let text = "# A place to think\n\nCafé, 東京, and an unhurried afternoon.\n"
        let saved = try await store.save(text, snapshot: created)

        #expect(!saved.preservedConflict)
        #expect(saved.snapshot.text == text)
        #expect(saved.snapshot.note.title == "A place to think")
        #expect(try String(contentsOf: saved.snapshot.note.url, encoding: .utf8) == text)
        let reopened = try await store.open(saved.snapshot.note)
        #expect(reopened.text == text)

        let cleared = try await store.save("", snapshot: reopened)
        #expect(!cleared.preservedConflict)
        #expect(cleared.snapshot.text.isEmpty)
        #expect(try String(contentsOf: cleared.snapshot.note.url, encoding: .utf8).isEmpty)
        let reloadedStore = await self.store(in: folder)
        let emptyNote = try #require(reloadedStore.notes.first)
        let reloaded = try await reloadedStore.open(emptyNote)
        #expect(reloaded.text.isEmpty)
        #expect(reloadedStore.notes.count == 1)
    }

    @Test
    func titleRenamePreservesOtherFilesAndCollisionSuffixStaysStable() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let existingURL = try seed("Hello\nExisting note", named: "Hello.md", in: folder)
        let store = await store(in: folder)
        let created = try await store.createNote()
        let firstSave = try await store.save("# Hello\nFirst version", snapshot: created)
        let secondSave = try await store.save("# Hello\nSecond version", snapshot: firstSave.snapshot)
        let thirdSave = try await store.save("# Hello\nThird version", snapshot: secondSave.snapshot)

        #expect(firstSave.snapshot.note.url != existingURL)
        #expect(firstSave.snapshot.note.url.lastPathComponent == "Hello 2.md")
        #expect(secondSave.snapshot.note.url == firstSave.snapshot.note.url)
        #expect(thirdSave.snapshot.note.url == firstSave.snapshot.note.url)
        #expect(try String(contentsOf: existingURL, encoding: .utf8) == "Hello\nExisting note")
        #expect(try contents(in: folder).count == 2)
        #expect(!FileManager.default.fileExists(atPath: created.note.url.path))
    }

    @Test
    func externalEditPreservesBothVersionsInsteadOfOverwriting() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let originalURL = try seed("Shared note\nOriginal", named: "Shared note.md", in: folder)
        let store = await store(in: folder)
        let original = try await store.open(try #require(store.notes.first))
        let externalText = "Shared note\nChanged on the Mac"
        try externalText.write(to: originalURL, atomically: true, encoding: .utf8)
        let localText = "Shared note\nChanged on the phone"

        let saved = try await store.save(localText, snapshot: original)

        #expect(saved.preservedConflict)
        #expect(saved.snapshot.note.url != originalURL)
        #expect(saved.snapshot.text == localText)
        #expect(try String(contentsOf: originalURL, encoding: .utf8) == externalText)
        #expect(Set(try contents(in: folder).values) == Set([externalText, localText]))
        let next = try await store.save(localText + "\nMore on the phone", snapshot: saved.snapshot)
        #expect(!next.preservedConflict)
        #expect(next.snapshot.note.url == saved.snapshot.note.url)
        #expect(try String(contentsOf: originalURL, encoding: .utf8) == externalText)
    }

    @Test
    func unchangedTextDoesNotOverwriteAnExternalEdit() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let originalURL = try seed("Shared\nOriginal", named: "Shared.md", in: folder)
        let store = await store(in: folder)
        let opened = try await store.open(try #require(store.notes.first))
        let external = "Shared\nA more recent edit"
        try external.write(to: originalURL, atomically: true, encoding: .utf8)

        _ = try await store.save(opened.text, snapshot: opened)

        #expect(try String(contentsOf: originalURL, encoding: .utf8) == external)
    }

    @Test
    func externallyDeletedNotePreservesNewLocalWritingInASeparateFile() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let originalURL = try seed("Shared\nOriginal", named: "Shared.md", in: folder)
        let store = await store(in: folder)
        let opened = try await store.open(try #require(store.notes.first))
        try FileManager.default.removeItem(at: originalURL)

        let saved = try await store.save("Shared\nStill writing on my phone", snapshot: opened)

        #expect(saved.preservedConflict)
        #expect(saved.snapshot.note.url != originalURL)
        #expect(!FileManager.default.fileExists(atPath: originalURL.path))
        #expect(try String(contentsOf: saved.snapshot.note.url, encoding: .utf8) == saved.snapshot.text)
    }

    @Test
    func missingAndUndecodableFilesThrowInsteadOfOpeningAsEmptyNotes() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try seed("Readable\nOriginal", named: "Readable.md", in: folder)
        let store = await store(in: folder)
        let note = try #require(store.notes.first)
        try Data([0xFF, 0xFE, 0xFF]).write(to: url)
        do {
            _ = try await store.open(note)
            Issue.record("Invalid UTF-8 must fail instead of becoming an empty document")
        } catch {}
        try FileManager.default.removeItem(at: url)
        do {
            _ = try await store.open(note)
            Issue.record("A missing note must fail instead of becoming an empty document")
        } catch {}
    }

    @Test
    func failedSaveCanRetryFromTheLastSuccessfulSnapshot() async throws {
        let folder = try makeTempFolder()
        let holding = folder.appendingPathExtension("unavailable")
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: holding)
        }
        _ = try seed("Retry\nOriginal", named: "Retry.md", in: folder)
        let store = await store(in: folder)
        let opened = try await store.open(try #require(store.notes.first))
        try FileManager.default.moveItem(at: folder, to: holding)
        try Data("This is a file, so no child note can be written.".utf8).write(to: folder)

        do {
            _ = try await store.save("Retry\nUnsaved writing", snapshot: opened)
            Issue.record("Saving into an unavailable folder must throw")
        } catch {}
        #expect(opened.text == "Retry\nOriginal")
        #expect(try String(contentsOf: holding.appendingPathComponent("Retry.md"), encoding: .utf8) == opened.text)

        try FileManager.default.removeItem(at: folder)
        try FileManager.default.moveItem(at: holding, to: folder)
        let retried = try await store.save("Retry\nUnsaved writing", snapshot: opened)
        #expect(!retried.preservedConflict)
        #expect(try String(contentsOf: retried.snapshot.note.url, encoding: .utf8) == "Retry\nUnsaved writing")
    }

    @Test
    func trashCanBeUndoneAfterReopeningTheStore() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let text = "Keep this\nA thought worth recovering."
        let url = try seed(text, named: "Keep this.md", in: folder)
        let store = await store(in: folder)
        let note = try #require(store.notes.first)

        try await store.trash(note)

        #expect(store.notes.isEmpty)
        #expect(store.search("recovering").isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(store.canUndoTrash)
        let reloaded = await self.store(in: folder)
        #expect(reloaded.canUndoTrash)
        try await reloaded.undoTrash()
        #expect(!reloaded.canUndoTrash)
        #expect(reloaded.notes.count == 1)
        let recovered = try await reloaded.open(try #require(reloaded.notes.first))
        #expect(recovered.text == text)
    }

    @Test
    func undoTrashDoesNotOverwriteAFileCreatedAtTheOldPath() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let oldText = "Same name\nThe deleted note"
        let url = try seed(oldText, named: "Same name.md", in: folder)
        let store = await store(in: folder)
        try await store.trash(try #require(store.notes.first))
        let newText = "Same name\nThe new note"
        try newText.write(to: url, atomically: true, encoding: .utf8)

        try await store.undoTrash()

        #expect(try String(contentsOf: url, encoding: .utf8) == newText)
        #expect(Set(try contents(in: folder).values) == Set([oldText, newText]))
    }

    @Test
    func undoKeepsTrashRetryableWhenPendingDraftRelocationFails() async throws {
        let fm = FileManager.default
        let folder = try makeTempFolder()
        defer { try? fm.removeItem(at: folder) }
        let originalText = "Keep writing\nThe version saved on disk."
        let draftText = "Keep writing\nThe newer thought is still only a local draft."
        let originalURL = try seed(originalText, named: "Keep writing.md", in: folder)
        let store = await store(in: folder)
        let baseline = try await store.open(try #require(store.notes.first))
        try await store.persistDraft(draftText, snapshot: baseline)
        try await store.trash(baseline.note)
        let trashFolder = folder.appendingPathComponent(".drift-trash", isDirectory: true)
        let trashedURL = try #require(fm.contentsOfDirectory(at: trashFolder, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "md" })

        // Obstruct only this session's destination journal, leaving every other
        // draft and the source recovery record readable and writable.
        let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                 appropriateFor: nil, create: true)
        let hash = SHA256.hash(data: Data(originalURL.standardizedFileURL.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let destinationJournal = support.appendingPathComponent("Drift/Drafts", isDirectory: true)
            .appendingPathComponent("\(hash).\(baseline.documentID.uuidString).json")
        try fm.createDirectory(at: destinationJournal, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: destinationJournal) }

        do {
            try await store.undoTrash()
            Issue.record("Undo must fail while it cannot relocate the pending draft")
        } catch {}
        #expect(try contents(in: folder).isEmpty)
        #expect(fm.fileExists(atPath: trashedURL.path))
        #expect(store.canUndoTrash)

        let restarted = await self.store(in: folder)
        #expect(restarted.canUndoTrash)
        #expect(restarted.notes.isEmpty)
        let trashedNote = Note(url: trashedURL, modified: baseline.note.modified,
                              title: baseline.note.title, preview: baseline.note.preview)
        let retained = try await restarted.open(trashedNote)
        #expect(retained.recoveredDraft)
        #expect(retained.text == draftText)
        #expect(retained.baselineText == originalText)
        #expect(retained.documentID == baseline.documentID)

        try fm.removeItem(at: destinationJournal)
        try await restarted.undoTrash()
        #expect(!restarted.canUndoTrash)
        #expect(restarted.notes.map(\.url) == [originalURL])
        #expect(try contents(in: folder) == [originalURL: originalText])
        let recovered = try await restarted.openForEditing(try #require(restarted.notes.first))
        #expect(recovered.recoveredDraft)
        #expect(recovered.text == draftText)
        #expect(recovered.baselineText == originalText)
        #expect(recovered.documentID == baseline.documentID)
        let saved = try await restarted.save(recovered.text, snapshot: recovered)
        #expect(!saved.preservedConflict)
        #expect(try contents(in: folder) == [originalURL: draftText])
    }

    @Test
    func searchFindsFullBodyWithMatchingContextAndIgnoresCase() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try seed(
            "Field notes\n\n" + String(repeating: "A quiet observation. ", count: 100)
                + "\nMeet at the BLUEBIRD café on Sunday.\nAnother thought.",
            named: "Field notes.md", in: folder
        )
        _ = try seed("Shopping\n\nCoffee and oranges", named: "Shopping.md", in: folder)
        let store = await store(in: folder)

        let hits = store.search("  bluebird  ")

        #expect(hits.count == 1)
        #expect(hits.first?.note.title == "Field notes")
        #expect(hits.first?.snippet?.localizedCaseInsensitiveContains("bluebird") == true)
        #expect(store.search("BLUEBIRD").map(\.note.url) == hits.map(\.note.url))
        #expect(store.search("   ").count == 2)
        #expect(store.search("does not exist").isEmpty)
    }

    @Test
    func searchReflectsSavesAndExternalRefreshes() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try seed("Working\nOriginal phrase", named: "Working.md", in: folder)
        let store = await store(in: folder)
        let opened = try await store.open(try #require(store.notes.first))
        let saved = try await store.save("Working\nFresh phrase", snapshot: opened)
        #expect(store.search("Original phrase").isEmpty)
        #expect(store.search("Fresh phrase").count == 1)

        try "Working\nExternal phrase".write(to: saved.snapshot.note.url, atomically: true, encoding: .utf8)
        await store.refresh()
        #expect(store.search("Fresh phrase").isEmpty)
        #expect(store.search("External phrase").count == 1)
    }

    @Test
    func recoveryDraftSurvivesStoreReloadAndRetainsConflictDetection() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try seed("Draft\nOriginal on disk", named: "Draft.md", in: folder)
        let store = await store(in: folder)
        let opened = try await store.open(try #require(store.notes.first))
        let draftText = "Draft\nWriting recovered after interruption"
        try await store.persistDraft(draftText, snapshot: opened)
        let externalText = "Draft\nMeanwhile, edited on desktop"
        try externalText.write(to: url, atomically: true, encoding: .utf8)

        let reloaded = await self.store(in: folder)
        let recovered = try await reloaded.open(try #require(reloaded.notes.first))
        #expect(recovered.recoveredDraft)
        #expect(recovered.text == draftText)
        let saved = try await reloaded.save(recovered.text, snapshot: recovered)
        #expect(saved.preservedConflict)
        #expect(Set(try contents(in: folder).values) == Set([draftText, externalText]))
    }

    @Test
    func localDraftRemainsDiscoverableAfterTheOriginalFileIsDeleted() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try seed("Keep writing\nOriginal on disk", named: "Keep writing.md", in: folder)
        let store = await store(in: folder)
        let opened = try await store.open(try #require(store.notes.first))
        let text = "Keep writing\nThe unsaved thought must survive."
        try await store.persistDraft(text, snapshot: opened)
        try FileManager.default.removeItem(at: url)

        let reloaded = await self.store(in: folder)
        let orphan = try #require(reloaded.notes.first)
        #expect(orphan.url == url)
        #expect(reloaded.search("unsaved thought").count == 1)
        let recovered = try await reloaded.open(orphan)
        #expect(recovered.recoveredDraft)
        #expect(recovered.text == text)
        let saved = try await reloaded.save(recovered.text, snapshot: recovered)
        #expect(saved.preservedConflict)
        #expect(try String(contentsOf: saved.snapshot.note.url, encoding: .utf8) == text)
    }

    @Test
    func completingAnOlderSavePreservesTheNewerDraftAcrossRename() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = await store(in: folder)
        let original = try await store.createNote()
        let savingText = "A new title\nThe first edit"
        let latestText = "A new title\nThe first edit and a newer thought"
        try await store.persistDraft(latestText, snapshot: original)

        let saved = try await store.save(savingText, snapshot: original)

        #expect(saved.snapshot.note.url != original.note.url)
        #expect(try String(contentsOf: saved.snapshot.note.url, encoding: .utf8) == savingText)
        let reloaded = await self.store(in: folder)
        #expect(reloaded.notes.count == 1)
        let recovered = try await reloaded.open(try #require(reloaded.notes.first))
        #expect(recovered.recoveredDraft)
        #expect(recovered.text == latestText)
        let finalSave = try await reloaded.save(recovered.text, snapshot: recovered)
        #expect(!finalSave.preservedConflict)
        #expect(try String(contentsOf: finalSave.snapshot.note.url, encoding: .utf8) == latestText)
    }

    @Test
    func delayedDraftWithTheOldSnapshotFollowsTheRenamedNote() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = await store(in: folder)
        let original = try await store.createNote()
        let saved = try await store.save("Renamed\nFirst edit", snapshot: original)
        let latest = "Renamed\nFirst edit and the last keystrokes"

        try await store.persistDraft(latest, snapshot: original)

        let reloaded = await self.store(in: folder)
        #expect(reloaded.notes.count == 1)
        let recovered = try await reloaded.open(saved.snapshot.note)
        #expect(recovered.recoveredDraft)
        #expect(recovered.text == latest)
        let finalSave = try await reloaded.save(recovered.text, snapshot: recovered)
        #expect(!finalSave.preservedConflict)
        #expect(try String(contentsOf: finalSave.snapshot.note.url, encoding: .utf8) == latest)
    }

    @Test
    func discardingARevertedDraftDoesNotRecoverAnAbandonedEdit() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = "A thought\nThe text I want to keep"
        _ = try seed(original, named: "A thought.md", in: folder)
        let store = await store(in: folder)
        let opened = try await store.open(try #require(store.notes.first))
        try await store.persistDraft("A thought\nAn edit I undid", snapshot: opened)

        try await store.discardDraft(snapshot: opened)

        let reloaded = await self.store(in: folder)
        let reopened = try await reloaded.open(try #require(reloaded.notes.first))
        #expect(!reopened.recoveredDraft)
        #expect(reopened.text == original)
    }

    @Test
    func reusingTheUntitledFilenameKeepsTwoNewNotesAndTheirJournalsSeparate() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = await store(in: folder)
        let firstOriginal = try await store.createNote()
        let firstText = "First\nWriting in the first note"
        let first = try await store.save(firstText, snapshot: firstOriginal)
        let secondOriginal = try await store.createNote()
        #expect(secondOriginal.note.url == firstOriginal.note.url)
        let secondText = "Second\nWriting in the second note"

        try await store.persistDraft(secondText, snapshot: secondOriginal)

        let firstWhileSecondIsDrafting = try await store.open(first.snapshot.note)
        #expect(firstWhileSecondIsDrafting.text == firstText)
        #expect(!firstWhileSecondIsDrafting.recoveredDraft)
        let secondDraft = try await store.open(secondOriginal.note)
        #expect(secondDraft.text == secondText)
        #expect(secondDraft.recoveredDraft)
        let second = try await store.save(secondText, snapshot: secondOriginal)
        let reloaded = await self.store(in: folder)
        #expect(reloaded.notes.count == 2)
        let reopenedFirst = try await reloaded.open(first.snapshot.note)
        let reopenedSecond = try await reloaded.open(second.snapshot.note)
        #expect(reopenedFirst.text == firstText)
        #expect(reopenedSecond.text == secondText)
        #expect(!reopenedFirst.recoveredDraft)
        #expect(!reopenedSecond.recoveredDraft)
        #expect(Set(try contents(in: folder).values) == Set([firstText, secondText]))
    }

    @Test
    func aDelayedFirstNoteDraftDoesNotBecomeTheNextUntitledNotesDraft() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = await store(in: folder)
        let firstOriginal = try await store.createNote()
        let first = try await store.save("First\nInitial writing", snapshot: firstOriginal)
        let secondOriginal = try await store.createNote()
        #expect(secondOriginal.note.url == firstOriginal.note.url)
        let secondText = "Second\nOnly the second note's writing"
        try await store.persistDraft(secondText, snapshot: secondOriginal)
        let lateFirstText = "First\nThe first note's final keystrokes"

        try await store.persistDraft(lateFirstText, snapshot: firstOriginal)
        let second = try await store.save(secondText, snapshot: secondOriginal)

        let recoveredFirst = try await store.open(first.snapshot.note)
        #expect(recoveredFirst.text == lateFirstText)
        #expect(recoveredFirst.recoveredDraft)
        let savedFirst = try await store.save(recoveredFirst.text, snapshot: recoveredFirst)
        #expect(!savedFirst.preservedConflict)
        let reloaded = await self.store(in: folder)
        let reopenedFirst = try await reloaded.open(savedFirst.snapshot.note)
        let reopenedSecond = try await reloaded.open(second.snapshot.note)
        #expect(reopenedFirst.text == lateFirstText)
        #expect(reopenedSecond.text == secondText)
        #expect(!reopenedFirst.recoveredDraft)
        #expect(!reopenedSecond.recoveredDraft)
        #expect(Set(try contents(in: folder).values) == Set([lateFirstText, secondText]))
    }

    @Test
    func independentEditingSessionsPreserveBothBranchesOfTheSameNote() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try seed("Shared\nOriginal text", named: "Shared.md", in: folder)
        let store = await store(in: folder)
        let note = try #require(store.notes.first)
        let firstSession = try await store.open(note)
        let secondSession = try await store.open(note)
        let firstText = "Shared\nWriting from the first session"
        let secondText = "Shared\nWriting from the second session"
        try await store.persistDraft(firstText, snapshot: firstSession)
        try await store.persistDraft(secondText, snapshot: secondSession)

        let firstSave = try await store.save(firstText, snapshot: firstSession)

        #expect(!firstSave.preservedConflict)
        let recoveredSecond = try await store.open(firstSave.snapshot.note)
        #expect(recoveredSecond.recoveredDraft)
        #expect(recoveredSecond.text == secondText)
        #expect(recoveredSecond.baselineText == secondSession.baselineText)
        let secondSave = try await store.save(recoveredSecond.text, snapshot: recoveredSecond)
        #expect(secondSave.preservedConflict)
        #expect(secondSave.snapshot.note.url != firstSave.snapshot.note.url)
        #expect(Set(try contents(in: folder).values) == Set([firstText, secondText]))
    }

    @Test
    func openingAnIndexedNoteDoesNotWaitForAnUnrelatedFileDuringLargeFolderRefresh() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let targetText = "Open immediately\nA small note should open even while another file is busy."
        let targetURL = try seed(targetText, named: "Open immediately.md", in: folder)
        let busyURL = try seed("Busy note\nBefore the external write", named: "Busy note.md", in: folder)
        let fillerBody = String(repeating: "A little writing to index. ", count: 40)
        for index in 0..<998 {
            _ = try seed("Note \(index)\n\(fillerBody)", named: "Note \(index).md", in: folder)
        }
        let store = await store(in: folder)
        #expect(store.notes.count == 1_000)
        let target = try #require(store.notes.first { $0.url == targetURL })

        // The changed body invalidates this file's warm metadata cache. A real
        // coordinator holds its write open while the folder index encounters
        // it, reproducing a stalled provider independently of machine speed.
        let barrier = CoordinatedWriteBarrier(
            url: busyURL, replacement: "Busy note\nAn external write is still in progress with more content."
        )
        defer { barrier.release() }
        try await barrier.waitUntilHolding()
        let refresh = Task { await store.refresh() }
        let startDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !store.isLoading, ContinuousClock.now < startDeadline { await Task.yield() }
        #expect(store.isLoading)

        do {
            let editingStarted = ContinuousClock.now
            let editing = try await store.openForEditing(target)
            let editingDuration = editingStarted.duration(to: .now)
            #expect(editing.text == targetText)
            #expect(barrier.isHolding,
                    "Opening an indexed note must not queue behind an unrelated coordinated write")

            let freshStarted = ContinuousClock.now
            let fresh = try await store.open(target)
            let freshDuration = freshStarted.duration(to: .now)
            #expect(fresh.text == targetText)
            #expect(barrier.isHolding,
                    "Refreshing the selected note must also be independent of background folder indexing")
            print("Large-folder coordination regression: cached opening \(editingDuration), fresh opening \(freshDuration); barrier still held=\(barrier.isHolding)")
        } catch {
            barrier.release()
            await refresh.value
            _ = await barrier.waitUntilFinished()
            throw error
        }
        barrier.release()
        await refresh.value
        #expect(await barrier.waitUntilFinished())
        #expect(!barrier.expired, "The coordinator barrier must be released by the test, not its safety timeout")
    }

    @Test
    func cachedEditingSnapshotStillPreservesAnExternalEditWhenSaved() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = "Shared thought\nThe version already indexed on the phone."
        let url = try seed(original, named: "Shared thought.md", in: folder)
        let store = await store(in: folder)
        let note = try #require(store.notes.first)
        let external = "Shared thought\nA newer version written on the Mac."
        try external.write(to: url, atomically: true, encoding: .utf8)

        let editing = try await store.openForEditing(note)

        #expect(editing.text == original)
        #expect(editing.baselineText == original)
        let verified = try await store.open(note)
        #expect(verified.text == external)
        let local = "Shared thought\nWriting begun before the background verification returned."
        let saved = try await store.save(local, snapshot: editing)
        #expect(saved.preservedConflict)
        #expect(saved.snapshot.note.url != url)
        #expect(try String(contentsOf: url, encoding: .utf8) == external)
        #expect(Set(try contents(in: folder).values) == Set([external, local]))
    }

    @Test
    func cachedEditingOpenRecoversThePendingDraftAndKeepsItsOriginalBaseline() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = "Shared draft\nThe original shared text."
        let url = try seed(original, named: "Shared draft.md", in: folder)
        let store = await store(in: folder)
        let note = try #require(store.notes.first)
        let baseline = try await store.open(note)
        let draft = "Shared draft\nThe phone's unsaved writing."
        try await store.persistDraft(draft, snapshot: baseline)
        let external = "Shared draft\nA different update from the Mac."
        try external.write(to: url, atomically: true, encoding: .utf8)

        let editing = try await store.openForEditing(note)

        #expect(editing.recoveredDraft)
        #expect(editing.text == draft)
        #expect(editing.baselineText == original)
        #expect(editing.documentID == baseline.documentID)
        let saved = try await store.save(editing.text, snapshot: editing)
        #expect(saved.preservedConflict)
        #expect(Set(try contents(in: folder).values) == Set([external, draft]))
    }

    @Test
    func untouchedAndWhitespaceComposersNeverCreateFilesRowsOrTrash() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let existingText = "Untitled\nAn existing note must be left alone."
        let existingURL = try seed(existingText, named: "Untitled.md", in: folder)
        let store = await store(in: folder)
        let untouched = try await store.makeUnsavedNote()
        let whitespace = try await store.makeUnsavedNote()
        #expect(untouched.isUnsaved)
        #expect(whitespace.isUnsaved)
        #expect(untouched.note.url != whitespace.note.url)
        #expect(!FileManager.default.fileExists(atPath: untouched.note.url.path))
        #expect(!FileManager.default.fileExists(atPath: whitespace.note.url.path))
        #expect(store.notes.map(\.url) == [existingURL])

        let firstSession = EditorDocumentSession(store: store, snapshot: untouched)
        await firstSession.flush()
        let secondSession = EditorDocumentSession(store: store, snapshot: whitespace)
        secondSession.changed(" \n\n\t  ")
        await secondSession.flush()

        let reloaded = await self.store(in: folder)
        #expect(reloaded.notes.map(\.url) == [existingURL])
        #expect(!reloaded.canUndoTrash)
        #expect(try contents(in: folder) == [existingURL: existingText])
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        #expect(files.map(\.lastPathComponent) == ["Untitled.md"],
                "Opening or abandoning a blank composer must not create even a hidden shared file or trash folder")
    }

    @Test
    func firstMeaningfulComposerEditCreatesOneTitledFileAndPreservesExistingNotes() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let existing = "An idea\nThe existing note with this title."
        let existingURL = try seed(existing, named: "An idea.md", in: folder)
        let store = await store(in: folder)
        let unsaved = try await store.makeUnsavedNote()
        let session = EditorDocumentSession(store: store, snapshot: unsaved)
        let text = "An idea\n\nWriting worth keeping."

        session.changed(text)
        await session.flush()

        #expect(!session.snapshot.isUnsaved)
        #expect(session.snapshot.documentID == unsaved.documentID)
        #expect(session.snapshot.note.url.lastPathComponent == "An idea 2.md")
        #expect(!session.isDirty)
        #expect(!FileManager.default.fileExists(atPath: unsaved.note.url.path))
        #expect(try String(contentsOf: existingURL, encoding: .utf8) == existing)
        #expect(Set(try contents(in: folder).values) == Set([existing, text]))
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(".drift-trash").path))
        let reopened = try await store.open(session.snapshot.note)
        #expect(reopened.text == text)
        #expect(!reopened.recoveredDraft)
    }

    @Test
    func firstUnsavedWritingCanRecoverFromItsJournalBeforeAnySharedFileExists() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = await store(in: folder)
        let unsaved = try await store.makeUnsavedNote()
        let text = "Before the first save\n\nKeep the thought even if the app stops now."
        try await store.persistDraft(text, snapshot: unsaved)
        #expect(try contents(in: folder).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: unsaved.note.url.path))

        let restarted = await self.store(in: folder)
        let recoveredNote = try #require(restarted.notes.first)
        #expect(restarted.notes.count == 1)
        let recovered = try await restarted.openForEditing(recoveredNote)
        #expect(recovered.isUnsaved)
        #expect(recovered.recoveredDraft)
        #expect(recovered.text == text)
        #expect(recovered.baselineText.isEmpty)
        #expect(recovered.documentID == unsaved.documentID)

        let saved = try await restarted.save(recovered.text, snapshot: recovered)

        #expect(!saved.preservedConflict)
        #expect(!saved.snapshot.isUnsaved)
        #expect(saved.snapshot.note.url.lastPathComponent == "Before the first save.md")
        #expect(saved.snapshot.documentID == unsaved.documentID)
        let reloaded = await self.store(in: folder)
        #expect(reloaded.notes.count == 1)
        #expect(try contents(in: folder) == [saved.snapshot.note.url: text])
        let final = try await reloaded.open(try #require(reloaded.notes.first))
        #expect(final.text == text)
        #expect(!final.recoveredDraft)
        #expect(!final.isUnsaved)
    }

    @Test
    func lateOperationsUsingTheOriginalComposerSnapshotStayWithTheMaterializedFile() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = await store(in: folder)
        let originalComposer = try await store.makeUnsavedNote()
        let firstText = "One page\nThe first meaningful writing."
        let firstSave = try await store.save(firstText, snapshot: originalComposer)
        let realURL = firstSave.snapshot.note.url
        #expect(!firstSave.snapshot.isUnsaved)

        let secondText = "One page\nAn update still carrying the original composer snapshot."
        let secondSave = try await store.save(secondText, snapshot: originalComposer)

        #expect(!secondSave.preservedConflict)
        #expect(secondSave.snapshot.note.url == realURL)
        #expect(secondSave.snapshot.documentID == originalComposer.documentID)
        #expect(try contents(in: folder) == [realURL: secondText])

        let lateText = "One page\nThe latest keystrokes arriving after the first file was created."
        try await store.persistDraft(lateText, snapshot: originalComposer)
        let restarted = await self.store(in: folder)
        #expect(restarted.notes.count == 1)
        let recovered = try await restarted.open(try #require(restarted.notes.first))
        #expect(recovered.note.url == realURL)
        #expect(recovered.recoveredDraft)
        #expect(!recovered.isUnsaved)
        #expect(recovered.text == lateText)
        #expect(recovered.baselineText == secondText)
        #expect(recovered.documentID == originalComposer.documentID)

        let finalSave = try await restarted.save(recovered.text, snapshot: recovered)

        #expect(!finalSave.preservedConflict)
        #expect(finalSave.snapshot.note.url == realURL)
        #expect(try contents(in: folder) == [realURL: lateText])
        #expect(!FileManager.default.fileExists(atPath: originalComposer.note.url.path))
        let final = try await restarted.open(finalSave.snapshot.note)
        #expect(!final.recoveredDraft)
        #expect(!final.isUnsaved)
    }

    @Test
    func deletingARecoveredUnsavedNoteCanUndoToOneRealFileWithoutDraftDebris() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = await store(in: folder)
        let unsaved = try await store.makeUnsavedNote()
        let text = "Worth keeping\n\nA thought recovered before its first shared save."
        try await store.persistDraft(text, snapshot: unsaved)
        let restarted = await self.store(in: folder)
        let recoveredRow = try #require(restarted.notes.first)
        #expect(recoveredRow.isUnsaved)
        #expect(restarted.notes.count == 1)

        try await restarted.trash(recoveredRow)

        #expect(restarted.notes.isEmpty)
        #expect(try contents(in: folder).isEmpty)
        #expect(restarted.canUndoTrash)
        try await restarted.undoTrash()
        #expect(restarted.notes.count == 1)
        let restoredRow = try #require(restarted.notes.first)
        #expect(!restoredRow.isUnsaved)
        let realURL = folder.appendingPathComponent("Worth keeping.md")
        #expect(restoredRow.url == realURL)
        #expect(try contents(in: folder) == [realURL: text])
        let restored = try await restarted.open(restoredRow)
        #expect(restored.text == text)
        #expect(!restored.recoveredDraft)
        #expect(!restored.isUnsaved)
        #expect(!FileManager.default.fileExists(atPath: unsaved.note.url.path))

        let reloaded = await self.store(in: folder)
        #expect(reloaded.notes.map(\.url) == [realURL])
        #expect(!reloaded.canUndoTrash)
    }

    @Test
    func refreshRequestedAfterMutationDoesNotJoinAnInvalidatedEarlierScan() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let targetURL = try seed("Changed locally\nThe original text.", named: "Changed locally.md", in: folder)
        let busyURL = try seed("Busy scan\nBefore", named: "Busy scan.md", in: folder)
        let store = await store(in: folder)
        let target = try #require(store.notes.first { $0.url == targetURL })
        let baseline = try await store.open(target)
        let barrier = CoordinatedWriteBarrier(url: busyURL, replacement: "Busy scan\nAn external write still in progress.")
        defer { barrier.release() }
        try await barrier.waitUntilHolding()
        let earlierRefresh = Task { await store.refresh() }
        let startDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !store.isLoading, ContinuousClock.now < startDeadline { await Task.yield() }
        #expect(store.isLoading)

        do {
            _ = try await store.save("Changed locally\nThe saved local edit.", snapshot: baseline)
            #expect(barrier.isHolding)
            // Saving invalidates the prior scan. This new external file is not
            // in the in-memory list; only a subsequent accepted scan can add it.
            let addedURL = try seed("Arrived meanwhile\nA note from another device.", named: "Arrived meanwhile.md", in: folder)
            var followupStarted = false
            let followup = Task {
                followupStarted = true
                await store.refresh()
            }
            let followupDeadline = ContinuousClock.now.advanced(by: .seconds(2))
            while !followupStarted, ContinuousClock.now < followupDeadline { await Task.yield() }
            #expect(followupStarted)
            barrier.release()
            await earlierRefresh.value
            await followup.value
            #expect(await barrier.waitUntilFinished())
            #expect(!barrier.expired)
            #expect(store.notes.contains { $0.url == addedURL },
                    "A refresh requested after mutation must perform an accepted scan, not merely wait for a stale one")
            #expect(store.search("saved local edit").contains { $0.note.url == targetURL })
        } catch {
            barrier.release()
            await earlierRefresh.value
            _ = await barrier.waitUntilFinished()
            throw error
        }
    }

    @Test
    func coldCataloguePublishesHundredsOfRowsBeforeAnUnrelatedBodyReadCompletes() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let busyURL = try seed("Busy body\nWaiting for another app.", named: "Busy body.md", in: folder)
        for index in 0..<800 {
            _ = try seed("Earlier note \(index)\nA short thought.", named: "Earlier note \(index).md", in: folder)
        }
        let targetText = "Ready to open\nThe chosen note should be available now."
        let targetURL = try seed(targetText, named: "Ready to open.md", in: folder)
        let barrier = CoordinatedWriteBarrier(url: busyURL)
        defer { barrier.release() }
        try await barrier.waitUntilHolding()
        let store = NoteStore(folderURL: folder)
        let started = ContinuousClock.now
        let refresh = Task { await store.refresh() }
        do {
            let published = await cataloguePublishes(store, count: 802, while: barrier)
            #expect(published, "File names must publish without waiting for all note bodies")
            let target = try #require(store.notes.first { $0.url == targetURL })
            let opened = try await store.openForEditing(target)
            #expect(opened.text == targetText)
            #expect(barrier.isHolding)
            print("Cold 802-note catalogue and selected note available in \(started.duration(to: .now)); unrelated body still held=\(barrier.isHolding)")
        } catch {
            barrier.release()
            await refresh.value
            _ = await barrier.waitUntilFinished()
            throw error
        }
        barrier.release()
        await refresh.value
        await store.flushCatalogueCache()
        #expect(await barrier.waitUntilFinished())
        #expect(!barrier.expired)
        #expect(store.notes.count == 802)
    }

    @Test
    func firstVisiblePreviewPublishesBeforeTheNextBodyReadCompletes() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let targetURL = try seed("Ready first\nA preview available now.\nA unique body-search phrase.",
                                 named: "Ready first.md", in: folder)
        let busyURL = try seed("Still arriving\nWaiting for the provider.", named: "Still arriving.md", in: folder)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)],
                                             ofItemAtPath: targetURL.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)],
                                             ofItemAtPath: busyURL.path)
        let barrier = CoordinatedWriteBarrier(url: busyURL)
        defer { barrier.release() }
        try await barrier.waitUntilHolding()
        let store = NoteStore(folderURL: folder)
        let refresh = Task { await store.refresh() }
        while barrier.isHolding && store.notes.first(where: { $0.url == targetURL })?.preview != "A preview available now." {
            await Task.yield()
        }
        #expect(barrier.isHolding, "The first ready preview must not wait for the next file or the next batch of reads")
        #expect(store.notes.first?.url == targetURL)
        #expect(store.notes.first?.preview == "A preview available now.")
        #expect(store.search("unique body-search phrase").map(\.note.url) == [targetURL],
                "Publish the indexed body with its preview so searching is immediately useful")
        #expect(store.notes.first(where: { $0.url == busyURL })?.preview == "")
        barrier.release()
        await refresh.value
        #expect(await barrier.waitUntilFinished())
        #expect(!barrier.expired)
    }

    @Test
    func persistedCatalogueOpensAfterRestartWhileTheProviderFolderIsBlocked() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = UserDefaults.standard
        let bookmarkKey = "drift.folderBookmark"
        let previousBookmark = defaults.data(forKey: bookmarkKey)
        defer {
            if let previousBookmark { defaults.set(previousBookmark, forKey: bookmarkKey) }
            else { defaults.removeObject(forKey: bookmarkKey) }
        }
        try #require(ProcessInfo.processInfo.environment["DRIFT_TEST_FOLDER"] == nil,
                     "This regression must exercise bookmark restoration, not the explicit test-folder override")
        let text = "Already here\nThe previously indexed text is available locally."
        let url = try seed(text, named: "Already here.md", in: folder)
        let initial = await store(in: folder)
        try await initial.setFolder(folder)
        await initial.flushCatalogueCache()
        let barrier = CoordinatedWriteBarrier(url: folder)
        defer { barrier.release() }
        try await barrier.waitUntilHolding()

        let restarted = NoteStore()
        // No refresh call: this must be the persisted local catalogue, not a
        // successful provider enumeration that happens to be fast on a Mac.
        #expect(await cataloguePublishes(restarted, count: 1, while: barrier))
        do {
            let note = try #require(restarted.notes.first)
            #expect(note.url == url)
            let opened = try await restarted.openForEditing(note)
            #expect(opened.text == text)
            #expect(opened.baselineText == text)
            #expect(barrier.isHolding, "Cached opening must not require a provider round trip")
        } catch {
            barrier.release()
            _ = await barrier.waitUntilFinished()
            throw error
        }
        barrier.release()
        #expect(await barrier.waitUntilFinished())
        #expect(!barrier.expired)
        await restarted.refresh()
        await restarted.flushCatalogueCache()
    }

    @Test
    func externalDeletionReconcilesOutOfTheCatalogueAndItsNextPersistedRestart() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let keptURL = try seed("Keep this\nStill present.", named: "Keep this.md", in: folder)
        let removedURL = try seed("Removed elsewhere\nNo longer present.", named: "Removed elsewhere.md", in: folder)
        let initial = await store(in: folder)
        await initial.flushCatalogueCache()
        try FileManager.default.removeItem(at: removedURL)

        let reconciled = NoteStore(folderURL: folder)
        await reconciled.refresh()
        #expect(reconciled.notes.map(\.url) == [keptURL])
        await reconciled.flushCatalogueCache()
        let barrier = CoordinatedWriteBarrier(url: folder)
        defer { barrier.release() }
        try await barrier.waitUntilHolding()
        let restarted = NoteStore(folderURL: folder)
        #expect(await cataloguePublishes(restarted, count: 1, while: barrier))
        #expect(restarted.notes.map(\.url) == [keptURL],
                "A reconciled deletion must remain absent even before the next provider scan")
        #expect(!FileManager.default.fileExists(atPath: removedURL.path))
        barrier.release()
        #expect(await barrier.waitUntilFinished())
        #expect(!barrier.expired)
    }

    @Test
    func persistedCatalogueNeverHidesAnOrphanedLocalDraftOrReplacesItWithCachedText() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = "Recovered thought\nThe cached original text."
        let originalURL = try seed(original, named: "Recovered thought.md", in: folder)
        let initial = await store(in: folder)
        let baseline = try await initial.open(try #require(initial.notes.first))
        await initial.flushCatalogueCache()
        let draft = "Recovered thought\nThe phone's newer, unsaved writing."
        try await initial.persistDraft(draft, snapshot: baseline)
        try FileManager.default.removeItem(at: originalURL)
        let barrier = CoordinatedWriteBarrier(url: folder)
        defer { barrier.release() }
        try await barrier.waitUntilHolding()
        let restarted = NoteStore(folderURL: folder)
        #expect(await cataloguePublishes(restarted, count: 1, while: barrier))
        do {
            let cachedRow = try #require(restarted.notes.first)
            let recovered = try await restarted.openForEditing(cachedRow)
            #expect(recovered.recoveredDraft)
            #expect(recovered.text == draft)
            #expect(recovered.baselineText == original)
            #expect(barrier.isHolding)
        } catch {
            barrier.release()
            _ = await barrier.waitUntilFinished()
            throw error
        }
        barrier.release()
        #expect(await barrier.waitUntilFinished())
        #expect(!barrier.expired)

        await restarted.refresh()
        #expect(restarted.notes.count == 1, "Metadata reconciliation must retain meaningful orphaned drafts")
        let orphan = try await restarted.openForEditing(try #require(restarted.notes.first))
        #expect(orphan.recoveredDraft)
        #expect(orphan.text == draft)
        let saved = try await restarted.save(orphan.text, snapshot: orphan)
        #expect(saved.preservedConflict)
        #expect(saved.snapshot.note.url != originalURL)
        #expect(try contents(in: folder) == [saved.snapshot.note.url: draft])
        await restarted.flushCatalogueCache()
    }

    @Test
    func completingBodyHydrationAfterDeletionCannotRestoreTheRowOrPersistItAgain() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let victimURL = try seed("Delete this\nThe note that will be deleted.", named: "Delete this.md", in: folder)
        let busyURL = try seed("Busy hydration\nBefore the change.", named: "Busy hydration.md", in: folder)
        let store = await store(in: folder)
        await store.flushCatalogueCache()
        let victim = try #require(store.notes.first { $0.url == victimURL })
        let barrier = CoordinatedWriteBarrier(url: busyURL, replacement: "Busy hydration\nThe changed body is still locked.")
        defer { barrier.release() }
        try await barrier.waitUntilHolding()
        let refresh = Task { await store.refresh() }
        let startDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !store.isLoading, ContinuousClock.now < startDeadline { await Task.yield() }
        #expect(store.isLoading)
        do {
            try await store.trash(victim)
            #expect(!store.notes.contains { $0.url == victimURL })
            #expect(barrier.isHolding)
        } catch {
            barrier.release()
            await refresh.value
            _ = await barrier.waitUntilFinished()
            throw error
        }
        barrier.release()
        await refresh.value
        #expect(await barrier.waitUntilFinished())
        #expect(!barrier.expired)
        #expect(store.notes.map(\.url) == [busyURL])
        await store.flushCatalogueCache()
        let cachedBarrier = CoordinatedWriteBarrier(url: folder)
        defer { cachedBarrier.release() }
        try await cachedBarrier.waitUntilHolding()
        let cached = NoteStore(folderURL: folder)
        #expect(await cataloguePublishes(cached, count: 1, while: cachedBarrier))
        #expect(cached.notes.map(\.url) == [busyURL])
        cachedBarrier.release()
        #expect(await cachedBarrier.waitUntilFinished())
        #expect(!cachedBarrier.expired)
    }
}

/// A real coordination barrier with a bounded lifetime, so a regression reports
/// a failure instead of leaving the test process waiting on a provider forever.
private final class CoordinatedWriteBarrier: @unchecked Sendable {
    private enum Failure: Error { case didNotStart, coordinationFailed }
    private let entered = DispatchSemaphore(value: 0)
    private let releaseSignal = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)
    private let stateLock = NSLock()
    private var holding = false
    private var didExpire = false
    private var failure: Error?

    init(url: URL, replacement: String? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?
            var enteredAccessor = false
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinated in
                enteredAccessor = true
                do {
                    if let replacement {
                        try replacement.write(to: coordinated, atomically: true, encoding: .utf8)
                    }
                    stateLock.lock()
                    holding = true
                    stateLock.unlock()
                    entered.signal()
                    let result = releaseSignal.wait(timeout: .now() + 8)
                    stateLock.lock()
                    holding = false
                    didExpire = result == .timedOut
                    stateLock.unlock()
                } catch {
                    recordFailure(error)
                    entered.signal()
                }
            }
            if !enteredAccessor {
                if let coordinationError { recordFailure(coordinationError) }
                else { recordFailure(Failure.coordinationFailed) }
                entered.signal()
            }
            finished.signal()
        }
    }

    var isHolding: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return holding
    }

    var expired: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return didExpire
    }

    private func recordFailure(_ error: Error) {
        stateLock.lock()
        failure = error
        stateLock.unlock()
    }

    private func recordedFailure() -> Error? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return failure
    }

    func waitUntilHolding() async throws {
        let started: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                continuation.resume(returning: entered.wait(timeout: .now() + 5) == .success)
            }
        }
        guard started else { throw Failure.didNotStart }
        if let failure = recordedFailure() { throw failure }
        guard isHolding else { throw Failure.didNotStart }
    }

    func release() { releaseSignal.signal() }

    func waitUntilFinished() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                continuation.resume(returning: finished.wait(timeout: .now() + 10) == .success)
            }
        }
    }
}

@MainActor
final class NotebookHydrationLayoutTests: XCTestCase {
    func testMetadataHydrationKeepsNotebookRowsAndScrollPositionStable() async throws {
        for category in [UIContentSizeCategory.large, .accessibilityLarge] {
            try await checkHydrationLayout(category: category)
        }
    }

    private func checkHydrationLayout(category: UIContentSizeCategory) async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-layout-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for index in 0..<12 {
            let title = String(format: "Thought %02d", index)
            let url = folder.appendingPathComponent(title + ".md")
            try "\(title)\nA quiet preview that arrives after the notebook is already visible."
                .write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000 - Double(index))],
                ofItemAtPath: url.path
            )
        }
        // Hydration visits the newest note first. Metadata can publish while
        // this real provider read remains blocked, with no timing hook in the app.
        let barrier = CoordinatedWriteBarrier(url: folder.appendingPathComponent("Thought 00.md"))
        defer { barrier.release() }
        try await barrier.waitUntilHolding()
        let store = NoteStore(folderURL: folder)
        let notebook = NotebookViewController(store: store)
        let navigation = PaperNavigationController(rootViewController: notebook)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.traitOverrides.preferredContentSizeCategory = category
        window.overrideUserInterfaceStyle = category == .large ? .light : .dark
        window.rootViewController = navigation
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        notebook.loadViewIfNeeded()
        let table = try XCTUnwrap(notebook.view.subviews.compactMap { $0 as? UITableView }.first)
        let refresh = Task { await store.refresh() }
        do {
            while barrier.isHolding && (!store.hasLoadedCatalogue || table.numberOfSections == 0 || table.numberOfRows(inSection: 0) != 12) {
                await settle(window)
            }
            XCTAssertTrue(barrier.isHolding, "Metadata rows must be visible before the body read is released")
            XCTAssertEqual(store.notes.count, 12)
            XCTAssertTrue(store.notes.allSatisfy { $0.preview.isEmpty }, "Capture the actual metadata-only phase")
            await settle(window)
            let top = try rowGeometry(table, in: notebook.view)
            attach(window, named: "metadata-home-\(category.rawValue)")

            table.setContentOffset(CGPoint(x: 0, y: -table.contentInset.top + 120), animated: false)
            await settle(window)
            let scrolled = try rowGeometry(table, in: notebook.view)
            let offset = table.contentOffset
            attach(window, named: "metadata-scrolled-\(category.rawValue)")

            barrier.release()
            await refresh.value
            let finished = await barrier.waitUntilFinished()
            XCTAssertTrue(finished)
            XCTAssertFalse(barrier.expired)
            XCTAssertTrue(store.notes.allSatisfy { !$0.preview.isEmpty }, "The comparison must include hydrated previews")
            await settle(window)
            attach(window, named: "hydrated-scrolled-\(category.rawValue)")
            XCTAssertEqual(table.contentOffset.y, offset.y, accuracy: 0.5,
                           "Loading previews must preserve the reader's scroll position (\(category.rawValue))")
            assertGeometry(scrolled, table: table, view: notebook.view, phase: "scrolled \(category.rawValue)")

            table.setContentOffset(CGPoint(x: 0, y: -table.contentInset.top), animated: false)
            await settle(window)
            attach(window, named: "hydrated-home-\(category.rawValue)")
            assertGeometry(top, table: table, view: notebook.view, phase: "home \(category.rawValue)")
        } catch {
            barrier.release()
            await refresh.value
            _ = await barrier.waitUntilFinished()
            throw error
        }
    }

    private struct RowGeometry {
        let indexPath: IndexPath
        let identifier: String
        let frame: CGRect
        let labelFrames: [String: CGRect]
    }

    private func rowGeometry(_ table: UITableView, in view: UIView) throws -> [RowGeometry] {
        let paths = try XCTUnwrap(table.indexPathsForVisibleRows).sorted().prefix(3)
        XCTAssertGreaterThanOrEqual(paths.count, 2, "Compare multiple visible rows so cumulative movement is measured")
        return try paths.map { path in
            let cell = try XCTUnwrap(table.cellForRow(at: path))
            let existingLabels = labels(in: cell.contentView).filter { !($0.text ?? "").isEmpty && !$0.isHidden }
            XCTAssertEqual(existingLabels.count, 2, "The metadata-only row should show its title and date")
            return RowGeometry(indexPath: path, identifier: try XCTUnwrap(cell.accessibilityIdentifier),
                               frame: table.convert(table.rectForRow(at: path), to: view),
                               labelFrames: Dictionary(uniqueKeysWithValues: existingLabels.map {
                                   ($0.text!, $0.convert($0.bounds, to: view))
                               }))
        }
    }

    private func assertGeometry(_ before: [RowGeometry], table: UITableView, view: UIView, phase: String) {
        for row in before {
            let frame = table.convert(table.rectForRow(at: row.indexPath), to: view)
            XCTAssertEqual(frame.height, row.frame.height, accuracy: 0.5,
                           "\(row.identifier) changes height when its preview arrives: \(phase)")
            XCTAssertEqual(frame.minY, row.frame.minY, accuracy: 0.5,
                           "\(row.identifier) moves when previews arrive: \(phase)")
            guard let cell = table.cellForRow(at: row.indexPath) else {
                XCTFail("The previously visible row disappeared during hydration: \(row.identifier), \(phase)")
                continue
            }
            XCTAssertEqual(cell.accessibilityIdentifier, row.identifier, "Hydration must not reorder visible notes")
            for (text, previous) in row.labelFrames {
                guard let label = labels(in: cell.contentView).first(where: { $0.text == text && !$0.isHidden }) else {
                    XCTFail("Hydration removed the existing label '\(text)': \(phase)")
                    continue
                }
                let actual = label.convert(label.bounds, to: view)
                XCTAssertEqual(actual.minX, previous.minX, accuracy: 0.5,
                               "Existing label '\(text)' shifts horizontally when its preview arrives: \(phase)")
                XCTAssertEqual(actual.minY, previous.minY, accuracy: 0.5,
                               "Existing label '\(text)' shifts vertically when its preview arrives: \(phase)")
                XCTAssertEqual(actual.height, previous.height, accuracy: 0.5,
                               "Existing label '\(text)' changes height when its preview arrives: \(phase)")
            }
        }
    }

    private func labels(in view: UIView) -> [UILabel] {
        (view as? UILabel).map { [$0] } ?? view.subviews.flatMap { labels(in: $0) }
    }

    private func settle(_ window: UIWindow) async {
        // Drain UIKit's queued snapshot/layout work; the file barrier controls
        // the phase, rather than an arbitrary sleep controlling the screenshot.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        window.setNeedsLayout()
        window.layoutIfNeeded()
        window.rootViewController?.view.layoutIfNeeded()
    }

    private func attach(_ window: UIWindow, named name: String) {
        // Capture the hosted view's actual label layers consistently across
        // repeated phases. System glass appearance is covered by UI screenshots.
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { context in
            window.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
struct EditorTextViewTests {
    @Test
    func returnContinuesBulletsNumbersAndUncheckedTasks() {
        let examples: [(initial: String, expected: String)] = [
            ("A list\n\n- Coffee", "A list\n\n- Coffee\n- "),
            ("A list\n\n  * Coffee", "A list\n\n  * Coffee\n  * "),
            ("A list\n\n9. Coffee", "A list\n\n9. Coffee\n10. "),
            ("A list\n\n2) Coffee", "A list\n\n2) Coffee\n3) "),
            ("A list\n\n- [x] Coffee", "A list\n\n- [x] Coffee\n- [ ] "),
        ]
        for example in examples {
            let editor = EditorTextView()
            editor.loadText(example.initial)
            editor.selectedRange = NSRange(location: (example.initial as NSString).length, length: 0)

            let handled = editor.continueList(for: editor.selectedRange, replacement: "\n")
            editor.styleChangedText()

            #expect(handled)
            #expect(editor.text == example.expected)
            #expect(editor.selectedRange == NSRange(location: (example.expected as NSString).length, length: 0))
        }
    }

    @Test
    func returnOnAnEmptyListItemEndsTheListWithoutAddingAnotherMarker() {
        let examples: [(initial: String, expected: String)] = [
            ("A list\n\n- Coffee\n- ", "A list\n\n- Coffee\n"),
            ("A list\n\n- [ ] ", "A list\n\n"),
            ("A list\n\n3. ", "A list\n\n"),
            ("A list\n\n  - ", "A list\n\n  "),
        ]
        for example in examples {
            let editor = EditorTextView()
            editor.loadText(example.initial)
            editor.selectedRange = NSRange(location: (example.initial as NSString).length, length: 0)

            #expect(editor.continueList(for: editor.selectedRange, replacement: "\n"))
            editor.styleChangedText()

            #expect(editor.text == example.expected)
        }
    }

    @Test
    func ordinaryReturnAndReplacementSelectionsStayWithNativeTextInput() {
        let editor = EditorTextView()
        let text = "A title\n\nAn ordinary paragraph."
        editor.loadText(text)
        editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        #expect(!editor.continueList(for: editor.selectedRange, replacement: "\n"))
        #expect(editor.text == text)
        editor.loadText("- Coffee")
        editor.selectedRange = NSRange(location: 2, length: 6)
        #expect(!editor.continueList(for: editor.selectedRange, replacement: "\n"))
        #expect(editor.text == "- Coffee")
    }

    @Test
    func restylingDistinguishesTitleAndBodyWithoutChangingTextOrSelection() throws {
        let editor = EditorTextView()
        let text = "\n\nA place to think\n\nCafé, 東京, and a little 🌿.\nAnother line."
        editor.loadText(text)
        let bodyRange = (text as NSString).range(of: "Café, 東京, and a little 🌿.")
        editor.selectedRange = bodyRange

        editor.restyleAll()

        #expect(editor.text == text)
        #expect(editor.selectedRange == bodyRange)
        let titleRange = (text as NSString).range(of: "A place to think")
        let titleFont = try #require(editor.textStorage.attribute(.font, at: titleRange.location, effectiveRange: nil) as? UIFont)
        let bodyFont = try #require(editor.textStorage.attribute(.font, at: bodyRange.location, effectiveRange: nil) as? UIFont)
        #expect(titleFont.pointSize > bodyFont.pointSize)
        // A new body edit must not turn the body into a title or move its caret.
        editor.selectedRange = NSRange(location: NSMaxRange(bodyRange), length: 0)
        editor.insertText(" More.")
        let editedText = editor.text
        let editedSelection = editor.selectedRange
        editor.styleChangedText()
        #expect(editor.text == editedText)
        #expect(editor.selectedRange == editedSelection)
        let editedBodyFont = try #require(editor.textStorage.attribute(.font, at: bodyRange.location, effectiveRange: nil) as? UIFont)
        #expect(editedBodyFont.pointSize == bodyFont.pointSize)
    }

    @Test
    func stylingPreservesNativePlainTextUndoAndRedo() throws {
        let editor = EditorTextView()
        let original = "A thought\n\nThe first sentence."
        editor.loadText(original)
        editor.selectedRange = NSRange(location: (original as NSString).length, length: 0)
        let undo = try #require(editor.undoManager)
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        editor.insertText(" And the next.")
        undo.endUndoGrouping()
        editor.styleChangedText()
        let edited = original + " And the next."
        #expect(editor.text == edited)
        #expect(undo.canUndo)

        undo.undo()
        editor.styleChangedText()
        #expect(editor.text == original)
        #expect(undo.canRedo)
        undo.redo()
        editor.styleChangedText()
        #expect(editor.text == edited)
    }
}

@MainActor
struct EditorDocumentSessionTests {
    private func makeTempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-session-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test
    func refreshStartedBeforeAnEditAndUndoCannotReplaceTheCurrentSession() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = "A thought\nThe first sentence."
        let url = folder.appendingPathComponent("A thought.md")
        try original.write(to: url, atomically: true, encoding: .utf8)
        let store = NoteStore(folderURL: folder)
        await store.refresh()
        let opened = try await store.open(try #require(store.notes.first))
        let session = EditorDocumentSession(store: store, snapshot: opened)
        let staleRequest = try #require(session.makeRefreshRequest())
        session.changed(original + " A temporary edit.")
        session.changed(original)
        await session.flush()
        let external = "A thought\nChanged on another device."
        try external.write(to: url, atomically: true, encoding: .utf8)
        let fresh = try await store.open(opened.note)

        #expect(!session.acceptCleanRefresh(fresh, request: staleRequest))
        #expect(session.text == original)
        let currentRequest = try #require(session.makeRefreshRequest())
        #expect(session.acceptCleanRefresh(fresh, request: currentRequest))
        #expect(session.text == external)
    }

    @Test
    func concurrentFlushCallersBothWaitForTheLatestTextAndJournalCleanup() async throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = NoteStore(folderURL: folder)
        await store.refresh()
        let opened = try await store.createNote()
        let session = EditorDocumentSession(store: store, snapshot: opened)
        session.changed("A new thought\nFirst edit")
        let firstFlush = Task {
            await session.flush()
            return session.snapshot
        }
        await Task.yield()
        let latest = "A new thought\nFirst edit and the final keystrokes"
        session.changed(latest)
        let secondFlush = Task {
            await session.flush()
            return session.snapshot
        }

        let firstResult = await firstFlush.value
        let secondResult = await secondFlush.value

        #expect(firstResult.text == latest)
        #expect(secondResult.text == latest)
        #expect(!session.isDirty)
        #expect(!session.isSaving)
        #expect(try String(contentsOf: session.snapshot.note.url, encoding: .utf8) == latest)
        let reopened = try await store.open(session.snapshot.note)
        #expect(!reopened.recoveredDraft)
        #expect(reopened.text == latest)
        #expect(session.makeRefreshRequest() != nil)
    }
}
