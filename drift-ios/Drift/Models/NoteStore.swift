import Foundation
import Observation

@Observable
final class NoteStore {
    private let bookmarkKey = "drift.folderBookmark"

    var folderURL: URL?
    var notes: [Note] = []
    var errorMessage: String?

    private var folderAccessing = false

    init() {
        if let testPath = ProcessInfo.processInfo.environment["DRIFT_TEST_FOLDER"] {
            let url = URL(fileURLWithPath: testPath, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            folderURL = url
            loadNotes()
            return
        }
        restoreFolder()
    }

    deinit {
        if folderAccessing, let url = folderURL {
            url.stopAccessingSecurityScopedResource()
        }
    }

    func setFolder(_ url: URL) {
        if folderAccessing, let current = folderURL {
            current.stopAccessingSecurityScopedResource()
            folderAccessing = false
        }

        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Couldn't access that folder. Try picking it again."
            return
        }
        folderAccessing = true
        folderURL = url

        do {
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
            errorMessage = "Saved folder, but couldn't store bookmark: \(error.localizedDescription)"
        }

        loadNotes()
    }

    func clearFolder() {
        if folderAccessing, let url = folderURL {
            url.stopAccessingSecurityScopedResource()
        }
        folderAccessing = false
        folderURL = nil
        notes = []
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    func loadNotes() {
        guard let folderURL else {
            notes = []
            return
        }

        let fm = FileManager.default
        do {
            let urls = try fm.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            let mdNotes: [Note] = urls.compactMap { url in
                guard url.pathExtension.lowercased() == "md" else { return nil }
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                if values?.isRegularFile == false { return nil }
                let modified = values?.contentModificationDate ?? .distantPast
                return Note(url: url, modified: modified)
            }

            notes = mdNotes.sorted { $0.modified > $1.modified }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load folder: \(error.localizedDescription)"
            notes = []
        }
    }

    func readContents(of note: Note) -> String {
        (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
    }

    func saveContents(_ text: String, for note: Note) {
        do {
            try text.write(to: note.url, atomically: true, encoding: .utf8)
            if let idx = notes.firstIndex(where: { $0.id == note.id }) {
                notes[idx].modified = Date()
                notes.sort { $0.modified > $1.modified }
            }
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func createNote() -> Note? {
        guard let folderURL else { return nil }
        let base = "Untitled"
        var name = "\(base).md"
        var counter = 2
        while FileManager.default.fileExists(atPath: folderURL.appendingPathComponent(name).path) {
            name = "\(base) \(counter).md"
            counter += 1
        }
        let url = folderURL.appendingPathComponent(name)
        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
            let note = Note(url: url, modified: Date())
            notes.insert(note, at: 0)
            return note
        } catch {
            errorMessage = "Couldn't create note: \(error.localizedDescription)"
            return nil
        }
    }

    func rename(_ note: Note, to newTitle: String) -> Note? {
        guard let folderURL else { return nil }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return note }

        let safe = trimmed.replacingOccurrences(of: "/", with: "-")
        let newURL = folderURL.appendingPathComponent("\(safe).md")
        guard newURL != note.url else { return note }

        do {
            if FileManager.default.fileExists(atPath: newURL.path) {
                errorMessage = "A note with that name already exists."
                return nil
            }
            try FileManager.default.moveItem(at: note.url, to: newURL)
            let updated = Note(url: newURL, modified: Date())
            if let idx = notes.firstIndex(where: { $0.id == note.id }) {
                notes[idx] = updated
            }
            return updated
        } catch {
            errorMessage = "Rename failed: \(error.localizedDescription)"
            return nil
        }
    }

    func delete(_ note: Note) {
        do {
            try FileManager.default.removeItem(at: note.url)
            notes.removeAll { $0.id == note.id }
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func restoreFolder() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            if url.startAccessingSecurityScopedResource() {
                folderAccessing = true
                folderURL = url
                loadNotes()
                if stale {
                    if let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                        UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
                    }
                }
            }
        } catch {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        }
    }
}
