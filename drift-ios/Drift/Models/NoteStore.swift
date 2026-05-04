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
                let body = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                let derived = Note.derive(from: body)
                return Note(url: url, modified: modified, title: derived.title, preview: derived.preview)
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

    /// Writes `text` to the note's file. If the derived title (first non-blank
    /// line) has changed, also renames the file to match (with " 2", " 3"…
    /// suffixes on collision). Returns the updated `Note` — callers holding a
    /// stale reference (e.g. an editor view) should adopt the returned value.
    @discardableResult
    func saveContents(_ text: String, for note: Note) -> Note {
        let derived = Note.derive(from: text)

        do {
            try text.write(to: note.url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
            return note
        }

        var updated = Note(url: note.url, modified: Date(), title: derived.title, preview: derived.preview)

        let currentBaseName = note.url.deletingPathExtension().lastPathComponent
        if derived.title != currentBaseName, let folderURL {
            let target = uniqueURL(forBaseName: derived.title, in: folderURL, excluding: note.url)
            do {
                try FileManager.default.moveItem(at: note.url, to: target)
                updated = Note(url: target, modified: Date(), title: derived.title, preview: derived.preview)
            } catch {
                // Keep original URL if rename fails (e.g. permissions).
            }
        }

        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = updated
            notes.sort { $0.modified > $1.modified }
        }
        return updated
    }

    @discardableResult
    func createNote() -> Note? {
        guard let folderURL else { return nil }
        let url = uniqueURL(forBaseName: Note.untitled, in: folderURL, excluding: nil)
        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
            let note = Note(url: url, modified: Date(), title: Note.untitled, preview: "")
            notes.insert(note, at: 0)
            return note
        } catch {
            errorMessage = "Couldn't create note: \(error.localizedDescription)"
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

    private func uniqueURL(forBaseName base: String, in folder: URL, excluding: URL?) -> URL {
        let candidate = folder.appendingPathComponent("\(base).md")
        if !exists(candidate, excluding: excluding) { return candidate }
        var counter = 2
        while true {
            let next = folder.appendingPathComponent("\(base) \(counter).md")
            if !exists(next, excluding: excluding) { return next }
            counter += 1
        }
    }

    private func exists(_ url: URL, excluding: URL?) -> Bool {
        if let excluding, url.standardizedFileURL == excluding.standardizedFileURL { return false }
        return FileManager.default.fileExists(atPath: url.path)
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
