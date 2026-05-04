import Testing
import Foundation
@testable import Drift

@MainActor
struct NoteStoreTests {

    private func makeTempFolder() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("drift-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func storeWithFolder(_ url: URL) -> NoteStore {
        let store = NoteStore()
        store.folderURL = url
        store.loadNotes()
        return store
    }

    @Test
    func loadNotesPicksUpMarkdownFiles() throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }

        try "# Hello".write(to: folder.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "ignored".write(to: folder.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try "second".write(to: folder.appendingPathComponent("c.md"), atomically: true, encoding: .utf8)

        let store = storeWithFolder(folder)

        #expect(store.notes.count == 2)
        let titles = Set(store.notes.map(\.title))
        #expect(titles == ["a", "c"])
    }

    @Test
    func notesAreSortedByModifiedDescending() throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }

        let older = folder.appendingPathComponent("older.md")
        let newer = folder.appendingPathComponent("newer.md")
        try "old".write(to: older, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600)],
            ofItemAtPath: older.path
        )
        try "new".write(to: newer, atomically: true, encoding: .utf8)

        let store = storeWithFolder(folder)

        #expect(store.notes.first?.title == "newer")
        #expect(store.notes.last?.title == "older")
    }

    @Test
    func createNoteAddsUniqueUntitled() throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }

        let store = storeWithFolder(folder)
        let first = store.createNote()
        let second = store.createNote()

        #expect(first?.title == "Untitled")
        #expect(second?.title == "Untitled 2")
        #expect(store.notes.count == 2)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Untitled.md").path))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Untitled 2.md").path))
    }

    @Test
    func saveContentsWritesToDiskAndUpdatesModified() async throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }

        let store = storeWithFolder(folder)
        guard let note = store.createNote() else {
            Issue.record("createNote returned nil")
            return
        }
        let originalModified = store.notes[0].modified

        try await Task.sleep(for: .milliseconds(20))
        store.saveContents("hello world", for: note)

        let onDisk = try String(contentsOf: note.url, encoding: .utf8)
        #expect(onDisk == "hello world")
        #expect(store.notes[0].modified >= originalModified)
    }

    @Test
    func renameMovesFile() throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }

        let store = storeWithFolder(folder)
        guard let note = store.createNote() else {
            Issue.record("createNote returned nil")
            return
        }
        store.saveContents("body", for: note)

        let renamed = store.rename(note, to: "Shopping List")
        #expect(renamed?.title == "Shopping List")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Shopping List.md").path))
        #expect(!FileManager.default.fileExists(atPath: note.url.path))

        let body = try String(contentsOf: renamed!.url, encoding: .utf8)
        #expect(body == "body")
    }

    @Test
    func renameToExistingNameFails() throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }

        try "a".write(to: folder.appendingPathComponent("Existing.md"), atomically: true, encoding: .utf8)

        let store = storeWithFolder(folder)
        guard let note = store.createNote() else {
            Issue.record("createNote returned nil")
            return
        }
        let result = store.rename(note, to: "Existing")
        #expect(result == nil)
        #expect(store.errorMessage != nil)
    }

    @Test
    func renameSanitizesSlashes() throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }

        let store = storeWithFolder(folder)
        guard let note = store.createNote() else {
            Issue.record("createNote returned nil")
            return
        }
        let renamed = store.rename(note, to: "a/b/c")
        #expect(renamed?.title == "a-b-c")
    }

    @Test
    func deleteRemovesFileAndEntry() throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }

        let store = storeWithFolder(folder)
        guard let note = store.createNote() else {
            Issue.record("createNote returned nil")
            return
        }
        store.delete(note)

        #expect(store.notes.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: note.url.path))
    }

    @Test
    func readContentsReturnsEmptyForMissingFile() {
        let store = NoteStore()
        let bogus = Note(url: URL(fileURLWithPath: "/nope/missing.md"), modified: .now)
        #expect(store.readContents(of: bogus) == "")
    }
}
