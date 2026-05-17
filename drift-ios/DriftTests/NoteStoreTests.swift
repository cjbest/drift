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

    private func storeWithFolder(_ url: URL) async -> NoteStore {
        let store = NoteStore()
        store.folderURL = url
        store.loadNotes()
        await store.awaitEnrichmentForTesting()
        return store
    }

    // MARK: - Title derivation

    @Test
    func titleStripsHeadingPrefix() {
        let (title, _) = Note.derive(from: "# Hello World\n\nbody")
        #expect(title == "Hello World")
    }

    @Test
    func titleStripsMultipleHashes() {
        let (title, _) = Note.derive(from: "### Subhead\n")
        #expect(title == "Subhead")
    }

    @Test
    func titleSkipsLeadingBlankLines() {
        let (title, _) = Note.derive(from: "\n\n  \nReal title here\n")
        #expect(title == "Real title here")
    }

    @Test
    func titleStripsFilenameUnsafeChars() {
        let (title, _) = Note.derive(from: "a/b\\c:d?e")
        #expect(title == "abcde")
    }

    @Test
    func titleCapsAt50Chars() {
        let long = String(repeating: "x", count: 80)
        let (title, _) = Note.derive(from: long)
        #expect(title.count == 50)
    }

    @Test
    func titleFallsBackToUntitled() {
        #expect(Note.derive(from: "").title == "Untitled")
        #expect(Note.derive(from: "\n\n  \n").title == "Untitled")
        #expect(Note.derive(from: "###  ").title == "Untitled")
    }

    @Test
    func previewIsSecondNonBlankLine() {
        let (_, preview) = Note.derive(from: "# Title\n\nThis is the body.\nMore.")
        #expect(preview == "This is the body.")
    }

    // MARK: - Loading

    @Test
    func loadNotesPicksUpMarkdownFilesAndDerivesTitles() async throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }

        try "# Hello".write(to: folder.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "ignored".write(to: folder.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try "Just text".write(to: folder.appendingPathComponent("c.md"), atomically: true, encoding: .utf8)

        let store = await storeWithFolder(folder)
        #expect(store.notes.count == 2)
        let titles = Set(store.notes.map(\.title))
        #expect(titles == ["Hello", "Just text"])
    }

    @Test
    func notesAreSortedByModifiedDescending() async throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }

        let older = folder.appendingPathComponent("older.md")
        let newer = folder.appendingPathComponent("newer.md")
        try "old body".write(to: older, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600)],
            ofItemAtPath: older.path
        )
        try "new body".write(to: newer, atomically: true, encoding: .utf8)

        let store = await storeWithFolder(folder)
        #expect(store.notes.first?.title == "new body")
        #expect(store.notes.last?.title == "old body")
    }

    // MARK: - Create

    @Test
    func createNoteAddsUniqueUntitled() async throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }

        let store = await storeWithFolder(folder)
        let first = store.createNote()
        let second = store.createNote()

        #expect(first?.title == "Untitled")
        #expect(second?.title == "Untitled")
        #expect(store.notes.count == 2)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Untitled.md").path))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Untitled 2.md").path))
    }

    // MARK: - Save (includes auto-rename)

    @Test
    func saveContentsWritesToDiskAndUpdatesModified() async throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }

        let store = await storeWithFolder(folder)
        guard let note = store.createNote() else {
            Issue.record("createNote returned nil")
            return
        }
        let originalModified = store.notes[0].modified

        try await Task.sleep(for: .milliseconds(20))
        let updated = store.saveContents("# Hello\nworld", for: note)

        #expect(updated.title == "Hello")
        let onDisk = try String(contentsOf: updated.url, encoding: .utf8)
        #expect(onDisk == "# Hello\nworld")
        #expect(updated.modified >= originalModified)
    }

    @Test
    func saveRenamesFileWhenTitleChanges() async throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }

        let store = await storeWithFolder(folder)
        guard let note = store.createNote() else {
            Issue.record("createNote returned nil")
            return
        }

        let renamed = store.saveContents("Shopping list\n- milk", for: note)
        #expect(renamed.title == "Shopping list")
        #expect(renamed.url.lastPathComponent == "Shopping list.md")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Shopping list.md").path))
        #expect(!FileManager.default.fileExists(atPath: note.url.path))
    }

    @Test
    func saveRenameSuffixesOnCollision() async throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }

        try "existing".write(to: folder.appendingPathComponent("Hello.md"), atomically: true, encoding: .utf8)

        let store = await storeWithFolder(folder)
        guard let note = store.createNote() else {
            Issue.record("createNote returned nil")
            return
        }

        let renamed = store.saveContents("# Hello", for: note)
        #expect(renamed.title == "Hello")
        #expect(renamed.url.lastPathComponent == "Hello 2.md")
    }

    @Test
    func saveDoesNotRenameWhenTitleMatchesFilename() async throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }

        let url = folder.appendingPathComponent("Stable.md")
        try "Stable\nbody".write(to: url, atomically: true, encoding: .utf8)
        let store = await storeWithFolder(folder)
        let note = try #require(store.notes.first)

        let result = store.saveContents("Stable\nupdated body", for: note)
        #expect(result.url == url)
        #expect(result.title == "Stable")
    }

    @Test
    func saveSanitizesUnsafeCharsInRename() async throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }

        let store = await storeWithFolder(folder)
        guard let note = store.createNote() else {
            Issue.record("createNote returned nil")
            return
        }

        let renamed = store.saveContents("a/b/c", for: note)
        #expect(renamed.title == "abc")
        #expect(renamed.url.lastPathComponent == "abc.md")
    }

    @Test
    func saveEmptyContentKeepsUntitled() async throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }

        let store = await storeWithFolder(folder)
        guard let note = store.createNote() else {
            Issue.record("createNote returned nil")
            return
        }

        let result = store.saveContents("\n\n", for: note)
        #expect(result.title == "Untitled")
        #expect(result.url.lastPathComponent == "Untitled.md")
    }

    // MARK: - Delete

    @Test
    func deleteRemovesFileAndEntry() async throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }

        let store = await storeWithFolder(folder)
        guard let note = store.createNote() else {
            Issue.record("createNote returned nil")
            return
        }
        store.delete(note)

        #expect(store.notes.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: note.url.path))
    }

    // MARK: - Search

    @Test
    func searchEmptyReturnsAllNotes() async throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }
        try "alpha".write(to: folder.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "beta".write(to: folder.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)

        let store = await storeWithFolder(folder)
        #expect(store.search("").count == 2)
        #expect(store.search("   ").count == 2)
    }

    @Test
    func searchMatchesTitle() async throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }
        try "Shopping list\n- milk".write(to: folder.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "Meeting notes".write(to: folder.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)

        let store = await storeWithFolder(folder)
        let hits = store.search("shopping")
        #expect(hits.count == 1)
        #expect(hits.first?.note.title == "Shopping list")
        // Title-only match: no body snippet (row falls back to default preview).
        #expect(hits.first?.snippet == nil)
    }

    @Test
    func searchMatchesBodyContent() async throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }
        try "Meeting notes\n\n- ship the iOS app overnight".write(to: folder.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "Random ideas\n\nthoughts about pasta".write(to: folder.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)

        let store = await storeWithFolder(folder)
        let hits = store.search("overnight")
        #expect(hits.count == 1)
        #expect(hits.first?.note.title == "Meeting notes")
    }

    @Test
    func searchIsCaseInsensitive() async throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }
        try "Welcome\n\nHello WORLD!".write(to: folder.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)

        let store = await storeWithFolder(folder)
        #expect(store.search("world").count == 1)
        #expect(store.search("WORLD").count == 1)
        #expect(store.search("WoRlD").count == 1)
    }

    @Test
    func searchUpdatesAfterSave() async throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }
        try "Welcome\n\noriginal body".write(to: folder.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)

        let store = await storeWithFolder(folder)
        #expect(store.search("freshly-typed").isEmpty)

        let note = try #require(store.notes.first)
        _ = store.saveContents("Welcome\n\nfreshly-typed text", for: note)
        #expect(store.search("freshly-typed").count == 1)
        // And the previous body content shouldn't match anymore.
        #expect(store.search("original body").isEmpty)
    }

    @Test
    func searchDropsDeletedNotes() async throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }
        try "alpha\n\nuniquetoken".write(to: folder.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)

        let store = await storeWithFolder(folder)
        let note = try #require(store.notes.first)
        store.delete(note)
        #expect(store.search("uniquetoken").isEmpty)
    }

    @Test
    func searchSnippetReturnsMatchingLine() async throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }
        try "Title\n\nFirst paragraph.\nThe magic word is overnight here.\nAnother line."
            .write(to: folder.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)

        let store = await storeWithFolder(folder)
        let hit = try #require(store.search("overnight").first)
        let snippet = try #require(hit.snippet)
        #expect(snippet == "The magic word is overnight here.")
    }

    @Test
    func searchSnippetPreservesOriginalCase() async throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }
        try "Welcome\n\nHello WORLD!".write(to: folder.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)

        let store = await storeWithFolder(folder)
        let hit = try #require(store.search("world").first)
        // Case-insensitive match, but the snippet keeps the source casing.
        #expect(hit.snippet == "Hello WORLD!")
    }

    @Test
    func searchSnippetWindowsAroundMatchDeepInLongLine() async throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }
        // Match is ~200 chars into the line — way past where lineLimit(1)
        // would cut off if we showed the line from the start.
        let longLine = String(repeating: "filler ", count: 30) + "keyword tail"
        try "Title\n\n\(longLine)".write(to: folder.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)

        let store = await storeWithFolder(folder)
        let hit = try #require(store.search("keyword").first)
        let snippet = try #require(hit.snippet)
        // Should start with an ellipsis (we trimmed the front) and contain
        // the match within the first ~25 chars.
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.contains("keyword"))
        let needleStart = try #require(snippet.range(of: "keyword")?.lowerBound)
        let charsBefore = snippet.distance(from: snippet.startIndex, to: needleStart)
        #expect(charsBefore <= 25)
    }

    @Test
    func searchSnippetDoesNotEllipsizeWhenMatchIsNearStart() async throws {
        let folder = try makeTempFolder()
        defer { cleanup(folder) }
        try "Title\n\nkeyword is right at the start"
            .write(to: folder.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)

        let store = await storeWithFolder(folder)
        let hit = try #require(store.search("keyword").first)
        let snippet = try #require(hit.snippet)
        #expect(!snippet.hasPrefix("…"))
        #expect(snippet == "keyword is right at the start")
    }

    @Test
    func readContentsReturnsEmptyForMissingFile() {
        let store = NoteStore()
        let bogus = Note(url: URL(fileURLWithPath: "/nope/missing.md"), modified: .now, title: "n/a", preview: "")
        #expect(store.readContents(of: bogus) == "")
    }
}
